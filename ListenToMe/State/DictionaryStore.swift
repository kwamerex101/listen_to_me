import Foundation

// MARK: - DictionaryEntry

struct DictionaryEntry: Codable, Identifiable {
    let id: UUID
    var word: String
    var origin: Origin
    var addedDate: Date
    var promotedFrom: String?
    var promotedAt: Date?
    var sourceBundleIds: [String]

    enum Origin: String, Codable {
        case manual, promoted
    }

    /// Convenience init for migrating legacy [String] entries.
    init(fromLegacy word: String) {
        self.id = UUID()
        self.word = word
        self.origin = .manual
        self.addedDate = Date()
        self.promotedFrom = nil
        self.promotedAt = nil
        self.sourceBundleIds = []
    }

    init(id: UUID = UUID(), word: String, origin: Origin, addedDate: Date,
         promotedFrom: String? = nil, promotedAt: Date? = nil, sourceBundleIds: [String] = []) {
        self.id = id
        self.word = word
        self.origin = origin
        self.addedDate = addedDate
        self.promotedFrom = promotedFrom
        self.promotedAt = promotedAt
        self.sourceBundleIds = sourceBundleIds
    }
}

// MARK: - DictionaryStore

@MainActor
final class DictionaryStore: ObservableObject {
    static let shared = DictionaryStore()

    @Published private(set) var entries: [DictionaryEntry] = []

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary.json")
    }()

    private init() { load() }

    func add(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !entries.contains(where: { $0.word == w }) else { return }
        let entry = DictionaryEntry(word: w, origin: .manual, addedDate: Date(), sourceBundleIds: [])
        entries.insert(entry, at: 0)
        save()
    }

    func remove(_ word: String) {
        entries.removeAll { $0.word == word }
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func add(promoted word: String, promotedFrom: String, bundleId: String?) {
        // Dedup: skip if already promoted with this word
        guard !entries.contains(where: { $0.word == word && $0.origin == .promoted }) else { return }
        let entry = DictionaryEntry(
            word: word,
            origin: .promoted,
            addedDate: Date(),
            promotedFrom: promotedFrom,
            promotedAt: Date(),
            sourceBundleIds: bundleId.map { [$0] } ?? []
        )
        entries.insert(entry, at: 0)
        save()
    }

    /// Comma-separated list fed to `whisper --prompt` so the model biases toward these terms.
    /// Whisper prompts cap out around ~224 tokens, so we trim at ~800 chars.
    var whisperPrompt: String? {
        guard !entries.isEmpty else { return nil }
        var joined = entries.map(\.word).joined(separator: ", ")
        if joined.count > 800 {
            joined = String(joined.prefix(800))
        }
        return joined
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Two-step migration: try new schema first, fall back to legacy [String]
        if let decoded = try? decoder.decode([DictionaryEntry].self, from: data) {
            entries = decoded
        } else if let legacyWords = try? decoder.decode([String].self, from: data) {
            entries = legacyWords.map { DictionaryEntry(fromLegacy: $0) }
            save()  // Persist migrated format immediately
        }
        // If both fail, leave entries empty — do NOT save (file may be corrupted; don't wipe it)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url)
        }
    }
}
