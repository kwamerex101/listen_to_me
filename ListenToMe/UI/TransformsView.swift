import SwiftUI

struct TransformsView: View {
    @ObservedObject private var store = TransformsStore.shared
    @State private var newName: String = ""
    @State private var newPrompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.transforms.isEmpty {
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
            Text("Transforms")
                .font(.system(size: 24, weight: .semibold))
            Text("Named prompts applied to your transcript after cleanup. Speak to get raw text, then run a transform to reshape it.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("Name (e.g. Bullet points)", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .frame(maxWidth: 220)

                TextField("Prompt (e.g. Convert to bullet points.)", text: $newPrompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .onSubmit(commit)

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
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                          || newPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 12)
        }
        .padding(.bottom, 20)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No transforms yet.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.transforms) { transform in
                    row(transform)
                    Divider()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func row(_ transform: Transform) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(transform.name)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 180, alignment: .leading)
            Text(transform.prompt)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button(action: { store.remove(id: transform.id) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func commit() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let prompt = newPrompt.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !prompt.isEmpty else { return }
        store.add(name: name, prompt: prompt)
        newName = ""
        newPrompt = ""
    }
}
