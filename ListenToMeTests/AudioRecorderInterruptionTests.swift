import XCTest
@testable import ListenToMe

/// Tests for `AudioRecorder.shouldReportInterruption`: the pure decision
/// behind Item 4's `onInputInterrupted` callback (fired when
/// `AVAudioEngineConfigurationChange` posts mid-recording, e.g. AirPods
/// disconnecting). AVAudioEngine itself isn't driven here — only the
/// extracted decision.
final class AudioRecorderInterruptionTests: XCTestCase {

    func test_shouldReport_true_whileRecording_notYetReported() {
        XCTAssertTrue(AudioRecorder.shouldReportInterruption(isRecording: true, engineRunning: false, alreadyReported: false))
    }

    func test_shouldReport_false_whenAlreadyReported() {
        // A single device switch can post more than one config-change
        // notification; only the first should reach onInputInterrupted.
        XCTAssertFalse(AudioRecorder.shouldReportInterruption(isRecording: true, engineRunning: false, alreadyReported: true))
    }

    func test_shouldReport_false_whenNotRecording() {
        // A notification arriving just after stop()/cancel() shouldn't
        // fire a callback for a recording that's already over.
        XCTAssertFalse(AudioRecorder.shouldReportInterruption(isRecording: false, engineRunning: false, alreadyReported: false))
    }

    func test_shouldReport_false_whenNotRecording_andAlreadyReported() {
        XCTAssertFalse(AudioRecorder.shouldReportInterruption(isRecording: false, engineRunning: false, alreadyReported: true))
    }

    func test_shouldReport_false_whenEngineStillRunning() {
        // A config change that didn't stop the engine cost no audio (e.g.
        // posted by our own input-device selection at start); ending the
        // recording there would cut off every dictation with a chosen mic.
        XCTAssertFalse(AudioRecorder.shouldReportInterruption(isRecording: true, engineRunning: true, alreadyReported: false))
    }
}
