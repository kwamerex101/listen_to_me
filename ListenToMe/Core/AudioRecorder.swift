import Accelerate
import AVFoundation
import Foundation

/// Records microphone audio to a 16kHz mono WAV file and publishes RMS level.
///
/// The tap callback installed on the input node runs on the AVAudioEngine's
/// audio render thread (real-time, NOT the main actor). Class is intentionally
/// not marked `@MainActor`: control-plane methods (`start`/`stop`/`cancel`)
/// are called from main and explicitly annotated; `process(buffer:target:)`
/// is `nonisolated` and runs on the audio thread. Shared state touched by
/// both threads (`converter`, `file`, `reusableOutBuffer`) is guarded by
/// `stateLock` to prevent races during teardown.
final class AudioRecorder {
    static let shared = AudioRecorder()

    private let engine = AVAudioEngine()

    /// Guards `converter`, `file`, and `reusableOutBuffer` — the only state
    /// shared between the main thread (start/stop/cancel) and the audio
    /// render thread (process).
    private let stateLock = NSLock()
    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    /// Reused across buffers within a session to avoid ~60 allocs/sec on
    /// the audio render thread. Reallocated only when an input buffer
    /// requests a larger output capacity than we've previously seen.
    private var reusableOutBuffer: AVAudioPCMBuffer?

    /// Rolling Float32 sample accumulator (16 kHz mono). Populated by
    /// the audio render thread alongside the WAV write so the streaming
    /// partial-transcripts feature (M5') can read the in-progress
    /// audio without re-reading a growing WAV file. Capped at
    /// `maxAccumulatedSamples` so a long forgotten hotkey-hold can't
    /// blow memory; whisper-base only sees the last ~30s anyway.
    /// nil when streaming isn't requested for this session — saves the
    /// ~2 MB / 30 s allocation when the user hasn't opted in.
    private var sampleAccumulator: [Float]?

    /// 30 seconds at 16 kHz = 480k Float32 = 1.92 MB. Whisper-base's
    /// receptive window caps at 30 s so anything older isn't usable as
    /// streaming context anyway — drop it.
    private static let maxAccumulatedSamples: Int = 480_000

    /// Touched only from the main thread.
    private var currentURL: URL?

    /// Watchdog that auto-stops a runaway session (e.g. stuck hotkey).
    private var maxDurationTask: Task<Void, Never>?

    /// Caller-provided callback fired exactly once when the watchdog
    /// triggers — AppDelegate listens and tears down the session via the
    /// normal release path so the rest of the pipeline runs.
    var onMaxDurationReached: (() -> Void)?

    /// Callback fired ~30Hz with normalized level 0…1.
    var onLevel: ((Float) -> Void)?

    private init() {}

