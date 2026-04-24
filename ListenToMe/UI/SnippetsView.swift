import SwiftUI

struct SnippetsView: View {
    @ObservedObject private var store = SnippetsStore.shared
    @State private var newKeyword: String = ""
    @State private var newExpansion: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.snippets.isEmpty {
                empty
            } else {
                list
            }
        }
        .padding(.top, 60)
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Snippets")
                .font(.system(size: 24, weight: .semibold))
            Text("Keywords you speak that expand into longer text. Replaced before AI cleanup so emails, links and canned replies come out clean.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("Keyword (e.g. “my email”)", text: $newKeyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .frame(maxWidth: 240)

                Text("→")
                    .foregroundStyle(.secondary)

                TextField("Expansion", text: $newExpansion)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )

                Button(action: commit) {
                    Text("Add")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty
                          || newExpansion.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 12)
        }
        .padding(.bottom, 20)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "scissors")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No snippets yet.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.snippets) { snippet in
                    row(snippet)
                    Divider()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func row(_ snippet: Snippet) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(snippet.keyword)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 180, alignment: .leading)
            Text("→")
                .foregroundStyle(.secondary)
            Text(snippet.expansion)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button(action: { store.remove(id: snippet.id) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func commit() {
        store.add(keyword: newKeyword, expansion: newExpansion)
        newKeyword = ""
        newExpansion = ""
    }
}
