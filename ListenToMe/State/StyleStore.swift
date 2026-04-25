import Foundation
import Combine

struct StyleRule: Codable, Identifiable {
    let id: UUID
    var appName: String
    var prompt: String
}

@MainActor
final class StyleStore: ObservableObject {
    static let shared = StyleStore()

    @Published private(set) var rules: [StyleRule] = []

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("styles.json")
    }()

    private init() { load() }

    func add(appName: String, prompt: String) {
        rules.append(StyleRule(id: UUID(), appName: appName, prompt: prompt))
        save()
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        rules = (try? JSONDecoder().decode([StyleRule].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(rules) {
            try? data.write(to: url)
        }
    }
}
