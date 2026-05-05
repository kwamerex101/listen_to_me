import Foundation

/// Spawns the `claude` CLI as a subprocess for transcript cleanup.
/// Mirrors the `WhisperRunner` pattern: Process + Pipe + terminationHandler.
enum ClaudeError: Error {
    case binaryNotFound
    case processFailed(code: Int32, stderr: String)
    case timedOut
    case emptyOutput
}

struct ClaudeClient {
    static let shared = ClaudeClient()

    /// Strict cleanup prompt — minimal intervention, reject anything that looks
    /// like preamble/commentary, match voice exactly.
    static let cleanupSystemPrompt: String = """
    You are a text-cleanup tool. The user message is a raw Whisper transcript of spoken dictation.

    TASK: Return the same text with ONLY these corrections:
      • Fix punctuation and capitalization.
      • Remove disfluency filler words: um, uh, er, uhm, erm, you know, like (only when used as filler), i mean.
      • Collapse repeated stutters ("the the cat" → "the cat").

    HARD RULES — violating any makes the output invalid:
      1. Output ONLY the cleaned text. Nothing else.
      2. No preamble. No "Here is", "Here's", "Sure", "Certainly", "Of course".
      3. No quotes around the output. No markdown. No code fences.
      4. Do NOT rewrite, summarize, translate, expand, or add ideas.
      5. Keep every content word the speaker used.
      6. If the input is already clean, return it unchanged.
      7. If you are unsure, return the input unchanged.

    EXAMPLES:

    Input: um so like i was thinking we could maybe you know try that approach
    Output: So I was thinking we could maybe try that approach.

    Input: the the cat sat on the mat
    Output: The cat sat on the mat.

    Input: hello world
    Output: Hello world.
    """

    /// Spawns `claude --print --bare ...` and feeds the transcript on stdin.
    /// Returns the cleaned text (already passed through `sanitize`).
    func clean(_ text: String, timeout: TimeInterval = 20) async throws -> String {
        // NOTE: deliberately NOT passing `--bare` — bare mode requires
        // ANTHROPIC_API_KEY (it ignores OAuth/keychain). The whole point of
        // shelling out to `claude` is to reuse the user's Claude Code
        // subscription auth, so we accept the slower default startup.
        let stdoutData = try await runClaude(
            input: text,
            args: [
                "--print",
                "--no-session-persistence",
                "--disable-slash-commands",
                "--model", "haiku",
                "--output-format", "text",
                "--append-system-prompt", Self.cleanupSystemPrompt,
            ],
            timeout: timeout
        )

        let raw = String(data: stdoutData, encoding: .utf8) ?? ""
        let sanitized = Self.sanitize(cleaned: raw, original: text)
        if sanitized.isEmpty { throw ClaudeError.emptyOutput }
        return sanitized
    }

    /// Quick check that the `claude` binary resolves on PATH. Used at launch
    /// to decide whether cleanup is viable.
    func isAvailable(timeout: TimeInterval = 2) async -> Bool {
        do {
            _ = try await runEnv(args: ["which", "claude"], input: nil, timeout: timeout)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Subprocess plumbing

    /// Spawns `/usr/bin/env claude <args>` with stdin piped and stdout captured.
    private func runClaude(input: String, args: [String], timeout: TimeInterval) async throws -> Data {
        try await runEnv(args: ["claude"] + args, input: input, timeout: timeout)
    }

    /// Generic `/usr/bin/env <args>` runner. macOS GUI apps inherit a stripped
    /// PATH, so we extend it here to include the common install locations for
    /// user-installed CLIs (npm global, ~/.local/bin, Homebrew).
    @discardableResult
    private func runEnv(args: [String], input: String?, timeout: TimeInterval) async throws -> Data {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = args
        proc.environment = Self.augmentedEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        let stdinPipe: Pipe?
        if input != nil {
            let p = Pipe()
            proc.standardInput = p
            stdinPipe = p
        } else {
            proc.standardInput = FileHandle.nullDevice
            stdinPipe = nil
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            // One-shot guard so we don't resume the continuation twice
            // (e.g. process exits exactly as the timeout fires).
            let didResume = Atomic(false)

            let timeoutItem = DispatchWorkItem {
                if proc.isRunning {
                    proc.terminate()
                    if didResume.compareAndSet(expected: false, new: true) {
                        cont.resume(throwing: ClaudeError.timedOut)
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            proc.terminationHandler = { p in
                timeoutItem.cancel()
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                guard didResume.compareAndSet(expected: false, new: true) else { return }

                if p.terminationStatus != 0 {
                    cont.resume(throwing: ClaudeError.processFailed(code: p.terminationStatus, stderr: errStr))
                    return
                }
                cont.resume(returning: outData)
            }

            do {
                try proc.run()
            } catch {
                timeoutItem.cancel()
                if didResume.compareAndSet(expected: false, new: true) {
                    // POSIX ENOENT (2) when /usr/bin/env can't find the binary.
                    cont.resume(throwing: ClaudeError.binaryNotFound)
                }
                return
            }

            if let stdinPipe, let input {
                let handle = stdinPipe.fileHandleForWriting
                if let data = input.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            }
        }
    }

    /// PATH extension so `/usr/bin/env claude` resolves when launched from
    /// /Applications (where Finder hands us a minimal PATH).
    private static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extras = [
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let merged = (extras + existing.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { acc, p in if !acc.contains(p) { acc.append(p) } }
            .joined(separator: ":")
        env["PATH"] = merged
        return env
    }

    /// Defensive filter on the model's response. Rejects common failure modes
    /// by returning the original text unchanged.
    static func sanitize(cleaned raw: String, original: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip wrapping quotes (single / double / smart)
        let quotePairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("\u{201C}", "\u{201D}"), ("\u{2018}", "\u{2019}")]
        for (open, close) in quotePairs {
            if text.first == open && text.last == close && text.count >= 2 {
                text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Strip markdown code fences
        if text.hasPrefix("```") {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 3 {
                text = lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Reject if starts with a known preamble — fall back to original
        let preambles = [
            "here is", "here's", "sure,", "sure!", "certainly", "of course",
            "cleaned:", "cleaned text:", "output:", "result:",
            "the cleaned text", "i've cleaned", "i have cleaned",
        ]
        let lower = text.lowercased()
        for p in preambles {
            if lower.hasPrefix(p) { return original }
        }

        // Reject if word count explodes (>1.4× original is likely hallucination)
        let origWords = original.split(whereSeparator: \.isWhitespace).count
        let cleanWords = text.split(whereSeparator: \.isWhitespace).count
        if origWords > 0, Double(cleanWords) > Double(origWords) * 1.4 + 1 {
            return original
        }

        // Reject if empty
        if text.isEmpty { return original }

        return text
    }
}

/// Tiny atomic-bool helper for the timeout/termination race.
private final class Atomic<T: Equatable> {
    private var value: T
    private let lock = NSLock()
    init(_ initial: T) { value = initial }
    func compareAndSet(expected: T, new: T) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if value == expected { value = new; return true }
        return false
    }
}
