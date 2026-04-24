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
        case .openApp(let name):     return try openApplication(named: name)
        case .shell(let body):       return try runShell(body)
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

    private static func openApplication(named rawName: String) throws -> String {
        // Strip trailing punctuation Whisper sometimes adds ("open chrome.")
        let name = rawName.trimmingCharacters(in: CharacterSet(charactersIn: ".,?! "))

        // Try launching by display name via NSWorkspace
        let ws = NSWorkspace.shared
        if let url = ws.urlForApplication(withBundleIdentifier: name) {
            try ws.launchApplication(at: url, options: [], configuration: [:])
            return "Opened \(name)"
        }
        // Fall back to fuzzy name match via `open -a`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", name]
        let err = Pipe()
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "ListenToMe.Command", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to open \(name): \(msg)"])
        }
        return "Opened \(name)"
    }

    private static func runShell(_ body: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", body]
        proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "ListenToMe.Command", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Shell failed: \(msg)"])
        }
        let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preview = output.split(separator: "\n").first.map(String.init) ?? "Shell OK"
        return String(preview.prefix(50))
    }
}
