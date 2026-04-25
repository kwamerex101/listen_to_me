import SwiftUI

struct StyleView: View {
    @ObservedObject private var store = StyleStore.shared
    @State private var newApp: String = ""
    @State private var newPrompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.rules.isEmpty {
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
            Text("Style")
                .font(.system(size: 24, weight: .semibold))
            Text("Per-app writing tone. When the active app matches, this prompt overrides the default cleanup instruction.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("App name (e.g. Mail)", text: $newApp)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .frame(maxWidth: 180)

                TextField("Style prompt (e.g. Be formal and concise.)", text: $newPrompt)
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
                .disabled(newApp.trimmingCharacters(in: .whitespaces).isEmpty
                          || newPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 12)
        }
        .padding(.bottom, 20)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "textformat")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No styles yet.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.rules) { rule in
                    row(rule)
                    Divider()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func row(_ rule: StyleRule) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(rule.appName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 140, alignment: .leading)
            Text(rule.prompt)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button(action: { store.remove(id: rule.id) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func commit() {
        let app = newApp.trimmingCharacters(in: .whitespaces)
        let prompt = newPrompt.trimmingCharacters(in: .whitespaces)
        guard !app.isEmpty, !prompt.isEmpty else { return }
        store.add(appName: app, prompt: prompt)
        newApp = ""
        newPrompt = ""
    }
}
