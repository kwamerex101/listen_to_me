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

    func shutdown() {
        manager = nil
        if status == .ready { status = .missing }
    }
}
