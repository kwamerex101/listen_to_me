import AVFoundation
import FluidAudio
import Foundation

/// Parakeet ASR via FluidAudio (Core ML / Apple Neural Engine). Wired into
/// the dictation pipeline (WhisperRunner routes `.parakeet` here, falling
/// back to the whisper CLI on any failure) and also powers the in-Settings
/// A/B benchmark against Whisper.
///
/// Lifecycle mirrors WhisperLib/LocalLLMEngine: published status for SwiftUI,
/// lazy load, model download into our Application Support tree (FluidAudio's
/// `downloadAndLoad(to:)` accepts a custom directory, so no hidden cache).
@MainActor
final class ParakeetEngine: ObservableObject {
    static let shared = ParakeetEngine()

    /// User-facing name for the model version currently loaded (or about to
    /// load), read from `Preferences.shared.parakeetModel`. Used by the
    /// benchmark UI's model-name column.
    static var modelDisplayName: String { Preferences.shared.parakeetModel.shortLabel }

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
    /// The model version currently loaded into `manager`/`models`, if any.
    /// Compared against `Preferences.shared.parakeetModel` on `ensureReady()`
    /// so a version switch in Settings reloads the right model instead of
    /// silently keeping the old one warm.
    private var loadedVersion: Preferences.ParakeetModel?
    private init() {}

    /// Models live alongside our other model trees. FluidAudio manages the
    /// contents (several .mlmodelc bundles) inside this directory.
    static var modelsDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListenToMe/parakeet", isDirectory: true)
    }

    var isReady: Bool { manager != nil }

    /// Download (if needed) + load the selected model version
    /// (`Preferences.shared.parakeetModel`, default v3). Safe to call
    /// repeatedly; no-ops when the right version is already ready. If a
    /// different version is loaded (the user switched in Settings), unloads
    /// it first so this call loads the newly-selected one. Progress is
    /// published for the benchmark UI.
    func ensureReady() async throws {
        let selected = Preferences.shared.parakeetModel
        if manager != nil, loadedVersion == selected { return }
        if manager != nil { shutdown() }
        if case .downloading = status { return }
        if case .loading = status { return }

        status = .downloading(progress: 0)
        do {
            let models = try await AsrModels.downloadAndLoad(
                to: Self.modelsDirectory,
                version: selected.asrModelVersion,
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
            loadedVersion = selected
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
    ///
    /// Works the same for either Parakeet model version: the CTC
    /// keyword-spotting model (`CtcModels`, variant `.ctc110m` by default,
    /// see FluidAudio's `CtcModels.swift`) is a separate model from the TDT
    /// decoder and never varies with `AsrModelVersion`, and
    /// `SlidingWindowAsrManager.configureVocabularyBoosting` sizes its
    /// rescorer purely from `vocabulary.terms.count` (the user's own
    /// dictionary size), never from the TDT model's vocabulary or tokenizer
    /// (see FluidAudio's `SlidingWindowAsrManager.swift`, roughly lines
    /// 86-115). So v2 needs no special-casing here.
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
        loadedVersion = nil
        if status == .ready { status = .missing }
    }

    /// Every folder FluidAudio writes Parakeet models into. It does NOT write
    /// inside `modelsDirectory`: both `AsrModels` (`repoPath(from:version:)`,
    /// FluidAudio 0.15.2 AsrModels.swift:151) and `CtcModels.download`
    /// (CtcModels.swift:204) take the directory's PARENT and append the repo's
    /// folder name, so the models land in siblings such as
    /// `ListenToMe/parakeet-tdt-0.6b-v3`. Built from FluidAudio's public
    /// `Repo.folderName` so a renamed repo folder follows along. Includes
    /// `modelsDirectory` itself for anything an older build left there.
    nonisolated static func modelFolders(in modelsDirectory: URL) -> [URL] {
        let parent = modelsDirectory.deletingLastPathComponent()
        let repos: [Repo] = [.parakeetV3, .parakeetV2] + CtcModelVariant.allCases.map(\.repo)
        return [modelsDirectory] + repos.map {
            parent.appendingPathComponent($0.folderName, isDirectory: true)
        }
    }

    /// Free the loaded model and delete every downloaded Parakeet model (both
    /// TDT versions and the vocabulary-boost CTC model) to reclaim disk space.
    /// Re-downloadable via `ensureReady()`, so this is a reclaim-space action,
    /// not data loss.
    func deleteModel() {
        shutdown()
        for folder in Self.modelFolders(in: Self.modelsDirectory) {
            try? FileManager.default.removeItem(at: folder)
        }
        status = .missing
    }
}
