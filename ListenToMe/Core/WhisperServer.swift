import Darwin
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

    /// Local-only loopback bind. A random free port is picked at launch
    /// (see `freeLoopbackPort`) so a crashed/orphaned previous instance,
    /// or any other local process squatting a fixed port, can never
    /// answer our probe or receive dictated audio. Falls back to this
    /// fixed port only if the helper can't find one.
    private let host = "127.0.0.1"
    private static let fallbackPort = 18763
    private var port: Int = WhisperServer.fallbackPort

    private var process: Process?
    private var stderrPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var isReady = false
    /// Serializes startup so two concurrent first-calls don't race to
    /// spawn the subprocess.
    private var startupTask: Task<Void, Error>?
    /// Model path the currently-running server was launched with. Used
    /// by `ensureRunning` to detect a model switch and restart.
    private var launchedModelPath: String?

    private var binaryURL: URL? {
        Bundle.main.url(forResource: "whisper-server", withExtension: nil)
    }

    /// Pidfile recording the child's pid across app relaunches, so a
    /// crashed/orphaned previous instance can be identified and killed
    /// before we try to bind the same port again.
    private static var pidfileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ListenToMe/whisper-server.pid")
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
    /// applicationWillTerminate, and on a model switch, so we don't leak
    /// whisper-server processes or keep serving a stale/deleted model.
    ///
    /// Runs synchronously on the caller's thread (main, per the class's
    /// @MainActor isolation): terminate(), poll `isRunning` in 50ms
    /// steps up to 0.5s, then SIGKILL if it's still alive. 0.5s worst
    /// case at quit/model-change is an acceptable, bounded cost, and
    /// unlike a fire-and-forget async fallback, it's guaranteed to run.
    func shutdown() {
        startupTask?.cancel()
        startupTask = nil
        if let p = process, p.isRunning {
            p.terminate()
            var waited: TimeInterval = 0
            while p.isRunning && waited < 0.5 {
                usleep(50_000)
                waited += 0.05
            }
            if p.isRunning {
                kill(p.processIdentifier, SIGKILL)
            }
        }
        try? FileManager.default.removeItem(at: Self.pidfileURL)
        process = nil
        stderrPipe = nil
        stdoutPipe = nil
        isReady = false
        launchedModelPath = nil
    }

    // MARK: - Lifecycle

    private func ensureRunning() async throws {
        // Model changed under a running server (Settings picker /
        // deleteModel already call shutdown() themselves, but this
        // covers any other path that lands here with a stale server).
        if isReady, let p = process, p.isRunning {
            if launchedModelPath != WhisperRunner.modelURL.path {
                shutdown()
            } else {
                return
            }
        }
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

        killStaleOrphan(ourBinaryPath: bin.path)

        port = Self.freeLoopbackPort() ?? Self.fallbackPort

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
        launchedModelPath = model.path
        writePidfile(pid: proc.processIdentifier)

        // Poll the inference endpoint until the server answers. With
        // the model file in page cache, readiness lands in 200-800ms;
        // after a true cold reboot the model load can take ~8s. Cap at
        // 20s so a wedged launch surfaces as an error instead of
        // hanging the dictation pipeline forever — but it's roomy
        // enough that a normal cold-cache start always wins the race.
        let started = Date()
        while Date().timeIntervalSince(started) < 20.0 {
            // Readiness must come from OUR child, if it already exited
            // (bind failure, model load crash, etc.) fail fast instead
            // of waiting out the timeout for a probe that will never
            // succeed.
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
    /// counts as "ready". Safe against a squatter answering on our port:
    /// the port itself is randomized per launch and the orphan check
    /// above only ever kills a pid whose executable matches ours, so by
    /// the time we probe, anything bound here is either our own child
    /// or an unrelated process we'd rather fail against than trust.
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

    // MARK: - Orphan cleanup

    /// Random free loopback port. Binds 127.0.0.1:0, lets the kernel
    /// assign an ephemeral port, reads it back via getsockname, then
    /// closes the socket immediately, whisper-server binds it moments
    /// later. There's a theoretical race if something else grabs the
    /// same port in between, but that's true of any "find a free port"
    /// scheme and is vastly less likely than colliding with a fixed
    /// well-known port. Returns nil on any socket failure.
    static func freeLoopbackPort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return nil }

        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getNameResult = withUnsafeMutablePointer(to: &actual) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &len)
            }
        }
        guard getNameResult == 0 else { return nil }

        return Int(UInt16(bigEndian: actual.sin_port))
    }

    /// Pure decision: should we kill the pid recorded in a stale pidfile
    /// before launching a new server? Only when its executable path is
    /// exactly our bundled whisper-server binary, never a pid that
    /// happens to be alive for an unrelated reason (pid reuse by the
    /// OS after our old child exited).
    static func shouldKillStale(pidExecutablePath: String?, ourBinaryPath: String) -> Bool {
        guard let pidExecutablePath else { return false }
        return pidExecutablePath == ourBinaryPath
    }

    /// If a pidfile from a previous launch exists, and the pid it names
    /// is still alive AND running our exact bundled binary, terminate
    /// it (SIGTERM then SIGKILL) so it can't hold the port or keep
    /// answering with a stale/deleted model. The pidfile is removed
    /// either way once we've looked at it.
    private func killStaleOrphan(ourBinaryPath: String) {
        let pidfile = Self.pidfileURL
        defer { try? FileManager.default.removeItem(at: pidfile) }

        guard let contents = try? String(contentsOf: pidfile, encoding: .utf8),
              let pid = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        // kill(pid, 0) with no signal just checks liveness/permission.
        guard kill(pid, 0) == 0 else { return }

        let execPath = Self.executablePath(forPid: pid)
        guard Self.shouldKillStale(pidExecutablePath: execPath, ourBinaryPath: ourBinaryPath) else { return }

        kill(pid, SIGTERM)
        var waited: TimeInterval = 0
        while kill(pid, 0) == 0 && waited < 0.5 {
            usleep(50_000)
            waited += 0.05
        }
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }

    /// Resolve a pid's executable path via `proc_pidpath` (libproc).
    /// Returns nil if the pid is gone or we lack permission to inspect it.
    private static func executablePath(forPid pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return nil }
        return String(cString: buffer)
    }

    private func writePidfile(pid: Int32) {
        let pidfile = Self.pidfileURL
        try? FileManager.default.createDirectory(
            at: pidfile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? String(pid).write(to: pidfile, atomically: true, encoding: .utf8)
    }

    // MARK: - HTTP inference

    /// Timeout for a single `/inference` POST, scaled to the recording's
    /// length so a long Large-Turbo dictation doesn't time out and get
    /// re-run cold by the CLI fallback. `wavBytes` is the file size of
    /// the 16 kHz mono 16-bit WAV AudioRecorder writes (see
    /// AudioRecorder.swift's `fileSettings`): 32000 bytes/sec of audio,
    /// plus a fixed ~44-byte header. Floors at 30s (today's fixed
    /// value) so short dictations keep their existing margin.
    static func inferenceTimeout(wavBytes: Int) -> TimeInterval {
        let seconds = max(0, Double(wavBytes - 44)) / 32_000
        return max(30, 20 + 1.5 * seconds)
    }

    private func postInference(wav: URL, prompt: String?) async throws -> String {
        let boundary = "----ListenToMeBoundary\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "http://\(host):\(port)/inference")!)
        req.httpMethod = "POST"
        let wavBytes = (try? FileManager.default.attributesOfItem(atPath: wav.path)[.size] as? Int) ?? 0
        req.timeoutInterval = Self.inferenceTimeout(wavBytes: wavBytes)
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
