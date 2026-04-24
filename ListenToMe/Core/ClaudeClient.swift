import Foundation

/// Thin HTTP client for the local `claude_local_api` FastAPI wrapper.
/// Base URL: http://localhost:8765
enum ClaudeError: Error {
    case badStatus(code: Int, body: String)
    case decodeFailed
    case serverUnreachable
}

struct ClaudeClient {
    static let shared = ClaudeClient()

    var baseURL = URL(string: "http://localhost:8765")!

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

    /// Calls /subprocess/query (the CLI-subprocess provider — most reliable locally).
    func clean(_ text: String, timeout: TimeInterval = 20) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("subprocess/query"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout

        let body: [String: Any] = [
            "prompt": text,
            "system": Self.cleanupSystemPrompt,
            "max_turns": 1,
            "stream": false,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw ClaudeError.serverUnreachable
        }

        guard let http = resp as? HTTPURLResponse else {
            throw ClaudeError.decodeFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.badStatus(code: http.statusCode, body: body)
        }

        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = obj["result"] as? String
        else { throw ClaudeError.decodeFailed }

        return Self.sanitize(cleaned: result, original: text)
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

    /// Quick health check (GET /health). Returns true if the server is reachable.
    func ping(timeout: TimeInterval = 2) async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("health"))
        req.timeoutInterval = timeout
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
