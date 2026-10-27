import Foundation

/// Keeps an explicit edit separate from later changes to its saved source.
struct TranscriptReviewDraft {
    let recordID: UUID
    private(set) var source: TranscriptRecord?
    private var acceptedText: String
    var text: String
    private(set) var sourceChanged = false

    init(record: TranscriptRecord) {
        recordID = record.id
        source = record
        acceptedText = record.finalText
        text = record.finalText
    }

    mutating func synchronize(records: [TranscriptRecord]) {
        source = records.first {
            $0.id == recordID && !$0.dismissed
                && !$0.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let source else { return }
        guard source.finalText != acceptedText else {
            sourceChanged = false
            return
        }
        if text == acceptedText {
            reloadSavedText()
        } else {
            sourceChanged = true
        }
    }

    mutating func reloadSavedText() {
        guard let source else { return }
        text = source.finalText
        acceptedText = source.finalText
        sourceChanged = false
    }
}
