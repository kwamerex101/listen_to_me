import SwiftUI

struct PagesView: View {
    @ObservedObject private var store = PagesStore.shared
    @State private var selectedID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left sidebar (page list)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pages")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button(action: newPage) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("New page")
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 14)

            Divider()

            if store.pages.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No pages yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button("New Page", action: newPage)
                        .font(.system(size: 13, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.pages) { page in
                            pageRow(page)
                        }
                    }
                }
            }
        }
        .frame(width: 220)
        .background(Color(.controlBackgroundColor))
    }

    private func pageRow(_ page: Page) -> some View {
        let selected = selectedID == page.id
        return Button(action: { selectedID = page.id }) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title.isEmpty ? "Untitled" : page.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(relativeDate(page.updatedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.09) : Color.clear)
            )
            .hoverableRow()   // hover overlay paints on top of selection fill
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .contextMenu {
            Button("Delete", role: .destructive) {
                if selectedID == page.id { selectedID = nil }
                store.remove(id: page.id)
            }
        }
    }

    // MARK: - Right editor

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID, let page = store.pages.first(where: { $0.id == id }) {
            PageEditorView(page: page)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(store.pages.isEmpty ? "Create a page to get started." : "Select a page to edit.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Helpers

    private func newPage() {
        let page = store.add()
        selectedID = page.id
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct PageEditorView: View {
    let page: Page
    @ObservedObject private var store = PagesStore.shared
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .padding(.horizontal, 36)
                .padding(.top, 60)
                .padding(.bottom, 12)
                .onChange(of: title) { _, _ in scheduleSave() }

            Divider()

            ZStack(alignment: .topLeading) {
                TextEditor(text: $content)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                    .onChange(of: content) { _, _ in scheduleSave() }

                if content.isEmpty {
                    Text("Start typing or hold Fn + ⌘ to dictate…")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            title = page.title
            content = page.content
        }
        .onChange(of: page.id) { _, _ in
            title = page.title
            content = page.content
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            store.updateTitle(id: page.id, title: title)
            store.updateContent(id: page.id, content: content)
        }
    }
}
