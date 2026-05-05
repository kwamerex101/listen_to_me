import SwiftUI
import AppKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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

        // Wire hotkey
        HotkeyMonitor.shared.onPress = { [weak self] in self?.handlePress() }
        HotkeyMonitor.shared.onRelease = { [weak self] in self?.handleRelease() }
        HotkeyMonitor.shared.start()

        // Wire button callbacks
        state.onStartTap = { [weak self] in self?.handlePress() }
        state.onStopTap = { [weak self] in self?.handleRelease() }
        state.onCancelTap = { [weak self] in self?.handleCancel() }
        state.onPillTap = { [weak self] in self?.handlePillTap() }

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
                    Haptics.success()
                    SoundCue.success()
                    HistoryStore.shared.add(rawText: raw, finalText: expanded, durationMs: durMs)
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
                let cleaned = try await ClaudeClient.shared.clean(expanded)
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self else { return }
                    if let newToken = Paster.replace(with: cleaned, token: token) {
                        // Successful replace — bookkeep the new token so the
                        // correction popover sees the cleaned text.
                        self.lastPasteToken = newToken
                        self.state.lastTranscript = cleaned
                        HistoryStore.shared.add(rawText: raw, finalText: cleaned, durationMs: durMs)
                    } else {
                        // Validation failed (focus changed, clipboard touched,
                        // user opened the correction popover, etc.). Raw stays.
                        self.state.lastTranscript = expanded
                        HistoryStore.shared.add(rawText: raw, finalText: expanded, durationMs: durMs)
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
                    HistoryStore.shared.add(rawText: raw, finalText: expanded, durationMs: durMs)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            // Don't yank the pill back to idle if the user is mid-correction
            // — they're actively editing.
            if case .correcting = self.state.phase { return }
            self.state.phase = .idle
            // Idle pill is click-through again so it doesn't intercept stray
            // clicks on whatever's underneath.
            PillWindow.shared.setInteractive(false)
        }
    }
}
