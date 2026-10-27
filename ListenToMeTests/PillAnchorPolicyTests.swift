import XCTest
@testable import ListenToMe

final class PillAnchorPolicyTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let bypassSize = CGSize(width: 360, height: 34)

    func testRestoredIdleChipIsVisibleInsideScreen() {
        XCTAssertTrue(PillAnchorPolicy.isVisible(CGPoint(x: 400, y: 40), on: [main]))
    }

    func testHalfVisibleChipUsesSeparateWidthAndHeightThresholds() {
        XCTAssertTrue(PillAnchorPolicy.isVisible(.zero, on: [main]))
        XCTAssertFalse(PillAnchorPolicy.isVisible(CGPoint(x: -1, y: 20), on: [main]))
        XCTAssertFalse(PillAnchorPolicy.isVisible(CGPoint(x: 20, y: -1), on: [main]))
    }

    func testOffscreenOrDisconnectedMonitorRejectsSavedAnchor() {
        let external = CGRect(x: 800, y: 0, width: 1000, height: 800)
        let saved = CGPoint(x: 1400, y: 30)
        XCTAssertTrue(PillAnchorPolicy.isVisible(saved, on: [main, external]))
        XCTAssertFalse(PillAnchorPolicy.isVisible(saved, on: [main]))
        XCTAssertFalse(PillAnchorPolicy.isVisible(saved, on: []))
    }

    func testExpandedBypassControlsFitAtLeftAndRightEdges() {
        let left = PillAnchorPolicy.displayAnchor(CGPoint(x: 0, y: 40), visibleSize: bypassSize, on: [main])
        let right = PillAnchorPolicy.displayAnchor(CGPoint(x: 800, y: 40), visibleSize: bypassSize, on: [main])
        XCTAssertEqual(left.x, 188)
        XCTAssertEqual(right.x, 612)
        XCTAssertEqual(left.y, 40)
        XCTAssertEqual(right.y, 40)
    }

    func testExpandedControlsFitAtTopAndBottomEdges() {
        let bottom = PillAnchorPolicy.displayAnchor(CGPoint(x: 400, y: 0), visibleSize: bypassSize, on: [main])
        let top = PillAnchorPolicy.displayAnchor(CGPoint(x: 400, y: 600), visibleSize: bypassSize, on: [main])
        XCTAssertEqual(bottom.y, 8)
        XCTAssertEqual(top.y, 558)
    }

    func testExpandedControlsStayOnTheirContainingMonitor() {
        let external = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        let saved = CGPoint(x: -5, y: 780)
        let displayed = PillAnchorPolicy.displayAnchor(saved, visibleSize: bypassSize, on: [main, external])
        XCTAssertEqual(displayed, CGPoint(x: -188, y: 758))
        XCTAssertEqual(saved, CGPoint(x: -5, y: 780))
    }

    func testExpandedControlsIncludePreviewHeadroomInVerticalClamp() {
        let previewSize = CGSize(width: 176, height: 94)
        let displayed = PillAnchorPolicy.displayAnchor(CGPoint(x: 400, y: 590), visibleSize: previewSize, on: [main])
        XCTAssertEqual(displayed.y, 498)
    }

    func testMissingScreensLeavesAnchorUnchanged() {
        let saved = CGPoint(x: 100, y: 100)
        XCTAssertEqual(PillAnchorPolicy.displayAnchor(saved, visibleSize: bypassSize, on: []), saved)
    }
}
