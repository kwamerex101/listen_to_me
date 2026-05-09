import XCTest
@testable import ListenToMe

/// Tests for `ClaudeClient.sanitize(cleaned:original:)` — the
/// defensive filter that catches the common ways an LLM cleanup
/// response can go wrong, and falls back to the original text rather
/// than pasting garbage. This is the load-bearing safety net in the
/// cleanup path; bugs here are user-visible immediately.
final class ClaudeClientSanitizeTests: XCTestCase {

    // MARK: - Quote stripping

    func test_strips_double_quotes() {
        let out = ClaudeClient.sanitize(cleaned: "\"Hello world.\"", original: "hello world")
        XCTAssertEqual(out, "Hello world.")
    }

    func test_strips_single_quotes() {
        let out = ClaudeClient.sanitize(cleaned: "'Hello world.'", original: "hello world")
        XCTAssertEqual(out, "Hello world.")
    }

    func test_strips_smart_double_quotes() {
        let out = ClaudeClient.sanitize(cleaned: "\u{201C}Hello world.\u{201D}", original: "hello world")
        XCTAssertEqual(out, "Hello world.")
    }

    func test_does_not_strip_mismatched_quotes() {
        // Only strip when first AND last chars are a matched pair.
        let out = ClaudeClient.sanitize(cleaned: "\"Hello world.", original: "hello world")
        XCTAssertEqual(out, "\"Hello world.")
    }

    // MARK: - Markdown fence stripping

    func test_strips_triple_backtick_fences() {
        let raw = "```\nHello world.\n```"
        let out = ClaudeClient.sanitize(cleaned: raw, original: "hello world")
        XCTAssertEqual(out, "Hello world.")
    }

    // MARK: - Preamble rejection

    func test_rejects_here_is_preamble_returns_original() {
        let out = ClaudeClient.sanitize(
            cleaned: "Here is the cleaned text: Hello world.",
            original: "hello world"
        )
        XCTAssertEqual(out, "hello world")
    }

    func test_rejects_sure_preamble() {
        let out = ClaudeClient.sanitize(
            cleaned: "Sure, here you go.",
            original: "hi"
        )
        XCTAssertEqual(out, "hi")
    }

    func test_rejects_certainly_preamble() {
        let out = ClaudeClient.sanitize(
            cleaned: "Certainly! Hello.",
            original: "hello"
        )
        XCTAssertEqual(out, "hello")
    }

    func test_rejects_output_label() {
        let out = ClaudeClient.sanitize(
            cleaned: "Output: Hello world.",
            original: "hello world"
        )
        XCTAssertEqual(out, "hello world")
    }

    // MARK: - Word-count explosion guard

    func test_rejects_when_word_count_explodes() {
        // 1.4× original + 1 is the cap; "the cat" (2 words) → cap = 3.8 → 3.
        // 5 words is over.
        let original = "the cat"
        let cleaned = "Once upon a time the cat sat on the mat by the fire."
        let out = ClaudeClient.sanitize(cleaned: cleaned, original: original)
        XCTAssertEqual(out, original)
    }

    func test_accepts_within_word_count_cap() {
        let original = "hello world"
        let cleaned = "Hello, world."
        let out = ClaudeClient.sanitize(cleaned: cleaned, original: original)
        XCTAssertEqual(out, "Hello, world.")
    }

    // MARK: - Empty rejection

    func test_empty_cleaned_returns_original() {
        let out = ClaudeClient.sanitize(cleaned: "   ", original: "hi")
        XCTAssertEqual(out, "hi")
    }

    // MARK: - Happy path

    func test_clean_punctuation_passes_through() {
        let out = ClaudeClient.sanitize(
            cleaned: "Hello, world. How are you?",
            original: "hello world how are you"
        )
        XCTAssertEqual(out, "Hello, world. How are you?")
    }

    func test_strips_leading_trailing_whitespace() {
        let out = ClaudeClient.sanitize(
            cleaned: "  Hello world.  \n",
            original: "hello world"
        )
        XCTAssertEqual(out, "Hello world.")
    }
}
