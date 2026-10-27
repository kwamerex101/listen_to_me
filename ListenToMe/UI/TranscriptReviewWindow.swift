import AppKit
import SwiftUI

@MainActor
final class TranscriptReviewWindow {
    static let shared = TranscriptReviewWindow()
    private var window: NSWindow?
    private var recordID: UUID?
    private var reviewModel: TranscriptReviewModel?

    var canOpen: Bool {
        TranscriptReviewPolicy.allowsReview(in: AppState.shared.phase)
            && TranscriptReviewPolicy.latest(in: HistoryStore.shared.records) != nil
    }

    func openLatest() {
        guard TranscriptReviewPolicy.allowsReview(in: AppState.shared.phase),
              let record = TranscriptReviewPolicy.latest(in: HistoryStore.shared.records) else { return }
        let current: NSWindow
        if let window {
            current = window
        } else {
            current = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            current.title = "Review last dictation"
            current.minSize = NSSize(width: 480, height: 360)
            current.isReleasedWhenClosed = false
            current.center()
            window = current
        }
        // Repeated shortcuts preserve an edited draft for this record.
        if recordID != record.id {
            let model = TranscriptReviewModel(record: record)
            reviewModel = model
            current.contentViewController = NSHostingController(rootView: TranscriptReviewView(
                review: model, onClose: { [weak self] in self?.window?.close() }))
            recordID = record.id
        }
        reviewModel?.synchronize(records: HistoryStore.shared.records)
        NSApp.setActivationPolicy(.regular)
        current.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class TranscriptReviewModel: ObservableObject {
    @Published var draft: TranscriptReviewDraft

    init(record: TranscriptRecord) { draft = TranscriptReviewDraft(record: record) }

    func synchronize(records: [TranscriptRecord]) { draft.synchronize(records: records) }
}

struct TranscriptReviewCommands: Commands {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var state = AppState.shared

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("How dictation works") { DictationGuideWindow.shared.open() }
        }
        CommandGroup(after: .pasteboard) {
            Button("Review last dictation") { TranscriptReviewWindow.shared.openLatest() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!TranscriptReviewPolicy.allowsReview(in: state.phase)
                          || TranscriptReviewPolicy.latest(in: history.records) == nil)
        }
    }
}

private struct TranscriptReviewView: View {
    @ObservedObject var review: TranscriptReviewModel
    let onClose: () -> Void
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var history = HistoryStore.shared
    @State private var copied = false

    private var canCopy: Bool {
        TranscriptReviewPolicy.allowsReview(in: state.phase)
            && review.draft.source != nil
            && history.records.contains(where: {
                $0.id == review.draft.recordID && !$0.dismissed
                    && !$0.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
            && !review.draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.space4) {
            Text("Review last dictation").font(DT.sectionTitle)
            if let source = review.draft.source {
                Text(source.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(DT.caption).foregroundStyle(.secondary)
            }
            Text("Edit a copy of your transcript, then paste it where you need it. Your saved history stays unchanged.")
                .font(DT.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if review.draft.source == nil {
                Text("This saved transcript is no longer available. Copying is disabled.")
                    .font(DT.caption).foregroundStyle(DT.statusError)
            } else if review.draft.sourceChanged {
                HStack {
                    Text("Saved transcript changed. Your edits are preserved.")
                        .font(DT.caption).foregroundStyle(.secondary)
                    Button("Reload saved text") { review.draft.reloadSavedText() }
                        .buttonStyle(.secondary)
                }
            }

            TextEditor(text: $review.draft.text)
                .font(DT.body)
                .padding(DT.space2)
                .background(.background, in: RoundedRectangle(cornerRadius: DT.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: DT.radiusMd).stroke(DT.separator))
                .accessibilityLabel("Editable transcript")
                .disabled(review.draft.source == nil)
                .onChange(of: review.draft.text) { _, _ in copied = false }

            if let source = review.draft.source,
               source.rawText != source.finalText && !source.rawText.isEmpty {
                DisclosureGroup("Original transcription") {
                    ScrollView {
                        Text(source.rawText)
                            .font(DT.body).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                }
                .font(DT.caption)
            }

            if !TranscriptReviewPolicy.allowsReview(in: state.phase) {
                Text("Finish the current dictation before copying.")
                    .font(DT.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.secondary)
                Spacer()
                if copied {
                    Label("Copied. Paste where you need it.", systemImage: "checkmark")
                        .font(DT.caption).foregroundStyle(DT.statusSuccess)
                }
                Button("Copy edited text") {
                    guard canCopy else { return }
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(review.draft.text, forType: .string)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.primary)
                .disabled(!canCopy)
            }
        }
        .padding(DT.space6)
        .frame(minWidth: 440, minHeight: 300)
        .onReceive(history.$records) { records in
            review.synchronize(records: records)
            copied = false
        }
    }
}
