import SwiftUI

struct SnippetsView: View {
    @ObservedObject private var store = SnippetsStore.shared
    @State private var newKeyword: String = ""
    @State private var newExpansion: String = ""
    @StateObject private var undo = UndoCenter()
    @State private var editingID: UUID?
    @State private var editKeyword = ""
    @State private var editExpansion = ""
    @FocusState private var editFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.space6) {
                PageHeader(
                    title: "Snippets",
                    subtitle: "Keywords you speak that expand into longer text. Replaced before AI cleanup so emails, links and canned replies come out clean.",
                    icon: "scissors",
                    iconTint: .pink
                )

                addSnippetRow

                if store.snippets.isEmpty {
                    EmptyState(
                        icon: "scissors",
                        title: "No snippets yet",
                        subtitle: "Add a keyword above and ListenToMe will replace it with the expansion before cleanup."
                    )
                } else {
                    list
                }
            }
            .padding(.top, DT.safeAreaTop)
            .padding(.horizontal, DT.space10)
            .padding(.bottom, DT.space10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .titleBarScrollEdge()
        .undoToast(undo)
    }

    private var canAdd: Bool {
        !newKeyword.trimmingCharacters(in: .whitespaces).isEmpty
            && !newExpansion.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Single line when it fits; at the minimum window width the expansion
    /// field would be squeezed, so fall back to a stacked layout.
    private var addSnippetRow: some View {
        ViewThatFits(in: .horizontal) {
            addSnippetRowWide
            addSnippetRowStacked
        }
    }

    private var addSnippetRowStacked: some View {
        VStack(alignment: .leading, spacing: DT.space3) {
            keywordField.frame(maxWidth: .infinity)
            expansionField
            HStack {
                Spacer()
                addButton
            }
        }
    }

    private var keywordField: some View {
        TextField("Keyword (e.g. “my email”)", text: $newKeyword)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .formField()
            .onSubmit(commit)
    }

    private var expansionField: some View {
        TextField("Expansion", text: $newExpansion)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .formField()
            .frame(maxWidth: .infinity)
            .onSubmit(commit)
    }

    private var addButton: some View {
        Button(action: commit) { Text("Add") }
            .buttonStyle(.primary)
            .disabled(!canAdd)
    }

    private var addSnippetRowWide: some View {
        HStack(spacing: DT.space3) {
            keywordField
                .frame(minWidth: 160, maxWidth: 260)

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            expansionField
                // Below ~280pt the expansion is too cramped to read; let
                // ViewThatFits drop to the stacked layout instead.
                .frame(minWidth: 280)

            addButton
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(store.snippets) { snippet in
                row(snippet)
                if snippet.id != store.snippets.last?.id {
                    Divider().background(DT.separator)
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func row(_ snippet: Snippet) -> some View {
        if editingID == snippet.id {
            editRow(snippet)
        } else {
            displayRow(snippet)
        }
    }

    private func displayRow(_ snippet: Snippet) -> some View {
        HStack(alignment: .top, spacing: DT.space4) {
            Text(snippet.keyword)
                .font(DT.bodyStrong)
                .frame(width: 200, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DT.accent.opacity(0.7))
                .padding(.top, 4)
            Text(snippet.expansion)
                .font(DT.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button(action: { beginEdit(snippet) }) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .help("Edit snippet")
            .accessibilityLabel("Edit snippet")
            Button(action: { remove(snippet) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .help("Remove snippet")
            .accessibilityLabel("Remove snippet")
        }
        .padding(.horizontal, DT.space5)
        .padding(.vertical, DT.space4)
        .contentShape(Rectangle())
        .onTapGesture { beginEdit(snippet) }
        .hoverableRow(cornerRadius: 0)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var canSaveEdit: Bool {
        !editKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !editExpansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func editRow(_ snippet: Snippet) -> some View {
        HStack(alignment: .center, spacing: DT.space3) {
            TextField("Keyword", text: $editKeyword)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .formField()
                .frame(width: 200)
                .focused($editFocused)
                .onSubmit { saveEdit(snippet) }
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DT.accent.opacity(0.7))
            TextField("Expansion", text: $editExpansion)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .formField()
                .frame(maxWidth: .infinity)
                .onSubmit { saveEdit(snippet) }
            Button("Cancel") { cancelEdit() }
                .buttonStyle(.pressable)
                .font(DT.captionStrong)
                .foregroundStyle(.secondary)
            Button("Save") { saveEdit(snippet) }
                .buttonStyle(.secondary)
                .controlSize(.small)
                .disabled(!canSaveEdit)
        }
        .padding(.horizontal, DT.space5)
        .padding(.vertical, DT.space3)
        .onExitCommand { cancelEdit() }
        .onAppear { editFocused = true }
    }

    private func beginEdit(_ snippet: Snippet) {
        editKeyword = snippet.keyword
        editExpansion = snippet.expansion
        editingID = snippet.id
    }

    private func cancelEdit() {
        editingID = nil
    }

    private func saveEdit(_ snippet: Snippet) {
        guard canSaveEdit else { return }
        if store.update(id: snippet.id, keyword: editKeyword, expansion: editExpansion) {
            editingID = nil
        }
    }

    /// Remove a snippet and offer to put it back at its old position.
    private func remove(_ snippet: Snippet) {
        let index = store.snippets.firstIndex(where: { $0.id == snippet.id })
        if editingID == snippet.id { editingID = nil }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            store.remove(id: snippet.id)
        }
        undo.show("Snippet removed") {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                store.restore(snippet, at: index)
            }
        }
    }

    private func commit() {
        let keyword = newKeyword.trimmingCharacters(in: .whitespaces)
        let expansion = newExpansion.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty, !expansion.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            store.add(keyword: newKeyword, expansion: newExpansion)
        }
        newKeyword = ""
        newExpansion = ""
    }
}
