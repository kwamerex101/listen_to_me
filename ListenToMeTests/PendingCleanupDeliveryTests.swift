import XCTest
@testable import ListenToMe

final class PendingCleanupDeliveryTests: XCTestCase {
    private func record(_ id: Int) -> PendingCleanupDelivery.Record {
        .init(id: id, raw: "raw words", expanded: "Raw words.",
              durMs: 1200, bundleId: "com.example.editor")
    }

    func testBypassWinsAndLatePolishCannotDeliverAgain() {
        var delivery = PendingCleanupDelivery()
        delivery.begin(record(1))
        let bypass = delivery.claim(id: 1, currentID: 1)
        XCTAssertEqual(bypass?.expanded, "Raw words.")
        XCTAssertEqual(bypass?.bundleId, "com.example.editor")
        XCTAssertNil(delivery.claim(id: 1, currentID: 1))
    }

    func testPolishWinsAndRepeatedBypassCannotDeliverAgain() {
        var delivery = PendingCleanupDelivery()
        delivery.begin(record(2))
        XCTAssertEqual(delivery.claim(id: 2, currentID: 2), record(2))
        XCTAssertNil(delivery.claim(id: 2, currentID: 2))
        XCTAssertNil(delivery.claim(id: 2, currentID: 2))
    }

    func testCancelledResultCannotBeClaimed() {
        var delivery = PendingCleanupDelivery()
        delivery.begin(record(1))
        delivery.discard()
        XCTAssertNil(delivery.claim(id: 1, currentID: 1))
    }

    func testStaleCompletionCannotConsumeNewerDictation() {
        var delivery = PendingCleanupDelivery()
        delivery.begin(record(1))
        XCTAssertEqual(delivery.discard(), record(1))
        delivery.begin(record(2))
        XCTAssertNil(delivery.claim(id: 1, currentID: 2))
        XCTAssertEqual(delivery.claim(id: 2, currentID: 2), record(2))
    }

    func testCurrentIdentityMustMatchBeforeAnyDelivery() {
        var delivery = PendingCleanupDelivery()
        delivery.begin(record(1))
        XCTAssertNil(delivery.claim(id: 1, currentID: 2))
        XCTAssertEqual(delivery.pending, record(1))
    }

    func testPendingRecordRetainedOnceForPreemptionHistory() {
        var delivery = PendingCleanupDelivery()
        delivery.begin(record(1))
        XCTAssertEqual(delivery.discard(), record(1))
        XCTAssertNil(delivery.discard())
        XCTAssertNil(delivery.claim(id: 1, currentID: 1))
    }

    func testBypassPillAndWindowShareExpandedWidth() {
        let phase = Phase.polishing(rawPreview: "Raw words.")
        let pill = PillMetrics.pillWidth(phase: phase, showPermissionPrompt: false,
                                         shrunkToDot: false, canInsertWithoutPolish: true)
        let window = PillMetrics.windowSize(phase: phase, showPermissionPrompt: false,
                                             partialPreviewVisible: false, canInsertWithoutPolish: true)
        XCTAssertGreaterThan(pill, PillMetrics.pillWidth(phase: phase,
                             showPermissionPrompt: false, shrunkToDot: false))
        XCTAssertEqual(window.width, pill + PillMetrics.windowPadding * 2)
    }
}
