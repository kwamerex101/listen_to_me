import XCTest
@testable import ListenToMe

/// Tests for `CommandRouter`: `fallsBackToDictation` (Item 3b) and
/// `runProcess` (Item 3a), the pipe-drain / timeout / cancellation fixes
/// for a subprocess that could otherwise deadlock on a full pipe, hang
/// forever with no timeout, or orphan a child process on cancellation.
final class CommandRouterTests: XCTestCase {

    // MARK: - fallsBackToDictation

    func test_fallsBackToDictation_true_forOpenApp() {
        XCTAssertTrue(CommandRouter.fallsBackToDictation(on: .openApp(name: "the PR and merge it")))
    }

    func test_fallsBackToDictation_false_forLogToday() {
        XCTAssertFalse(CommandRouter.fallsBackToDictation(on: .logToday(text: "note")))
    }

    func test_fallsBackToDictation_false_forShell() {
        XCTAssertFalse(CommandRouter.fallsBackToDictation(on: .shell(body: "echo hi")))
    }

    // MARK: - runProcess: no pipe deadlock

    func test_runProcess_drainsLargeOutput_withoutDeadlock() async throws {
        // A child writing more than the 64KB pipe buffer before exiting
        // used to block forever on readDataToEndOfFile() in the
        // terminationHandler. 200KB comfortably exceeds that buffer.
        let result = try await CommandRouter.runProcess(
            url: URL(fileURLWithPath: "/bin/sh"),
            args: ["-c", "yes | head -c 200000"],
            captureStdout: true,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.utf8.count, 200_000)
    }

    // MARK: - runProcess: timeout

    func test_runProcess_timesOut_promptly() async throws {
        let start = Date()
        do {
            _ = try await CommandRouter.runProcess(
                url: URL(fileURLWithPath: "/bin/sleep"),
                args: ["5"],
                captureStdout: false,
                timeout: 0.5
            )
            XCTFail("expected a timeout error")
        } catch is CommandRouter.ProcessError {
            // expected
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
    }

    // MARK: - runProcess: cancellation

    func test_runProcess_cancellation_returnsPromptly() async throws {
        let task = Task {
            try await CommandRouter.runProcess(
                url: URL(fileURLWithPath: "/bin/sleep"),
                args: ["5"],
                captureStdout: false,
                timeout: 30
            )
        }
        // Give the process a moment to actually launch before cancelling.
        try await Task.sleep(for: .milliseconds(200))
        let start = Date()
        task.cancel()
        // `onCancel` terminates the child immediately, so the continuation
        // resolves right away, either with the process's own (SIGTERM'd)
        // termination status, or a thrown error. Either is fine; a
        // `sleep 5` that isn't cut short by cancellation is the actual bug.
        _ = try? await task.value
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
    }
}
