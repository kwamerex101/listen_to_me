import AVFoundation
import FluidAudio
import Foundation

/// Parakeet TDT v3 ASR via FluidAudio (Core ML / Apple Neural Engine).
/// Wave 8 scope: powers the in-Settings A/B benchmark against Whisper only —
/// NOT wired into the dictation pipeline until the benchmark proves it out
/// (see docs/plans/2026-06-12-wave8-parakeet-adr.md).
///
/// Lifecycle mirrors WhisperLib/LocalLLMEngine: published status for SwiftUI,
/// lazy load, model download into our Application Support tree (FluidAudio's
/// `downloadAndLoad(to:)` accepts a custom directory, so no hidden cache).
@MainActor
final class ParakeetEngine: ObservableObject {
    static let shared = ParakeetEngine()

    enum Status: Equatable {
        case missing
        case downloading(progress: Double)
        case loading
        case ready
        case failed(message: String)
    }

    @Published private(set) var status: Status = .missing

    private var manager: AsrManager?
    private var models: AsrModels?            // retained to share with the sliding manager
    // Lazy vocabulary-biasing stack (only built when boosting is actually used).
    private var ctcModels: CtcModels?
    private var slidingManager: SlidingWindowAsrManager?
    private var configuredTerms: Set<String> = []
    private init() {}

    /// Models live alongside our other model trees. FluidAudio manages the
    /// contents (several .mlmodelc bundles) inside this directory.
    static var modelsDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListenToMe/parakeet", isDirectory: true)
    }

    var isReady: Bool { manager != nil }

    /// Download (if needed) + load the v3 models. Safe to call repeatedly;
    /// no-ops when already ready. Progress is published for the benchmark UI.
    func ensureReady() async throws {
        if manager != nil { return }
        if case .downloading = status { return }
        if case .loading = status { return }

        status = .downloading(progress: 0)
        do {
            let models = try await AsrModels.downloadAndLoad(
                to: Self.modelsDirectory,
                version: .v3,
                progressHandler: { progress in
                    Task { @MainActor in
                        // Only regress-proof updates; download phases restart %.
                        if case .downloading = ParakeetEngine.shared.status {
                            ParakeetEngine.shared.status =
                                .downloading(progress: progress.fractionCompleted)
                        }
                    }
                }
            )
            status = .loading
            let mgr = AsrManager(config: .default)
            try await mgr.loadModels(models)
            manager = mgr
            self.models = models
            status = .ready
        } catch {
            status = .failed(message: error.localizedDescription)
            throw error
        }
    }

    /// Transcribe 16 kHz mono Float samples (the app's native recording
    /// format). Fresh decoder state per utterance — push-to-talk clips are
    /// independent. Returns the text plus the engine-reported processing time.
    func transcribe(samples: [Float]) async throws -> (text: String, seconds: Double) {
        try await ensureReady()
        guard let manager else {
            throw NSError(domain: "ParakeetEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "models not loaded"])
        }
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(samples, decoderState: &state)
        return (result.text, result.processingTime)
    }

    /// Transcribe with optional dictionary biasing. When `biasTerms` is empty
    /// this is exactly the fast one-shot path. Otherwise it routes through the
    /// sliding-window manager with CTC word-spotting so the given terms (e.g.
    /// proper nouns) are favored. ANY failure in the biased path falls back to
    /// the fast path — dictation never breaks.
    func transcribe(samples: [Float], biasTerms: [String]) async throws -> (text: String, seconds: Double) {
        let terms = biasTerms
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 }   // CTC-WS skips very short terms anyway
        guard !terms.isEmpty else { return try await transcribe(samples: samples) }

        do {
            let start = Date()
            let text = try await biasedTranscribe(samples: samples, terms: terms)
            return (text, Date().timeIntervalSince(start))
        } catch {
            NSLog("[ListenToMe] Parakeet vocab-boost failed (\(error)) — using fast path")
            return try await transcribe(samples: samples)
        }
    }

    private func biasedTranscribe(samples: [Float], terms: [String]) async throws -> String {
        try await ensureReady()
        guard let models else { throw ASRBiasError.notReady }

        try await ensureVocabConfigured(terms: terms, models: models)
        guard let sliding = slidingManager else { throw ASRBiasError.notReady }

        let buffer = try Self.makeBuffer(from: samples)
        try await sliding.startStreaming(source: .microphone)
        await sliding.streamAudio(buffer)
        let text = try await sliding.finish()
        try? await sliding.reset()   // ready for the next utterance
        return text
    }

    /// Build/refresh the CTC + sliding stack for the given term set. Rebuilds
    /// the vocabulary only when the set changed (cheap to skip otherwise).
    private func ensureVocabConfigured(terms: [String], models: AsrModels) async throws {
        let termSet = Set(terms)
        if slidingManager != nil, configuredTerms == termSet { return }

        if ctcModels == nil {
            ctcModels = try await CtcModels.downloadAndLoad(to: Self.modelsDirectory)
        }
        guard let ctc = ctcModels else { throw ASRBiasError.notReady }

        let sliding = slidingManager ?? SlidingWindowAsrManager(config: .default)
        if slidingManager == nil {
            try await sliding.loadModels(models)
        }
        let vocab = CustomVocabularyContext(terms: terms.map { CustomVocabularyTerm(text: $0) })
        try await sliding.configureVocabularyBoosting(vocabulary: vocab, ctcModels: ctc)
        slidingManager = sliding
        configuredTerms = termSet
    }

    /// [Float] @ 16 kHz mono → AVAudioPCMBuffer (FluidAudio's stream input).
    nonisolated private static func makeBuffer(from samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: 16_000, channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt,
                                         frameCapacity: AVAudioFrameCount(max(1, samples.count)))
        else { throw ASRBiasError.bufferAllocFailed }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let dst = buf.floatChannelData?[0], let base = src.baseAddress {
                dst.update(from: base, count: samples.count)
            }
        }
        return buf
    }

    enum ASRBiasError: Error { case notReady, bufferAllocFailed }

    func shutdown() {
        manager = nil
        models = nil
        slidingManager = nil
        ctcModels = nil
        configuredTerms = []
        if status == .ready { status = .missing }
    }

    /// Free the loaded model and delete the on-disk Parakeet model tree to
    /// reclaim disk space. FluidAudio stores several `.mlmodelc` bundles under
    /// `modelsDirectory`, so we remove the whole directory. Re-downloadable via
    /// `ensureReady()`, so this is a reclaim-space action, not data loss.
    func deleteModel() {
        shutdown()
        try? FileManager.default.removeItem(at: Self.modelsDirectory)
        status = .missing
    }
}
