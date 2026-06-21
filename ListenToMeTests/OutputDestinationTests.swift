import XCTest
@testable import ListenToMe

/// Round-trip + default tests for the output-destination preferences.
/// Tests enum static properties only; no UserDefaults access.
final class OutputDestinationTests: XCTestCase {

    func test_outputDestination_defaults_to_activeApp() {
        XCTAssertEqual(OutputDestination.activeApp.rawValue, "activeApp")
        XCTAssertEqual(OutputDestination(rawValue: "clipboard"), .clipboard)
        XCTAssertEqual(OutputDestination(rawValue: "appleNotes"), .appleNotes)
        XCTAssertEqual(OutputDestination.allCases.count, 3)
    }

    func test_noteMode_cases_and_labels_are_distinct() {
        let labels = NoteMode.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, NoteMode.allCases.count)
        XCTAssertEqual(NoteMode.allCases.count, 3)
    }

    func test_outputDestination_labels_are_nonempty() {
        for d in OutputDestination.allCases {
            XCTAssertFalse(d.label.isEmpty)
        }
    }
}
