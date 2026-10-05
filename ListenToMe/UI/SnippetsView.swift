import SwiftUI

struct SnippetsView: View {
    @ObservedObject private var store = SnippetsStore.shared
    @State private var newKeyword: String = ""
    @State private var newExpansion: String = ""
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
    }

    private var addSnippetRow: some View {
        HStack(spacing: DT.space3) {
            TextField("Keyword (e.g. “my email”)", text: $newKeyword)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .formField()
                .frame(maxWidth: 260)
                .onSubmit(commit)

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Expansion", text: $newExpansion)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .formField()
                .frame(maxWidth: .infinity)
                .onSubmit(commit)

            Button(action: commit) { Text("Add") }
                .buttonStyle(.primary)
                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty
                          || newExpansion.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func row(_ snippet: Snippet) -> some View {
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
            Button(action: {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    store.remove(id: snippet.id)
                }
            }) {
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
        .hoverableRow(cornerRadius: 0)
        .transition(.opacity.combined(with: .move(edge: .top)))
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
