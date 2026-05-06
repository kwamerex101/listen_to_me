import SwiftUI

struct ScratchpadView: View {
    @ObservedObject private var store = ScratchpadStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            editor
        }
        .padding(.top, 60)
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scratchpad")
                    .font(.system(size: 24, weight: .semibold))
                Text("Freeform dictation workspace. Hold Fn + ⌘ to dictate directly here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack(spacing: 12) {
                Text(wordCountLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Button("Clear") {
                    store.clear()
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .buttonStyle(.pressable)
                .disabled(store.text.isEmpty)
            }
        }
        .padding(.bottom, 16)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)

            TextEditor(text: $store.text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(14)
                .onChange(of: store.text) { _ in
                    store.scheduleSave()
                }

            if store.text.isEmpty {
                Text("Start typing or hold Fn + ⌘ to dictate here…")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .padding(18)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var wordCountLabel: String {
        let words = store.text.split(whereSeparator: \.isWhitespace).count
        return store.text.isEmpty ? "" : "\(words) word\(words == 1 ? "" : "s")"
    }
}
