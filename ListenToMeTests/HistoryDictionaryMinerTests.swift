import XCTest
@testable import ListenToMe

/// Pure-logic tests for `HistoryDictionaryMiner.mine`. Both kinds of
/// failure here matter: a false positive would auto-promote junk into
/// the user's whisper prompt; a false negative just means the
/// auto-dictionary never fires for that word.
final class HistoryDictionaryMinerTests: XCTestCase {

    private typealias Record = (rawText: String, finalText: String, bundleId: String?)

    // MARK: - Single-word swap detection

    func test_clear_proper_noun_swap_detected() {
        // The motivating example from the design doc.
        let records: [Record] = [
            ("hi danqua", "Hi Danquah", "com.apple.mail")
        ]
        let hits = HistoryDictionaryMiner.mine(records: records)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].swap.original.lowercased(), "danqua")
        XCTAssertEqual(hits[0].swap.replacement, "Danquah")
        XCTAssertEqual(hits[0].bundleId, "com.apple.mail")
    }

    func test_one_word_swap_with_trailing_punctuation_strips_correctly() {
        let records: [Record] = [
            ("hi danqua.", "Hi Danquah.", nil)
        ]
        let hits = HistoryDictionaryMiner.mine(records: records)
        XCTAssertEqual(hits.count, 1)
        XCTAssertFalse(hits[0].swap.original.contains("."))
        XCTAssertFalse(hits[0].swap.replacement.contains("."))
    }

    // MARK: - False-positive guards

    func test_capitalization_only_diff_is_excluded() {
        // Whisper rendering "for" lowercase that cleanup capitalized to
        // "For" is the cleanup pass's job, NOT a dictionary signal.
        let records: [Record] = [
            ("for the AI backend", "For the AI backend", nil)
        ]
        XCTAssertEqual(HistoryDictionaryMiner.mine(records: records).count, 0)
    }

    func test_multi_word_diff_is_excluded() {
        // Two positions differ — that's a sentence rewrite, not a name fix.
        let records: [Record] = [
            ("send report by friday", "send the report by Tuesday", nil)
        ]
        XCTAssertEqual(HistoryDictionaryMiner.mine(records: records).count, 0)
    }

    func test_different_word_count_is_excluded() {
        // Cleanup added a word — not a single-word swap.
        let records: [Record] = [
            ("send report friday", "send the report friday", nil)
        ]
        XCTAssertEqual(HistoryDictionaryMiner.mine(records: records).count, 0)
    }

    func test_short_word_swap_is_excluded() {
        // Both sides need ≥3 chars; "a" → "an" is whisper-quality not
        // a useful dictionary signal.
        let records: [Record] = [
            ("a apple", "an apple", nil)
        ]
        XCTAssertEqual(HistoryDictionaryMiner.mine(records: records).count, 0)
    }

    func test_punctuation_in_word_is_excluded() {
        // Symbols other than apostrophe / hyphen are tokenization
        // artifacts; not real-word swaps.
        let records: [Record] = [
            ("hello user@x", "hello user_x", nil)
        ]
        XCTAssertEqual(HistoryDictionaryMiner.mine(records: records).count, 0)
    }

    func test_apostrophe_words_are_allowed() {
        // "don't" / "I'll" / "Tom's" should pass the letter-class
        // filter (apostrophe explicitly allowed).
        let records: [Record] = [
            ("can't go today", "can't go tomorrow", nil)
        ]
        // Different word count after split? "today" ≠ "tomorrow", same
        // word count — should hit IF lengths qualify; both are >= 3.
        let hits = HistoryDictionaryMiner.mine(records: records)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].swap.original, "today")
        XCTAssertEqual(hits[0].swap.replacement, "tomorrow")
    }

    func test_empty_strings_are_excluded() {
        let records: [Record] = [
            ("", "Hi Danquah", nil),
            ("hi danqua", "", nil),
            ("", "", nil),
        ]
        XCTAssertEqual(HistoryDictionaryMiner.mine(records: records).count, 0)
    }

    func test_identical_raw_and_final_excluded() {
        // No cleanup happened — no signal either way.
        let records: [Record] = [
            ("perfect sentence", "perfect sentence", nil)
        ]
        XCTAssertEqual(HistoryDictionaryMiner.mine(records: records).count, 0)
    }

    // MARK: - Bulk behavior

    func test_multiple_records_each_yield_independent_hits() {
        let records: [Record] = [
            ("hi danqua", "Hi Danquah", "com.apple.mail"),
            ("for the AI backend", "For the AI backend", nil), // capitalization only — excluded
            ("ping raks", "ping Rex", "com.tinyspeck.slackmacgap"),
        ]
        let hits = HistoryDictionaryMiner.mine(records: records)
        XCTAssertEqual(hits.count, 2)
        let originals = Set(hits.map { $0.swap.original.lowercased() })
        XCTAssertTrue(originals.contains("danqua"))
        XCTAssertTrue(originals.contains("raks"))
    }

    func test_mining_preserves_bundle_id_per_record() {
        // Both records use letters-only mangled→clean swaps — using
        // "rex" → "Rex" would be a cap-only diff that the miner
        // correctly excludes (verified in
        // test_capitalization_only_diff_is_excluded).
        let records: [Record] = [
            ("ping danqua", "ping Danquah", "com.apple.mail"),
            ("ping raks", "ping Rex", "com.tinyspeck.slackmacgap"),
        ]
        let hits = HistoryDictionaryMiner.mine(records: records)
        // Dictionary value type is the optional bundleId; double-wrap
        // the lookup result by unwrapping once.
        var bundleByOriginal: [String: String?] = [:]
        for h in hits { bundleByOriginal[h.swap.original.lowercased()] = h.bundleId }
        XCTAssertEqual(bundleByOriginal["danqua"] ?? nil, "com.apple.mail")
        XCTAssertEqual(bundleByOriginal["raks"] ?? nil, "com.tinyspeck.slackmacgap")
    }
}
