import Foundation

/// Spawns the `claude` CLI as a subprocess for transcript cleanup.
/// Mirrors the `WhisperRunner` pattern: Process + Pipe + terminationHandler.
enum ClaudeError: Error {
    case binaryNotFound
    case processFailed(code: Int32, stderr: String)
    case timedOut
    case emptyOutput
    /// User picked the .api backend but no key is in the Keychain.
    case apiKeyMissing
    /// Anthropic API returned a non-2xx status.
    case apiHTTPError(status: Int, body: String)
    /// Anthropic API returned 2xx but the body wasn't shaped how we expected.
    case apiResponseMalformed(String)
}

struct ClaudeClient {
    static let shared = ClaudeClient()

    /// Code-aware cleanup prompt — swapped in when AppContext.category
    /// is .codeEditor. Same hard-rule safety net as the default
    /// prompt, but the casing/punctuation guidance shifts so the
    /// model doesn't fight code-friendly identifiers.
    static let codeCleanupSystemPrompt: String = """
    You are a text-cleanup tool for dictation INTO a code editor. The user message is a raw Whisper transcript.

    TASK: Return the cleaned text following these rules:
      • Remove disfluency filler words: um, uh, er, uhm, erm, you know, like (only when used as filler), i mean.
      • Collapse repeated stutters ("the the cat" → "the cat").
      • DO NOT auto-capitalize the first word of every sentence — code identifiers and keywords are case-sensitive.
      • If the speaker said "camel case <words>", join them as camelCase (first word lowercase, subsequent words capitalized, no spaces).
      • If the speaker said "pascal case <words>", join them as PascalCase.
      • If the speaker said "snake case <words>", join them with underscores in lowercase: snake_case_words.
      • If the speaker said "kebab case <words>", join them with hyphens in lowercase: kebab-case-words.
      • If the speaker said "screaming snake case <words>", join them in upper snake_case: SCREAMING_SNAKE_CASE.
      • Recognize common programming keywords and keep them lowercase: for, while, if, else, return, function, class, const, let, var, def, async, await, import, from, true, false, null, none, this, self, public, private, static.
      • For ambiguous homophones in code context, prefer the keyword: "for" → for (not four), "if" → if, "while" → while, "return" → return.
      • Punctuation: minimal — only commas / periods that the speaker actually intended.
      • Preserve any escape phrasing like "literal X" or "the word X" verbatim, dropping the marker word.

    HARD RULES — violating any makes the output invalid:
      1. Output ONLY the cleaned text. Nothing else.
      2. No preamble. No "Here is", "Here's", "Sure", "Certainly", "Of course".
      3. No quotes around the output. No markdown. No code fences.
      4. Do NOT rewrite, summarize, translate, expand, or add ideas.
      5. If unsure, return the input unchanged.

    EXAMPLES:

    Input: camel case user name
    Output: userName

    Input: snake case max retry count
    Output: max_retry_count

    Input: for loop from zero to ten
    Output: for loop from zero to ten

    Input: const user name equals new user
    Output: const userName = new User
    """

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
    ///
    /// `bundleId` (Phase 4) opts the call into per-app tone tuning. When set
    /// AND `StyleStore.promptHint(for:)` returns non-nil, the per-tone STYLE
    /// NOTE is PREPENDED above `cleanupSystemPrompt` (HARD RULES section
    /// untouched). When nil or no hint exists, the default prompt is used —
    /// preserving exact pre-0.10.0 behavior at every existing call site.
    func clean(_ text: String,
               bundleId: String? = nil,
               timeout: TimeInterval = 20) async throws -> String {
        // Build effective system prompt on the MainActor (StyleStore.shared
        // and AppContext.current() are @MainActor-isolated). Layered:
        //   [App context]  ← M3a.5: bundleId, app name, category, browser URL
        //   [Per-app tone] ← StyleStore.promptHint, when learned
        //   [Base cleanup] ← cleanupSystemPrompt (HARD RULES untouched)
        // Each layer optional; missing layers just collapse into a
        // shorter prefix.
        let systemPrompt: String = await MainActor.run {
            var sections: [String] = []
            let context = AppContext.current()
            if let line = context.promptLine {
                sections.append("CONTEXT — \(line)")
            }
            if let bundleId, let hint = StyleStore.shared.promptHint(for: bundleId) {
                sections.append(hint)
            }
            // Code-mode swap (M3a.6): if the target is a code editor /
            // terminal, use the casing-aware base prompt. Per-app tone
            // hint still applies on top — they layer.
            let basePrompt: String
            switch context.category {
            case .codeEditor, .terminal:
                basePrompt = Self.codeCleanupSystemPrompt
            default:
                basePrompt = Self.cleanupSystemPrompt
            }
            sections.append(basePrompt)
            return sections.joined(separator: "\n\n")
        }

        // Backend selection per Preferences. .auto picks API when a key
        // is configured (it's ~3-5× faster than CLI cold-start), falls
        // back to CLI otherwise — preserving the original
        // "reuse-Claude-Code-subscription" behavior for users without
        // their own API key.
        let (backend, apiKey): (Preferences.CleanupBackend, String?) = await MainActor.run {
            (Preferences.shared.cleanupBackend, Preferences.shared.anthropicAPIKey)
        }

        let useAPI: Bool
        switch backend {
        case .auto: useAPI = (apiKey?.isEmpty == false)
        case .cli:  useAPI = false
        case .api:  useAPI = true
        }

        if useAPI {
            guard let key = apiKey, !key.isEmpty else { throw ClaudeError.apiKeyMissing }
            return try await runDirectAPI(
                text: text,
                systemPrompt: systemPrompt,
                apiKey: key,
                timeout: timeout
            )
        }

        // CLI path. NOTE: deliberately NOT passing `--bare` — bare mode
        // requires ANTHROPIC_API_KEY (it ignores OAuth/keychain). The whole
        // point of shelling out to `claude` is to reuse the user's Claude
        // Code subscription auth, so we accept the slower default startup.
        let stdoutData = try await runClaude(
            input: text,
            args: [
                "--print",
                "--no-session-persistence",
                "--disable-slash-commands",
                "--model", "haiku",
                "--output-format", "text",
                "--append-system-prompt", systemPrompt,
            ],
            timeout: timeout
        )

        let raw = String(data: stdoutData, encoding: .utf8) ?? ""
        let sanitized = Self.sanitize(cleaned: raw, original: text)
        if sanitized.isEmpty { throw ClaudeError.emptyOutput }
        return sanitized
    }

