import XCTest
@testable import ListenToMe

/// Pure-logic tests for `AppContext`. AppleScript-based browser-URL
/// extraction is intentionally NOT tested here — it depends on
/// runtime apps being open, would block the test runner waiting for
/// AppleScript, and the 0.3 s timeout / nil-fallback path is the safe
/// behavior. Everything else (category mapping, prompt-line
/// construction) is covered.
final class AppContextTests: XCTestCase {

    // MARK: - Prompt-line assembly

    func test_promptLine_includes_app_and_category() {
        let ctx = AppContext(
            bundleId: "com.tinyspeck.slackmacgap",
            displayName: "Slack",
            category: .messaging,
            url: nil
        )
        let line = ctx.promptLine
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("Slack"))
        XCTAssertTrue(line!.contains("com.tinyspeck.slackmacgap"))
        XCTAssertTrue(line!.contains("messaging"))
        XCTAssertFalse(line!.contains("URL:"))   // no URL → no URL field
    }

    func test_promptLine_includes_url_for_browser() {
        let ctx = AppContext(
            bundleId: "com.apple.Safari",
            displayName: "Safari",
            category: .browser,
            url: "https://github.com/anthropics/claude-code"
        )
        let line = ctx.promptLine
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("URL: https://github.com/anthropics/claude-code"))
    }

    func test_promptLine_caps_long_url() {
        let longURL = "https://example.com/" + String(repeating: "a", count: 500)
        let ctx = AppContext(
            bundleId: "com.apple.Safari",
            displayName: "Safari",
            category: .browser,
            url: longURL
        )
        let line = ctx.promptLine
        XCTAssertNotNil(line)
        // 240-char cap on URL portion.
        XCTAssertTrue(line!.contains("URL: "))
        let urlSection = line!.split(separator: ";").first { $0.contains("URL:") }!
        let extracted = String(urlSection).replacingOccurrences(of: " URL: ", with: "")
        XCTAssertLessThanOrEqual(extracted.count, 240)
    }

    func test_promptLine_returns_nil_without_bundle_id() {
        let ctx = AppContext(bundleId: nil, displayName: nil, category: nil, url: nil)
        XCTAssertNil(ctx.promptLine)
    }

    func test_promptLine_returns_nil_for_empty_bundle_id() {
        let ctx = AppContext(bundleId: "", displayName: nil, category: nil, url: nil)
        XCTAssertNil(ctx.promptLine)
    }

    func test_promptLine_falls_back_when_display_name_missing() {
        let ctx = AppContext(
            bundleId: "com.example.app",
            displayName: nil,
            category: .other,
            url: nil
        )
        let line = ctx.promptLine
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("App: com.example.app"))
    }

    // MARK: - Category allowlists are sane

    func test_known_code_editors_classified_correctly() {
        // We can't call the private classifier directly; instead spot-
        // check the public allowlist sets are populated.
        XCTAssertTrue(AppContext.codeEditorBundles.contains("com.apple.dt.Xcode"))
        XCTAssertTrue(AppContext.codeEditorBundles.contains("com.microsoft.VSCode"))
        XCTAssertTrue(AppContext.codeEditorBundles.contains("com.googlecode.iterm2"))
        XCTAssertTrue(AppContext.codeEditorBundles.contains("io.zed.Zed"))
        XCTAssertFalse(AppContext.codeEditorBundles.contains("com.apple.mail"))
    }

    func test_known_browsers_classified_correctly() {
        XCTAssertTrue(AppContext.browserBundles.contains("com.apple.Safari"))
        XCTAssertTrue(AppContext.browserBundles.contains("com.google.Chrome"))
        XCTAssertTrue(AppContext.browserBundles.contains("company.thebrowser.Browser"))   // Arc
        XCTAssertTrue(AppContext.browserBundles.contains("org.mozilla.firefox"))
        XCTAssertFalse(AppContext.browserBundles.contains("com.apple.dt.Xcode"))
    }

    func test_known_messaging_apps_classified_correctly() {
        XCTAssertTrue(AppContext.messagingBundles.contains("com.tinyspeck.slackmacgap"))
        XCTAssertTrue(AppContext.messagingBundles.contains("com.apple.MobileSMS"))
        XCTAssertTrue(AppContext.messagingBundles.contains("com.hnc.Discord"))
    }

    func test_known_email_apps_classified_correctly() {
        XCTAssertTrue(AppContext.emailBundles.contains("com.apple.mail"))
        XCTAssertTrue(AppContext.emailBundles.contains("com.readdle.smartemail-Mac"))
    }

    // MARK: - Category enum coverage

    func test_all_categories_have_distinct_raw_values() {
        let cases: [AppContext.Category] = [
            .codeEditor, .browser, .messaging, .email,
            .document, .terminal, .other
        ]
        let raws = Set(cases.map(\.rawValue))
        XCTAssertEqual(raws.count, cases.count, "Category rawValues must be unique")
    }
}
