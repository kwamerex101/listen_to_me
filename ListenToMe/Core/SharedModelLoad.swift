import Foundation

/// Shares one load across callers and rejects results from invalidated loads.
@MainActor
final class SharedModelLoad<Key: Equatable, Value> {
    private struct Entry {
        let id: UUID
        let generation: UUID
        let task: Task<Value, Error>
    }

    private var entry: Entry?
    private var generation = UUID()
    private(set) var key: Key?

    func isCurrent(_ id: UUID) -> Bool { entry?.id == id }

    func value(for key: Key,
               operation: @escaping @MainActor (UUID) async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        if self.key != key {
            invalidate()
            self.key = key
        }
        let current: Entry
        if let entry {
            current = entry
        } else {
            let id = UUID()
            current = Entry(id: id, generation: generation, task: Task { try await operation(id) })
            entry = current
        }

        let result = await current.task.result
        // Eviction permits a retry without invalidating peers of the failed load.
        // An older waiter must never evict a retry that has already started.
        if case .failure = result, entry?.id == current.id { entry = nil }
        try Task.checkCancellation()
        guard current.generation == generation else { throw CancellationError() }
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    func invalidate() {
        entry?.task.cancel()
        entry = nil
        key = nil
        generation = UUID()
    }
}
