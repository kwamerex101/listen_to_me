import XCTest
@testable import ListenToMe

/// Structural tests for `BuiltinTransform.all`. The transforms
/// themselves are LLM-driven (output covered by ClaudeClient.sanitize
/// + the `transform` system-prompt safety rules); these tests verify
/// the catalog itself is well-formed so the menu doesn't ship with
/// duplicate ids, empty labels, or instructions a model can't act on.
final class BuiltinTransformsTests: XCTestCase {

    func test_catalog_is_non_empty() {
        XCTAssertFalse(BuiltinTransform.all.isEmpty)
    }

    func test_all_ids_are_unique() {
        let ids = Set(BuiltinTransform.all.map(\.id))
        XCTAssertEqual(ids.count, BuiltinTransform.all.count,
                       "Duplicate ids would break SwiftUI ForEach diffing")
    }

    func test_all_labels_are_non_empty_and_short() {
        for t in BuiltinTransform.all {
            XCTAssertFalse(t.label.isEmpty, "\(t.id) has empty label")
            XCTAssertLessThanOrEqual(t.label.count, 32,
                                     "\(t.id) label '\(t.label)' is too long for a menu row")
        }
    }

    func test_all_instructions_are_non_trivial() {
        for t in BuiltinTransform.all {
            XCTAssertGreaterThanOrEqual(t.instruction.count, 20,
                                        "\(t.id) instruction is suspiciously short — Claude won't have enough signal")
            // An instruction must end with terminal punctuation so the
            // appended user text reads as a separate sentence.
            let last = t.instruction.last
            XCTAssertTrue(last == "." || last == "!" || last == "?",
                          "\(t.id) instruction should end with terminal punctuation")
        }
    }

    func test_well_known_built_ins_are_present() {
        let labels = Set(BuiltinTransform.all.map { $0.label.lowercased() })
        XCTAssertTrue(labels.contains("make formal"))
        XCTAssertTrue(labels.contains("make casual"))
        XCTAssertTrue(labels.contains("tighten"))
        XCTAssertTrue(labels.contains("bulletize"))
        XCTAssertTrue(labels.contains("summarize"))
    }

    func test_translate_entries_specify_target_language() {
        // Translation entries must name the target language so the
        // model has unambiguous direction.
        let translates = BuiltinTransform.all.filter { $0.label.lowercased().contains("translate") }
        XCTAssertGreaterThanOrEqual(translates.count, 1)
        for t in translates {
            let lower = t.instruction.lowercased()
            XCTAssertTrue(lower.contains("spanish") || lower.contains("french") ||
                          lower.contains("german") || lower.contains("japanese") ||
                          lower.contains("chinese") || lower.contains("portuguese"),
                          "\(t.id) instruction must name a target language")
        }
    }
}
