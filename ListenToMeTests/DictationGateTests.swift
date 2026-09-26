import XCTest
@testable import ListenToMe

/// Tests for `DictationGate`: the pure phase check that fixes the two
/// dictation races in Fix C: a press during `.transcribing` starting a
/// second recording, and `autoReset` yanking an active recording back to
/// `.idle`. Both used to leave the mic on or drop a dictation.
final class DictationGateTests: XCTestCase {

    // MARK: - acceptsPress

    func test_acceptsPress_false_whileRecording() {
        XCTAssertFalse(DictationGate.acceptsPress(in: .recording))
    }

    func test_acceptsPress_false_whileTranscribing() {
        XCTAssertFalse(DictationGate.acceptsPress(in: .transcribing))
    }

    func test_acceptsPress_true_whileIdle() {
        XCTAssertTrue(DictationGate.acceptsPress(in: .idle))
    }

    func test_acceptsPress_true_whileSuccess() {
        XCTAssertTrue(DictationGate.acceptsPress(in: .success(preview: "hi")))
    }

    func test_acceptsPress_true_whilePolishing() {
        XCTAssertTrue(DictationGate.acceptsPress(in: .polishing(rawPreview: "revising")))
    }

    func test_acceptsPress_true_whileNoSpeech() {
        XCTAssertTrue(DictationGate.acceptsPress(in: .noSpeech))
    }

    func test_acceptsPress_true_whileError() {
        XCTAssertTrue(DictationGate.acceptsPress(in: .error(message: "oops")))
    }

    // MARK: - allowsAutoReset

    func test_allowsAutoReset_false_whileRecording() {
        XCTAssertFalse(DictationGate.allowsAutoReset(in: .recording))
    }

    func test_allowsAutoReset_false_whileTranscribing() {
        XCTAssertFalse(DictationGate.allowsAutoReset(in: .transcribing))
    }

    func test_allowsAutoReset_false_whileCorrecting() {
        XCTAssertFalse(DictationGate.allowsAutoReset(in: .correcting))
    }

    func test_allowsAutoReset_false_whileSuggestion() {
        XCTAssertFalse(DictationGate.allowsAutoReset(in: .suggestion(bundleId: "com.example.app", tone: .casual)))
    }

    func test_allowsAutoReset_true_whileSuccess() {
        XCTAssertTrue(DictationGate.allowsAutoReset(in: .success(preview: "hi")))
    }

    func test_allowsAutoReset_true_whileError() {
        XCTAssertTrue(DictationGate.allowsAutoReset(in: .error(message: "oops")))
    }

    func test_allowsAutoReset_true_whileNoSpeech() {
        XCTAssertTrue(DictationGate.allowsAutoReset(in: .noSpeech))
    }

    func test_allowsAutoReset_true_whileIdle() {
        XCTAssertTrue(DictationGate.allowsAutoReset(in: .idle))
    }
}
