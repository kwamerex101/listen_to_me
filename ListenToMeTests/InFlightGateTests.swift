import XCTest
@testable import ListenToMe

/// `InFlightGate` is the fix for the use-after-free where switching,
/// deleting, or quitting mid-inference freed a model/context out from
/// under a still-running detached transform/transcribe. These tests drive
/// the pure state machine directly.
final class InFlightGateTests: XCTestCase {

    func test_beginEnd_withoutRelease_endReturnsFalse() {
        var gate = InFlightGate()
        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.end())
        XCTAssertFalse(gate.isBusy)
    }

    func test_release_whileIdle_succeedsImmediately() {
        var gate = InFlightGate()
        XCTAssertTrue(gate.requestRelease())
        XCTAssertFalse(gate.releasePending)
    }

    func test_release_whileBusy_deferredThenEndReturnsTrueOnce() {
        var gate = InFlightGate()
        XCTAssertTrue(gate.begin())

        XCTAssertFalse(gate.requestRelease())
        XCTAssertTrue(gate.releasePending)

        XCTAssertTrue(gate.end())
        XCTAssertFalse(gate.isBusy)
        XCTAssertFalse(gate.releasePending)

        // Second end() (e.g. a defer firing twice by mistake) must not
        // report a release again.
        XCTAssertFalse(gate.end())
    }

    func test_begin_refused_whileBusy() {
        var gate = InFlightGate()
        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())
    }

    func test_begin_refused_whileReleasePending() {
        var gate = InFlightGate()
        XCTAssertTrue(gate.begin())
        _ = gate.requestRelease()
        XCTAssertFalse(gate.begin())
    }

    func test_begin_allowedAgain_afterDeferredReleaseCompletes() {
        var gate = InFlightGate()
        XCTAssertTrue(gate.begin())
        _ = gate.requestRelease()
        _ = gate.end()   // deferred release completes here

        XCTAssertTrue(gate.begin())
    }
}
