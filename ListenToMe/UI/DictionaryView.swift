import SwiftUI

struct DictionaryView: View {
    @ObservedObject private var store = DictionaryStore.shared
    @ObservedObject private var candidateStore = CandidateStore.shared
    @State private var newWord: String = ""
    @FocusState private var focused: Bool
    @State private var candidatesExpanded = true
    @State private var promotedExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.entries.isEmpty && candidateStore.candidates.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        candidatesSection
                        promotedSection
                        manualList
                    }
                }
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

    // MARK: - Candidates section

    private var candidatesSection: some View {
        DisclosureGroup(isExpanded: $candidatesExpanded) {
            if candidateStore.candidates.isEmpty {
                Text("No misreads detected yet — keep dictating.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(candidateStore.candidates) { candidate in
                        candidateRow(candidate)
                        Divider()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
        } label: {
            HStack {
                Text("Candidates")
                    .font(.system(size: 16, weight: .semibold))
                Text("(\(candidateStore.candidates.count))")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 16)
    }

    private func candidateRow(_ candidate: DictionaryCandidate) -> some View {
        HStack(spacing: 10) {
            // original → replacement
            Text(candidate.original)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(candidate.replacement)
                .font(.system(size: 14))
            Spacer()
            // occurrence badge
            Text("\(candidate.occurrences.count)/3")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
            // last-seen date
            if let lastDate = candidate.occurrences.last?.date {
                Text(lastDate, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            // source app (bundle ID string, truncated — Phase 5 adds icon)
            if let bundleId = candidate.occurrences.last?.bundleId {
                Text(bundleId.components(separatedBy: ".").last ?? bundleId)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // action buttons
            Button("Accept") { candidateStore.accept(id: candidate.id) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                )
            Button("Reject") { candidateStore.reject(id: candidate.id) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .hoverableRow()
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
                            Divider()
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                } label: {
                    HStack {
                        Text("Promoted")
                            .font(.system(size: 16, weight: .semibold))
                        Text("(\(promoted.count))")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func promotedRow(_ entry: DictionaryEntry) -> some View {
        HStack {
            Text(entry.word)
                .font(.system(size: 14))
            Spacer()
            Button(action: { store.remove(id: entry.id) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Originally transcribed as: \(entry.promotedFrom ?? entry.word)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .hoverableRow()
    }

    // MARK: - Manual list

    private var manualList: some View {
        let manual = store.entries.filter { $0.origin == .manual }
        return Group {
            if !manual.isEmpty {
                VStack(spacing: 0) {
                    ForEach(manual) { entry in
                        row(entry.word)
                        Divider()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Empty state

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
        .hoverableRow()
    }

    private func commit() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return }
        store.add(w)
        newWord = ""
        focused = true
    }
}
