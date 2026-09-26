import CryptoKit
import Foundation

/// Reactive façade over the on-disk Whisper model file.
///
/// The Whisper binary expects `ggml-base.en.bin` at
/// `~/Library/Application Support/ListenToMe/models/`. `scripts/setup.sh`
/// downloads it once during first-time setup, but a user who skipped that
/// step needs an in-app way to fetch it. This manager:
///
/// - reports the current state (`missing` / `downloading(progress)` / `ready`)
/// - downloads the model from the same Hugging Face URL the setup script uses
/// - publishes progress updates on the main actor so SwiftUI can bind directly
///
/// Network is plain `URLSession` — no third-party deps per CLAUDE.md.
@MainActor
final class WhisperModelManager: NSObject, ObservableObject {
    enum Status: Equatable {
        case missing
        case downloading(progress: Double)   // 0.0 – 1.0
        case ready(sizeBytes: Int64)
        case failed(message: String)
    }

    static let shared = WhisperModelManager()

    @Published private(set) var status: Status = .missing

    /// Derives download URL, size floor, and SHA from the currently selected model.
    private var activeModel: Preferences.WhisperModel { Preferences.shared.selectedWhisperModel }

    /// Model + destination captured at the moment `startDownload()` is
    /// called. The completion handler uses these — not `activeModel` — so
    /// switching the Settings picker mid-download can't land the bytes
    /// under a different model's filename (the picker's own `refreshStatus`
    /// call also can't clobber the in-flight download; see `refreshStatus`).
    /// `nil` whenever no download is in flight.
    private var downloadingModel: Preferences.WhisperModel?
    private var downloadingDestination: URL?

    /// Optional Core ML encoder package (ANE-accelerated encoder).
    /// whisper.cpp linked builds auto-load this when the .mlmodelc
    /// directory sits next to the .bin. Without it, the encoder runs
    /// on Metal/CPU — same accuracy, slightly slower per-call.
    static var coreMLPackageURL: URL {
        let modelURL = WhisperRunner.modelURL
        let stem = modelURL.deletingPathExtension().lastPathComponent
        return modelURL.deletingLastPathComponent()
            .appendingPathComponent("\(stem)-encoder.mlmodelc", isDirectory: true)
    }

    var coreMLPackageInstalled: Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: Self.coreMLPackageURL.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

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

