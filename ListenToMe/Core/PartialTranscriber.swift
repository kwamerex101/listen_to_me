import Foundation

/// Drives the M5' streaming-partial-transcripts loop. While the user
/// holds the hotkey, periodically grabs the in-progress samples from
/// `AudioRecorder.currentSamples()`, runs a fast `WhisperLib.transcribe`
/// pass against them, and posts the result to `AppState.partialText`
/// so the pill can render a live preview.
///
/// Design choices:
/// - 1.5 s cadence (not 500 ms): partial passes on sub-second audio
///   chunks hallucinate ("[BLANK_AUDIO]", generic phrases). 1.5 s is
///   tight enough to feel live, slow enough to be coherent.
/// - First pass deferred by 2.0 s: whisper-base hallucinates badly on
///   < 1 s audio. By 2.0 s the user has typically said something
///   meaningful.
/// - `WhisperLib.isBusy` gate: if a partial is still running when the
///   next tick fires, skip — don't queue. The audio is still
///   accumulating; the next tick will see more.
/// - Hallucination filter: well-known whisper-on-silence outputs
///   (`[BLANK_AUDIO]`, `[SILENCE]`, `(silence)`, `Thank you.`,
///   `you`, etc.) are dropped instead of shown.
/// - `stop()` cancels the in-flight task; `AppState.partialText` is
///   cleared by the caller (AppDelegate) so the final transcript
///   pasted into the target app doesn't briefly show through the pill.
@MainActor
final class PartialTranscriber {
    static let shared = PartialTranscriber()

    /// Polling cadence. Conservative — see class doc.
    private let pollInterval: TimeInterval = 1.5
    /// Defer the first pass until at least this much audio is in the
    /// accumulator. Avoids whisper-on-silence hallucinations.
    private let warmupSeconds: TimeInterval = 2.0
    /// 16 kHz mono → 32k samples per warmup-second.
    private var warmupSampleCount: Int { Int(16_000 * warmupSeconds) }

    /// Common whisper outputs on silence / blank audio. Lowercased
    /// match. Dropped before posting to AppState.partialText.
    /// Nonisolated so the pure `filterHallucination` can access it
    /// without crossing the MainActor.
    nonisolated private static let hallucinations: Set<String> = [
        "[blank_audio]",
        "[silence]",
        "(silence)",
        "[music]",
        "[ music ]",
        "thank you.",
        "thank you",
        "you",
        ".",
        "...",
    ]

    private var loopTask: Task<Void, Never>?
    private var isStarted = false

    private init() {}

    /// Begin polling. No-op when already started or when the user has
    /// not opted into streaming. AppDelegate calls this on entering
    /// `.recording`.
    func start() {
        guard !isStarted else { return }
        guard Preferences.shared.streamingPartialsEnabled else { return }
        guard Preferences.shared.transcriptionEngine == .linked else {
            NSLog("[ListenToMe] streaming partials skipped — engine is .server (linked required)")
            return
        }
        guard WhisperLib.shared.isReady else {
            NSLog("[ListenToMe] streaming partials skipped — model not downloaded yet")
            return
        }
        isStarted = true
        AppState.shared.partialText = ""
        loopTask = Task { @MainActor [weak self] in
            await self?.runLoop()
        }
    }

    /// Stop polling. Idempotent. AppDelegate calls this on
    /// `.transcribing` entry, on cancel, and on phase exit.
    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isStarted = false
        // Don't clear AppState.partialText here — caller decides
        // whether the partial should briefly remain visible (e.g.
        // during the .transcribing phase to avoid a flicker) or be
        // wiped immediately.
    }

    // MARK: - Loop

    private func runLoop() async {
        // Poll ~5x per second until we have enough audio to start.
        while !Task.isCancelled {
            let samples = AudioRecorder.shared.currentSamples()
            if samples.count >= warmupSampleCount { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        if Task.isCancelled { return }

        // Now run partial passes at the configured cadence until
        // cancelled. Skip if a previous partial is still in flight.
        while !Task.isCancelled {
            let samples = AudioRecorder.shared.currentSamples()
            if !samples.isEmpty {
                await runOnePartial(samples: samples)
            }
            if Task.isCancelled { return }
            try? await Task.sleep(for: .seconds(pollInterval))
        }
    }

    private func runOnePartial(samples: [Float]) async {
        do {
            // No prompt for partials — DictionaryStore biasing applies
            // to the FINAL pass on release; partials are throwaway
            // previews.
            let raw = try await WhisperLib.shared.transcribe(samples: samples, prompt: nil)
            let cleaned = Self.filterHallucination(raw)
            if !cleaned.isEmpty, !Task.isCancelled {
                AppState.shared.partialText = cleaned
            }
        } catch WhisperLib.LibError.alreadyBusy {
            // Previous tick still running — skip this one. The next
            // tick sees newer audio anyway.
        } catch {
            // Any other failure (model not found, inference error)
            // stops the loop silently; the final pass at hotkey
            // release will surface a real error if there's a real
            // problem.
            NSLog("[ListenToMe] partial transcribe error (giving up loop): \(error)")
            loopTask?.cancel()
        }
    }

    /// Drop common whisper-on-silence hallucinations. Returns "" when
    /// the input matches a known empty-audio pattern; the caller skips
    /// the AppState update so the previous (real) partial stays
    /// visible. `nonisolated` because it's pure — tests call directly
    /// without spinning up the singleton.
    nonisolated static func filterHallucination(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if hallucinations.contains(trimmed.lowercased()) { return "" }
        return trimmed
    }
}
