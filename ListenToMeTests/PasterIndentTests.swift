import XCTest
@testable import ListenToMe

/// Pure-logic tests for `Paster.injectIndent` — the mirror-indent rule
/// applied when pasting multi-line text at an indented cursor (D-03).
@MainActor
final class PasterIndentTests: XCTestCase {

    func test_noop_when_whitespace_empty() {
        XCTAssertEqual(Paster.injectIndent("a\nb", leadingWhitespace: ""), "a\nb")
    }

    func test_noop_when_single_line() {
        XCTAssertEqual(Paster.injectIndent("hello", leadingWhitespace: "    "), "hello")
    }

    func test_indents_continuation_lines() {
        XCTAssertEqual(
            Paster.injectIndent("line one\nline two\nline three", leadingWhitespace: "  "),
            "line one\n  line two\n  line three"
        )
    }

    func test_blank_lines_stay_blank() {
        // Paragraph breaks from pause detection ("\n\n") must not gain
        // trailing whitespace, and the paragraph after the break still
        // gets the mirror indent.
        XCTAssertEqual(
            Paster.injectIndent("Para one.\n\nPara two.", leadingWhitespace: "\t"),
            "Para one.\n\n\tPara two."
        )
    }

    func test_preserves_tab_indent_unit() {
        XCTAssertEqual(
            Paster.injectIndent("a\nb", leadingWhitespace: "\t\t"),
            "a\n\t\tb"
        )
    }

    func test_trailing_newline_preserved_without_dangling_indent() {
        XCTAssertEqual(
            Paster.injectIndent("a\nb\n", leadingWhitespace: "  "),
            "a\n  b\n"
        )
    }
}
