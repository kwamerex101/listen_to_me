import Foundation

/// Tracks one in-flight native call and a release requested while it runs, so
/// a model or context is never freed under a detached inference still using
/// it. `LocalLLMEngine` and `WhisperLib` both hop off the MainActor to run
/// the actual decode/transcribe with a raw pointer; `shutdown()` (model
/// switch, delete, app quit) used to free that pointer immediately and reset
/// the busy flag, racing the detached task into a use-after-free. This type
/// holds no pointers itself — callers still own freeing the model/context —
/// it only decides WHEN it's safe to do so.
struct InFlightGate {
    private(set) var isBusy = false
    private(set) var releasePending = false

    /// Returns false if already busy, or a release is pending (the resource
    /// is on its way out; don't start new work on it) — caller throws its
    /// busy error in either case.
    mutating func begin() -> Bool {
        guard !isBusy, !releasePending else { return false }
        isBusy = true
        return true
    }

    /// Call when the in-flight work finishes. Returns true if a release was
    /// requested meanwhile and the caller must free now.
    mutating func end() -> Bool {
        isBusy = false
        if releasePending {
            releasePending = false
            return true
        }
        return false
    }

    /// Returns true if the caller may free immediately (idle); otherwise
    /// marks the release pending — `end()` will return true when the
    /// in-flight call finishes — and returns false.
    mutating func requestRelease() -> Bool {
        guard isBusy else { return true }
        releasePending = true
        return false
    }
}
