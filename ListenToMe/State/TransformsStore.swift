import Foundation
import Combine

struct Transform: Codable, Identifiable {
    let id: UUID
    var name: String
    var prompt: String
}

@MainActor
final class TransformsStore: ObservableObject {
    static let shared = TransformsStore()

    @Published private(set) var transforms: [Transform] = []

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transforms.json")
    }()

    private init() { load() }

    func add(name: String, prompt: String) {
        transforms.append(Transform(id: UUID(), name: name, prompt: prompt))
        save()
    }

    func remove(id: UUID) {
        transforms.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        transforms = (try? JSONDecoder().decode([Transform].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(transforms) {
            try? data.write(to: url)
        }
    }
}
