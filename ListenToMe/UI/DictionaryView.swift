import SwiftUI

struct DictionaryView: View {
    @ObservedObject private var store = DictionaryStore.shared
    @State private var newWord: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.words.isEmpty {
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dictionary")
                    .font(.system(size: 24, weight: .semibold))
                Spacer()
            }
            Text("Words Whisper should recognize. Names, jargon, product terms — add them here and transcription picks them up.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("Add a word or phrase…", text: $newWord)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit(commit)
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
                .keyboardShortcut(.return, modifiers: [])
                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 12)
        }
        .padding(.bottom, 20)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No custom words yet.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.words, id: \.self) { word in
                    row(word)
                    Divider()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func row(_ word: String) -> some View {
        HStack {
            Text(word)
                .font(.system(size: 14))
            Spacer()
            Button(action: { store.remove(word) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func commit() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return }
        store.add(w)
        newWord = ""
        focused = true
    }
}
