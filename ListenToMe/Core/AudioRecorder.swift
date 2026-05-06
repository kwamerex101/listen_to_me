import Accelerate
import AVFoundation
import Foundation

/// Records microphone audio to a 16kHz mono WAV file and publishes RMS level.
@MainActor
final class AudioRecorder {
    static let shared = AudioRecorder()

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    private var currentURL: URL?
    /// Reused across buffers within a session to avoid ~60 allocs/sec on
    /// the audio render thread. Reallocated only when an input buffer
    /// requests a larger output capacity than we've previously seen.
    private var reusableOutBuffer: AVAudioPCMBuffer?

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

    func start() throws -> URL {
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
        file = try AVAudioFile(forWriting: url, settings: fileSettings)

        converter = AVAudioConverter(from: hwFormat, to: targetFormat)

        let bufferSize: AVAudioFrameCount = 1024
        input.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, target: targetFormat)
        }

        engine.prepare()
        try engine.start()
        return url
    }

    func stop() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let url = currentURL
        file = nil
        currentURL = nil
        reusableOutBuffer = nil
        return url
    }

    /// Stop recording and discard the captured audio.
    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let url = currentURL {
            try? FileManager.default.removeItem(at: url)
        }
        file = nil
        currentURL = nil
        reusableOutBuffer = nil
    }

    private func process(buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard let converter else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32

        // Reuse the output PCM buffer across calls; reallocate only when a
        // larger capacity is needed (rare — input buffer size is fixed at
        // 1024 frames). Eliminates ~60 allocations/sec on the audio render
        // thread without changing the WAV output.
        if reusableOutBuffer == nil || reusableOutBuffer!.frameCapacity < outCapacity {
            reusableOutBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity)
        }
        guard let outBuffer = reusableOutBuffer else { return }
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
        if error != nil { return }

        do {
            try file?.write(from: outBuffer)
        } catch {
            NSLog("[ListenToMe] file write failed: \(error)")
        }

        // RMS level for waveform — Accelerate's vDSP_rmsqv is vectorized and
        // numerically stable; same output as the manual sum-of-squares loop
        // but ~5-10× faster on typical buffer sizes.
        if let floatData = outBuffer.floatChannelData?[0] {
            let n = vDSP_Length(outBuffer.frameLength)
            var rms: Float = 0
            if n > 0 { vDSP_rmsqv(floatData, 1, &rms, n) }
            let normalized = min(1, max(0, rms * 6))   // crude gain
            let cb = onLevel
            DispatchQueue.main.async { cb?(normalized) }
        }
    }
}
