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

    func applicationWillTerminate(_ notification: Notification) {
        APIServer.shared.stop()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        MenuBarController.shared.install()

        // Always-visible compact pill
        PillWindow.shared.showPersistent()

        // Bring up claude_local_api in the background so cleanup works after reboot
        Task { await APIServer.shared.startIfNeeded() }

        // Mic permission up front
        Task {
            let granted = await AudioRecorder.requestMicAccess()
            state.micGranted = granted
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
        guard case .idle = state.phase else { return }
        guard state.micGranted else {
            state.phase = .error(message: "Mic permission needed")
            autoReset()
            return
        }

        do {
            _ = try AudioRecorder.shared.start()
            recordingStartedAt = Date()
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

                // Snippet expansion runs BEFORE cleanup so the cleaned result
                // flows naturally around the expanded text.
                let expanded = SnippetsStore.shared.expand(in: raw)

                // Cleanup via claude_local_api — only when the cleanup mode says so.
                let words = expanded.split(whereSeparator: \.isWhitespace).count
                let output: String
                if Preferences.shared.cleanupMode.shouldClean(wordCount: words) {
                    state.phase = .cleaning
                    do {
                        let cleaned = try await ClaudeClient.shared.clean(expanded)
                        output = cleaned.isEmpty ? expanded : cleaned
                    } catch {
                        NSLog("[ListenToMe] cleanup failed, using raw: \(error)")
                        output = expanded
                    }
                } else {
                    output = expanded
                }
                state.lastTranscript = output
                Paster.paste(output)
                Haptics.success()
                SoundCue.success()

                // Record in history
                let durMs = recordingStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
                recordingStartedAt = nil
                HistoryStore.shared.add(
                    rawText: raw,
                    finalText: output,
                    durationMs: durMs
                )

                state.phase = .success(preview: String(output.prefix(30)))
                autoReset(after: 0.8)
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

    private func autoReset(after seconds: Double = 1.4) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.state.phase = .idle
            // pill contracts via SwiftUI phase change
        }
    }
}
