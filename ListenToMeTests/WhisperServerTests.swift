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
}
