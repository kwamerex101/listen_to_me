import CryptoKit
import Foundation

/// Reactive façade over the on-disk Gemma GGUF used for on-device polish.
/// Mirrors WhisperModelManager: reports state, downloads from HuggingFace via
/// plain URLSession (no third-party deps), publishes progress on the main
/// actor for SwiftUI. The GGUF lands in Application Support/ListenToMe/llm/
/// (LocalLLMEngine.modelURL), separate from whisper models.
///
/// Integrity: every model in `Preferences.LocalLLMModel` carries a
/// SHA-256 (from the HF API's `lfs.oid`, pinned alongside a commit-locked
/// download URL, see `Preferences.swift`), verified against the
/// downloaded temp file before it's moved into place. A truncated download
/// is also caught by the size floor.
@MainActor
final class LLMModelManager: NSObject, ObservableObject {
    enum Status: Equatable {
        case missing
        case downloading(progress: Double)
        case ready(sizeBytes: Int64)
        case failed(message: String)
    }

    static let shared = LLMModelManager()

    @Published private(set) var status: Status = .missing

    /// The model the user has selected for local polish.
    private var activeModel: Preferences.LocalLLMModel { Preferences.shared.selectedLocalLLMModel }

    private var destURL: URL { LocalLLMEngine.modelURL(for: activeModel.filename) }

    /// Model + destination captured at the moment `startDownload()` is
    /// called. The completion handler uses these, not `activeModel`, so
    /// switching the model picker mid-download can't land a multi-GB GGUF
    /// under a different model's filename. `nil` whenever no download is
    /// in flight.
    private var downloadingModel: Preferences.LocalLLMModel?
    private var downloadingDestination: URL?

    private var downloadTask: URLSessionDownloadTask?
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.allowsExpensiveNetworkAccess = true
        cfg.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        refreshStatus()
    }

    /// Where a given model's GGUF lives on disk, independent of the current
    /// selection. Pure function of the model. Used to capture the download
    /// destination at `startDownload()` time.
    static func downloadDestination(for model: Preferences.LocalLLMModel) -> URL {
        LocalLLMEngine.modelURL(for: model.filename)
    }

    /// Recompute `status` from disk for the currently selected model.
    ///
    /// No-op while a download is in flight (`downloadTask != nil`), see
    /// the identical note on `WhisperModelManager.refreshStatus`: without
    /// this a picker-driven refresh could stomp `.downloading` back to
    /// `.missing` for the model that's still landing.
    func refreshStatus() {
        guard downloadTask == nil else { return }
        let url = destURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            status = .missing
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        if size < activeModel.expectedMinBytes {
            try? FileManager.default.removeItem(at: url)   // truncated prior attempt
            status = .missing
            return
        }
        if let expected = activeModel.sha256,
           let actual = WhisperModelManager.sha256(of: url), actual != expected {
            NSLog("[ListenToMe] LLM model SHA mismatch (got \(actual.prefix(12))…, expected \(expected.prefix(12))…): removing")
            try? FileManager.default.removeItem(at: url)
            status = .failed(message: "Model integrity check failed. Re-download required")
            return
        }
        status = .ready(sizeBytes: size)
    }

    /// Begin a download if we don't already have one in flight. Refuses a
    /// second concurrent request rather than cancelling-and-restarting,
    /// the UI already disables the control while `.downloading`.
    func startDownload() {
        guard downloadTask == nil else { return }
        if case .ready = status { return }

        let model = activeModel
        let dest = Self.downloadDestination(for: model)
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        downloadingModel = model
        downloadingDestination = dest
        status = .downloading(progress: 0)
        let task = session.downloadTask(with: model.downloadURL)
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingModel = nil
        downloadingDestination = nil
        refreshStatus()
    }

    /// Delete the on-disk cleanup GGUF to reclaim disk space, unloading the
    /// engine first. Re-downloadable via `startDownload()`, so this is a
    /// reclaim-space action, not data loss.
    func deleteModel() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingModel = nil
        downloadingDestination = nil
        LocalLLMEngine.shared.shutdown()   // release the loaded model before unlinking the file
        try? FileManager.default.removeItem(at: destURL)
        status = .missing
    }

    fileprivate func handleProgress(_ p: Double) {
        status = .downloading(progress: max(0, min(1, p)))
    }

    /// Runs off the MainActor: streams the just-downloaded temp file
    /// through SHA-256 before handing off to `handleFinished` to move it
    /// into place, so verifying a multi-GB GGUF never blocks the UI thread.
    nonisolated private func verifyAndFinish(temp: URL) async {
        let model = await MainActor.run { self.downloadingModel }
        if let model, let expected = model.sha256 {
            let actual = WhisperModelManager.sha256(of: temp)
            guard actual == expected else {
                try? FileManager.default.removeItem(at: temp)
                await MainActor.run { self.handleHashMismatch() }
                return
            }
        }
        await MainActor.run { self.handleFinished(temp: temp) }
    }

    fileprivate func handleHashMismatch() {
        downloadTask = nil
        downloadingModel = nil
        downloadingDestination = nil
        status = .failed(message: "Downloaded model failed integrity check. Please retry")
    }

    private func clearDownloadState() {
        downloadTask = nil
        downloadingModel = nil
        downloadingDestination = nil
    }

    fileprivate func handleFinished(temp: URL) {
        guard let dest = downloadingDestination else {
            try? FileManager.default.removeItem(at: temp)
            clearDownloadState()
            status = .failed(message: "Couldn't save model: no destination recorded for this download")
            return
        }
        do {
            // Atomic swap into place; handles "no existing file" too.
            _ = try FileManager.default.replaceItemAt(dest, withItemAt: temp)
        } catch {
            // Clear the in-flight state too: startDownload refuses while a
            // download is recorded, so leaving it set would block every retry.
            try? FileManager.default.removeItem(at: temp)
            clearDownloadState()
            status = .failed(message: "Couldn't save model: \(error.localizedDescription)")
            return
        }
        let finishedModel = downloadingModel
        downloadTask = nil
        downloadingModel = nil
        downloadingDestination = nil
        refreshStatus()
        // Point the engine at the freshly downloaded model and warm it,
        // only when it's still the active selection (the user may have
        // switched away while this download was in flight).
        if case .ready = status, let finishedModel, finishedModel == activeModel {
            LocalLLMEngine.shared.preload(modelFile: finishedModel.filename)
        }
    }

    fileprivate func handleFailure(_ error: Error) {
        downloadTask = nil
        downloadingModel = nil
        downloadingDestination = nil
        if let urlErr = error as? URLError, urlErr.code == .cancelled {
            refreshStatus()
            return
        }
        status = .failed(message: error.localizedDescription)
    }
}

// MARK: - URLSessionDownloadDelegate

extension LLMModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.handleProgress(p) }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let owned = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListenToMe-llm-\(UUID().uuidString).gguf")
        do {
            try FileManager.default.moveItem(at: location, to: owned)
        } catch {
            Task { @MainActor in self.handleFailure(error) }
            return
        }
        // Not `@MainActor`, hashing a multi-GB GGUF must not run on the
        // main thread.
        Task { await self.verifyAndFinish(temp: owned) }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in self.handleFailure(error) }
    }
}
