import Foundation

/// Reactive façade over the on-disk Gemma GGUF used for on-device polish.
/// Mirrors WhisperModelManager: reports state, downloads from HuggingFace via
/// plain URLSession (no third-party deps), publishes progress on the main
/// actor for SwiftUI. The GGUF lands in Application Support/ListenToMe/llm/
/// (LocalLLMEngine.modelURL), separate from whisper models.
///
/// Integrity: size-floor only. The HF GGUF re-uploads don't publish stable
/// checksums the way whisper.cpp's models do; a truncated download is caught
/// by the size floor, and a corrupt file fails at llama model load (surfaced
/// as a transform error, keeping the raw transcript).
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

    /// Recompute `status` from disk for the currently selected model. Cheap —
    /// just a stat (no hashing, unlike whisper, since we don't pin a SHA).
    func refreshStatus() {
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
        status = .ready(sizeBytes: size)
    }

    func startDownload() {
        if case .downloading = status { return }
        if case .ready = status { return }

        let dest = destURL
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        status = .downloading(progress: 0)
        let task = session.downloadTask(with: activeModel.downloadURL)
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        refreshStatus()
    }

    /// Delete the on-disk cleanup GGUF to reclaim disk space, unloading the
    /// engine first. Re-downloadable via `startDownload()`, so this is a
    /// reclaim-space action, not data loss.
    func deleteModel() {
        downloadTask?.cancel()
        downloadTask = nil
        LocalLLMEngine.shared.shutdown()   // release the loaded model before unlinking the file
        try? FileManager.default.removeItem(at: destURL)
        status = .missing
    }

    fileprivate func handleProgress(_ p: Double) {
        status = .downloading(progress: max(0, min(1, p)))
    }

    fileprivate func handleFinished(temp: URL) {
        let dest = destURL
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: temp, to: dest)
        } catch {
            status = .failed(message: "Couldn't save model: \(error.localizedDescription)")
            return
        }
        downloadTask = nil
        refreshStatus()
        // Point the engine at the freshly downloaded model and warm it.
        if case .ready = status {
            LocalLLMEngine.shared.preload(modelFile: activeModel.filename)
        }
    }

    fileprivate func handleFailure(_ error: Error) {
        downloadTask = nil
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
        Task { @MainActor in self.handleFinished(temp: owned) }
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
