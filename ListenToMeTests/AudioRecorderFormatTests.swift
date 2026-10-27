import AVFoundation
import CObjCException
import XCTest
@testable import ListenToMe

/// Tests for the format handling behind the "Failed to create tap due to
/// format mismatch" crash: AirPods switching from 48 kHz playback to 24 kHz
/// microphone mode left AVAudioEngine's cached format stale, and installTap
/// raised an Objective-C exception that took the app down. AVAudioEngine
/// itself isn't driven here, only the extracted decisions and the exception
/// catcher.
final class AudioRecorderFormatTests: XCTestCase {

    private func format(_ rate: Double, _ channels: AVAudioChannelCount) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                      channels: channels, interleaved: false)!
    }

    // MARK: isUsableInputFormat

    func test_usable_normalMic() {
        XCTAssertTrue(AudioRecorder.isUsableInputFormat(sampleRate: 48_000, channels: 1))
    }

    func test_usable_bluetoothMicMode() {
        XCTAssertTrue(AudioRecorder.isUsableInputFormat(sampleRate: 24_000, channels: 1))
    }

    func test_notUsable_zeroSampleRate() {
        // A device mid-disconnect can report 0 Hz.
        XCTAssertFalse(AudioRecorder.isUsableInputFormat(sampleRate: 0, channels: 1))
    }

    func test_notUsable_zeroChannels() {
        XCTAssertFalse(AudioRecorder.isUsableInputFormat(sampleRate: 48_000, channels: 0))
    }

    // MARK: needsNewConverter

    func test_needsConverter_whenNoneYet() {
        XCTAssertTrue(AudioRecorder.needsNewConverter(current: nil, incoming: format(48_000, 1)))
    }

    func test_noNewConverter_whenFormatUnchanged() {
        XCTAssertFalse(AudioRecorder.needsNewConverter(current: format(48_000, 1), incoming: format(48_000, 1)))
    }

    func test_needsConverter_whenSampleRateChanged() {
        // The AirPods case: built for 48 kHz, audio arrives at 24 kHz.
        XCTAssertTrue(AudioRecorder.needsNewConverter(current: format(48_000, 1), incoming: format(24_000, 1)))
    }

    func test_needsConverter_whenChannelCountChanged() {
        XCTAssertTrue(AudioRecorder.needsNewConverter(current: format(48_000, 1), incoming: format(48_000, 2)))
    }

    // MARK: LTMObjCException

    func test_catching_returnsNormally_whenNoException() throws {
        var ran = false
        try LTMObjCException.catching { ran = true }
        XCTAssertTrue(ran)
    }

    func test_catching_turnsExceptionIntoError() {
        XCTAssertThrowsError(try LTMObjCException.catching {
            NSException(name: NSExceptionName("com.apple.coreaudio.avfaudio"),
                        reason: "Failed to create tap due to format mismatch",
                        userInfo: nil).raise()
        }) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, LTMObjCExceptionErrorDomain)
            XCTAssertEqual(nsError.userInfo[LTMObjCExceptionNameKey] as? String, "com.apple.coreaudio.avfaudio")
            XCTAssertEqual(nsError.localizedDescription, "Failed to create tap due to format mismatch")
        }
    }

    func test_inputUnavailable_userMessage() {
        XCTAssertEqual(AudioRecorderError.inputUnavailable.userMessage, "Mic unavailable")
    }
}
