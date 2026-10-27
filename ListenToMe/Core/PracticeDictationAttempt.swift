import Foundation

/// A practice attempt needs both pipeline success and new editor content.
/// Synthetic paste events can update the editor before or after success.
struct PracticeDictationAttempt {
    private var baseline: String?
    private var pipelineSucceeded = false

    mutating func begin(text: String) {
        baseline = text
        pipelineSucceeded = false
    }

    mutating func recordSuccess(text: String) -> Bool {
        guard baseline != nil else { return false }
        pipelineSucceeded = true
        return editorChanged(text: text)
    }

    mutating func editorChanged(text: String) -> Bool {
        guard let baseline, pipelineSucceeded, text != baseline,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        reset()
        return true
    }

    mutating func reset() {
        baseline = nil
        pipelineSucceeded = false
    }
}
