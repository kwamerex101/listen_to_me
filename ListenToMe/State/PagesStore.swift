import Foundation
import Combine

struct Page: Codable, Identifiable {
    let id: UUID
    var title: String
    var content: String
    var updatedAt: Date
}

@MainActor
final class PagesStore: ObservableObject {
    static let shared = PagesStore()

    @Published private(set) var pages: [Page] = []

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pages.json")
    }()

    private init() { load() }

    @discardableResult
    func add(title: String = "Untitled") -> Page {
        let page = Page(id: UUID(), title: title, content: "", updatedAt: Date())
        pages.insert(page, at: 0)
        save()
        return page
    }

    func remove(id: UUID) {
        pages.removeAll { $0.id == id }
        save()
    }

    func updateTitle(id: UUID, title: String) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].title = title
        pages[i].updatedAt = Date()
        save()
    }

    func updateContent(id: UUID, content: String) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].content = content
        pages[i].updatedAt = Date()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        pages = (try? decoder.decode([Page].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(pages) {
            try? data.write(to: url)
        }
    }
}
