import Foundation

@MainActor
final class DictionaryStore: ObservableObject {
    static let shared = DictionaryStore()

    @Published private(set) var words: [String] = []

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary.json")
    }()

    private init() { load() }

    func add(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, !words.contains(w) else { return }
        words.insert(w, at: 0)
        save()
    }

    func remove(_ word: String) {
        words.removeAll { $0 == word }
        save()
    }

    /// Comma-separated list fed to `whisper --prompt` so the model biases toward these terms.
    /// Whisper prompts cap out around ~224 tokens, so we trim at ~800 chars.
    var whisperPrompt: String? {
        guard !words.isEmpty else { return nil }
        var joined = words.joined(separator: ", ")
        if joined.count > 800 {
            joined = String(joined.prefix(800))
        }
        return joined
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        words = (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(words) {
            try? data.write(to: url)
        }
    }
}
