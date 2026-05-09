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

    /// Mirror the URL used by `scripts/setup.sh` so the dev path and the
    /// in-app path stay in sync. If we ever move to a smaller model (e.g.
    /// `ggml-base.en-q5_1.bin`) update this and `WhisperRunner.modelURL`
    /// in lockstep.
    private let downloadURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
    )!

    /// Approximate expected size — used as a quick sanity check after
    /// download to catch obviously-truncated files. Authoritative
    /// integrity comes from the SHA-256 below.
    private let expectedMinBytes: Int64 = 100_000_000

    /// SHA-256 of the canonical Hugging Face ggml-base.en.bin
    /// (147,964,211 bytes). Verified by `shasum -a 256` against a clean
    /// download. If we ever swap to a different model file (small.en,
    /// quantized variant, Core ML encoder package, etc.) update this in
    /// lockstep with `downloadURL` — a mismatch is treated as tampering
    /// and the file is removed.
    private let expectedSHA256: String = "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"

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

    /// Recompute `status` from disk. Cheap when the file is already in
    /// page cache — at ~150 MB the SHA pass takes ~50-100 ms on M-series
    /// silicon. Called once on launch (init) and after a download
    /// completes, so the user-felt cost is invisible.
    func refreshStatus() {
        let url = WhisperRunner.modelURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            status = .missing
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        if size < expectedMinBytes {
            // Truncated download from a previous attempt — treat as missing.
            try? FileManager.default.removeItem(at: url)
            status = .missing
            return
        }
        // SHA-256 verification. Mismatch means tampering, partial
        // download corruption, or a different model dropped at the same
        // path — in every case the safe action is to remove and re-fetch.
        if let actual = Self.sha256(of: url), actual != expectedSHA256 {
            NSLog("[ListenToMe] model SHA mismatch (got \(actual.prefix(12))…, expected \(expectedSHA256.prefix(12))…) — removing")
            try? FileManager.default.removeItem(at: url)
            status = .failed(message: "Model integrity check failed — re-download required")
            return
        }
        status = .ready(sizeBytes: size)
    }

    /// Stream the file through SHA256 in 1 MB chunks so we never load the
    /// 150 MB blob into memory all at once.
    private static func sha256(of url: URL) -> String? {
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

    /// Begin a download if we don't already have one in flight.
    func startDownload() {
        if case .downloading = status { return }
        if case .ready = status { return }

        // Ensure the destination directory exists. Mirrors WhisperRunner.modelURL.
        let dest = WhisperRunner.modelURL
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        status = .downloading(progress: 0)
        let task = session.downloadTask(with: downloadURL)
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        refreshStatus()
    }

    fileprivate func handleProgress(_ p: Double) {
        status = .downloading(progress: max(0, min(1, p)))
    }

    fileprivate func handleFinished(temp: URL) {
        let dest = WhisperRunner.modelURL
        do {
            // Move temp file to final destination. Replace any existing
            // truncated file from a prior attempt.
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
    }

    fileprivate func handleFailure(_ error: Error) {
        downloadTask = nil
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
        // and dispatch — synchronously snapshot, then hop to main.
        // Move it to a stable temp file we own so it doesn't get cleaned up
        // before MainActor.handleFinished runs.
        let owned = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListenToMe-model-\(UUID().uuidString).bin")
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
