import Accelerate
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
/// - First pass deferred by 1.0 s: whisper-base hallucinates badly on
///   < 1 s audio. At 1.0 s there's usually a word or two to show; the
///   hallucination filter below catches the residual silence outputs,
///   and the next tick (1.5 s later) corrects any junk.
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
    private let warmupSeconds: TimeInterval = 1.0
    /// 16 kHz mono → 32k samples per warmup-second.
    private var warmupSampleCount: Int { Int(16_000 * warmupSeconds) }
    /// Partial passes only transcribe the most recent slice of audio.
    /// The preview renders two head-truncated lines (the transcript
    /// tail), so re-transcribing the whole accumulated buffer every
    /// tick is O(n²) waste — a 60 s hold would re-process the first
    /// second forty times. 15 s comfortably fills two preview lines
    /// at normal speech rate while keeping per-tick cost constant.
    /// Window-start can clip a word mid-syllable; acceptable for a
    /// throwaway preview whose head is truncated out of view anyway.
    nonisolated private static let maxWindowSamples = 15 * 16_000

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
    /// Dictionary biasing prompt, snapshotted once per dictation in
    /// `start()`. Entries can't change mid-hold, and snapshotting avoids
    /// re-reading the store on every tick.
    private var dictionaryPrompt: String?

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
        dictionaryPrompt = DictionaryStore.shared.whisperPrompt
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
                await runOnePartial(samples: Array(samples.suffix(Self.maxWindowSamples)))
            }
            if Task.isCancelled { return }
            try? await Task.sleep(for: .seconds(pollInterval))
        }
    }

    /// Linear RMS below which the whole accumulated buffer counts as
    /// silence (~-40 dBFS). Whisper hallucinates fluent text on silent
    /// input; skipping the pass entirely is both more correct and
    /// cheaper than transcribe-then-filter.
    nonisolated private static let silenceRMSThreshold: Float = 0.01

    /// True when the buffer contains no speech-level energy anywhere.
    /// Checked per 0.5 s window, not whole-buffer: a single whole-buffer
    /// RMS dilutes — one second of quiet speech inside a long pause-heavy
    /// hold would average below the threshold and wrongly mute partials
    /// mid-dictation. Any window with energy ⇒ not silent, so once the
    /// user has spoken the gate stays open for the rest of the hold.
    /// `nonisolated` + static so tests can call directly.
    nonisolated static func isSilent(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return true }
        let window = 8_000  // 0.5 s at 16 kHz
        var start = 0
        while start < samples.count {
            let count = min(window, samples.count - start)
            var rms: Float = 0
            samples.withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress! + start, 1, &rms, vDSP_Length(count))
            }
            if rms >= silenceRMSThreshold { return false }
            start += window
        }
        return true
    }

    private func runOnePartial(samples: [Float]) async {
        // VAD gate: nothing said yet — no point waking whisper just to
        // hallucinate "Thank you." over room tone.
        if Self.isSilent(samples) { return }
        do {
            // Bias partials with the same dictionary prompt the final
            // pass uses, so user-trained terms render correctly in the
            // live preview too. Snapshotted in start() — see
            // `dictionaryPrompt`.
            let raw = try await WhisperLib.shared.transcribe(samples: samples, prompt: dictionaryPrompt)
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
