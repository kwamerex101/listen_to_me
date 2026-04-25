import Foundation
import Combine

@MainActor
final class ScratchpadStore: ObservableObject {
    static let shared = ScratchpadStore()

    @Published var text: String = ""

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scratchpad.txt")
    }()

    private var saveTask: Task<Void, Never>?

    private init() { load() }

    func clear() {
        text = ""
        save()
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled { save() }
        }
    }

    private func load() {
        text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func save() {
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
