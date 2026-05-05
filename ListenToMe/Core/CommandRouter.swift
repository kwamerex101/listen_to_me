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
            captureStdout: true
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

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Runs a subprocess to completion without blocking the caller. Mirrors
    /// the `Process` + `Pipe` + `terminationHandler` pattern used by
    /// `WhisperRunner` and `ClaudeClient`.
    private static func runProcess(url: URL,
                                   args: [String],
                                   workingDir: URL? = nil,
                                   captureStdout: Bool) async throws -> ProcessResult {
        let proc = Process()
        proc.executableURL = url
        proc.arguments = args
        if let wd = workingDir { proc.currentDirectoryURL = wd }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = captureStdout ? stdoutPipe : FileHandle.nullDevice
        proc.standardError = stderrPipe
        proc.standardInput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessResult, Error>) in
            proc.terminationHandler = { p in
                let outData = captureStdout
                    ? stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    : Data()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: ProcessResult(
                    exitCode: p.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                ))
            }
            do {
                try proc.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
