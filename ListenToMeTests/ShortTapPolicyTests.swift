import XCTest
@testable import ListenToMe

/// Tests for `ShortTapPolicy`: the pure decision behind CORR-01's short-tap
/// correction popover. Fixes the bug where a short tap could never open
/// correction because by the time the decision ran, `state.phase` already
/// reflected the tap's own just-discarded recording rather than the
/// dictation that preceded it.
final class ShortTapPolicyTests: XCTestCase {

    func test_opensCorrection_true_whenPhaseAtPressWasSuccess_andHasToken() {
        XCTAssertTrue(ShortTapPolicy.opensCorrection(
            phaseAtPress: .success(preview: "hi"), hasPasteToken: true))
    }

    func test_opensCorrection_false_whenNoPasteToken() {
        XCTAssertFalse(ShortTapPolicy.opensCorrection(
            phaseAtPress: .success(preview: "hi"), hasPasteToken: false))
    }

    func test_opensCorrection_false_whenPhaseAtPressWasPolishing() {
        // Clean-first hasn't pasted anything yet, opening correction here
        // would edit the token from the dictation before this one.
        XCTAssertFalse(ShortTapPolicy.opensCorrection(
            phaseAtPress: .polishing(rawPreview: "revising"), hasPasteToken: true))
    }

    func test_opensCorrection_false_whenPhaseAtPressWasIdle() {
        XCTAssertFalse(ShortTapPolicy.opensCorrection(
            phaseAtPress: .idle, hasPasteToken: true))
    }

    func test_opensCorrection_false_whenPhaseAtPressWasRecording() {
        XCTAssertFalse(ShortTapPolicy.opensCorrection(
            phaseAtPress: .recording, hasPasteToken: true))
    }

    func test_opensCorrection_false_whenPhaseAtPressWasError() {
        XCTAssertFalse(ShortTapPolicy.opensCorrection(
            phaseAtPress: .error(message: "oops"), hasPasteToken: true))
    }
}