    static func requestMicAccess() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    @MainActor
    func start(accumulateSamples: Bool = false) throws -> URL {
        // Fresh file each session
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("listentome-\(UUID().uuidString).wav")
        currentURL = url

        let input = engine.inputNode

        // Defensive teardown — installTap raises an Objective-C NSException
        // (which Swift `throws` cannot catch) if a tap is already on the bus
        // or if the engine is already running. A previous session that
        // failed to fully stop, a quick press-release-press sequence, or any
        // unexpected exit from stop()/cancel() leaves us in that state. Make
        // start() idempotent by tearing down first.
        if engine.isRunning {
            engine.stop()
        }
        input.removeTap(onBus: 0)

        let hwFormat = input.outputFormat(forBus: 0)

        // Target format for whisper.cpp: 16kHz mono PCM Float32 (CAF-safe WAV)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else { throw NSError(domain: "ListenToMe", code: 1) }

        // AVAudioFile wants non-interleaved float; we write at target rate
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let newFile = try AVAudioFile(forWriting: url, settings: fileSettings)
        let newConverter = AVAudioConverter(from: hwFormat, to: targetFormat)

        // Publish the new audio-thread state under the lock so a tap
        // callback that may already be queued sees a fully-initialized
        // pair (or the previous nil) — never a half-installed state.
        // Sample accumulator is reserved up front to avoid append-time
        // reallocations in the hot path.
        stateLock.lock()
        file = newFile
        converter = newConverter
        reusableOutBuffer = nil
        if accumulateSamples {
            var buf: [Float] = []
            buf.reserveCapacity(Self.maxAccumulatedSamples)
            sampleAccumulator = buf
        } else {
            sampleAccumulator = nil
        }
        stateLock.unlock()

        let bufferSize: AVAudioFrameCount = 1024
        input.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, target: targetFormat)
        }

        engine.prepare()
        try engine.start()

        // Watchdog: auto-stop after Preferences.maxRecordingSec to defend
        // against a stuck hotkey or unexpected hold. Cancelled in stop().
        let cap = Preferences.shared.maxRecordingSec
        maxDurationTask?.cancel()
        maxDurationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(cap))
            if Task.isCancelled { return }
            self?.onMaxDurationReached?()
        }
        return url
    }

    @MainActor
    func stop() -> URL? {
        maxDurationTask?.cancel()
        maxDurationTask = nil
        // removeTap is synchronous — no new tap callbacks fire after this.
        // Any in-flight callback will block on stateLock below before
        // touching the about-to-be-cleared state.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let url = currentURL
        currentURL = nil
        stateLock.lock()
        file = nil
        converter = nil
        reusableOutBuffer = nil
        sampleAccumulator = nil
        stateLock.unlock()
        return url
    }

    /// Stop recording and discard the captured audio.
    @MainActor
    func cancel() {
        maxDurationTask?.cancel()
        maxDurationTask = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let url = currentURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentURL = nil
        stateLock.lock()
        file = nil
        converter = nil
        reusableOutBuffer = nil
        sampleAccumulator = nil
        stateLock.unlock()
    }

    /// Return a snapshot of the accumulator (M5' streaming partials).
    /// Empty array when streaming wasn't requested for this session or
    /// no audio has arrived yet. Safe to call from any thread —
    /// stateLock guards the read.
    func currentSamples() -> [Float] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return sampleAccumulator ?? []
    }

    /// Runs on the AVAudioEngine render thread. All shared-state access
    /// is held under `stateLock` to avoid races with stop()/cancel() that
    /// nil out converter/file mid-buffer.
    nonisolated private func process(buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32

        stateLock.lock()
        guard let converter = self.converter, let file = self.file else {
            stateLock.unlock()
            return
        }
        // Reuse the output PCM buffer across calls; reallocate only when a
        // larger capacity is needed (rare — input buffer size is fixed at
        // 1024 frames). Eliminates ~60 allocations/sec on the audio render
        // thread without changing the WAV output.
        if reusableOutBuffer == nil || reusableOutBuffer!.frameCapacity < outCapacity {
            reusableOutBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity)
        }
        guard let outBuffer = reusableOutBuffer else {
            stateLock.unlock()
            return
        }
        outBuffer.frameLength = 0   // converter writes from frame 0

        var supplied = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if error != nil {
            stateLock.unlock()
            return
        }

        do {
            try file.write(from: outBuffer)
        } catch {
            NSLog("[ListenToMe] file write failed: \(error)")
        }

        // Snapshot floatData / level work while still holding the lock —
        // outBuffer is owned by us and the lock keeps it valid for the
        // duration of the read.
        var normalized: Float = 0
        if let floatData = outBuffer.floatChannelData?[0] {
            let n = vDSP_Length(outBuffer.frameLength)
            var rms: Float = 0
            if n > 0 { vDSP_rmsqv(floatData, 1, &rms, n) }
            normalized = min(1, max(0, rms * 6))   // crude gain

            // M5': feed the streaming-partials accumulator with the same
            // 16 kHz mono Float32 samples we just wrote to disk. Trim
            // the head when we exceed the cap (whisper-base only sees
            // the last 30 s anyway). nil accumulator is the common
            // path when streaming isn't requested — zero overhead.
            if sampleAccumulator != nil {
                let count = Int(outBuffer.frameLength)
                let buf = UnsafeBufferPointer(start: floatData, count: count)
                sampleAccumulator!.append(contentsOf: buf)
                let overflow = sampleAccumulator!.count - Self.maxAccumulatedSamples
                if overflow > 0 {
                    sampleAccumulator!.removeFirst(overflow)
                }
            }
        }
        stateLock.unlock()

        // RMS level for waveform — vectorized via Accelerate above. Hop to
        // main without holding the lock so the level callback can safely
        // touch @MainActor state.
        let cb = onLevel
        if cb != nil {
            DispatchQueue.main.async { cb?(normalized) }
        }
    }
}
