import Foundation

/// Curated raw→ideal cleanup pairs for the eval harness. Seeded by hand to
/// cover the behaviours that matter; in production this set should also be
/// grown from real `HistoryStore` rows the user did NOT re-correct (de-facto
/// accept signals). Kept as Swift literals (not a bundled JSON) to avoid
/// test-target resource plumbing — the shape mirrors a JSON record so it can
/// move to a file later.
struct CleanupFixture {
    let id: String
    let raw: String
    let ideal: String
    let category: String
    let note: String
}

enum CleanupFixtures {
    static let all: [CleanupFixture] = [
        .init(id: "already-clean",
              raw: "The meeting is scheduled for 3 PM on Tuesday.",
              ideal: "The meeting is scheduled for 3 PM on Tuesday.",
              category: "document",
              note: "Clean input must pass through ~unchanged — anti-over-edit anchor."),
        .init(id: "heavy-filler",
              raw: "um so like i was thinking we could uh maybe you know try that approach",
              ideal: "So I was thinking we could maybe try that approach.",
              category: "messaging",
              note: "Filler removal + punctuation, content preserved."),
        .init(id: "stutter",
              raw: "the the cat sat on on the mat",
              ideal: "The cat sat on the mat.",
              category: "document",
              note: "Collapse repeated stutters."),
        .init(id: "proper-noun",
              raw: "send the report to danqua by friday",
              ideal: "Send the report to Danquah by Friday.",
              category: "email",
              note: "Capitalization + proper-noun fix; content words survive."),
        .init(id: "run-on",
              raw: "i finished the draft it needs review can you look at it today",
              ideal: "I finished the draft. It needs review. Can you look at it today?",
              category: "messaging",
              note: "Sentence splitting + terminal punctuation."),
        .init(id: "short-utterance",
              raw: "yeah sounds good",
              ideal: "Yeah, sounds good.",
              category: "messaging",
              note: "Very short — must not over-formalize into a paragraph."),
        .init(id: "numbers",
              raw: "we need to finalize the q3 report by the fifteenth",
              ideal: "We need to finalize the Q3 report by the fifteenth.",
              category: "email",
              note: "Preserve domain tokens (Q3) and numbers."),
        .init(id: "list",
              raw: "first we scope it second we build it third we ship it",
              ideal: "First, we scope it. Second, we build it. Third, we ship it.",
              category: "document",
              note: "Spoken enumeration → punctuated clauses."),
        .init(id: "multi-sentence-filler",
              raw: "okay so the plan is uh we launch monday and then um we monitor for issues",
              ideal: "Okay, so the plan is we launch Monday and then we monitor for issues.",
              category: "messaging",
              note: "Mixed filler across clauses."),
        .init(id: "question",
              raw: "do you think we should ship it now or wait until next week",
              ideal: "Do you think we should ship it now or wait until next week?",
              category: "messaging",
              note: "Question mark inference."),
        .init(id: "homophone-steel-stale",
              raw: "when the user hits retry we take their biometrics again so it doesn't use the steel biometrics and keep failing",
              ideal: "When the user hits retry, we take their biometrics again so it doesn't use the stale biometrics and keep failing.",
              category: "messaging",
              note: "ASR homophone substitution: 'steel'→'stale'. Both are real words and "
                  + "'steel biometrics' is grammatical, so only meaning-aware cleanup can catch "
                  + "it — purely acoustic/grammar passes can't. STRETCH: current local prompt is "
                  + "not expected to fix this; fixture exists to measure whether a meaning-aware "
                  + "prompt catches it WITHOUT regressing recall on the anti-over-edit anchors. "
                  + "Real slip captured from live dictation 2026-06-12."),
        .init(id: "doubled-word-and-garble",
              raw: "then some padding around there's just in case a user has big fingers and let's improve the gesture detector detector",
              ideal: "Then some padding around there, just in case a user has big fingers, and let's improve the gesture detector.",
              category: "messaging",
              note: "Two real cleanup misses from live dictation 2026-06-12 on Gemma E2B: a "
                  + "stuttered doubled word ('detector detector'→'detector') and a spurious "
                  + "possessive ('there's'→'there'). VoiceEditor now collapses the doubled word "
                  + "deterministically BEFORE cleanup, but the eval harness feeds raw straight to "
                  + "the model — so this measures whether the cleanup model alone catches both."),
    ]
}
