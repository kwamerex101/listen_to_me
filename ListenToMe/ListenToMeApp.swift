import SwiftUI
import AppKit
import ApplicationServices

@main
struct ListenToMeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No windows — menu bar app. Settings window can live here in later phases.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState.shared
    private var recordingStartedAt: Date?
    /// In-flight background cleanup for streaming-preview. Cancelled when a
    /// new dictation starts, so a slow earlier cleanup can never silently
    /// overwrite a newer one.
    private var cleanupTask: Task<Void, Never>?
    /// The most-recent paste token. Drives the correction popover —
    /// updated whenever we paste or successfully replace.
    private var lastPasteToken: PasteToken?
    /// Original raw whisper transcript for the most recent dictation, kept
    /// so corrections can update the matching history record.
    private var lastRawTranscript: String?
    /// Pending retype-detection probe. Cancelled when a new dictation starts
    /// so we don't AX-poll an out-of-context window 7s later.
    private var retypeTask: Task<Void, Never>?
    /// Pending auto-reset back to .idle. Stored so a `.suggestion` banner
    /// firing right after a `.success` can cancel the reset and let the user
    /// read the banner without it being yanked away after 3s (Phase 4 A4).
    private var autoResetTask: Task<Void, Never>?
    /// Auto-dismiss timer for the .suggestion banner. Cleared on Keep/Dismiss
    /// to avoid clobbering a freshly-set phase.
    private var suggestionTimeoutTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Apply user's theme preference before any UI lands so the first
        // paint is correct and we avoid a flash to the system appearance.
        Preferences.shared.appearance.apply()

        MenuBarController.shared.install()

        // Always-visible compact pill
        PillWindow.shared.showPersistent()

        // Mic permission up front
        Task {
            let granted = await AudioRecorder.requestMicAccess()
            state.micGranted = granted
        }

        // One-shot probe of the `claude` CLI. Drives the menu-bar warning
        // when cleanup is enabled but the binary isn't installed.
        Task {
            let available = await ClaudeClient.shared.isAvailable()
            state.claudeAvailable = available
            NotificationCenter.default.post(name: .phaseChanged, object: nil)
        }

        // Accessibility — show permission card animating out of the pill if not granted
        state.hotkeyGranted = HotkeyMonitor.isAccessibilityGranted()
        if !state.hotkeyGranted {
            state.showPermissionPrompt = true
            PillWindow.shared.setInteractive(true)
        }

        // Wire state → waveform
        AudioRecorder.shared.onLevel = { [weak self] level in
            self?.state.level = level
        }
        // QUAL-03: when the watchdog fires, treat as a normal release so
        // the pipeline finishes the dictation cleanly — better than just
        // dropping the audio.
        AudioRecorder.shared.onMaxDurationReached = { [weak self] in
            guard case .recording = self?.state.phase else { return }
            self?.handleRelease()
        }

        // Wire hotkey
        HotkeyMonitor.shared.onPress = { [weak self] in self?.handlePress() }
        HotkeyMonitor.shared.onRelease = { [weak self] in self?.handleRelease() }
        HotkeyMonitor.shared.start()

        // Wire button callbacks
        state.onStartTap = { [weak self] in self?.handlePress() }
        state.onStopTap = { [weak self] in self?.handleRelease() }
        state.onCancelTap = { [weak self] in self?.handleCancel() }
        state.onPillTap = { [weak self] in self?.handlePillTap() }
        state.onSuggestionKeep = { [weak self] in self?.handleSuggestionKeep() }
        state.onSuggestionDismiss = { [weak self] in self?.handleSuggestionDismiss() }

        // Warm Phase 4 singletons so their JSON files are touched on launch
        // and `entries` / `samplesByBundle` are loaded before the first
        // dictation lands.
        _ = StyleSamplesStore.shared
        _ = StyleStore.shared

        // Emit phase-change notifications for menu bar
        Task { @MainActor [weak self] in
            guard let self else { return }
            var last: Phase = .idle
            while !Task.isCancelled {
                if self.state.phase != last {
                    last = self.state.phase
                    NotificationCenter.default.post(name: .phaseChanged, object: nil)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    // MARK: - Hotkey handlers

    private func handlePress() {
        // Allow press from any non-recording phase. If a previous cleanup
        // is still running we cancel it — its replace would target an old
        // app/text and shouldn't execute. Also dismiss any open correction
        // popover so the new dictation has a clean slate.
        if case .recording = state.phase { return }
        cleanupTask?.cancel()
        cleanupTask = nil
        retypeTask?.cancel()
        retypeTask = nil
        if case .correcting = state.phase {
            CorrectionWindow.shared.dismiss()
        }

        guard state.micGranted else {
            state.phase = .error(message: "Mic permission needed")
            autoReset()
            return
        }

        do {
            _ = try AudioRecorder.shared.start()
            recordingStartedAt = Date()
            PillWindow.shared.repositionToActiveScreen()
            state.phase = .recording
            Haptics.start()
            SoundCue.recordingStart()
            PillWindow.shared.setInteractive(true)
        } catch {
            state.phase = .error(message: "Record failed")
            // pill animates via SwiftUI phase change
            autoReset()
        }
    }

    private func handleCancel() {
        guard case .recording = state.phase else { return }
        AudioRecorder.shared.cancel()
        Haptics.stop()
        PillWindow.shared.setInteractive(false)
        HistoryStore.shared.add(rawText: "", finalText: "", durationMs: 0, dismissed: true)
        recordingStartedAt = nil
        state.phase = .idle
    }

    private func handleRelease() {
        guard case .recording = state.phase else { return }
        Haptics.stop()
        SoundCue.recordingStop()
        PillWindow.shared.setInteractive(false)
        guard let wav = AudioRecorder.shared.stop() else {
            state.phase = .error(message: "No audio")
            autoReset()
            return
        }
        state.phase = .transcribing

        let whisperPrompt = DictionaryStore.shared.whisperPrompt
        Task { @MainActor in
            do {
                let raw = try await WhisperRunner.shared.transcribe(wav: wav, prompt: whisperPrompt)
                if raw.isEmpty {
                    state.phase = .error(message: "Empty transcript")
                    autoReset()
                    return
                }

                // Voice-command interception — runs BEFORE cleanup on the raw text
                if let cmd = CommandRouter.parse(raw) {
                    do {
                        let summary = try await CommandRouter.execute(cmd)
                        Haptics.success()
                        let durMs = recordingStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                        recordingStartedAt = nil
                        HistoryStore.shared.add(rawText: raw, finalText: "[cmd] \(summary)", durationMs: durMs)
                        state.phase = .success(preview: summary)
                        autoReset(after: 1.0)
                    } catch {
                        NSLog("[ListenToMe] command failed: \(error)")
                        state.phase = .error(message: "Command failed")
                        autoReset()
                    }
                    return
                }

                // Voice-editing commands (comma, period, scratch that, new
                // paragraph) run on the raw transcript before snippets and
                // cleanup. Pure transform; deterministic punctuation never
                // depends on the LLM's mood.
                let edited = VoiceEditor.apply(raw)

                // Pure-undo edge case: user said only "scratch that" (or it
                // resolved to empty). Skip paste, no history, brief feedback.
                if edited.isEmpty {
                    let durMs = recordingStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                    recordingStartedAt = nil
                    HistoryStore.shared.add(rawText: raw, finalText: "",
                                             durationMs: durMs, dismissed: true)
                    state.phase = .success(preview: "(scratched)")
                    autoReset(after: 0.6)
                    return
                }

                // Snippet expansion runs BEFORE cleanup so the cleaned result
                // flows naturally around the expanded text.
                let expanded = SnippetsStore.shared.expand(in: edited)
                let words = expanded.split(whereSeparator: \.isWhitespace).count
                let durMs = recordingStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                recordingStartedAt = nil

                // Streaming preview: paste the raw transcript NOW so the
                // user sees text within ~1.5s of release. Cleanup runs in
                // the background and may swap in a polished version.
                lastRawTranscript = raw
                if Preferences.shared.cleanupMode.shouldClean(wordCount: words) {
                    state.lastTranscript = expanded
                    let token = Paster.pasteTracked(expanded)
                    lastPasteToken = token
                    Haptics.success()
                    SoundCue.success()
                    state.phase = .polishing(rawPreview: String(expanded.prefix(40)))
                    PillWindow.shared.setInteractive(true)
                    startCleanupTask(raw: raw, expanded: expanded, durMs: durMs, token: token)
                } else {
                    // No-cleanup mode: still paste-tracked so the user can
                    // open the correction popover; we just never call replace.
                    state.lastTranscript = expanded
                    let token = Paster.pasteTracked(expanded)
                    lastPasteToken = token
                    scheduleRetypeDetection(token: token)
                    recordStyleSample(token: token, cleaned: expanded)
                    Haptics.success()
                    SoundCue.success()
                    HistoryStore.shared.add(rawText: raw, finalText: expanded,
                                             durationMs: durMs, bundleId: token.bundleId)
                    state.phase = .success(preview: String(expanded.prefix(30)))
                    PillWindow.shared.setInteractive(true)
                    // Longer success window so the user has time to click the
                    // pill if they want to correct.
                    autoReset(after: 3.0)
                }
            } catch WhisperError.modelNotFound(let path) {
                NSLog("[ListenToMe] model not found: \(path)")
                state.phase = .error(message: "Model missing")
                autoReset()
            } catch {
                NSLog("[ListenToMe] transcription failed: \(error)")
                state.phase = .error(message: "Transcribe failed")
                autoReset()
            }
        }
    }

    /// Run cleanup in the background while the raw transcript already sits
    /// in the user's target app. On success, swap the raw for the polished
    /// version (subject to validation gates in `Paster.replace`). On any
    /// failure we keep the raw and just record history.
    private func startCleanupTask(raw: String,
                                  expanded: String,
                                  durMs: Int,
                                  token: PasteToken) {
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            do {
                let timeout = TimeInterval(Preferences.shared.cleanupTimeoutSec)
                let cleaned = try await ClaudeClient.shared.clean(
                    expanded,
                    bundleId: token.bundleId,
                    timeout: timeout
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self else { return }
                    if let newToken = Paster.replace(with: cleaned, token: token) {
                        // Successful replace — bookkeep the new token so the
                        // correction popover sees the cleaned text.
                        self.lastPasteToken = newToken
                        self.state.lastTranscript = cleaned
                        self.scheduleRetypeDetection(token: newToken)
                        self.recordStyleSample(token: newToken, cleaned: cleaned)
                        HistoryStore.shared.add(rawText: raw, finalText: cleaned,
                                                 durationMs: durMs, bundleId: newToken.bundleId)
                    } else {
                        // Validation failed (focus changed, clipboard touched,
                        // user opened the correction popover, etc.). Raw stays.
                        self.state.lastTranscript = expanded
                        HistoryStore.shared.add(rawText: raw, finalText: expanded,
                                                 durationMs: durMs, bundleId: token.bundleId)
                    }
                    if self.isStillPolishing(token: token) {
                        let preview = self.state.lastTranscript.prefix(30)
                        self.state.phase = .success(preview: String(preview))
                        self.autoReset(after: 3.0)
                    }
                }
            } catch is CancellationError {
                // New dictation started OR user opened the correction popover.
                // Leave raw in place; the new flow / correction will record
                // its own history.
                await MainActor.run { Paster.finalize(token: token) }
            } catch {
                NSLog("[ListenToMe] cleanup failed, raw stands: \(error)")
                await MainActor.run {
                    guard let self else { return }
                    Paster.finalize(token: token)
                    HistoryStore.shared.add(rawText: raw, finalText: expanded,
                                             durationMs: durMs, bundleId: token.bundleId)
                    if self.isStillPolishing(token: token) {
                        self.state.phase = .success(preview: String(expanded.prefix(30)))
                        self.autoReset(after: 3.0)
                    }
                }
            }
        }
    }

    /// True if the pill is still in the polishing state for this token —
    /// i.e. the user hasn't started a new dictation since. Prevents the
    /// callback from clobbering a fresher phase.
    private func isStillPolishing(token: PasteToken) -> Bool {
        if case .polishing = state.phase { return true }
        return false
    }

    // MARK: - Retype detection

    /// Snapshot the token at paste-success time, sleep 7s, then diff.
    /// Cancelled on new dictation so we don't AX-poll a stale window.
    private func scheduleRetypeDetection(token: PasteToken) {
        retypeTask?.cancel()
        retypeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(7))
            if Task.isCancelled { return }
            self?.detectRetype(against: token)
        }
    }

    /// Append a line to ~/Library/Application Support/ListenToMe/retype-debug.log.
    /// Used for diagnostics because macOS unified logging redacts Swift NSLog
    /// string interpolations as `<private>` by default.
    private func retypeDebug(_ line: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("retype-debug.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp)  \(line)\n"
        if let data = entry.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func detectRetype(against snapshot: PasteToken) {
        retypeDebug("probe fired bundle=\(snapshot.bundleId ?? "nil") pasted=\"\(snapshot.pastedText.prefix(60))\"")

        // D-07 bail conditions
        let currentBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard currentBundle == snapshot.bundleId else {
            retypeDebug("BAIL bundle-mismatch current=\(currentBundle ?? "nil") expected=\(snapshot.bundleId ?? "nil")")
            return
        }
        let age = Date().timeIntervalSince(snapshot.timestamp)
        guard age <= 8.0 else {  // 7s + 1s grace
            retypeDebug("BAIL stale age=\(age)s")
            return
        }

        // D-08: always diff against LATEST pastedText (cleanup-replace may have updated it)
        let referenceText = lastPasteToken?.pastedText ?? snapshot.pastedText
        guard !referenceText.isEmpty else {
            retypeDebug("BAIL empty-reference")
            return
        }

        // AX read — try systemWide first, fall back to per-app AX which
        // sometimes works in Electron apps (Claude Desktop, Slack, VS Code,
        // Notion) where systemWide returns nothing.
        var focusedElement: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedErr = AXUIElementCopyAttributeValue(systemWide,
              kAXFocusedUIElementAttribute as CFString, &focusedRef)
        if focusedErr == .success, let focusedRef {
            focusedElement = (focusedRef as! AXUIElement)
        } else {
            retypeDebug("systemWide focused failed axerr=\(focusedErr.rawValue) — trying per-app AX")
            // Per-app fallback: build AXUIElement from the target's PID,
            // ask it for its focused UI element directly.
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == snapshot.bundleId }) {
                let appAX = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(appAX, 0.5)
                var appFocusedRef: CFTypeRef?
                let appFocusedErr = AXUIElementCopyAttributeValue(appAX,
                      kAXFocusedUIElementAttribute as CFString, &appFocusedRef)
                if appFocusedErr == .success, let appFocusedRef {
                    focusedElement = (appFocusedRef as! AXUIElement)
                    retypeDebug("per-app AX focused element acquired pid=\(app.processIdentifier)")
                } else {
                    retypeDebug("BAIL per-app AX focused failed axerr=\(appFocusedErr.rawValue) — Electron app likely AX-blind")
                    return
                }
            } else {
                retypeDebug("BAIL no running app for bundle=\(snapshot.bundleId ?? "nil")")
                return
            }
        }

        guard let element = focusedElement else {
            retypeDebug("BAIL no-focused-element (both systemWide and per-app failed)")
            return
        }
        AXUIElementSetMessagingTimeout(element, 0.5)   // seconds, NOT milliseconds (see Paster.swift)

        var textRef: CFTypeRef?
        let valueErr = AXUIElementCopyAttributeValue(element,
              kAXValueAttribute as CFString, &textRef)
        guard valueErr == .success else {
            retypeDebug("BAIL ax-value-failed axerr=\(valueErr.rawValue) — likely Electron/web app without AXValue support")
            return
        }
        guard let currentText = textRef as? String else {
            retypeDebug("BAIL ax-value-not-string type=\(type(of: textRef as Any))")
            return
        }

        // D-07: byte-identical means no edit — nothing to learn
        guard currentText != referenceText else {
            retypeDebug("BAIL byte-identical (no edit) len=\(currentText.count)")
            return
        }

        // Window slice bounds tokenizer cost on long documents (RESEARCH Pattern 6)
        let pasteLocation = snapshot.selection?.selectionRange.location ?? 0
        let radius = max(referenceText.count * 5, 200)
        let windowedCurrent = currentText.windowSlice(around: pasteLocation, radius: radius)

        let refTokens = tokenize(referenceText)
        let curTokens = tokenize(windowedCurrent)
        retypeDebug("DIFF refTokens=\(refTokens.count) curTokens=\(curTokens.count) refField=\"\(referenceText.prefix(80))\" curField=\"\(windowedCurrent.prefix(80))\"")

        if let (original, replacement) = singleWordSwap(from: referenceText, to: windowedCurrent) {
            retypeDebug("CAPTURED \"\(original)\" → \"\(replacement)\" bundle=\(currentBundle ?? "nil")")
            CandidateStore.shared.recordOccurrence(
                original: original,
                replacement: replacement,
                bundleId: currentBundle
            )
        } else {
            retypeDebug("BAIL singleWordSwap-rejected (token-count mismatch, multi-diff, or short/digit-only)")
        }
    }

    // MARK: - Inline correction popover

    private func handlePillTap() {
        // Only open the correction popover if the user is in a state that
        // logically followed a paste, and we still have a token pointing at it.
        switch state.phase {
        case .success, .polishing: break
        default: return
        }
        guard let token = lastPasteToken, !token.pastedText.isEmpty else { return }

        // The user is taking manual control — abandon any in-flight cleanup.
        cleanupTask?.cancel()
        cleanupTask = nil

        state.phase = .correcting

        CorrectionWindow.shared.show(
            initialText: token.pastedText,
            onApply: { [weak self] corrected in self?.applyCorrection(corrected, token: token) },
            onCancel: { [weak self] in self?.cancelCorrection(token: token) }
        )
    }

    private func applyCorrection(_ corrected: String, token: PasteToken) {
        CorrectionWindow.shared.dismiss()

        // Re-activate the original target app so Cmd+Z+Cmd+V land in the
        // right place. Skip if the bundle ID isn't recoverable.
        if let bundleId = token.bundleId,
           let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            target.activate(options: [])
        }

        // Brief delay for the activation to take effect before posting keys.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            if let newToken = Paster.replace(with: corrected, token: token) {
                self.lastPasteToken = newToken
                self.state.lastTranscript = corrected
                HistoryStore.shared.updateLast(finalText: corrected)
                self.state.phase = .success(preview: String(corrected.prefix(30)))
                self.autoReset(after: 3.0)
            } else {
                self.state.phase = .error(message: "Couldn't apply correction")
                self.autoReset()
            }
        }
    }

    private func cancelCorrection(token: PasteToken) {
        CorrectionWindow.shared.dismiss()
        // Re-activate the target app (the user dismissed without applying;
        // they probably want to keep working there).
        if let bundleId = token.bundleId,
           let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            target.activate(options: [])
        }
        state.phase = .success(preview: String(token.pastedText.prefix(30)))
        autoReset(after: 1.5)
    }

    private func autoReset(after seconds: Double = 1.4) {
        autoResetTask?.cancel()
        autoResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if Task.isCancelled { return }
            guard let self else { return }
            // Don't yank the pill back to idle if the user is mid-correction
            // — they're actively editing. Also bail if we've since entered a
            // .suggestion banner (Phase 4 A4: banner cancels this task, but
            // belt-and-braces guard).
            if case .correcting = self.state.phase { return }
            if case .suggestion = self.state.phase { return }
            self.state.phase = .idle
            // Idle pill is click-through again so it doesn't intercept stray
            // clicks on whatever's underneath.
            PillWindow.shared.setInteractive(false)
        }
    }

    // MARK: - Phase 4 — Style sample capture, inference, suggestion

    /// After a successful paste, append the cleaned text to
    /// `StyleSamplesStore` and trigger inference. Skips when bundleId is nil
    /// or empty (Pitfall P5: no usable scoping key — Desktop with no
    /// frontmost app, etc.). Also skips voice-command outputs by virtue of
    /// only being called from the two paste-success branches; the command
    /// path never reaches Paster.replace (Pitfall P2).
    private func recordStyleSample(token: PasteToken, cleaned: String) {
        guard let bundleId = token.bundleId, !bundleId.isEmpty else { return }
        StyleSamplesStore.shared.record(sample: cleaned, bundleId: bundleId)
        runStyleInference(bundleId: bundleId)
    }

    /// Run the deterministic tone rubric and update StyleStore. Fires the
    /// suggestion banner if the gate passes (no acceptedTone, tone != .none,
    /// tone not previously dismissed).
    private func runStyleInference(bundleId: String) {
        let samples = StyleSamplesStore.shared.samples(for: bundleId)
        guard samples.count >= 20 else { return }
        let tone = ToneInferencer.infer(samples: samples)
        StyleStore.shared.update(bundleId: bundleId, inferredTone: tone)
        if let suggested = StyleStore.shared.shouldSuggest(bundleId: bundleId) {
            fireSuggestion(bundleId: bundleId, tone: suggested)
        }
    }

    /// Enter `.suggestion` phase. Cancels any pending `.success` autoReset so
    /// the banner has a stable read-time; the pill becomes interactive so
    /// Keep / Dismiss receive clicks. Also schedules an 8s passive timeout —
    /// timeout-clear does NOT persist to dismissedTones (CHECK CONCERN-2),
    /// so a missed banner re-fires on the next dictation into this app.
    private func fireSuggestion(bundleId: String, tone: InferredTone) {
        autoResetTask?.cancel()
        autoResetTask = nil
        suggestionTimeoutTask?.cancel()

        state.phase = .suggestion(bundleId: bundleId, tone: tone)
        PillWindow.shared.setInteractive(true)

        suggestionTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self else { return }
            if case .suggestion = self.state.phase {
                // Timeout-only clear. Do NOT call onSuggestionDismiss — that
                // would persistently kill this (bundleId, tone) pair.
                self.state.phase = .idle
                PillWindow.shared.setInteractive(false)
            }
        }
    }

    private func handleSuggestionKeep() {
        if case .suggestion(let bundleId, _) = state.phase {
            StyleStore.shared.accept(bundleId: bundleId)
        }
        suggestionTimeoutTask?.cancel()
        suggestionTimeoutTask = nil
        state.phase = .idle
        PillWindow.shared.setInteractive(false)
    }

    private func handleSuggestionDismiss() {
        if case .suggestion(let bundleId, let tone) = state.phase {
            // Pitfall P3: dismiss writes to disk BEFORE clearing phase, so a
            // crash mid-flow doesn't lose the dismissal (CandidateStore
            // remove-before-promote precedent).
            StyleStore.shared.dismiss(bundleId: bundleId, tone: tone)
        }
        suggestionTimeoutTask?.cancel()
        suggestionTimeoutTask = nil
        state.phase = .idle
        PillWindow.shared.setInteractive(false)
    }
}
