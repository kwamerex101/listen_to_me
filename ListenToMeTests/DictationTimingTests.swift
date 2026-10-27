import XCTest
@testable import ListenToMe

final class DictationTimingTests: XCTestCase {
    func testRecordingDurationExcludesTranscriptionAndPolish() {
        var timing = DictationTimingLedger()
        timing.begin(id: 1, at: 0)
        timing.mark(.recordingReady, id: 1, at: 0.1)
        timing.mark(.released, id: 1, at: 2.1)
        timing.mark(.transcribed, id: 1, at: 3.1)
        timing.mark(.polishStarted, id: 1, at: 3.2)
        timing.mark(.polishFinished, id: 1, at: 5.2)
        XCTAssertEqual(timing.recordingDurationMs(id: 1), 2_000)
        timing.finish(id: 1, outcome: .pasted, at: 5.3)
        let sample = timing.samples[0]
        XCTAssertEqual(sample.recordingMs!, 2_000, accuracy: 0.001)
        XCTAssertEqual(sample.transcriptionMs!, 1_000, accuracy: 0.001)
        XCTAssertEqual(sample.polishMs!, 2_000, accuracy: 0.001)
        XCTAssertEqual(sample.deliveryMs!, 3_200, accuracy: 0.001)
    }

    func testStaleOrOutOfOrderEventsCannotChangeCurrentAttempt() {
        var timing = DictationTimingLedger()
        timing.begin(id: 1, at: 10)
        timing.mark(.released, id: 1, at: 11)
        XCTAssertNil(timing.recordingDurationMs(id: 1))
        timing.mark(.recordingReady, id: 1, at: 12)
        timing.mark(.released, id: 1, at: 11)
        XCTAssertNil(timing.recordingDurationMs(id: 1))
        timing.begin(id: 2, at: 13)
        timing.mark(.recordingReady, id: 1, at: 14)
        timing.finish(id: 1, outcome: .pasted, at: 15)
        timing.mark(.recordingReady, id: 2, at: 14)
        timing.mark(.released, id: 2, at: 16)
        XCTAssertEqual(timing.recordingDurationMs(id: 2), 2_000)
        XCTAssertEqual(timing.samples.count, 1)
        XCTAssertEqual(timing.samples.first?.outcome, .cancelled)
    }

    func testCancellationAndBlockedOutcomesAreExcludedFromDeliveryStatistics() {
        var timing = DictationTimingLedger()
        for (id, outcome) in [DictationTimingLedger.Outcome.cancelled, .blocked, .failed].enumerated() {
            timing.begin(id: id, at: 0)
            timing.mark(.recordingReady, id: id, at: 1)
            timing.mark(.released, id: id, at: 2)
            timing.mark(.transcribed, id: id, at: 3)
            timing.finish(id: id, outcome: outcome, at: 4)
        }
        XCTAssertTrue(timing.samples.compactMap(\.deliveryMs).isEmpty)
    }

    func testBypassRecordsWaitWithoutClaimingPolishCompleted() {
        var timing = DictationTimingLedger()
        timing.begin(id: 1, at: 0)
        timing.mark(.recordingReady, id: 1, at: 1)
        timing.mark(.released, id: 1, at: 2)
        timing.mark(.transcribed, id: 1, at: 3)
        timing.mark(.polishStarted, id: 1, at: 3)
        timing.finish(id: 1, outcome: .pasted, bypassedPolish: true, at: 4)
        XCTAssertEqual(timing.samples.first?.polishMs, 1_000)
        XCTAssertEqual(timing.samples.first?.bypassedPolish, true)
        timing.mark(.polishFinished, id: 1, at: 5)
        timing.finish(id: 1, outcome: .pasted, at: 6)
        XCTAssertEqual(timing.samples.count, 1)
    }

    func testPercentilesAndBoundedSamples() {
        XCTAssertNil(DictationTimingLedger.percentile(0.5, of: []))
        XCTAssertEqual(DictationTimingLedger.percentile(0.5, of: [4, 1, 3, 2]), 2)
        XCTAssertEqual(DictationTimingLedger.median(of: [4, 1, 3, 2]), 2.5)
        XCTAssertEqual(DictationTimingLedger.percentile(0.95, of: Array(1...20).map(Double.init)), 19)
        var timing = DictationTimingLedger(capacity: 2)
        for id in 0..<3 {
            timing.begin(id: id, at: 0)
            timing.finish(id: id, outcome: .failed, at: 1)
        }
        XCTAssertEqual(timing.samples.map(\.id), [1, 2])
    }
}
