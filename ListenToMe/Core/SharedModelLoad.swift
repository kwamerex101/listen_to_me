import Foundation

/// Shares one load across callers and rejects results from invalidated loads.
@MainActor
final class SharedModelLoad<Key: Equatable, Value> {
    private struct Entry {
        let id: UUID
        let key: Key
        let task: Task<Value, Error>
    }

    private var entry: Entry?
    var key: Key? { entry?.key }

    func isCurrent(_ id: UUID) -> Bool { entry?.id == id }

    func value(for key: Key,
               operation: @escaping @MainActor (UUID) async throws -> Value) async throws -> Value {
        if entry?.key != key { invalidate() }
        let current: Entry
        if let entry {
            current = entry
        } else {
            let id = UUID()
            current = Entry(id: id, key: key, task: Task { try await operation(id) })
            entry = current
        }

        let result = await current.task.result
        guard isCurrent(current.id) else { throw CancellationError() }
        switch result {
        case .success(let value):
            // A cancelled waiter must not discard a load used by other callers.
            try Task.checkCancellation()
            return value
        case .failure(let error):
            entry = nil
            throw error
        }
    }

    func invalidate() {
        entry?.task.cancel()
        entry = nil
    }
}
