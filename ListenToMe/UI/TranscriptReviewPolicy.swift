import Foundation

enum TranscriptReviewPolicy {
    static func latest(in records: [TranscriptRecord]) -> TranscriptRecord? {
        records.filter {
            !$0.dismissed && !$0.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.max { $0.timestamp < $1.timestamp }
    }

    static func allowsReview(in phase: Phase) -> Bool {
        switch phase {
        case .idle, .success, .error, .noSpeech: return true
        case .recording, .transcribing, .cleaning, .polishing, .correcting, .suggestion: return false
        }
    }
}