    /// Rewrite `original` per `revision` instructions. Used by the
    /// Backtrack flow: the user just dictated something, we pasted it,
    /// and now they want a revision rather than an additional paste.
    ///
    /// Returns the rewritten text. Same backend selection as `clean`:
    /// direct API when a key is present, CLI subprocess fallback.
    func rewrite(original: String,
                 revision: String,
                 timeout: TimeInterval = 20) async throws -> String {
        let systemPrompt = """
        You are a text-revision tool. The user previously dictated text and now wants to revise it.

        ORIGINAL TEXT:
        \(original)

        TASK: Apply the user's revision request (in the user message) to the ORIGINAL TEXT and output ONLY the revised text. Preserve the original's overall length and tone unless the revision explicitly changes it.

        HARD RULES — violating any makes the output invalid:
          1. Output ONLY the revised text. Nothing else.
          2. No preamble. No "Here is", "Here's", "Sure", "Certainly", "Of course".
          3. No quotes around the output. No markdown. No code fences.
          4. Do NOT explain what you changed. Do NOT add commentary.
          5. If the revision is unclear or unsafe, return the ORIGINAL TEXT unchanged.

        EXAMPLES:

        ORIGINAL: Send the report by Friday.
        Revision: actually make that next Thursday
        Output: Send the report by next Thursday.

        ORIGINAL: Hey team, the staging URL is broken.
        Revision: change that to the production URL
        Output: Hey team, the production URL is broken.
        """

        let (backend, apiKey): (Preferences.CleanupBackend, String?) = await MainActor.run {
            (Preferences.shared.cleanupBackend, Preferences.shared.anthropicAPIKey)
        }
        let useAPI: Bool
        switch backend {
        case .auto: useAPI = (apiKey?.isEmpty == false)
        case .cli:  useAPI = false
        case .api:  useAPI = true
        }

        if useAPI {
            guard let key = apiKey, !key.isEmpty else { throw ClaudeError.apiKeyMissing }
            return try await runDirectAPI(
                text: revision,
                systemPrompt: systemPrompt,
                apiKey: key,
                timeout: timeout
            )
        }

        let stdoutData = try await runClaude(
            input: revision,
            args: [
                "--print",
                "--no-session-persistence",
                "--disable-slash-commands",
                "--model", "haiku",
                "--output-format", "text",
                "--append-system-prompt", systemPrompt,
            ],
            timeout: timeout
        )
        let raw = String(data: stdoutData, encoding: .utf8) ?? ""
        let sanitized = Self.sanitize(cleaned: raw, original: original)
        if sanitized.isEmpty { throw ClaudeError.emptyOutput }
        return sanitized
    }

