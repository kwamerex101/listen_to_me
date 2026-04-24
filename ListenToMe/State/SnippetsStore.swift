import Foundation

struct Snippet: Codable, Identifiable, Equatable {
    let id: UUID
    var keyword: String
    var expansion: String

    init(id: UUID = UUID(), keyword: String, expansion: String) {
        self.id = id
        self.keyword = keyword
        self.expansion = expansion
    }
}

@MainActor
final class SnippetsStore: ObservableObject {
    static let shared = SnippetsStore()

    @Published private(set) var snippets: [Snippet] = []

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snippets.json")
    }()

    private init() { load() }

    func add(keyword: String, expansion: String) {
        let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !e.isEmpty else { return }
        // If the keyword already exists, update it rather than duplicating.
        if let idx = snippets.firstIndex(where: { $0.keyword.lowercased() == k.lowercased() }) {
            snippets[idx] = Snippet(id: snippets[idx].id, keyword: k, expansion: e)
        } else {
            snippets.insert(Snippet(keyword: k, expansion: e), at: 0)
        }
        save()
    }

    func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    /// Replace each snippet keyword with its expansion, case-insensitive with
    /// word-boundary matching so we don't accidentally replace substrings.
    /// Keywords with more words are applied first so "my email address" wins over "email".
    func expand(in text: String) -> String {
        guard !snippets.isEmpty else { return text }
        var out = text
        let sorted = snippets.sorted {
            $0.keyword.split(separator: " ").count > $1.keyword.split(separator: " ").count
        }
        for s in sorted {
            let escaped = NSRegularExpression.escapedPattern(for: s.keyword)
            let pattern = "\\b\(escaped)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(
                    in: out, options: [], range: range, withTemplate: s.expansion
                )
            }
        }
        return out
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        snippets = (try? JSONDecoder().decode([Snippet].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(snippets) {
            try? data.write(to: url)
        }
    }
}
