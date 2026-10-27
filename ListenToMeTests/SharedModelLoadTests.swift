import XCTest
@testable import ListenToMe

@MainActor
final class SharedModelLoadTests: XCTestCase {
    private enum LoadFailure: Error, Equatable { case download(Int) }

    private final class PendingValue {
        let started = XCTestExpectation(description: "load started")
        private var continuation: CheckedContinuation<Int, Error>?

        func load() async throws -> Int {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }

        func finish(_ result: Result<Int, Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }
    }

    func testConcurrentCallersWaitForTheSameLoad() async throws {
        let shared = SharedModelLoad<String, Int>()
        let pending = PendingValue()
        var calls = 0
        let first = Task {
            try await shared.value(for: "v3") { _ in
                calls += 1
                return try await pending.load()
            }
        }
        await fulfillment(of: [pending.started], timeout: 1)
        let secondEntered = expectation(description: "second caller entered")
        let second = Task {
            secondEntered.fulfill()
            return try await shared.value(for: "v3") { _ in
                calls += 1
                return -1
            }
        }
        await fulfillment(of: [secondEntered], timeout: 1)
        XCTAssertEqual(calls, 1)
        pending.finish(.success(42))
        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, 42)
        XCTAssertEqual(secondValue, 42)
        XCTAssertEqual(calls, 1)
    }

    func testFailedLoadCanBeRetried() async throws {
        enum Failure: Error { case download }
        let shared = SharedModelLoad<String, Int>()
        do {
            _ = try await shared.value(for: "v3") { _ in throw Failure.download }
            XCTFail("A failed download must reach its caller")
        } catch Failure.download {}
        let value = try await shared.value(for: "v3") { _ in 7 }
        XCTAssertEqual(value, 7)
    }

    func testInvalidationRejectsUncooperativeLoadCompletion() async throws {
        let shared = SharedModelLoad<String, Int>()
        let pending = PendingValue()
        let old = Task { try await shared.value(for: "v3") { _ in try await pending.load() } }
        await fulfillment(of: [pending.started], timeout: 1)
        shared.invalidate()
        pending.finish(.success(1))
        do {
            _ = try await old.value
            XCTFail("Shutdown must reject a late model")
        } catch is CancellationError {}
        XCTAssertNil(shared.key)
        let next = try await shared.value(for: "v3") { _ in 2 }
        XCTAssertEqual(next, 2)
    }

    func testVersionSwitchKeepsNewLoadWhenOldLoadFinishes() async throws {
        let shared = SharedModelLoad<String, Int>()
        let pending = PendingValue()
        let old = Task { try await shared.value(for: "v3") { _ in try await pending.load() } }
        await fulfillment(of: [pending.started], timeout: 1)
        let next = try await shared.value(for: "v2") { _ in 2 }
        pending.finish(.success(3))
        do {
            _ = try await old.value
            XCTFail("The old version must not win the race")
        } catch is CancellationError {}
        XCTAssertEqual(next, 2)
        XCTAssertEqual(shared.key, "v2")
        let cached = try await shared.value(for: "v2") { _ in -1 }
        XCTAssertEqual(cached, 2)
    }

    func testCancelledWaiterDoesNotCancelSharedLoad() async throws {
        let shared = SharedModelLoad<String, Int>()
        let pending = PendingValue()
        let first = Task { try await shared.value(for: "v3") { _ in try await pending.load() } }
        await fulfillment(of: [pending.started], timeout: 1)
        first.cancel()
        pending.finish(.success(5))
        do {
            _ = try await first.value
            XCTFail("A cancelled waiter must not consume the result")
        } catch is CancellationError {}
        let value = try await shared.value(for: "v3") { _ in -1 }
        XCTAssertEqual(value, 5)
    }

    func testConcurrentWaitersReceiveTheOriginalFailure() async {
        let shared = SharedModelLoad<String, Int>()
        let pending = PendingValue()
        let first = Task { try await shared.value(for: "v3") { _ in try await pending.load() } }
        await fulfillment(of: [pending.started], timeout: 1)
        let joined = expectation(description: "peer joined shared load")
        let second = Task {
            joined.fulfill()
            return try await shared.value(for: "v3") { _ in
                XCTFail("Concurrent callers must share the failing operation")
                return -1
            }
        }
        await fulfillment(of: [joined], timeout: 1)
        pending.finish(.failure(LoadFailure.download(42)))
        for waiter in [first, second] {
            do {
                _ = try await waiter.value
                XCTFail("Each waiter must receive the load failure")
            } catch {
                XCTAssertEqual(error as? LoadFailure, .download(42))
            }
        }
        XCTAssertEqual(shared.key, "v3")
    }

    func testFailureWaitersCanJoinOneRetryWithoutDiscardingIt() async throws {
        let shared = SharedModelLoad<String, Int>()
        let failing = PendingValue()
        let retry = PendingValue()
        var attempts = 0
        let joined = expectation(description: "both failure waiters joined")
        joined.expectedFulfillmentCount = 2
        func loadThenRetry() async throws -> Int {
            joined.fulfill()
            do {
                return try await shared.value(for: "v3") { _ in
                    attempts += 1
                    return try await failing.load()
                }
            } catch {
                XCTAssertEqual(error as? LoadFailure, .download(42))
                return try await shared.value(for: "v3") { _ in
                    attempts += 1
                    guard attempts == 2 else {
                        XCTFail("A late failed waiter discarded the shared retry")
                        return -1
                    }
                    return try await retry.load()
                }
            }
        }
        let first = Task { try await loadThenRetry() }
        await fulfillment(of: [failing.started], timeout: 1)
        let second = Task { try await loadThenRetry() }
        await fulfillment(of: [joined], timeout: 1)
        failing.finish(.failure(LoadFailure.download(42)))
        await fulfillment(of: [retry.started], timeout: 1)
        retry.finish(.success(9))
        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, 9)
        XCTAssertEqual(secondValue, 9)
        XCTAssertEqual(attempts, 2)
        let cached = try await shared.value(for: "v3") { _ in -1 }
        XCTAssertEqual(cached, 9)
    }

    func testInvalidationRejectsLateFailureAndPreservesReplacement() async throws {
        let shared = SharedModelLoad<String, Int>()
        let pending = PendingValue()
        let old = Task { try await shared.value(for: "v3") { _ in try await pending.load() } }
        await fulfillment(of: [pending.started], timeout: 1)
        shared.invalidate()
        let replacement = try await shared.value(for: "v3") { _ in 8 }
        pending.finish(.failure(LoadFailure.download(42)))
        do {
            _ = try await old.value
            XCTFail("Invalidation must reject failures from the earlier generation")
        } catch is CancellationError {}
        XCTAssertEqual(replacement, 8)
        let cached = try await shared.value(for: "v3") { _ in -1 }
        XCTAssertEqual(cached, 8)
    }

    func testCancelledWaiterGetsCancellationOnFailureAndNextCallCanRetry() async throws {
        let shared = SharedModelLoad<String, Int>()
        let pending = PendingValue()
        let cancelled = Task { try await shared.value(for: "v3") { _ in try await pending.load() } }
        await fulfillment(of: [pending.started], timeout: 1)
        cancelled.cancel()
        pending.finish(.failure(LoadFailure.download(42)))
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled waiter must not receive a fallback-triggering failure")
        } catch is CancellationError {}
        let retried = try await shared.value(for: "v3") { _ in 7 }
        XCTAssertEqual(retried, 7)
    }
}
