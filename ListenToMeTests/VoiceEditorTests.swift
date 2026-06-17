import XCTest
@testable import ListenToMe

/// Pure-logic tests for `VoiceEditor.apply` — the deterministic
/// transcript transformer that handles voice-editing tokens (comma,
/// period, scratch that, new paragraph, …) before cleanup.
final class VoiceEditorTests: XCTestCase {

    func test_apply_replacesSpokenComma() {
        // Auto-capitalizes the first letter (start-of-sentence rule).
        XCTAssertEqual(VoiceEditor.apply("hello comma world"), "Hello, world")
    }

    func test_apply_replacesSpokenPeriodAndCapitalizesNext() {
        let out = VoiceEditor.apply("first sentence period second sentence")
        XCTAssertTrue(out.contains("First sentence."))
        XCTAssertTrue(out.contains("Second sentence"))
    }

    func test_apply_questionMark() {
        let out = VoiceEditor.apply("really question mark")
        XCTAssertTrue(out.contains("Really?"))
    }

    func test_apply_exclamationPoint() {
        let out = VoiceEditor.apply("watch out exclamation point")
        XCTAssertTrue(out.contains("Watch out!"))
    }

    func test_apply_newParagraph() {
        let out = VoiceEditor.apply("first new paragraph second")
        XCTAssertTrue(out.contains("\n\n"))
    }

    func test_apply_scratchThat_dropsPriorSentence() {
        // "scratch that" wipes the most recent sentence.
        let out = VoiceEditor.apply("hello world period bye scratch that")
        XCTAssertFalse(out.lowercased().contains("bye"))
    }

    func test_apply_pureScratchProducesEmpty() {
        // Edge case the pipeline relies on: pure-undo dictation.
        let out = VoiceEditor.apply("scratch that")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func test_apply_passesThroughBenignText_capitalizingFirstLetter() {
        XCTAssertEqual(VoiceEditor.apply("plain text"), "Plain text")
    }

    // MARK: - Spoken "dot" → "." (file names / domains / decimals)

    func test_dot_gluesFilenameToExtension() {
        XCTAssertEqual(VoiceEditor.apply("open the readme dot md"), "Open the readme.md")
    }

    func test_dot_determinerKeepsLeadingDotDetached() {
        // "all the dot md files" → the article must NOT glue: "the .md files".
        XCTAssertEqual(VoiceEditor.apply("all the dot md files"), "All the .md files")
    }

    func test_dot_bothPatternsInOneUtterance() {
        // Mirrors the real failing transcript.
        let out = VoiceEditor.apply(
            "have we made sure all the dot md files are updated comma like the readme dot md question mark")
        XCTAssertEqual(out, "Have we made sure all the .md files are updated, like the readme.md?")
    }

    func test_dot_domain() {
        XCTAssertEqual(VoiceEditor.apply("go to example dot com"), "Go to example.com")
    }

    func test_dot_decimal() {
        XCTAssertEqual(VoiceEditor.apply("version 3 dot 14"), "Version 3.14")
    }

    func test_dot_leavesProseDotAlone() {
        // "dot product" / "dot matrix" are not extensions/TLDs — untouched.
        XCTAssertEqual(VoiceEditor.apply("the dot product is zero"), "The dot product is zero")
    }

    // MARK: - Spoken "plus" → "+" (version build metadata / C++)

    func test_plus_versionBuildMetadata() {
        // Mirrors the real failing transcript.
        XCTAssertEqual(
            VoiceEditor.apply("let's create a new PR for release 1.0.29 plus 230"),
            "Let's create a new PR for release 1.0.29+230")
    }

    func test_plus_cPlusPlusIdiom() {
        XCTAssertEqual(VoiceEditor.apply("c plus plus is fast"), "C++ is fast")
    }

    func test_plus_leavesBareMathAlone() {
        // No dotted version on the left → ambiguous, left as words.
        XCTAssertEqual(VoiceEditor.apply("2 plus 2 equals 4"), "2 plus 2 equals 4")
    }

    func test_plus_leavesProsePlusAlone() {
        XCTAssertEqual(VoiceEditor.apply("plus one to that"), "Plus one to that")
    }

    // MARK: - Collapse stuttered repeats ("detector detector" → "detector")

    func test_repeat_collapsesDoubledNoun() {
        // The real failing transcript's headline error.
        XCTAssertEqual(
            VoiceEditor.apply("improve the gesture detector detector for these"),
            "Improve the gesture detector for these")
    }

    func test_repeat_collapsesFunctionWordAndTriple() {
        XCTAssertEqual(VoiceEditor.apply("the the cat sat"), "The cat sat")
        XCTAssertEqual(VoiceEditor.apply("go go go now"), "Go now")
    }

    func test_repeat_preservesEmphaticAndGrammaticalDoubles() {
        XCTAssertEqual(VoiceEditor.apply("it is very very important"), "It is very very important")
        XCTAssertEqual(VoiceEditor.apply("i had had lunch"), "I had had lunch")
    }

    func test_repeat_preservesRepeatedDigits() {
        // Dictating a number twice on purpose must survive.
        XCTAssertEqual(VoiceEditor.apply("call 230 230 now"), "Call 230 230 now")
    }

    func test_repeat_doesNotCrossPunctuation() {
        // "done. Done" is two sentences, not a stutter.
        let out = VoiceEditor.apply("we are done period done deal")
        XCTAssertEqual(out, "We are done. Done deal")
    }

    // MARK: - Dictionary-seeded acronyms ("kyc" → "KYC")

    func test_acronyms_extractsAllCapsLettersOnly() {
        let set = VoiceEditor.acronyms(from: ["KYC", "API", "v2", "OAuth", "Danquah", "IT", "S3"])
        // v2/S3 have digits, OAuth/Danquah aren't all-caps, IT is a stopword.
        XCTAssertEqual(set, ["KYC", "API"])
    }

    func test_acronyms_forceUppercasesInTranscript() {
        let out = VoiceEditor.apply("processing the v2 kyc process", acronyms: ["KYC"])
        XCTAssertEqual(out, "Processing the v2 KYC process")
    }

    func test_acronyms_handleMixedCaseAndSentenceStart() {
        let out = VoiceEditor.apply("call the api then check the Sdk", acronyms: ["API", "SDK"])
        XCTAssertEqual(out, "Call the API then check the SDK")
    }

    func test_acronyms_doNotMatchInsideWords() {
        let out = VoiceEditor.apply("the kyclayer is fine", acronyms: ["KYC"])
        XCTAssertEqual(out, "The kyclayer is fine")
    }

    func test_acronyms_emptyByDefaultLeavesTextUnchanged() {
        XCTAssertEqual(VoiceEditor.apply("the kyc flow"), "The kyc flow")
    }
}
