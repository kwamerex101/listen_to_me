import Foundation

/// Owns the one delivery allowed for a clean-first dictation.
/// Used only on the main actor, so claiming the result and delivering it
/// cannot interleave with a cancel, another click, or a new recording.
struct PendingCleanupDelivery {
    struct Record: Equatable {
        let id: Int
        let raw: String
        let expanded: String
        let durMs: Int
        let bundleId: String?
    }

    private(set) var pending: Record?

    mutating func begin(_ record: Record) {
        pending = record
    }

    /// A late result must never consume a newer dictation's record.
    mutating func claim(id: Int, currentID: Int) -> Record? {
        guard id == currentID, pending?.id == id else { return nil }
        return discard()
    }

    /// Returns the cancelled record so a pre-empting press can retain it
    /// in History. Explicit discard callers ignore the returned value.
    @discardableResult
    mutating func discard() -> Record? {
        defer { pending = nil }
        return pending
    }
}
