import XCTest
@testable import ListenToMe

/// Pure-logic tests for NotesWriter. No Notes.app contact — only the script
/// strings and helpers are exercised here.
final class NotesWriterTests: XCTestCase {

    func test_escapeHTML_escapes_reserved_characters() {
        XCTAssertEqual(
            NotesWriter.escapeHTML("a < b & c > d \"q\""),
            "a &lt; b &amp; c &gt; d &quot;q&quot;"
        )
    }

    func test_escapeHTML_converts_newlines_to_breaks() {
        XCTAssertEqual(NotesWriter.escapeHTML("line1\nline2"), "line1<br>line2")
    }

    func test_bodyParagraph_wraps_and_bolds_timestamp() {
        let html = NotesWriter.bodyParagraph(timestamp: "14:05", text: "hello & hi")
        XCTAssertEqual(html, "<div><b>14:05</b>&nbsp;hello &amp; hi</div>")
    }

    func test_noteTitle_dailyNote_uses_date() {
        let t = NotesWriter.noteTitle(mode: .dailyNote, defaultTitle: "ListenToMe",
                                      text: "anything", dateString: "2026-06-21")
        XCTAssertEqual(t, "2026-06-21")
    }

    func test_noteTitle_appendToDefault_uses_default() {
        let t = NotesWriter.noteTitle(mode: .appendToDefault, defaultTitle: "ListenToMe",
                                      text: "anything at all", dateString: "2026-06-21")
        XCTAssertEqual(t, "ListenToMe")
    }

    func test_noteTitle_newEachTime_uses_first_words() {
        let t = NotesWriter.noteTitle(mode: .newEachTime, defaultTitle: "ListenToMe",
                                      text: "Buy milk eggs bread cheese and a dozen other things",
                                      dateString: "2026-06-21")
        // First 6 words.
        XCTAssertEqual(t, "Buy milk eggs bread cheese and")
    }

    func test_noteTitle_newEachTime_empty_text_falls_back_to_date() {
        let t = NotesWriter.noteTitle(mode: .newEachTime, defaultTitle: "ListenToMe",
                                      text: "   ", dateString: "2026-06-21")
        XCTAssertEqual(t, "2026-06-21")
    }

    func test_createScript_embeds_escaped_folder_and_title() {
        let s = NotesWriter.createScript(folder: "ListenToMe", title: "2026-06-21",
                                         bodyHTML: "<div>hi</div>")
        XCTAssertTrue(s.contains("make new folder with properties {name:\"ListenToMe\"}"))
        XCTAssertTrue(s.contains("make new note at thisFolder with properties {name:\"2026-06-21\", body:\"<div>hi</div>\"}"))
    }

    func test_appendScript_concatenates_body() {
        let s = NotesWriter.appendScript(folder: "ListenToMe", title: "ListenToMe",
                                         bodyHTML: "<div>hi</div>")
        XCTAssertTrue(s.contains("set body of theNote to (body of theNote) & \"<div>hi</div>\""))
    }

    func test_scripts_escape_applescript_quotes_in_title() {
        // A title containing a double-quote must not break the AppleScript literal.
        let s = NotesWriter.createScript(folder: "F", title: "say \"hi\"", bodyHTML: "<div>x</div>")
        XCTAssertTrue(s.contains("name:\"say \\\"hi\\\"\""))
    }
}
