import Combine
import Foundation

/// Single-row store backed by SQLite (`scratchpad` table). The
/// in-memory shape is unchanged — UI binds to `text`; the disk-write
/// path is now an `UPDATE scratchpad SET text=?, updated_at=?`
/// instead of a full-file `String.write(to:atomically:)`. Same
/// debounce semantics; same failure-mode-silent (the store is best-
/// effort by design — losing a draft to a crash is an acceptable
/// tradeoff for not blocking the UI on every keystroke).
///
/// Migration: on first launch with this build, if `scratchpad.txt`
/// exists, we read it into the SQLite row and rename the source to
/// `.txt.bak`. Idempotent across launches: a second launch sees the
/// `.bak` file and does nothing.
@MainActor
final class ScratchpadStore: ObservableObject {
    static let shared = ScratchpadStore()

    @Published var text: String = ""

    private let legacyURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        return dir.appendingPathComponent("scratchpad.txt")
    }()

    private var saveTask: Task<Void, Never>?

    private init() { load() }

    func clear() {
        text = ""
        save()
    }

    /// Debounced 500ms save — same cadence as the previous JSON-file
    /// version. Coalesces bursts of keystrokes into a single write.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            await MainActor.run { self?.save() }
        }
    }

    // MARK: - Persistence

    private func load() {
        do {
            try Database.shared.connect()
            let rows = try Database.shared.query("SELECT text FROM scratchpad WHERE id = 1;")
            if let s = rows.first?.first?.asString, !s.isEmpty {
                text = s
                migrateLegacyIfPresent()   // archive the .txt once we have a populated row
                return
            }
            // Empty SQL row — try the legacy file before settling for "".
            if let legacy = try? String(contentsOf: legacyURL, encoding: .utf8), !legacy.isEmpty {
                text = legacy
                save()
                migrateLegacyIfPresent()
                return
            }
            text = ""
        } catch {
            NSLog("[ListenToMe] ScratchpadStore.load failed: \(error)")
            // Fall back to legacy text-file load so a DB problem can't
            // lose the user's existing notes.
            text = (try? String(contentsOf: legacyURL, encoding: .utf8)) ?? ""
        }
    }

    private func save() {
        do {
            try Database.shared.connect()
            try Database.shared.write(
                "UPDATE scratchpad SET text = ?, updated_at = ? WHERE id = 1;",
                [.text(text), .real(Date().timeIntervalSince1970)]
            )
        } catch {
            NSLog("[ListenToMe] ScratchpadStore.save failed: \(error)")
        }
    }

    /// One-time migration: rename `scratchpad.txt` to `.txt.bak` after
    /// the SQLite row is populated. Idempotent — once `.bak` exists
    /// the file move noops.
    private func migrateLegacyIfPresent() {
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        let backup = legacyURL.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: legacyURL, to: backup)
        NSLog("[ListenToMe] migrated scratchpad.txt → SQLite; legacy at \(backup.lastPathComponent)")
    }
}
