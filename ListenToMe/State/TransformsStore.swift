import Combine
import Foundation

struct Transform: Identifiable, Equatable {
    let id: UUID
    var name: String
    var prompt: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, prompt: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.createdAt = createdAt
    }
}

/// User-defined cleanup prompts surfaced in the history-row Polish/
/// Transform menu (see `Core/BuiltinTransforms.swift` for the
/// shipped defaults). Backed by SQLite (`transforms` table); same
/// in-memory shape as the previous JSON-backed version.
///
/// Migration: on first launch with this build, if `transforms.json`
/// exists AND the table is empty, the JSON contents are imported and
/// the source is renamed `.json.bak`. Idempotent.
@MainActor
final class TransformsStore: ObservableObject {
    static let shared = TransformsStore()

    @Published private(set) var transforms: [Transform] = []

    private let legacyURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        return dir.appendingPathComponent("transforms.json")
    }()

    private init() { load() }

    func add(name: String, prompt: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !p.isEmpty else { return }
        let t = Transform(name: n, prompt: p)
        transforms.append(t)
        do {
            try Database.shared.connect()
            try Database.shared.write(
                "INSERT INTO transforms (id, name, prompt, created_at) VALUES (?, ?, ?, ?);",
                [.text(t.id.uuidString), .text(t.name), .text(t.prompt),
                 .real(t.createdAt.timeIntervalSince1970)]
            )
        } catch {
            NSLog("[ListenToMe] TransformsStore.add failed: \(error)")
        }
    }

    func remove(id: UUID) {
        transforms.removeAll { $0.id == id }
        do {
            try Database.shared.write(
                "DELETE FROM transforms WHERE id = ?;",
                [.text(id.uuidString)]
            )
        } catch {
            NSLog("[ListenToMe] TransformsStore.remove failed: \(error)")
        }
    }

    // MARK: - Persistence

    private func load() {
        do {
            try Database.shared.connect()
            let rows = try Database.shared.query(
                "SELECT id, name, prompt, created_at FROM transforms ORDER BY created_at ASC;"
            )
            transforms = rows.compactMap { r in
                guard let idStr = r[0].asString,
                      let id = UUID(uuidString: idStr),
                      let name = r[1].asString,
                      let prompt = r[2].asString else { return nil }
                let createdAt = r[3].asDouble.map { Date(timeIntervalSince1970: $0) } ?? Date()
                return Transform(id: id, name: name, prompt: prompt, createdAt: createdAt)
            }
            if transforms.isEmpty, FileManager.default.fileExists(atPath: legacyURL.path) {
                migrateFromLegacyJSON()
            }
        } catch {
            NSLog("[ListenToMe] TransformsStore.load failed: \(error) — falling back to legacy JSON")
            // Same fallback shape as SnippetsStore — a DB problem must
            // not lose user-defined prompts.
            struct LegacyTransform: Decodable { let id: UUID; let name: String; let prompt: String }
            if let data = try? Data(contentsOf: legacyURL),
               let arr = try? JSONDecoder().decode([LegacyTransform].self, from: data) {
                transforms = arr.map { Transform(id: $0.id, name: $0.name, prompt: $0.prompt) }
            }
        }
    }

    private func migrateFromLegacyJSON() {
        guard let data = try? Data(contentsOf: legacyURL) else { return }
        struct LegacyTransform: Decodable { let id: UUID; let name: String; let prompt: String }
        guard let arr = try? JSONDecoder().decode([LegacyTransform].self, from: data) else { return }
        let now = Date().timeIntervalSince1970
        do {
            try Database.shared.transaction {
                for (i, t) in arr.enumerated() {
                    let trans = Transform(id: t.id, name: t.name, prompt: t.prompt,
                                          createdAt: Date(timeIntervalSince1970: now + Double(i)))
                    transforms.append(trans)
                    try Database.shared.write(
                        "INSERT OR REPLACE INTO transforms (id, name, prompt, created_at) VALUES (?, ?, ?, ?);",
                        [.text(trans.id.uuidString), .text(trans.name),
                         .text(trans.prompt), .real(trans.createdAt.timeIntervalSince1970)]
                    )
                }
            }
            let backup = legacyURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: legacyURL, to: backup)
            NSLog("[ListenToMe] migrated \(arr.count) transforms to SQLite; legacy at \(backup.lastPathComponent)")
        } catch {
            NSLog("[ListenToMe] TransformsStore migration failed: \(error)")
        }
    }
}