    /// Quick check that cleanup is viable. Returns true when EITHER the
    /// `claude` binary resolves on PATH (CLI path) OR an Anthropic API
    /// key is configured (direct path) — matches what `clean(...)` will
    /// actually do.
    func isAvailable(timeout: TimeInterval = 2) async -> Bool {
        // API path is "available" the moment a key exists. Cheap sync
        // check — no network round-trip — because verifying the key
        // would cost a real API call.
        let hasKey = await MainActor.run {
            (Preferences.shared.anthropicAPIKey?.isEmpty == false)
        }
        if hasKey { return true }
        do {
            _ = try await runEnv(args: ["which", "claude"], input: nil, timeout: timeout)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Direct Anthropic API path

    /// POST to `https://api.anthropic.com/v1/messages` with Haiku 4.5.
    /// The system prompt is wrapped in a content block with
    /// `cache_control: ephemeral` so subsequent calls within the cache
    /// window get prompt-caching pricing/latency benefits.
    ///
    /// Target: ~250-500ms vs the CLI subprocess's ~1.5-3s cold start.
    private func runDirectAPI(text: String,
                              systemPrompt: String,
                              apiKey: String,
                              timeout: TimeInterval) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        // Caching prompt blocks is on by default for the messages API
        // when cache_control is present; no separate beta header required
        // as of the 2025+ messages API.

        // Conservative cap — cleaned transcript should never exceed input
        // length, but allow 2× headroom for punctuation expansion etc.
        let inputTokenEstimate = max(64, text.count / 3)
        let maxOutputTokens = min(2048, max(128, inputTokenEstimate * 2))

        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": maxOutputTokens,
            "system": [[
                "type": "text",
                "text": systemPrompt,
                "cache_control": ["type": "ephemeral"],
            ]],
            "messages": [[
                "role": "user",
                "content": text,
            ]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.apiResponseMalformed("non-HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiHTTPError(status: http.statusCode, body: body)
        }

        // Response shape: { content: [{ type: "text", text: "..." }, ...], ... }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw ClaudeError.apiResponseMalformed("missing content array; got: \(preview)")
        }
        let cleaned = content.compactMap { block -> String? in
            guard let type = block["type"] as? String, type == "text" else { return nil }
            return block["text"] as? String
        }.joined()

        let sanitized = Self.sanitize(cleaned: cleaned, original: text)
        if sanitized.isEmpty { throw ClaudeError.emptyOutput }
        return sanitized
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
    ///
    /// Computed once and cached — the inputs (HOME, ProcessInfo env) do not
    /// change at runtime, and we previously rebuilt this on every cleanup
    /// call. Even small allocations matter on a hot path the user feels.
    private static let cachedAugmentedEnvironment: [String: String] = {
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
    }()

    private static func augmentedEnvironment() -> [String: String] {
        cachedAugmentedEnvironment
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
