import Foundation

/// Wispr-style "Polish / Transform on selection" built-ins. Surfaced
/// in the history-row context menu alongside any user-defined
/// transforms from `TransformsStore`. Each entry pairs a short menu
/// label with the natural-language instruction we hand to
/// `ClaudeClient.transform(text:transformInstruction:)`.
struct BuiltinTransform: Identifiable, Equatable {
    let id: String         // stable key for SwiftUI ForEach
    let label: String      // shown in the menu
    let instruction: String

    static let all: [BuiltinTransform] = [
        BuiltinTransform(
            id: "make-formal",
            label: "Make formal",
            instruction: "Rewrite the input in a more formal, professional tone. Preserve the meaning. Keep roughly the same length."
        ),
        BuiltinTransform(
            id: "make-casual",
            label: "Make casual",
            instruction: "Rewrite the input in a more casual, conversational tone. Preserve the meaning. Keep roughly the same length."
        ),
        BuiltinTransform(
            id: "tighten",
            label: "Tighten",
            instruction: "Rewrite the input to be more concise. Cut redundancy and filler. Preserve every key fact and the overall meaning."
        ),
        BuiltinTransform(
            id: "bulletize",
            label: "Bulletize",
            instruction: "Rewrite the input as a Markdown-style bulleted list (\"- \" prefix per item). One idea per bullet. Preserve every key fact."
        ),
        BuiltinTransform(
            id: "summarize",
            label: "Summarize",
            instruction: "Summarize the input in 1-3 sentences. Capture the main point and any decisions or action items."
        ),
        BuiltinTransform(
            id: "translate-spanish",
            label: "Translate to Spanish",
            instruction: "Translate the input to Spanish. Preserve names and code identifiers verbatim."
        ),
        BuiltinTransform(
            id: "translate-french",
            label: "Translate to French",
            instruction: "Translate the input to French. Preserve names and code identifiers verbatim."
        ),
    ]
}
