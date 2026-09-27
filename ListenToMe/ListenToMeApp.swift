import SwiftUI
import AppKit
import ApplicationServices
import Combine
import AVFoundation

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

    /// Combine subscription that posts `.phaseChanged` whenever
    /// `AppState.phase` actually changes. Replaces the previous 150ms
    /// polling loop so the menu-bar update is event-driven and the app
    /// has no idle wake-ups outside of timers it actually needs.
    private var phaseChangeCancellable: AnyCancellable?

    /// In-flight Task spawned by handleRelease that owns the
    /// transcribe → command-route → expand → paste pipeline. Tracked
    /// so the user can abort during `.transcribing` and we won't
    /// silently push state forward when the result eventually arrives.
    private var transcribeTask: Task<Void, Never>?

    /// Identity of the current dictation. Bumped whenever a press actually
    /// starts a new recording, or a cancel discards a `.transcribing` /
    /// `.polishing` one. A background task captures the id it was started
    /// with; once `dictationID` moves past it, the task knows it's stale
    /// (see `isCurrent`) and stops touching phase/pastes it no longer owns,
    /// while still finishing writes (History, Notes, clipboard) that
    /// shouldn't be lost.
    private var dictationID = 0

    /// True when `id` is still the in-flight dictation. Callers use this to
    /// gate UI-visible side effects (phase, autoReset, PillWindow
    /// interactivity, Haptics/SoundCue) so a slow background task from an
    /// older dictation can't clobber a newer one.
    private func isCurrent(_ id: Int) -> Bool { id == dictationID }

    /// Phase snapshotted at the very start of `handlePress`, before the
    /// gate check or anything else can change it. A short tap needs this:
    /// by the time its decision runs, `state.phase` reflects the tap's own
    /// just-discarded recording, not the dictation that came before it.
    private var phaseAtPress: Phase = .idle

    /// True once `handlePress` has actually started a recording for the
    /// press currently in flight. False when the gate refused the press
    /// (already `.recording` / `.transcribing`) or mic access was denied,
    /// `handleShortTap` uses this to know whether there's a just-started
    /// recording to discard at all.
    private var pressStartedRecording = false

    /// Snapshot of the pending clean-first cleanup's inputs (Item 2b). Set
    /// when `startCleanupTask` begins, cleared when it finishes, either
    /// normally, or because the caller (a pre-empting `handlePress`, or an
    /// explicit `handleCancel`) is about to cancel it. Lets a pre-empting
    /// press record the discarded dictation to History instead of losing
    /// it silently, while a user-initiated cancel still discards it.
    private var pendingCleanupRecord: (raw: String, expanded: String, durMs: Int)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // PR C: one-time migration pinning existing users to `.server`
        // before Parakeet becomes the new-install default below. Must run
        // before anything else reads `transcriptionEngine`.
        Preferences.shared.migrateEngineDefaultIfNeeded()

        // Apply user's theme preference before any UI lands so the first
        // paint is correct and we avoid a flash to the system appearance.
        Preferences.shared.appearance.apply()

        MenuBarController.shared.install()

        // Start Sparkle's updater (scheduler + one-time consent prompt on
        // the second launch). This never triggers a check itself; the
        // `Updater.shared` access below just starts the controller Sparkle
        // needs to hand off to.
        _ = Updater.shared

        // Always-visible compact pill
        PillWindow.shared.showPersistent()

        // Mic permission up front
        Task {
            let granted = await AudioRecorder.requestMicAccess()
            state.micGranted = granted
        }

        // One-shot probe of the `claude` CLI. Drives the menu-bar warning
        // when cleanup is enabled but the binary isn't installed. Only runs
        // when cloud cleanup is actually selected — `which claude` stats every
        // $PATH entry, which triggers a "network volume" TCC prompt if any
        // PATH dir lives on a network mount. On-device users never use the
        // CLI, so skipping the probe removes that prompt for them.
        if Preferences.shared.cleanupMode != .off,
           Preferences.shared.llmBackend == .cloud {
            Task {
                let available = await ClaudeClient.shared.isAvailable()
                state.claudeAvailable = available
                NotificationCenter.default.post(name: .phaseChanged, object: nil)
            }
        }

        // Accessibility — show permission card animating out of the pill if not granted
        state.hotkeyGranted = HotkeyMonitor.isAccessibilityGranted()
        if !state.hotkeyGranted {
            state.showPermissionPrompt = true
            PillWindow.shared.setInteractive(true)
        }

        // Wire state → waveform. removeTap is synchronous, but a buffer
        // already in-flight on the audio render thread can deliver one
        // last callback after stop()/cancel(). Gate on phase so a stale
        // tail tick doesn't churn @Published subscribers (PillView
        // onChange) for nothing during transcribe/cleanup/idle.
        AudioRecorder.shared.onLevel = { [weak self] level in
            guard let self else { return }
            if case .recording = self.state.phase {
                self.state.level = level
            }
        }
        // QUAL-03: when the watchdog fires, treat as a normal release so
        // the pipeline finishes the dictation cleanly — better than just
        // dropping the audio.
        AudioRecorder.shared.onMaxDurationReached = { [weak self] in
            guard case .recording = self?.state.phase else { return }
            self?.handleRelease()
        }
        // Item 4: AirPods disconnecting (or any input-device change) mid-
        // recording stops the engine silently, without this the rest of
        // the speech is just gone. Treat it like the watchdog: finish the
        // dictation with whatever was captured so far instead of losing it.
        AudioRecorder.shared.onInputInterrupted = { [weak self] in
            guard case .recording = self?.state.phase else { return }
            NSLog("[ListenToMe] input device changed mid-recording")
            self?.handleRelease()
        }

        // Wire hotkey
        HotkeyMonitor.shared.onPress = { [weak self] in self?.handlePress() }
        HotkeyMonitor.shared.onRelease = { [weak self] in self?.handleRelease() }
        // CORR-01: short-tap of the hotkey opens the correction popover
        // (same behaviour as clicking the pill in success/polishing).
        HotkeyMonitor.shared.onShortTap = { [weak self] in self?.handleShortTap() }
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
        // Also warm HistoryStore so the legacy-JSON → NDJSON migration
        // runs at launch (otherwise it'd defer until the first add()).
        _ = HistoryStore.shared
        // M6: warm the SQLite-backed stores so their JSON → SQL
        // migration runs at launch rather than at first tab visit.
        // Each store is a thin façade that auto-imports its legacy
        // .json once and renames it to .json.bak.
        _ = SnippetsStore.shared
        _ = TransformsStore.shared

        // Warm the whisper context off-main so the first hotkey press
        // doesn't stall on the synchronous model load. Only the linked
        // engine uses the in-process context; server/CLI manage their own.
        if Preferences.shared.transcriptionEngine == .linked {
            WhisperLib.shared.preload()
        }

        // Warm Parakeet (Core ML / ANE) off-main when it's the active engine,
        // so the first dictation doesn't pay the model download/load.
        if Preferences.shared.transcriptionEngine == .parakeet {
            Task { try? await ParakeetEngine.shared.ensureReady() }
        }

        // Warm the on-device LLM too when local polish is selected and the
        // GGUF is present, so the first dictation doesn't pay the model load.
        if Preferences.shared.llmBackend == .local {
            let file = Preferences.shared.selectedLocalLLMModel.filename
            if LocalLLMEngine.shared.isReady(modelFile: file) {
                LocalLLMEngine.shared.preload(modelFile: file)
            }
        }

        // M3b: mine the existing history for single-word swaps that
        // claude cleanup consistently fixed (e.g. "danqua" → "Danquah").
        // Feeds CandidateStore via the same promotion pipeline used by
        // retype detection. Off-main, low-priority — never blocks
        // launch or audio.
        Task.detached(priority: .background) { [weak self] in
            await self?.runHistoryDictionaryMining()
        }

        // Emit phase-change notifications for menu bar — event-driven via
        // Combine instead of a 150ms polling loop so the app has zero idle
        // wake-ups beyond what it actually needs (#GSD Phase C-3).
        // Also clear AppState.partialText when leaving .recording so the
        // streaming preview doesn't bleed into the final paste's pill UI.
        phaseChangeCancellable = state.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                NotificationCenter.default.post(name: .phaseChanged, object: nil)
                if case .recording = phase {
                    // entering or staying in recording — preserve the partial
                } else if case .transcribing = phase {
                    // keep partial visible briefly through transcribing as a
                    // "finalizing what you saw" cue; cleared on next phase
                } else {
                    self?.state.partialText = ""
                }
                // A failure should be felt, not just seen — success already
                // taps, this balances it. Fired centrally so every .error
                // path (mic, record, transcribe, command, cleanup) gets it.
                if case .error = phase { Haptics.error() }
            }

        // First-run onboarding. Deferred one runloop tick so the menu bar +
        // pill are installed before the panel takes key focus. Shown once;
        // completing it (or closing) sets the flag. Skipped under tests:
        // the test host reads `hasCompletedOnboarding` from its own
        // isolated defaults suite (always unset on a fresh run), and
        // popping the onboarding panel mid-test-run would steal key focus.
        if !RuntimeEnvironment.isRunningUnderTests && !Preferences.shared.hasCompletedOnboarding {
            DispatchQueue.main.async {
                OnboardingWindow.shared.present {
                    Preferences.shared.hasCompletedOnboarding = true
                }
            }
        }
    }

    /// Tear down long-lived subprocesses cleanly on quit so we don't
    /// leave whisper-server (or anything else with a port bound) running
    /// after the app exits.
    func applicationWillTerminate(_ notification: Notification) {
        WhisperServer.shared.shutdown()
        WhisperLib.shared.shutdown()
        LocalLLMEngine.shared.shutdown()
        ParakeetEngine.shared.shutdown()
        Database.shared.close()
    }

    /// M3b: read history snapshot on main, run pure mining off-main,
    /// hand results back to CandidateStore on main.
    private func runHistoryDictionaryMining() async {
        let snapshot: [(rawText: String, finalText: String, bundleId: String?)] = await MainActor.run {
            HistoryStore.shared.records.map {
                (rawText: $0.rawText, finalText: $0.finalText, bundleId: $0.bundleId)
            }
        }
        // Pure analysis off-main.
        let swaps = HistoryDictionaryMiner.mine(records: snapshot)
        guard !swaps.isEmpty else { return }
        await MainActor.run {
            CandidateStore.shared.ingestMined(swaps)
        }
    }

    // MARK: - Hotkey handlers

    private func handlePress() {
        // Snapshot BEFORE anything (even the gate check) can change the
        // phase. `handleShortTap` needs the phase this press interrupted,
        // not the phase left behind by the short recording it starts.
        phaseAtPress = state.phase
        pressStartedRecording = false

        // Ignore a press while recording (already live) or transcribing
        // (short, ~1s; starting a second recording here used to strand the
        // mic once the old transcribeTask finished and overwrote
        // state.phase). If a previous cleanup is still running we cancel
        // it: its deferred paste would land in an old app/context and
        // shouldn't execute. Also dismiss any open correction popover so
        // the new dictation has a clean slate.
        guard DictationGate.acceptsPress(in: state.phase) else { return }
        // Item 2b: a press pre-empting a still-running clean-first cleanup
        // (phase == .polishing) is about to cancel it below. Nothing has
        // pasted yet, but the words are real, record them to History
        // before the cancel, instead of the cleanup's CancellationError
        // branch silently dropping them.
        if let pending = pendingCleanupRecord {
            HistoryStore.shared.add(rawText: pending.raw, finalText: pending.expanded,
                                     durationMs: pending.durMs, bundleId: nil)
            NSLog("[ListenToMe] pre-empted pending cleanup, recorded to history")
            pendingCleanupRecord = nil
        }
        cleanupTask?.cancel()
        cleanupTask = nil
        retypeTask?.cancel()
        retypeTask = nil
        // Cancel any pending auto-reset. Without this, dictating again
        // shortly after a previous dictation let its autoReset(after:) fire
        // mid-recording and set .idle, so the eventual release was ignored
        // and the mic stayed on.
        autoResetTask?.cancel()
        autoResetTask = nil
        if case .correcting = state.phase {
            CorrectionWindow.shared.dismiss()
        }

        // Mic permission is cached at launch; if the user grants it later
        // in System Settings, re-read the live status now rather than
        // showing "Mic permission needed" on every press until relaunch.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            state.micGranted = true
        }
        guard state.micGranted else {
            state.phase = .error(message: "Mic permission needed")
            autoReset()
            return
        }

        do {
            // Streaming partials need an in-memory sample accumulator
            // alongside the WAV write. Gate on the user pref so the
            // common case (off) pays zero allocation.
            let streamPartials = Preferences.shared.streamingPartialsEnabled
                && Preferences.shared.transcriptionEngine == .linked
            _ = try AudioRecorder.shared.start(accumulateSamples: streamPartials)
            // Only bump the dictation id once the recorder actually started,
            // so a failed start below doesn't orphan the previous dictation's
            // still-in-flight background work.
            dictationID &+= 1
            pressStartedRecording = true
            recordingStartedAt = Date()
            PillWindow.shared.repositionToActiveScreen()
            state.phase = .recording
            Haptics.start()
            SoundCue.recordingStart()
            PillWindow.shared.setInteractive(true)
            // Begin polling after the recording state is published so
            // PillView is already showing the recording UI when the
            // first partial lands.
            if streamPartials {
                PartialTranscriber.shared.start()
            }
        } catch {
            state.phase = .error(message: "Record failed")
            // pill animates via SwiftUI phase change
            autoReset()
        }
    }

    /// Single entry point for "user wants out NOW", regardless of phase.
    /// .recording → discard audio + history dismissed row.
    /// .transcribing → cancel whisper task; the result (if it arrives)
    ///                 short-circuits via Task.isCancelled.
    /// .polishing → cancel cleanup; raw transcript already pasted, leave
    ///              it standing (user can correct if they want).
    /// Any other phase → no-op.
    private func handleCancel() {
        switch state.phase {
        case .recording:
            PartialTranscriber.shared.stop()
            state.partialText = ""
            AudioRecorder.shared.cancel()
            Haptics.stop()
            PillWindow.shared.setInteractive(false)
            HistoryStore.shared.add(rawText: "", finalText: "", durationMs: 0, dismissed: true)
            recordingStartedAt = nil
            state.level = 0   // clear stale tail so a fast re-entry starts cold
            state.phase = .idle
        case .transcribing:
            dictationID &+= 1
            transcribeTask?.cancel()
            transcribeTask = nil
            // Don't shut down WhisperServer — the model load is shared
            // across dictations and the next press will reuse it.
            recordingStartedAt = nil
            PillWindow.shared.setInteractive(false)
            state.phase = .idle
        case .polishing:
            // Clean-first: cleanup is still running and nothing has been
            // pasted yet. Cancel BOTH cleanupTask and transcribeTask:
            // Notes, Clipboard, and Backtrack delivery all run inside
            // transcribeTask itself, so cancelling only cleanupTask let
            // them finish and write anyway after the user hit cancel.
            // Bumping dictationID too so any check further down the
            // pipeline treats this dictation as stale.
            dictationID &+= 1
            // Explicit discard (the X, not a pre-empting press): drop the
            // pending record rather than adding it to History.
            pendingCleanupRecord = nil
            cleanupTask?.cancel()
            cleanupTask = nil
            transcribeTask?.cancel()
            transcribeTask = nil
            PillWindow.shared.setInteractive(false)
            state.phase = .idle
            autoReset(after: 0.6)
        default:
            return
        }
    }

    private func handleRelease() {
        guard case .recording = state.phase else { return }
        Haptics.stop()
        SoundCue.recordingStop()
        PillWindow.shared.setInteractive(false)
        // Stop the streaming-partial loop BEFORE the final transcribe
        // so the WhisperLib busy-gate is clear. Don't wipe partialText
        // immediately — let it linger through .transcribing as a
        // "we're finalizing what you saw" signal; the success-paste
        // branch below clears it.
        PartialTranscriber.shared.stop()
        guard let wav = AudioRecorder.shared.stop() else {
            state.phase = .error(message: "No audio")
            autoReset()
            return
        }
        state.level = 0   // mute waveform during transcribe/cleanup
        // Keep the pill interactive so the cancel X added in .transcribing
        // and .polishing actually receives clicks.
        PillWindow.shared.setInteractive(true)
        state.phase = .transcribing

        let whisperPrompt = DictionaryStore.shared.whisperPrompt
        // Snapshot this dictation's identity and start time before the task
        // begins, and clear recordingStartedAt right away. Without the local
        // copy, an old task reading recordingStartedAt after a new press
        // started the next recording would compute that NEXT recording's
        // duration instead of its own.
        let id = dictationID
        let startedAt = recordingStartedAt
        recordingStartedAt = nil
        transcribeTask?.cancel()
        transcribeTask = Task { @MainActor in
            do {
                let transcribed = try await WhisperRunner.shared.transcribe(wav: wav, prompt: whisperPrompt)
                // User aborted via the cancel button while we were waiting
                // on whisper: bail before mutating any pipeline state.
                if Task.isCancelled { return }
                // Drop engine-emitted non-speech markers ("[BLANK_AUDIO]" etc.)
                // so a silent recording is treated as empty rather than pasting
                // the literal marker into the target app and History.
                let raw = TranscriptHygiene.stripNonSpeechMarkers(transcribed)
                if raw.isEmpty {
                    // Silence or a pure non-speech marker: paste nothing and
                    // show a calm cue rather than a red error — this wasn't a
                    // failure, there was just nothing to type.
                    if self.isCurrent(id) {
                        PillWindow.shared.setInteractive(false)
                        self.state.phase = .noSpeech
                        self.autoReset(after: 0.8)
                    }
                    return
                }

                // Backtrack interception — runs BEFORE other commands and
                // before cleanup. If the user said "actually, …" / "scratch
                // that, …" AND we have a still-valid lastPasteToken, ask
                // Claude to revise the prior paste in place rather than
                // pasting new text.
                if let bt = Backtrack.parse(raw),
                   let token = self.lastPasteToken,
                   !token.pastedText.isEmpty {
                    do {
                        if self.isCurrent(id) {
                            PillWindow.shared.setInteractive(true)
                            self.state.phase = .polishing(rawPreview: "revising…")
                        }
                        let revised = try await ClaudeClient.shared.rewrite(
                            original: token.pastedText,
                            revision: bt.revision,
                            timeout: TimeInterval(Preferences.shared.cleanupTimeoutSec)
                        )
                        if Task.isCancelled { return }
                        if !self.isCurrent(id) {
                            // A newer dictation is already recording. Don't
                            // send Cmd+Z/Cmd+V into it, and don't fall through
                            // either: the normal pipeline would paste too. Keep
                            // the utterance in History so nothing is lost.
                            NSLog("[ListenToMe] backtrack: superseded by a newer dictation, not applied")
                            let durMs = startedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                            HistoryStore.shared.add(rawText: raw, finalText: raw,
                                                     durationMs: durMs, dismissed: true)
                            return
                        } else if let newToken = Paster.replace(with: revised, token: token) {
                            self.lastPasteToken = newToken
                            self.state.lastTranscript = revised
                            HistoryStore.shared.updateLast(finalText: revised)
                            let durMs = startedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                            HistoryStore.shared.add(rawText: raw, finalText: "[backtrack]",
                                                     durationMs: durMs, dismissed: true,
                                                     bundleId: newToken.bundleId)
                            Haptics.success()
                            self.state.phase = .success(preview: String(revised.prefix(30)))
                            self.autoReset(after: 1.5)
                            return
                        } else {
                            // Validation gate failed — pasteboard moved on,
                            // user switched apps, etc. Fall through to
                            // normal pipeline so the revision phrase still
                            // reaches the user as a normal dictation.
                            NSLog("[ListenToMe] backtrack: replace gate failed, falling back to normal pipeline")
                        }
                    } catch {
                        NSLog("[ListenToMe] backtrack rewrite failed: \(error), falling back to normal pipeline")
                        // Fall through and treat the utterance as a normal dictation.
                    }
                }

                // Voice-command interception — runs BEFORE cleanup on the raw
                // text. Opt-in: "log today" writes to ~/Documents/daily and
                // "shell" runs /bin/sh, so it's gated behind a Privacy toggle.
                if Preferences.shared.voiceCommandsEnabled, let cmd = CommandRouter.parse(raw) {
                    // Nothing set the phase before this point (transcribe
                    // ended in `.transcribing`), so without this the pill
                    // sits on "transcribing" for however long the command
                    // takes to run.
                    if self.isCurrent(id) {
                        self.state.phase = .polishing(rawPreview: "running…")
                        PillWindow.shared.setInteractive(true)
                    }
                    do {
                        let summary = try await CommandRouter.execute(cmd)
                        if Task.isCancelled { return }
                        let durMs = startedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                        HistoryStore.shared.add(rawText: raw, finalText: "[cmd] \(summary)", durationMs: durMs)
                        if self.isCurrent(id) {
                            Haptics.success()
                            self.state.phase = .success(preview: summary)
                            self.autoReset(after: 1.0)
                        }
                        return
                    } catch {
                        if Task.isCancelled { return }
                        if CommandRouter.fallsBackToDictation(on: cmd) {
                            // "Open the PR and merge it" parses as .openApp
                            // because it starts with "open ", when `open -a`
                            // fails, that was never really an app-launch
                            // command, so fall through to the normal
                            // dictation pipeline instead of eating the words
                            // behind "Command failed".
                            NSLog("[ListenToMe] command failed, falling back to dictation: \(error)")
                        } else {
                            NSLog("[ListenToMe] command failed: \(error)")
                            if self.isCurrent(id) {
                                self.state.phase = .error(message: "Command failed")
                                self.autoReset()
                            }
                            return
                        }
                    }
                }

                // Voice-editing commands (comma, period, scratch that, new
                // paragraph) run on the raw transcript before snippets and
                // cleanup. Pure transform; deterministic punctuation never
                // depends on the LLM's mood.
                let edited = VoiceEditor.apply(
                    raw,
                    terms: VoiceEditor.canonicalTerms(from: DictionaryStore.shared.entries.map(\.word)))

                // Pure-undo edge case: user said only "scratch that" (or it
                // resolved to empty). Skip paste, no history, brief feedback.
                if edited.isEmpty {
                    let durMs = startedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                    HistoryStore.shared.add(rawText: raw, finalText: "",
                                             durationMs: durMs, dismissed: true)
                    if self.isCurrent(id) {
                        self.state.phase = .success(preview: "(scratched)")
                        self.autoReset(after: 0.6)
                    }
                    return
                }

                // Snippet expansion runs BEFORE cleanup so the cleaned result
                // flows naturally around the expanded text.
                let expanded = SnippetsStore.shared.expand(in: edited)
                let words = expanded.split(whereSeparator: \.isWhitespace).count
                let durMs = startedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0

                // Secure-input guard. If a password field (or any secure-event-
                // input context) has focus, never insert the transcript and
                // never store it in history — doing either would leak a secret
                // the user is plainly typing. Covers both cleanup branches below.
                if SecureInput.isActive {
                    self.lastRawTranscript = nil
                    if self.isCurrent(id) {
                        self.state.phase = .error(message: "Secure field — not inserted")
                        self.autoReset()
                    }
                    return
                }

                self.lastRawTranscript = raw

                // Route on the user's output destination. .activeApp keeps the
                // streaming paste → background-cleanup → replace pipeline; the
                // Apple Notes path cleans to completion (Notes has no
                // undo-replace) then writes the note off-main.
                switch Preferences.shared.outputDestination {
                case .appleNotes:
                    await self.deliverToNotes(id: id, raw: raw, expanded: expanded,
                                              words: words, durMs: durMs)

                case .clipboard:
                    await self.deliverToClipboard(id: id, raw: raw, expanded: expanded,
                                                  words: words, durMs: durMs)

                case .activeApp:
                    // Clean FIRST, then paste exactly once. The old flow pasted
                    // the raw transcript immediately and later swapped in the
                    // polished version via Cmd+Z (undo) + Cmd+V — but in apps
                    // where Cmd+Z isn't text-undo (terminals), the undo no-op'd
                    // and the cleaned text landed *after* the raw, duplicating
                    // the dictation. Pasting once, after cleanup, has nothing to
                    // undo. Trade-off: text appears after cleanup rather than
                    // streaming in raw first.
                    if CleanupGate.shouldClean(text: expanded, wordCount: words,
                                               mode: Preferences.shared.cleanupMode) {
                        // Capture the focused app now for context-aware tone; we
                        // paste into it once cleanup returns.
                        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                        if self.isCurrent(id) {
                            self.state.phase = .polishing(rawPreview: String(expanded.prefix(40)))
                            PillWindow.shared.setInteractive(true)
                        }
                        self.startCleanupTask(id: id, raw: raw, expanded: expanded,
                                             durMs: durMs, bundleId: bundleId)
                    } else {
                        // No-cleanup mode: still paste-tracked so the user can
                        // open the correction popover; we just never call replace.
                        self.state.lastTranscript = expanded
                        let token = Paster.pasteTracked(expanded)
                        self.lastPasteToken = token
                        self.scheduleRetypeDetection(token: token)
                        self.recordStyleSample(token: token, cleaned: expanded)
                        HistoryStore.shared.add(rawText: raw, finalText: expanded,
                                                 durationMs: durMs, bundleId: token.bundleId)
                        if self.isCurrent(id) {
                            Haptics.success()
                            SoundCue.success()
                            self.state.phase = .success(preview: String(expanded.prefix(30)))
                            PillWindow.shared.setInteractive(true)
                            // Longer success window so the user has time to click the
                            // pill if they want to correct.
                            self.autoReset(after: 3.0)
                        }
                    }
                }
            } catch WhisperError.modelNotFound(let path) {
                NSLog("[ListenToMe] model not found: \(path)")
                if self.isCurrent(id) {
                    self.state.phase = .error(message: "Model missing")
                    self.autoReset()
                }
            } catch {
                NSLog("[ListenToMe] transcription failed: \(error)")
                if self.isCurrent(id) {
                    self.state.phase = .error(message: "Transcribe failed")
                    self.autoReset()
                }
            }
        }
    }

    /// Apple Notes destination: clean to completion (subject to the gate),
    /// then write the polished text into Notes. No paste, no replace, no
    /// correction popover — Notes is a one-shot sink. History is recorded so
    /// the dashboard/History still reflect the dictation.
    private func deliverToNotes(id: Int, raw: String, expanded: String,
                                words: Int, durMs: Int) async {
        // No paste target on this path — clear any stale token so a later
        // "actually, …" backtrack can't revise into a previous active-app paste.
        lastPasteToken = nil

        if isCurrent(id) {
            state.phase = .polishing(rawPreview: String(expanded.prefix(40)))
            PillWindow.shared.setInteractive(true)
        }

        var finalText = expanded
        if CleanupGate.shouldClean(text: expanded, wordCount: words,
                                   mode: Preferences.shared.cleanupMode) {
            do {
                let timeout = TimeInterval(Preferences.shared.cleanupTimeoutSec)
                finalText = try await ClaudeClient.shared.clean(
                    expanded, bundleId: nil, timeout: timeout)
            } catch {
                NSLog("[ListenToMe] notes cleanup failed, raw stands: \(error)")
                finalText = expanded
            }
        }
        // User cancelled while cleanup was running: no Notes write, no history.
        if Task.isCancelled { return }

        // No cancel check after the write: once the note exists, History
        // must reflect it.
        let result = await OutputRouter.deliverToNotes(text: finalText)
        switch result {
        case .success:
            state.lastTranscript = finalText
            HistoryStore.shared.add(rawText: raw, finalText: finalText,
                                     durationMs: durMs, bundleId: "com.apple.Notes")
            if isCurrent(id) {
                Haptics.success()
                SoundCue.success()
                state.phase = .success(preview: "Saved to Notes")
                autoReset(after: 2.0)
            }
        case .failure(let err):
            NSLog("[ListenToMe] notes write failed: \(err)")
            if isCurrent(id) {
                state.phase = .error(message: "Notes write failed")
                autoReset()
            }
        }
        if isCurrent(id) {
            PillWindow.shared.setInteractive(false)
        }
    }

    /// Clipboard destination: clean to completion (subject to the gate), copy
    /// to the pasteboard WITHOUT simulating Cmd+V, and record history. The
    /// user pastes when they're ready. No replace, no correction popover.
    private func deliverToClipboard(id: Int, raw: String, expanded: String,
                                    words: Int, durMs: Int) async {
        // No paste target on this path — clear any stale token so a later
        // "actually, …" backtrack can't revise into a previous active-app paste.
        lastPasteToken = nil

        if isCurrent(id) {
            state.phase = .polishing(rawPreview: String(expanded.prefix(40)))
            PillWindow.shared.setInteractive(true)
        }

        var finalText = expanded
        if CleanupGate.shouldClean(text: expanded, wordCount: words,
                                   mode: Preferences.shared.cleanupMode) {
            do {
                let timeout = TimeInterval(Preferences.shared.cleanupTimeoutSec)
                finalText = try await ClaudeClient.shared.clean(
                    expanded, bundleId: nil, timeout: timeout)
            } catch {
                NSLog("[ListenToMe] clipboard cleanup failed, raw stands: \(error)")
                finalText = expanded
            }
        }
        // User cancelled while cleanup was running: no clipboard write, no history.
        if Task.isCancelled { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(finalText, forType: .string)

        state.lastTranscript = finalText
        HistoryStore.shared.add(rawText: raw, finalText: finalText,
                                 durationMs: durMs, bundleId: nil)
        if isCurrent(id) {
            Haptics.success()
            SoundCue.success()
            state.phase = .success(preview: "Copied to clipboard")
            autoReset(after: 2.0)
        }
    }

    /// Run cleanup, then paste the polished text into the focused app exactly
    /// once. Nothing is pasted until cleanup returns, so there is no earlier
    /// paste to undo — this replaces the old stream-raw-then-Cmd+Z-replace
    /// flow, which duplicated text in apps where Cmd+Z isn't text-undo
    /// (terminals). On cleanup failure the raw (`expanded`) is pasted instead.
    /// Cancellation (new dictation / user bail) aborts before any paste.
    /// Before that paste, `PasteTarget.decide` re-checks the frontmost app
    /// and secure-input state, since cleanup can take seconds: a secure
    /// field blocks the paste entirely, and a changed frontmost app copies
    /// to the clipboard instead of pasting into whatever's there now.
    /// `bundleId` is the frontmost app when cleanup started, used as the
    /// expected target for that check.
    private func startCleanupTask(id: Int,
                                  raw: String,
                                  expanded: String,
                                  durMs: Int,
                                  bundleId: String?) {
        cleanupTask?.cancel()
        // Item 2b: remember these inputs so a pre-empting press can record
        // the dictation to History if it cancels us before we paste.
        // Cleared below once we actually finish (paste, copy, or block),
        // by then the caller no longer needs it.
        pendingCleanupRecord = (raw: raw, expanded: expanded, durMs: durMs)
        cleanupTask = Task { [weak self] in
            var finalText = expanded
            do {
                let timeout = TimeInterval(Preferences.shared.cleanupTimeoutSec)
                finalText = try await ClaudeClient.shared.clean(
                    expanded,
                    bundleId: bundleId,
                    timeout: timeout
                )
                try Task.checkCancellation()
            } catch is CancellationError {
                // New dictation started OR the user bailed. Whoever
                // cancelled us already recorded (or deliberately dropped)
                // pendingCleanupRecord, so there's nothing left to do here.
                return
            } catch {
                NSLog("[ListenToMe] cleanup failed, raw stands: \(error)")
                finalText = expanded
            }
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.pendingCleanupRecord = nil

                // Cleanup can take seconds; re-check the target now rather
                // than trusting the bundleId captured before cleanup
                // started — the user may have switched apps or focused a
                // password field while we were waiting.
                let currentBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                switch PasteTarget.decide(expectedBundleId: bundleId,
                                          currentBundleId: currentBundleId,
                                          secureInputActive: SecureInput.isActive) {
                case .block:
                    // Same contract as the pre-cleanup secure-field guard:
                    // never insert, never store.
                    self.lastRawTranscript = nil
                    if self.isCurrent(id) {
                        self.state.phase = .error(message: "Secure field — not inserted")
                        self.autoReset()
                    }
                    return

                case .copyInstead:
                    // Deliberate copy, not a paste — no restore-on-timer
                    // like the correction flow uses.
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(finalText, forType: .string)
                    self.lastPasteToken = nil
                    self.state.lastTranscript = finalText
                    HistoryStore.shared.add(rawText: raw, finalText: finalText,
                                             durationMs: durMs, bundleId: nil)
                    if self.isCurrent(id) {
                        self.state.phase = .success(preview: "Copied (app changed)")
                        self.autoReset(after: 2.0)
                    }

                case .paste:
                    let token = Paster.pasteTracked(finalText)
                    self.lastPasteToken = token
                    self.state.lastTranscript = finalText
                    self.scheduleRetypeDetection(token: token)
                    self.recordStyleSample(token: token, cleaned: finalText)
                    HistoryStore.shared.add(rawText: raw, finalText: finalText,
                                             durationMs: durMs, bundleId: token.bundleId)
                    if self.isCurrent(id) {
                        self.state.phase = .success(preview: String(finalText.prefix(30)))
                        self.autoReset(after: 3.0)
                    }
                }
            }
        }
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

    /// Reused across calls — ISO8601DateFormatter is expensive to instantiate.
    private static let retypeLogTimestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    /// Hard cap on retype-debug.log size before rotation. When the file
    /// crosses this threshold the current contents move to `.log.1` (single
    /// generation kept) and a fresh log starts. Bounds long-term disk use
    /// for a strictly diagnostic file.
    private static let retypeLogMaxBytes: Int = 1_048_576

    /// Append a line to ~/Library/Application Support/ListenToMe/retype-debug.log.
    /// Used for diagnostics because macOS unified logging redacts Swift NSLog
    /// string interpolations as `<private>` by default. Gated behind
    /// `Preferences.diagnosticsEnabled` (default false) — no-op when off, so
    /// shipping users get no disk writes from retype detection.
    private func retypeDebug(_ line: String) {
        guard Preferences.shared.diagnosticsEnabled else { return }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("retype-debug.log")

        // Rotate: if the existing log is at/over the cap, move it aside
        // (single generation) before appending. Cheap stat check.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue >= Self.retypeLogMaxBytes {
            let rotated = dir.appendingPathComponent("retype-debug.log.1")
            try? FileManager.default.removeItem(at: rotated)
            try? FileManager.default.moveItem(at: url, to: rotated)
        }

        let stamp = Self.retypeLogTimestampFormatter.string(from: Date())
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

    /// CORR-01: a short tap of the hotkey opens the correction popover.
    /// The press half of the tap already started a recording (there's no
    /// way to know it's a tap, not a hold, until the release); discard that
    /// recording silently, no history row, nothing pasted, then decide
    /// whether to open correction from `phaseAtPress`, the phase the tap
    /// interrupted, NOT `state.phase` (which by now just reflects the
    /// tap's own discarded recording).
    private func handleShortTap() {
        guard pressStartedRecording else {
            // The press half of this tap never actually started a
            // recording (the gate refused it, or mic access was denied),
            // so there's nothing to discard and no new context to weigh in.
            return
        }
        pressStartedRecording = false

        PartialTranscriber.shared.stop()
        state.partialText = ""
        AudioRecorder.shared.cancel()
        Haptics.stop()
        PillWindow.shared.setInteractive(false)
        recordingStartedAt = nil
        state.level = 0
        dictationID &+= 1

        let hasToken = lastPasteToken.map { !$0.pastedText.isEmpty } ?? false
        if ShortTapPolicy.opensCorrection(phaseAtPress: phaseAtPress, hasPasteToken: hasToken),
           let token = lastPasteToken {
            openCorrection(token: token)
        } else {
            state.phase = .idle
        }
    }

    /// Clicking the pill opens the correction popover. Only offered right
    /// after a paste actually landed (`.success`), during `.polishing`
    /// (clean-first) nothing has pasted yet, so tapping there used to open
    /// correction on the PREVIOUS dictation's token. Keep in sync with
    /// `PillView.isPillTappable`.
    private func handlePillTap() {
        switch state.phase {
        case .success: break
        default: return
        }
        guard let token = lastPasteToken, !token.pastedText.isEmpty else { return }
        openCorrection(token: token)
    }

    private func openCorrection(token: PasteToken) {
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
            // Auto-reset must never yank an active recording/transcription
            // (or the correction popover / suggestion banner) back to idle.
            // (Phase 4 A4: the .suggestion banner also cancels this task on
            // entry, but this is a belt-and-braces guard.)
            guard DictationGate.allowsAutoReset(in: self.state.phase) else { return }
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
