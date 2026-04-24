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
    }

    private func process(buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard let converter else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: target,
            frameCapacity: outCapacity
        ) else { return }

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

        // RMS level for waveform
        if let floatData = outBuffer.floatChannelData?[0] {
            let n = Int(outBuffer.frameLength)
            var sum: Float = 0
            for i in 0..<n {
                let s = floatData[i]
                sum += s * s
            }
            let rms = n > 0 ? sqrt(sum / Float(n)) : 0
            let normalized = min(1, max(0, rms * 6))   // crude gain
            let cb = onLevel
            DispatchQueue.main.async { cb?(normalized) }
        }
    }
}
