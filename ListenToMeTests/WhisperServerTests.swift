import XCTest
@testable import ListenToMe

/// Tests for the pure/extracted pieces of `WhisperServer`'s lifecycle fix:
/// random port allocation, the stale-pid-kill decision, and the
/// audio-length-scaled inference timeout. None of these touch the actual
/// subprocess.
final class WhisperServerTests: XCTestCase {

    // MARK: - freeLoopbackPort

    @MainActor
    func test_freeLoopbackPort_returnsPortInEphemeralRange() {
        guard let port = WhisperServer.freeLoopbackPort() else {
            XCTFail("expected a free port")
            return
        }
        XCTAssertGreaterThanOrEqual(port, 1024)
        XCTAssertLessThanOrEqual(port, 65535)
    }

    @MainActor
    func test_freeLoopbackPort_twoCallsBothBindable() {
        // Sanity: the helper doesn't leak the socket or hand out a port it
        // then can't rebind (it closes its probe socket before returning).
        guard let a = WhisperServer.freeLoopbackPort(),
              let b = WhisperServer.freeLoopbackPort() else {
            XCTFail("expected two free ports")
            return
        }
        XCTAssertGreaterThanOrEqual(a, 1024)
        XCTAssertGreaterThanOrEqual(b, 1024)
    }

    // MARK: - shouldKillStale

    @MainActor
    func test_shouldKillStale_nilPath_isFalse() {
        XCTAssertFalse(WhisperServer.shouldKillStale(pidExecutablePath: nil, ourBinaryPath: "/a/whisper-server"))
    }

    @MainActor
    func test_shouldKillStale_otherPath_isFalse() {
        XCTAssertFalse(WhisperServer.shouldKillStale(pidExecutablePath: "/usr/bin/somethingElse",
                                                      ourBinaryPath: "/a/whisper-server"))
    }

    @MainActor
    func test_shouldKillStale_samePath_isTrue() {
        XCTAssertTrue(WhisperServer.shouldKillStale(pidExecutablePath: "/a/whisper-server",
                                                     ourBinaryPath: "/a/whisper-server"))
    }

    // MARK: - inferenceTimeout

    @MainActor
    func test_inferenceTimeout_zeroBytes_isFloor() {
        XCTAssertEqual(WhisperServer.inferenceTimeout(wavBytes: 0), 30)
    }

    @MainActor
    func test_inferenceTimeout_tenSeconds_is35() {
        // 10s of 16kHz mono 16-bit audio = 320,000 bytes + 44-byte header.
        let bytes = 44 + 10 * 32_000
        XCTAssertEqual(WhisperServer.inferenceTimeout(wavBytes: bytes), 35)
    }

    @MainActor
    func test_inferenceTimeout_sixHundredSeconds_is920() {
        let bytes = 44 + 600 * 32_000
        XCTAssertEqual(WhisperServer.inferenceTimeout(wavBytes: bytes), 920)
    }

    @MainActor
    func test_inferenceTimeout_belowHeaderSize_isFloor() {
        // Malformed/truncated file smaller than the header, must not go negative.
        XCTAssertEqual(WhisperServer.inferenceTimeout(wavBytes: 10), 30)
    }

    // MARK: - transcriptText

    private func jsonData(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    @MainActor
    func test_transcriptText_verboseJsonContiguousSegments_joinsToOneLine() {
        // Real whisper-server verbose_json segments, contiguous timestamps
        // (each segment's start == the previous segment's end).
        let segments: [[String: Any]] = [
            ["start": 0.0, "end": 3.41, "text": " Please send the quarterly report to Rex and Sarah in a CRA,"],
            ["start": 3.41, "end": 4.68, "text": " because the deployment failed"],
            ["start": 4.68, "end": 10.64, "text": " after the second attempt when the API server timed out."],
            ["start": 10.64, "end": 13.14, "text": " New paragraph starts here after a long pause."],
        ]
        let data = jsonData(["text": "unused-since-segments-take-priority", "segments": segments])
        let text = WhisperServer.transcriptText(from: data)
        XCTAssertNotNil(text)
        XCTAssertFalse(text!.contains("\n"))
        XCTAssertFalse(text!.contains("  "))
        XCTAssertTrue(text!.hasPrefix("Please"))
        XCTAssertTrue(text!.hasSuffix("pause."))
    }

    @MainActor
    func test_transcriptText_segmentGapAtLeast1_5s_insertsOneParagraphBreak() {
        let segments: [[String: Any]] = [
            ["start": 0.0, "end": 2.0, "text": "First segment."],
            ["start": 4.0, "end": 6.0, "text": " Second segment."],
        ]
        let data = jsonData(["segments": segments])
        XCTAssertEqual(WhisperServer.transcriptText(from: data), "First segment.\n\nSecond segment.")
    }

    @MainActor
    func test_transcriptText_textOnly_flattensOneSegmentPerLine() {
        let data = jsonData(["text": " a\n b\n"])
        XCTAssertEqual(WhisperServer.transcriptText(from: data), "a b")
    }

    @MainActor
    func test_transcriptText_emptySegmentsArray_isEmptyString() {
        let data = jsonData(["segments": [[String: Any]]()])
        XCTAssertEqual(WhisperServer.transcriptText(from: data), "")
    }

    @MainActor
    func test_transcriptText_garbageData_isNil() {
        let data = "not json at all".data(using: .utf8)!
        XCTAssertNil(WhisperServer.transcriptText(from: data))
    }
}
