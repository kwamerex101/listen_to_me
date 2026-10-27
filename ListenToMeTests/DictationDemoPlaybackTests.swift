import XCTest
@testable import ListenToMe

@MainActor
final class DictationDemoPlaybackTests: XCTestCase {
    private final class PendingPause {
        let started = XCTestExpectation(description: "demo pause started")
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }

        func finish() {
            continuation?.resume()
            continuation = nil
        }
    }

    func testPlaybackDemonstratesEachStageAndStopsAtCompletion() async {
        let playback = DictationDemoPlayback()
        var seen: [DictationDemoStage] = []
        await playback.run(reduceMotion: false) { _ in seen.append(playback.stage) }
        XCTAssertEqual(seen, [.hold, .speakOne, .speakTwo, .speakThree, .processing])
        XCTAssertEqual(playback.stage, .complete)
        XCTAssertFalse(playback.isPlaying)
    }

    func testReduceMotionCompletesWithoutSchedulingAnyPause() async {
        let playback = DictationDemoPlayback()
        var pauses = 0
        await playback.run(reduceMotion: true) { _ in pauses += 1 }
        XCTAssertEqual(pauses, 0)
        XCTAssertEqual(playback.stage, .complete)
        XCTAssertFalse(playback.isPlaying)
    }

    func testCancellationStopsLateStageUpdates() async {
        let playback = DictationDemoPlayback()
        let pause = PendingPause()
        let task = Task { await playback.run(reduceMotion: false) { _ in await pause.wait() } }
        await fulfillment(of: [pause.started], timeout: 1)
        task.cancel()
        pause.finish()
        await task.value
        XCTAssertEqual(playback.stage, .hold)
        XCTAssertFalse(playback.isPlaying)
    }

    func testReplayRejectsLateUpdatesFromEarlierRun() async {
        let playback = DictationDemoPlayback()
        let pause = PendingPause()
        let earlier = Task { await playback.run(reduceMotion: false) { _ in await pause.wait() } }
        await fulfillment(of: [pause.started], timeout: 1)
        await playback.run(reduceMotion: false) { _ in }
        XCTAssertEqual(playback.stage, .complete)
        pause.finish()
        await earlier.value
        XCTAssertEqual(playback.stage, .complete)
        XCTAssertFalse(playback.isPlaying)
    }
}
