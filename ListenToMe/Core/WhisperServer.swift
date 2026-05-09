import Foundation

/// Persistent whisper-server subprocess wrapper. Loads the model once
/// and answers per-dictation HTTP requests at `/inference`, eliminating
/// the per-call cold-start (~300-800 ms) of spawning whisper-cli.
///
/// Lifecycle:
///   - First call to `transcribe(...)` lazy-launches the server.
///   - Subsequent calls reuse the running process.
///   - `shutdown()` terminates cleanly on app exit (wired by AppDelegate).
///   - Any HTTP failure (server crashed, port collision, etc.) bubbles
///     up so the caller can fall back to the CLI path.
///
/// Concurrency:
///   - All process state lives on the MainActor.
///   - HTTP calls are async via URLSession; multiple concurrent
///     dictations are technically supported but the audio pipeline is
///     serial in practice (one hotkey hold at a time).
@MainActor
final class WhisperServer {
    static let shared = WhisperServer()

    enum ServerError: Error {
        case binaryNotFound
        case modelNotFound(String)
        case launchFailed(String)
        case startupTimeout
        case httpError(status: Int, body: String)
        case responseMalformed(String)
    }

    /// Local-only loopback bind. Picked high to avoid common collisions.
    /// If anything else is squatting on this port we fail loudly and
    /// fall back to CLI rather than racing for it.
    private let host = "127.0.0.1"
    private let port: Int = 18763

    private var process: Process?
    private var stderrPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var isReady = false
    /// Serializes startup so two concurrent first-calls don't race to
    /// spawn the subprocess.
    private var startupTask: Task<Void, Error>?

    private var binaryURL: URL? {
        Bundle.main.url(forResource: "whisper-server", withExtension: nil)
    }

    private init() {}

    // MARK: - Public

    /// Returns true if the server binary is present in the app bundle —
    /// i.e. the warm-path is even possible. Cheap; safe to call from
    /// hot paths.
    var isAvailable: Bool { binaryURL != nil }

    /// Transcribe `wav` against the running server, lazy-starting it on
    /// first call. `prompt` is forwarded to whisper-server as the
    /// initial prompt. Throws on any failure — caller should fall back
    /// to the CLI path.
    func transcribe(wav: URL, prompt: String? = nil) async throws -> String {
        try await ensureRunning()
        return try await postInference(wav: wav, prompt: prompt)
    }

    /// Tear down the subprocess. Idempotent. Called from AppDelegate's
    /// applicationWillTerminate so we don't leak whisper-server processes.
    func shutdown() {
        startupTask?.cancel()
        startupTask = nil
        if let p = process, p.isRunning {
            p.terminate()
            // SIGTERM grace; if it ignores us, SIGKILL after 1s. Most
            // HTTP servers exit on SIGTERM cleanly.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak p] in
                if let p, p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
        }
        process = nil
        stderrPipe = nil
        stdoutPipe = nil
        isReady = false
    }

    // MARK: - Lifecycle

    private func ensureRunning() async throws {
        if isReady, let p = process, p.isRunning { return }
        // Stale state — a previous server died unexpectedly. Reset.
        if let p = process, !p.isRunning { shutdown() }

        if let inFlight = startupTask {
            try await inFlight.value
            return
        }
        let task = Task<Void, Error> { [weak self] in
            try await self?.launchAndAwaitReady()
        }
        startupTask = task
        defer { startupTask = nil }
        try await task.value
    }

    private func launchAndAwaitReady() async throws {
        guard let bin = binaryURL else { throw ServerError.binaryNotFound }
        let model = WhisperRunner.modelURL
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw ServerError.modelNotFound(model.path)
        }

        let proc = Process()
        proc.executableURL = bin
        proc.arguments = [
            "-m", model.path,
            "--host", host,
            "--port", String(port),
            "--inference-path", "/inference",
            // Mirror whisper-cli args we'd otherwise pass per-call so
            // both paths produce equivalent transcripts.
            "-l", "en",
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        // Drain async so the pipe buffers don't fill and stall the
        // server (same lesson as WhisperRunner Phase C #1).
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }

        do {
            try proc.run()
        } catch {
            throw ServerError.launchFailed(String(describing: error))
        }
        process = proc
        stdoutPipe = outPipe
        stderrPipe = errPipe

        // Poll the inference endpoint until the server answers. With
        // the model file in page cache, readiness lands in 200-800ms;
        // after a true cold reboot the model load can take ~8s. Cap at
        // 20s so a wedged launch surfaces as an error instead of
        // hanging the dictation pipeline forever — but it's roomy
        // enough that a normal cold-cache start always wins the race.
        let started = Date()
        while Date().timeIntervalSince(started) < 20.0 {
            if !proc.isRunning {
                throw ServerError.launchFailed("whisper-server exited during startup")
            }
            if await probeReady() {
                isReady = true
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Timed out — kill the process so we don't leak it, then surface.
        shutdown()
        throw ServerError.startupTimeout
    }

    /// Cheap connectivity check. whisper-server returns 400/405 for a
    /// bare GET on /inference (it expects POST multipart) — that's still
    /// proof the HTTP layer is up. Any successful TCP+HTTP exchange
    /// counts as "ready".
    private func probeReady() async -> Bool {
        var req = URLRequest(url: URL(string: "http://\(host):\(port)/inference")!)
        req.httpMethod = "GET"
        req.timeoutInterval = 0.4
        do {
            _ = try await URLSession.shared.data(for: req)
            return true
        } catch {
            return false
        }
    }

    // MARK: - HTTP inference

    private func postInference(wav: URL, prompt: String?) async throws -> String {
        let boundary = "----ListenToMeBoundary\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "http://\(host):\(port)/inference")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")
        req.httpBody = try multipartBody(boundary: boundary, wav: wav, prompt: prompt)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ServerError.responseMalformed("non-HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServerError.httpError(status: http.statusCode, body: body)
        }

        // Whisper-server returns either JSON ({ "text": "..." }) when
        // response_format=json (default), or plain text when text. We
        // didn't set the format so default JSON applies.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fall back to raw body — tolerate either shape.
        if let plain = String(data: data, encoding: .utf8) {
            return plain.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw ServerError.responseMalformed("could not decode response body")
    }

    private func multipartBody(boundary: String, wav: URL, prompt: String?) throws -> Data {
        var body = Data()
        let crlf = "\r\n"

        // file part
        let wavData = try Data(contentsOf: wav)
        body.append("--\(boundary)\(crlf)")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(wav.lastPathComponent)\"\(crlf)")
        body.append("Content-Type: audio/wav\(crlf)\(crlf)")
        body.append(wavData)
        body.append(crlf)

        if let prompt, !prompt.isEmpty {
            body.append("--\(boundary)\(crlf)")
            body.append("Content-Disposition: form-data; name=\"prompt\"\(crlf)\(crlf)")
            body.append(prompt)
            body.append(crlf)
        }

        // response_format json so we get a stable shape to parse
        body.append("--\(boundary)\(crlf)")
        body.append("Content-Disposition: form-data; name=\"response_format\"\(crlf)\(crlf)")
        body.append("json")
        body.append(crlf)

        body.append("--\(boundary)--\(crlf)")
        return body
    }
}

// Convenience: append UTF-8 string into a Data buffer.
private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
