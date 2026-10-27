import XCTest
@testable import ListenToMe

final class PracticeDictationAttemptTests: XCTestCase {
    func testTypingWithoutRecordingDoesNotCompletePractice() {
        var attempt = PracticeDictationAttempt()
        XCTAssertFalse(attempt.editorChanged(text: "Typed text"))
        XCTAssertFalse(attempt.recordSuccess(text: "Typed text"))
    }

    func testExistingTextDoesNotCountAsANewInsertion() {
        var attempt = PracticeDictationAttempt()
        attempt.begin(text: "Already typed")
        XCTAssertFalse(attempt.recordSuccess(text: "Already typed"))
        XCTAssertFalse(attempt.editorChanged(text: "Already typed"))
    }

    func testSuccessBeforeSyntheticPasteWaitsForEditorChange() {
        var attempt = PracticeDictationAttempt()
        attempt.begin(text: "")
        XCTAssertFalse(attempt.recordSuccess(text: ""))
        XCTAssertTrue(attempt.editorChanged(text: "Dictated words"))
        XCTAssertFalse(attempt.editorChanged(text: "Dictated words again"))
    }

    func testSyntheticPasteBeforeSuccessWaitsForPipeline() {
        var attempt = PracticeDictationAttempt()
        attempt.begin(text: "")
        XCTAssertFalse(attempt.editorChanged(text: "Dictated words"))
        XCTAssertTrue(attempt.recordSuccess(text: "Dictated words"))
    }

    func testScratchOrOtherDestinationWithoutEditorChangeDoesNotComplete() {
        var attempt = PracticeDictationAttempt()
        attempt.begin(text: "Existing text")
        XCTAssertFalse(attempt.recordSuccess(text: "Existing text"))
    }

    func testEmptyOrWhitespaceEditorDoesNotComplete() {
        var attempt = PracticeDictationAttempt()
        attempt.begin(text: "Existing text")
        XCTAssertFalse(attempt.recordSuccess(text: ""))
        XCTAssertFalse(attempt.editorChanged(text: " \n "))
    }

    func testResetClearsPendingSuccessForCancelErrorOrStepExit() {
        var attempt = PracticeDictationAttempt()
        attempt.begin(text: "")
        XCTAssertFalse(attempt.recordSuccess(text: ""))
        attempt.reset()
        XCTAssertFalse(attempt.editorChanged(text: "Late paste"))
    }

    func testNewRecordingReplacesPriorBaselineAndSuccess() {
        var attempt = PracticeDictationAttempt()
        attempt.begin(text: "")
        XCTAssertFalse(attempt.recordSuccess(text: ""))
        attempt.begin(text: "Existing text")
        XCTAssertFalse(attempt.editorChanged(text: "Existing text plus dictation"))
        XCTAssertTrue(attempt.recordSuccess(text: "Existing text plus dictation"))
    }
}
