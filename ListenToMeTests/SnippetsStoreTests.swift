import XCTest
@testable import ListenToMe

/// Pure-logic tests for `SnippetsStore.expand(in:)`. The expander runs
/// against every dictation BEFORE cleanup, so a regression silently
/// breaks every snippet a user has set up.
@MainActor
final class SnippetsStoreTests: XCTestCase {

    func test_expand_passesThroughWhenNoSnippets() {
        let store = SnippetsStore.shared
        // Snapshot + clear so the test is hermetic.
        let backup = store.snippets
        for s in backup { store.remove(id: s.id) }
        defer {
            for s in store.snippets { store.remove(id: s.id) }
            for s in backup { store.add(keyword: s.keyword, expansion: s.expansion) }
        }

        XCTAssertEqual(store.expand(in: "no snippets configured"),
                       "no snippets configured")
    }

    func test_expand_replacesWordBoundaryKeywordOnly() {
        let store = SnippetsStore.shared
        let backup = store.snippets
        for s in backup { store.remove(id: s.id) }
        defer {
            for s in store.snippets { store.remove(id: s.id) }
            for s in backup { store.add(keyword: s.keyword, expansion: s.expansion) }
        }
        store.add(keyword: "btw", expansion: "by the way")

        // Whole-word match expands; substring inside another word doesn't.
        XCTAssertEqual(store.expand(in: "btw send it later"),
                       "by the way send it later")
        XCTAssertEqual(store.expand(in: "btwxyz unchanged"),
                       "btwxyz unchanged")
    }
}
