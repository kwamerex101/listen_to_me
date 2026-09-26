import AppKit
import Foundation

enum WfCommand: Equatable {
    /// Append to today's daily note at ~/Documents/daily/YYYY-MM-DD.md
    case logToday(text: String)
    /// Launch a Mac app by display name.
    case openApp(name: String)
    /// Shell one-liner executed via `/bin/sh -c`.
    case shell(body: String)
}

enum CommandRouter {

    // MARK: - Parsing

    /// Matches against the raw whisper output. Case-insensitive; whisper often
    /// capitalizes and punctuates — strip both first.
    static func parse(_ raw: String) -> WfCommand? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        let lower = normalized.lowercased()

        // "log to today: …" or "log today: …"
        for marker in ["log to today:", "log today:", "log to today,", "log today,"] {
            if lower.hasPrefix(marker) {
                let body = String(normalized.dropFirst(marker.count))
                    .trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { return nil }
                return .logToday(text: body)
            }
        }

        // "shell: …"
        if lower.hasPrefix("shell:") || lower.hasPrefix("shell,") {
            let body = String(normalized.dropFirst(6))
                .trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return nil }
            return .shell(body: body)
        }

        // "open <app>"
        if lower.hasPrefix("open ") {
            let name = String(normalized.dropFirst(5))
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return .openApp(name: name)
        }

        return nil
    }

    // MARK: - Execution

    @discardableResult
    static func execute(_ command: WfCommand) async throws -> String {
        switch command {
        case .logToday(let text):    return try appendToDailyNote(text)
        case .openApp(let name):     return try await openApplication(named: name)
        case .shell(let body):       return try await runShell(body)
        }
    }

    /// True when a failed command should silently fall back to the normal
    /// dictation pipeline (paste the raw words) rather than surface an
    /// error. Only `.openApp` qualifies: "Open the PR and merge it" parses
    /// as `.openApp(name: "the PR and merge it")` purely because it starts
    /// with "open " — that's ordinary English, not a command the user
    /// meant, so failing to launch an app by that name shouldn't eat the
    /// dictation behind a "Command failed" cue. `.logToday` and `.shell`
    /// are unambiguous, deliberate commands, so their failures still
    /// surface as errors.
    static func fallsBackToDictation(on command: WfCommand) -> Bool {
        switch command {
        case .openApp: return true
        case .logToday, .shell: return false
        }
    }

    private static func appendToDailyNote(_ text: String) throws -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())

        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let stamp = tf.string(from: Date())

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/daily", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let file = dir.appendingPathComponent("\(today).md")
        let line = "- **\(stamp)** — \(text)\n"
        if FileManager.default.fileExists(atPath: file.path),
           let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            let header = "# \(today)\n\n"
            try (header + line).write(to: file, atomically: true, encoding: .utf8)
        }
        return "Logged to \(today).md"
    }

    private static func openApplication(named rawName: String) async throws -> String {
        // Strip trailing punctuation Whisper sometimes adds ("open chrome.")
        let name = rawName.trimmingCharacters(in: CharacterSet(charactersIn: ".,?! "))

        // Try launching by display name via NSWorkspace (sync, fast).
        let ws = NSWorkspace.shared
        if let url = ws.urlForApplication(withBundleIdentifier: name) {
            try ws.launchApplication(at: url, options: [], configuration: [:])
            return "Opened \(name)"
        }
        // Fall back to fuzzy name match via `open -a`. Runs as a subprocess
        // so we don't block the main actor while it spins up the target app.
        let result = try await runProcess(
            url: URL(fileURLWithPath: "/usr/bin/open"),
            args: ["-a", name],
            captureStdout: false
        )
        if result.exitCode != 0 {
            throw NSError(
                domain: "ListenToMe.Command", code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: "Failed to open \(name): \(result.stderr)"]
            )
        }
        return "Opened \(name)"
    }

    private static func runShell(_ body: String) async throws -> String {
        let result = try await runProcess(
            url: URL(fileURLWithPath: "/bin/sh"),
            args: ["-c", body],
            workingDir: FileManager.default.homeDirectoryForCurrentUser,
            captureStdout: true,
            timeout: 30
        )
        if result.exitCode != 0 {
            throw NSError(
                domain: "ListenToMe.Command", code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: "Shell failed: \(result.stderr)"]
            )
        }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = output.split(separator: "\n").first.map(String.init) ?? "Shell OK"
        return String(preview.prefix(50))
    }

    // MARK: - Async subprocess helper

    struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    enum ProcessError: Error, LocalizedError {
        case timedOut(TimeInterval)

        var errorDescription: String? {
            switch self {
            case .timedOut(let seconds): return "Command timed out after \(Int(seconds))s"
            }
        }
    }

    /// Thread-safe append-only byte buffer. `readabilityHandler` fires on a
    /// GCD dispatch-I/O thread, not the caller's — this is the only state
    /// that thread and the resume path both touch.
    private final class PipeBuffer {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) {
            lock.lock(); data.append(chunk); lock.unlock()
        }
        func snapshot() -> Data {
            lock.lock(); defer { lock.unlock() }
            return data
        }
    }

    /// Makes sure the continuation is resumed exactly once even though the
    /// termination handler and the timeout watchdog both race to resume it.
    private final class ResumeOnce {
        private let lock = NSLock()
        private var done = false
        /// Returns true the first time it's called; false on every call after.
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    /// Runs a subprocess to completion without blocking the caller. Mirrors
    /// the `Process` + `Pipe` + `terminationHandler` pattern used by
    /// `WhisperRunner` and `ClaudeClient`, with two additions:
    ///
    /// - Both pipes are drained continuously via `readabilityHandler`
    ///   instead of `readDataToEndOfFile()` in the termination handler. A
    ///   child that writes more than the pipe's 64KB kernel buffer before
    ///   exiting would otherwise block forever on a full pipe, and the
    ///   whole dictation pipeline (the pill sits in "transcribing") along
    ///   with it.
    /// - A timeout terminates a runaway child: `terminate()` (SIGTERM),
    ///   then SIGKILL half a second later if it's still alive. Cancelling
    ///   the enclosing `Task` does the same via
    ///   `withTaskCancellationHandler`, so a cancelled command never
    ///   orphans a `/bin/sh`.
    ///
    /// `internal` (not `private`) so tests can call it directly.
    static func runProcess(url: URL,
                           args: [String],
                           workingDir: URL? = nil,
                           captureStdout: Bool,
                           timeout: TimeInterval = 15) async throws -> ProcessResult {
        let proc = Process()
        proc.executableURL = url
        proc.arguments = args
        if let wd = workingDir { proc.currentDirectoryURL = wd }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = captureStdout ? stdoutPipe : FileHandle.nullDevice
        proc.standardError = stderrPipe
        proc.standardInput = FileHandle.nullDevice

        let outBuffer = PipeBuffer()
        let errBuffer = PipeBuffer()

        if captureStdout {
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    outBuffer.append(chunk)
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                errBuffer.append(chunk)
            }
        }

        let resumeOnce = ResumeOnce()

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessResult, Error>) in
                let timeoutWork = DispatchWorkItem {
                    guard resumeOnce.claim() else { return }
                    proc.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
                    }
                    cont.resume(throwing: ProcessError.timedOut(timeout))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

                proc.terminationHandler = { p in
                    timeoutWork.cancel()
                    guard resumeOnce.claim() else { return }
                    // Stop the async handlers before the final synchronous
                    // read: FileHandle must not be read both ways at once.
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    // Flush any last bytes that landed after the final
                    // readabilityHandler call but before exit.
                    let tailOut = captureStdout
                        ? stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        : Data()
                    let tailErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    if !tailOut.isEmpty { outBuffer.append(tailOut) }
                    if !tailErr.isEmpty { errBuffer.append(tailErr) }
                    cont.resume(returning: ProcessResult(
                        exitCode: p.terminationStatus,
                        stdout: String(data: outBuffer.snapshot(), encoding: .utf8) ?? "",
                        stderr: String(data: errBuffer.snapshot(), encoding: .utf8) ?? ""
                    ))
                }
                do {
                    try proc.run()
                } catch {
                    timeoutWork.cancel()
                    if resumeOnce.claim() {
                        cont.resume(throwing: error)
                    }
                }
            }
        }, onCancel: {
            if proc.isRunning { proc.terminate() }
        })
    }
}
