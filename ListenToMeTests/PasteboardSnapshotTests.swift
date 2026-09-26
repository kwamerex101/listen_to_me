import XCTest
import AppKit
@testable import ListenToMe

/// Tests for `PasteboardSnapshot`: the full-pasteboard capture/restore used
/// to give the user their clipboard back after a dictation paste, including
/// non-string types (images, files, rich text), not just `.string`.
final class PasteboardSnapshotTests: XCTestCase {

    private var pb: NSPasteboard!

    override func setUp() {
        super.setUp()
        pb = NSPasteboard(name: NSPasteboard.Name("ltm-test-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pb.releaseGlobally()
        pb = nil
        super.tearDown()
    }

    func test_roundTrips_stringCustomTypeAndRTF_exactly() {
        let binaryType = NSPasteboard.PasteboardType("com.listentome.test.binary")
        let binaryBytes = Data([0x00, 0x01, 0xFF, 0x42, 0x13])
        let rtfData = "Hello world".data(using: .utf8)!

        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("Hello world", forType: .string)
        item.setData(binaryBytes, forType: binaryType)
        item.setData(rtfData, forType: .rtf)
        pb.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(from: pb)

        // Overwrite the pasteboard with something else entirely, then restore.
        pb.clearContents()
        pb.setString("clobbered", forType: .string)

        snapshot.restore(to: pb)

        XCTAssertEqual(pb.string(forType: .string), "Hello world")
        XCTAssertEqual(pb.data(forType: binaryType), binaryBytes)
        XCTAssertEqual(pb.data(forType: .rtf), rtfData)
    }

    func test_emptySnapshot_restoresToEmptyPasteboard() {
        // Nothing on the pasteboard at capture time.
        pb.clearContents()
        let snapshot = PasteboardSnapshot.capture(from: pb)
        XCTAssertTrue(snapshot.isEmpty)

        // Put something on it, then restore the empty snapshot.
        pb.setString("should be cleared", forType: .string)
        snapshot.restore(to: pb)

        XCTAssertNil(pb.string(forType: .string))
        XCTAssertTrue(pb.pasteboardItems?.isEmpty ?? true)
    }

    func test_concealedPassword_isNotCapturedOrRestored() {
        // A password manager's copy: string plus the nspasteboard.org marker.
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("hunter2", forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(from: pb)
        XCTAssertTrue(snapshot.isEmpty)

        // Our dictation goes on the clipboard; the restore must clear it and
        // must not put the password back.
        pb.clearContents()
        pb.setString("dictated text", forType: .string)
        snapshot.restore(to: pb)
        XCTAssertNil(pb.string(forType: .string))
    }
}

/// Tests for `Paster.pasteboardUntouched(since:currentChangeCount:)`: Gate 3
/// of `Paster.replace`. Fix B3: an automatic clipboard restore bumps
/// `changeCount`, so this needs to tell "we restored it ourselves" apart
/// from "the user copied something" without breaking the gate.
final class PasterPasteboardUntouchedTests: XCTestCase {

    private func makeToken(changeCountAtPaste: Int) -> PasteToken {
        PasteToken(
            bundleId: "com.example.app",
            changeCountAtPaste: changeCountAtPaste,
            pastedText: "hello",
            priorPasteboard: PasteboardSnapshot(items: []),
            timestamp: Date(),
            selection: nil
        )
    }

    func test_true_forExactChangeCount() {
        let token = makeToken(changeCountAtPaste: 100)
        XCTAssertTrue(Paster.pasteboardUntouched(since: token, currentChangeCount: 100))
    }

    func test_false_forDifferentChangeCount() {
        let token = makeToken(changeCountAtPaste: 200)
        XCTAssertFalse(Paster.pasteboardUntouched(since: token, currentChangeCount: 201))
    }

    func test_true_afterRecordedRestore() {
        let token = makeToken(changeCountAtPaste: 300)
        Paster.recordRestore(pasteChangeCount: 300, restoredChangeCount: 301)
        XCTAssertTrue(Paster.pasteboardUntouched(since: token, currentChangeCount: 301))
    }

    func test_boundedMap_dropsEarliestEntry() {
        // Record 20 restores with distinct, increasing keys; only the most
        // recent ~8 should remain, so the earliest is evicted.
        let base = 10_000
        for i in 0..<20 {
            Paster.recordRestore(pasteChangeCount: base + i, restoredChangeCount: base + i + 1)
        }
        let earliestToken = makeToken(changeCountAtPaste: base)
        XCTAssertFalse(Paster.pasteboardUntouched(since: earliestToken, currentChangeCount: base + 1))

        let latestToken = makeToken(changeCountAtPaste: base + 19)
        XCTAssertTrue(Paster.pasteboardUntouched(since: latestToken, currentChangeCount: base + 20))
    }
}
