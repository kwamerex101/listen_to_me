import SwiftUI

struct DictionaryView: View {
    @ObservedObject private var store = DictionaryStore.shared
    @ObservedObject private var candidateStore = CandidateStore.shared
    @State private var newWord: String = ""
    @FocusState private var focused: Bool
    @State private var candidatesExpanded = true
    @State private var promotedExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.space6) {
                PageHeader(
                    title: "Dictionary",
                    subtitle: "Words Whisper should recognize. Names, jargon, product terms — add them here and transcription picks them up.",
                    icon: "doc.text",
                    iconTint: DT.accent
                )

                addWordRow

                if store.entries.isEmpty && candidateStore.candidates.isEmpty {
                    EmptyState(
                        icon: "doc.text",
                        title: "No custom words yet",
                        subtitle: "Add a word above, or keep dictating — ListenToMe captures retype-corrections automatically."
                    )
                } else {
                    candidatesSection
                    promotedSection
                    manualSection
                }
            }
            .padding(.top, 60)
            .padding(.horizontal, DT.space10)
            .padding(.bottom, DT.space10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Add row

    private var addWordRow: some View {
        HStack(spacing: DT.space3) {
            TextField("Add a word or phrase…", text: $newWord)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .onSubmit(commit)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .formField()
                .frame(maxWidth: .infinity)

            Button(action: commit) { Text("Add") }
                .buttonStyle(.primary)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Candidates section

    private var candidatesSection: some View {
        DisclosureGroup(isExpanded: $candidatesExpanded) {
            if candidateStore.candidates.isEmpty {
                Text("No misreads detected yet — keep dictating.")
                    .font(DT.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DT.space4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(candidateStore.candidates) { candidate in
                        candidateRow(candidate)
                        if candidate.id != candidateStore.candidates.last?.id {
                            Divider().background(DT.separator)
                        }
                    }
                }
                .card()
                .padding(.top, DT.space2)
            }
        } label: {
            sectionLabel("Candidates", count: candidateStore.candidates.count, tint: .orange)
        }
    }

    private func candidateRow(_ candidate: DictionaryCandidate) -> some View {
        HStack(spacing: DT.space3) {
            // original → replacement
            HStack(spacing: 6) {
                Text(candidate.original)
                    .font(DT.body)
                    .foregroundStyle(.secondary)
                    .strikethrough()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DT.accent.opacity(0.7))
                Text(candidate.replacement)
                    .font(DT.bodyStrong)
            }
            .frame(maxWidth: 280, alignment: .leading)

            Spacer()

            // occurrence badge
            occurrenceBadge(count: candidate.occurrences.count)

            // last-seen date
            if let lastDate = candidate.occurrences.last?.date {
                Text(lastDate, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            // source app
            if let bundleId = candidate.occurrences.last?.bundleId {
                Text(bundleId.components(separatedBy: ".").last ?? bundleId)
                    .font(DT.monoCaption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Button("Accept") { candidateStore.accept(id: candidate.id) }
                .buttonStyle(.secondary)
                .controlSize(.small)
            Button("Reject") { candidateStore.reject(id: candidate.id) }
                .buttonStyle(.pressable)
                .font(DT.captionStrong)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DT.space5)
        .padding(.vertical, DT.space3)
        .hoverableRow(cornerRadius: 0)
    }

    private func occurrenceBadge(count: Int) -> some View {
        let progress = Double(min(count, 3)) / 3.0
        return HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10))
                .foregroundStyle(progress >= 1 ? Color.orange : Color.orange.opacity(0.5))
            Text("\(count)/3")
                .font(DT.monoCaption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.orange.opacity(0.10))
        )
    }

    // MARK: - Promoted section

    private var promotedSection: some View {
        let promoted = store.entries.filter { $0.origin == .promoted }
        return Group {
            if !promoted.isEmpty {
                DisclosureGroup(isExpanded: $promotedExpanded) {
                    VStack(spacing: 0) {
                        ForEach(promoted) { entry in
                            promotedRow(entry)
                            if entry.id != promoted.last?.id {
                                Divider().background(DT.separator)
                            }
                        }
                    }
                    .card()
                    .padding(.top, DT.space2)
                } label: {
                    sectionLabel("Promoted", count: promoted.count, tint: DT.accent)
                }
            }
        }
    }

    private func promotedRow(_ entry: DictionaryEntry) -> some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(DT.accent)
            Text(entry.word)
                .font(DT.bodyStrong)
            if let from = entry.promotedFrom {
                Text("from “\(from)”")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: { store.remove(id: entry.id) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.pressable)
            .help("Remove from dictionary")
        }
        .padding(.horizontal, DT.space5)
        .padding(.vertical, DT.space4)
        .hoverableRow(cornerRadius: 0)
    }

    // MARK: - Manual section

    private var manualSection: some View {
        let manual = store.entries.filter { $0.origin == .manual }
        return Group {
            if !manual.isEmpty {
                VStack(alignment: .leading, spacing: DT.space2) {
                    sectionLabel("Manual", count: manual.count, tint: .gray, asEyebrow: true)

                    VStack(spacing: 0) {
                        ForEach(manual) { entry in
                            manualRow(entry.word)
                            if entry.id != manual.last?.id {
                                Divider().background(DT.separator)
                            }
                        }
                    }
                    .card()
                }
            }
        }
    }

    private func manualRow(_ word: String) -> some View {
        HStack {
            Image(systemName: "text.cursor")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(word)
                .font(DT.body)
            Spacer()
            Button(action: { store.remove(word) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.pressable)
            .help("Remove word")
        }
        .padding(.horizontal, DT.space5)
        .padding(.vertical, DT.space4)
        .hoverableRow(cornerRadius: 0)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionLabel(_ title: String, count: Int, tint: Color, asEyebrow: Bool = false) -> some View {
        if asEyebrow {
            HStack(spacing: 6) {
                SectionEyebrow(title: title)
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(DT.surfaceCard))
            }
        } else {
            HStack(spacing: 8) {
                Text(title)
                    .font(DT.sectionTitle)
                Text("\(count)")
                    .font(DT.captionStrong.monospacedDigit())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(tint.opacity(0.14))
                    )
            }
        }
    }

    private func commit() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return }
        store.add(w)
        newWord = ""
        focused = true
    }
}