    /// Where a given model's file lives on disk, independent of the current
    /// selection — a pure function of the model, mirroring
    /// `WhisperRunner.modelURL`'s path construction (which is keyed off
    /// `Preferences.shared.selectedWhisperModel` instead). Used to capture
    /// the download destination at `startDownload()` time.
    static func downloadDestination(for model: Preferences.WhisperModel) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ListenToMe/models/\(model.filename)")
    }

    /// Recompute `status` from disk for the currently selected model. Cheap
    /// when the file is already in page cache — at ~150 MB the SHA pass
    /// takes ~50-100 ms on M-series silicon. Called once on launch (init)
    /// and after a download completes, so the user-felt cost is invisible.
    ///
    /// No-op while a download is in flight (`downloadTask != nil`) — without
    /// this, a caller (e.g. the Settings model picker reacting to a
    /// selection change) could stomp `.downloading` back to `.missing` for
    /// the model that's still landing, and `startDownload()`'s "already
    /// downloading" refusal would stop applying.
    func refreshStatus() {
        guard downloadTask == nil else { return }
        let model = activeModel
        let url = WhisperRunner.modelURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            status = .missing
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        if size < model.expectedMinBytes {
            // Truncated download from a previous attempt — treat as missing.
            try? FileManager.default.removeItem(at: url)
            status = .missing
            return
        }
        // SHA-256 verification where a known hash exists. nil = size-only check.
        if let expected = model.sha256,
           let actual = Self.sha256(of: url), actual != expected {
            NSLog("[ListenToMe] model SHA mismatch (got \(actual.prefix(12))…, expected \(expected.prefix(12))…) — removing")
            try? FileManager.default.removeItem(at: url)
            status = .failed(message: "Model integrity check failed — re-download required")
            return
        }
        status = .ready(sizeBytes: size)
    }

    /// Stream the file through SHA256 in 1 MB chunks so we never load a
    /// multi-hundred-MB or multi-GB file into memory all at once.
    /// `nonisolated` and off the actor deliberately: callers that verify a
    /// freshly-downloaded temp file do so from a background `Task`, not the
    /// MainActor, so a large model's hash pass never blocks the UI.
    nonisolated static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Begin a download if we don't already have one in flight. Refuses
    /// (rather than cancelling-and-restarting) a second concurrent request —
    /// simpler to reason about, and the UI already disables the download
    /// control while `.downloading`.
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

    /// Delete the on-disk Whisper model (and its optional Core ML encoder
    /// package) to reclaim disk space, freeing any in-process context first.
    /// Re-downloadable via `startDownload()`, so this is a reclaim-space
    /// action, not data loss.
    func deleteModel() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingModel = nil
        downloadingDestination = nil
        WhisperLib.shared.shutdown()   // release the loaded context before unlinking the file
        WhisperServer.shared.shutdown()   // and the warm subprocess, so it can't keep serving the deleted file from RAM
        try? FileManager.default.removeItem(at: WhisperRunner.modelURL)
        if coreMLPackageInstalled {
            try? FileManager.default.removeItem(at: Self.coreMLPackageURL)
        }
        status = .missing
    }

    fileprivate func handleProgress(_ p: Double) {
        status = .downloading(progress: max(0, min(1, p)))
    }

    /// Runs off the MainActor: streams the just-downloaded temp file
    /// through SHA-256 (when the model publishes one) before handing off to
    /// `handleFinished` to move it into place. Keeps a multi-hundred-MB
    /// verification pass from blocking the UI thread.
    nonisolated private func verifyAndFinish(temp: URL) async {
        let model = await MainActor.run { self.downloadingModel }
        if let model, let expected = model.sha256 {
            let actual = Self.sha256(of: temp)
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
        status = .failed(message: "Downloaded model failed integrity check — please retry")
    }

    private func clearDownloadState() {
        downloadTask = nil
        downloadingModel = nil
        downloadingDestination = nil
    }

    fileprivate func handleFinished(temp: URL) {
        guard let dest = downloadingDestination else {
            // Shouldn't happen — startDownload() always sets this before a
            // download can start — but don't strand the temp file either way.
            try? FileManager.default.removeItem(at: temp)
            clearDownloadState()
            status = .failed(message: "Couldn't save model: no destination recorded for this download")
            return
        }
        do {
            // Atomic swap into place. replaceItemAt handles "no existing
            // file at dest" too (it just performs the move).
            _ = try FileManager.default.replaceItemAt(dest, withItemAt: temp)
        } catch {
            // Clear the in-flight state too: startDownload refuses while a
            // download is recorded, so leaving it set would block every retry.
            try? FileManager.default.removeItem(at: temp)
            clearDownloadState()
            status = .failed(message: "Couldn't save model: \(error.localizedDescription)")
            return
        }
        downloadTask = nil
        downloadingModel = nil
        downloadingDestination = nil
        refreshStatus()
    }

    fileprivate func handleFailure(_ error: Error) {
        downloadTask = nil
        downloadingModel = nil
        downloadingDestination = nil
        // Cancellation surfaces as URLError(.cancelled); treat as a clean
        // reset rather than a user-visible error.
        if let urlErr = error as? URLError, urlErr.code == .cancelled {
            refreshStatus()
            return
        }
        status = .failed(message: error.localizedDescription)
    }
}

// MARK: - URLSessionDownloadDelegate

extension WhisperModelManager: URLSessionDownloadDelegate {
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
        // The downloaded file lives in the temp directory until this delegate
        // returns; we need to copy/move it synchronously OR snapshot the path
        // and dispatch — synchronously snapshot, then hop off-actor to verify.
        // Move it to a stable temp file we own so it doesn't get cleaned up
        // before the hash/move runs.
        let owned = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListenToMe-model-\(UUID().uuidString).bin")
        do {
            try FileManager.default.moveItem(at: location, to: owned)
        } catch {
            Task { @MainActor in self.handleFailure(error) }
            return
        }
        // Not `@MainActor` — the hash pass over a multi-hundred-MB/GB file
        // must not run on the main thread.
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
