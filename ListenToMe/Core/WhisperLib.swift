import AVFoundation
import CWhisper
import Foundation

/// Direct-link Swift wrapper around whisper.cpp's C API. Eliminates
/// the per-call subprocess (whisper-cli) and HTTP (whisper-server)
/// hops in favor of in-process calls. Required for streaming partial
/// transcripts during press-and-hold (whisper-server is request /
/// response only).
///
/// Lifecycle:
///   - One `whisper_context` per app session, lazily initialized on
///     first `transcribe` and reused. Model load (~200-800 ms warm
///     cache, up to ~8 s cold) happens once.
///   - `shutdown()` frees the context on app exit.
///
/// Concurrency:
///   - All public methods are MainActor-isolated. The actual whisper
///     call (`whisper_full`) runs on a background priority via
///     Task.detached so the audio pipeline doesn't block.
///   - Concurrent `transcribe` calls are serialized via an in-flight
///     gate (`isBusy`); a second call returns an error immediately.
///     Real usage is serial (one hotkey hold at a time).
@MainActor
final class WhisperLib {
    static let shared = WhisperLib()

    enum LibError: Error {
        case modelNotFound(String)
        case initFailed
        case alreadyBusy
        case inferenceFailed(Int32)
    }

    /// Lazily initialized whisper context. nil means "not yet loaded
    /// or torn down". Held outside an actor so the off-main `whisper_full`
    /// call can use it directly via the wrapper struct.
    private var ctx: OpaquePointer?
    private var isBusy: Bool = false

    private init() {}

    /// True when the bundled CWhisper module is available and the
    /// model file exists on disk. Cheap; safe to call from
    /// `isAvailable` polling.
    var isReady: Bool {
        FileManager.default.fileExists(atPath: WhisperRunner.modelURL.path)
    }

    /// Transcribe a 16 kHz mono Float32 PCM buffer to text. Use this
    /// path for both batch (full WAV) and streaming partial passes.
    /// Returns the concatenated segment text.
    func transcribe(samples: [Float], prompt: String? = nil) async throws -> String {
        guard !isBusy else { throw LibError.alreadyBusy }
        try ensureContext()
        guard let ctx else { throw LibError.initFailed }
        isBusy = true
        defer { isBusy = false }

        let promptCopy = prompt
        let result: Result<String, LibError> = await Task.detached(priority: .userInitiated) {
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            // Match the CLI args we use elsewhere: English-only,
            // 4-thread tuning per Apple Silicon norms, no realtime
            // printing.
            return "en".withCString { lang -> Result<String, LibError> in
                params.language = lang
                params.print_progress = false
                params.print_realtime = false
                params.print_timestamps = false
                params.print_special = false
                params.translate = false
                params.no_context = true
                params.single_segment = false
                params.n_threads = 4

                // initial_prompt is borrowed; whisper.cpp does NOT
                // copy it. The promptBytes lifetime spans the inner
                // withCString call.
                if let p = promptCopy, !p.isEmpty {
                    return p.withCString { promptCStr -> Result<String, LibError> in
                        params.initial_prompt = promptCStr
                        return Self.runWhisperFull(ctx: ctx, params: params, samples: samples)
                    }
                }
                return Self.runWhisperFull(ctx: ctx, params: params, samples: samples)
            }
        }.value
        switch result {
        case .success(let text): return text
        case .failure(let err):  throw err
        }
    }

    /// Tear down the model context. Idempotent. Wired from
    /// AppDelegate.applicationWillTerminate alongside WhisperServer.
    func shutdown() {
        if let ctx {
            whisper_free(ctx)
        }
        ctx = nil
        isBusy = false
    }

    // MARK: - Internals

    private func ensureContext() throws {
        if ctx != nil { return }
        let modelPath = WhisperRunner.modelURL.path
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LibError.modelNotFound(modelPath)
        }
        var cparams = whisper_context_default_params()
        // Metal backend on Apple Silicon is what makes this fast;
        // explicit YES so a future header default flip doesn't
        // accidentally turn it off. Core ML encoder is auto-loaded
        // by whisper.cpp when an `<model>-encoder.mlmodelc` package
        // sits next to the .bin (handled by WhisperModelManager).
        cparams.use_gpu = true
        cparams.flash_attn = true
        let p = modelPath.withCString { whisper_init_from_file_with_params($0, cparams) }
        guard let p else { throw LibError.initFailed }
        ctx = p
    }

    /// The actual `whisper_full` call. Pulled into a static helper so
    /// the caller's `withCString` and `params` lifetime is obvious and
    /// we don't accidentally let `params.language` / `initial_prompt`
    /// dangle. `nonisolated` because the Task.detached closure runs
    /// off the main actor; the ctx pointer and samples buffer are
    /// passed in by value / address-stable via withUnsafeBufferPointer.
    nonisolated private static func runWhisperFull(ctx: OpaquePointer,
                                                   params: whisper_full_params,
                                                   samples: [Float]) -> Result<String, LibError> {
        let n = Int32(samples.count)
        let rc = samples.withUnsafeBufferPointer { buf -> Int32 in
            whisper_full(ctx, params, buf.baseAddress, n)
        }
        if rc != 0 {
            return .failure(.inferenceFailed(rc))
        }
        let segs = whisper_full_n_segments(ctx)
        var out = ""
        for i in 0..<segs {
            if let cstr = whisper_full_get_segment_text(ctx, i) {
                out += String(cString: cstr)
            }
        }
        return .success(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - WAV → Float samples

/// Read a 16 kHz mono Float32 WAV (the format AudioRecorder writes,
/// although AudioRecorder writes 16-bit PCM). For the linked path we
/// still read the same WAV format whisper-cli was reading and convert
/// to Float32 samples for whisper_full's input shape.
enum WhisperWAVReader {
    enum ReaderError: Error {
        case openFailed
        case unsupportedFormat
    }

    /// Decode `url` (a 16 kHz mono PCM WAV — int16 or float32) into the
    /// Float32 array shape whisper.cpp expects: [-1, 1] normalized,
    /// channel 0 only.
    static func samples(at url: URL) throws -> [Float] {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw ReaderError.openFailed }

        // Target buffer in float32 mono — whisper expects this exact
        // shape, so we construct the buffer from the source format and
        // convert via AVAudioConverter if the WAV is int16 (which is
        // what AudioRecorder writes).
        let srcFormat = file.processingFormat
        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else { throw ReaderError.unsupportedFormat }

        let frameCount = AVAudioFrameCount(file.length)
        guard let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else {
            throw ReaderError.unsupportedFormat
        }
        try file.read(into: srcBuf)

        let converter = AVAudioConverter(from: srcFormat, to: dstFormat)
        let dstCapacity = AVAudioFrameCount(Double(srcBuf.frameLength) * dstFormat.sampleRate / srcFormat.sampleRate) + 32
        guard let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: dstCapacity) else {
            throw ReaderError.unsupportedFormat
        }
        var supplied = false
        let block: AVAudioConverterInputBlock = { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return srcBuf
        }
        var convError: NSError?
        converter?.convert(to: dstBuf, error: &convError, withInputFrom: block)
        if convError != nil { throw ReaderError.unsupportedFormat }

        guard let chan = dstBuf.floatChannelData?[0] else {
            throw ReaderError.unsupportedFormat
        }
        let n = Int(dstBuf.frameLength)
        return Array(UnsafeBufferPointer(start: chan, count: n))
    }
}
