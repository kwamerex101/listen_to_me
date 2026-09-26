import XCTest
@testable import ListenToMe

/// Tests for `ClaudeClient.sanitizeRewrite(output:original:)`: the guard
/// that validates a Backtrack rewrite against the ORIGINAL sentence, not the
/// short revision phrase. Fix A3: a naive sanitize against the revision
/// phrase rejected correct full-sentence rewrites and pasted the revision
/// phrase itself over the user's sentence.
final class BacktrackRewriteGuardTests: XCTestCase {

    func test_acceptsGoodRewrite() throws {
        let out = try ClaudeClient.sanitizeRewrite(
            output: "Send the report by next Thursday.",
            original: "Send the report by Friday."
        )
        XCTAssertEqual(out, "Send the report by next Thursday.")
    }

    func test_acceptsGoodRewrite_wordSwap() throws {
        let out = try ClaudeClient.sanitizeRewrite(
            output: "Hey team, the production URL is broken.",
            original: "Hey team, the staging URL is broken."
        )
        XCTAssertEqual(out, "Hey team, the production URL is broken.")
    }

    func test_rejectsOutputIdenticalToOriginal() {
        XCTAssertThrowsError(try ClaudeClient.sanitizeRewrite(
            output: "Send the report by Friday.",
            original: "Send the report by Friday."
        )) { error in
            XCTAssertEqual(error as? ClaudeError, .revisionRejected)
        }
    }

    func test_rejectsBareRevisionPhrase() {
        XCTAssertThrowsError(try ClaudeClient.sanitizeRewrite(
            output: "make that next Thursday",
            original: "Send the report by Friday."
        )) { error in
            XCTAssertEqual(error as? ClaudeError, .revisionRejected)
        }
    }

    func test_rejectsPreamble() {
        XCTAssertThrowsError(try ClaudeClient.sanitizeRewrite(
            output: "Here is the revised text: Send the report by next Thursday.",
            original: "Send the report by Friday."
        )) { error in
            XCTAssertEqual(error as? ClaudeError, .revisionRejected)
        }
    }

    func test_rejectsEmptyOutput() {
        XCTAssertThrowsError(try ClaudeClient.sanitizeRewrite(
            output: "",
            original: "Send the report by Friday."
        )) { error in
            XCTAssertEqual(error as? ClaudeError, .revisionRejected)
        }
    }
}
