import AppKit
import Foundation

/// Snapshot of the user's *target* app at paste time — what we're
/// dictating INTO. Fed to ClaudeClient as a system-prompt prefix so
/// cleanup tone, formatting, and casing can adapt per context.
///
/// Construction is best-effort: any field can be nil. We never block
/// the dictation pipeline waiting for context — the AppleScript
/// browser-URL probe has a hard 0.3s timeout and silently nils out.
struct AppContext: Equatable {
    let bundleId: String?
    let displayName: String?
    let category: Category?
    /// URL of the front tab, when the target is a browser we know.
    /// nil for non-browsers and for browsers whose AppleScript probe
    /// timed out / errored.
    let url: String?

    /// Coarse category used to drive prompt phrasing and gate Code Mode.
    /// Add new entries here AND in `Self.category(for:)` together.
    enum Category: String, Equatable {
        case codeEditor    // Cursor, Xcode, VS Code, iTerm…
        case browser       // Safari, Chrome, Arc, Brave, Edge, Firefox
        case messaging     // Slack, Messages, Discord
        case email         // Mail, Spark, Airmail
        case document      // Pages, Word, Notion, Bear
        case terminal      // Terminal (already in codeEditor for tone)
        case other
    }

    /// Read the current context. Cheap when the target isn't a browser
    /// (no AX walk, no AppleScript). For browsers, kicks off a bounded
    /// AppleScript probe with a 0.3s timeout.
    @MainActor
    static func current() -> AppContext {
        let app = NSWorkspace.shared.frontmostApplication
        let bid = app?.bundleIdentifier
        let name = app?.localizedName
        let cat = category(for: bid)
        let url: String? = {
            // Opt-in only: reading the active-tab URL sends an Apple Event to
            // the browser (drives the "control <browser>" automation prompt).
            guard Preferences.shared.contextAwareToneEnabled,
                  cat == .browser, let bid else { return nil }
            return frontBrowserURL(bundleId: bid)
        }()
        return AppContext(bundleId: bid, displayName: name, category: cat, url: url)
    }

    /// Compact one-line context the cleanup prompt can prepend. Returns
    /// nil when there's nothing useful to say (no bundle id detected).
    var promptLine: String? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        var parts: [String] = []
        if let displayName, !displayName.isEmpty {
            parts.append("App: \(displayName) (\(bundleId))")
        } else {
            parts.append("App: \(bundleId)")
        }
        if let category {
            parts.append("Category: \(category.rawValue)")
        }
        if let url, !url.isEmpty {
            // Cap URL length so a runaway query string doesn't blow
            // out the prompt.
            let trimmed = url.count > 240 ? String(url.prefix(240)) : url
            parts.append("URL: \(trimmed)")
        }
        return parts.joined(separator: "; ")
    }

    // MARK: - Category mapping

    private static func category(for bundleId: String?) -> Category? {
        guard let bundleId else { return nil }
        // Keep this allowlist explicit; matching is exact-bundle so we
        // don't accidentally classify a sibling app.
        if codeEditorBundles.contains(bundleId) { return .codeEditor }
        if browserBundles.contains(bundleId) { return .browser }
        if messagingBundles.contains(bundleId) { return .messaging }
        if emailBundles.contains(bundleId) { return .email }
        if documentBundles.contains(bundleId) { return .document }
        if terminalBundles.contains(bundleId) { return .terminal }
        return .other
    }

    static let codeEditorBundles: Set<String> = [
        "com.todesktop.230313mzl4w4u92",       // Cursor
        "com.microsoft.VSCode",                // VS Code
        "com.visualstudio.code.oss",           // VS Code OSS
        "com.apple.dt.Xcode",                  // Xcode
        "com.jetbrains.intellij",              // IntelliJ
        "com.jetbrains.pycharm",               // PyCharm
        "com.jetbrains.WebStorm",              // WebStorm
        "com.googlecode.iterm2",               // iTerm2
        "com.apple.Terminal",                  // Terminal
        "co.zeit.hyper",                       // Hyper
        "com.github.atom",                     // Atom (legacy)
        "io.zed.Zed",                          // Zed
        "dev.warp.Warp-Stable",                // Warp
        "com.sublimetext.4",                   // Sublime Text 4
    ]

    static let browserBundles: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "company.thebrowser.Browser",          // Arc
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.vivaldi.Vivaldi",
    ]

    static let messagingBundles: Set<String> = [
        "com.tinyspeck.slackmacgap",           // Slack
        "com.apple.MobileSMS",                 // Messages
        "com.hnc.Discord",
        "com.microsoft.teams2",
        "com.skype.skype",
    ]

    static let emailBundles: Set<String> = [
        "com.apple.mail",
        "com.readdle.smartemail-Mac",          // Spark
        "it.bloop.airmail3",
    ]

    static let documentBundles: Set<String> = [
        "com.apple.iWork.Pages",
        "com.microsoft.Word",
        "notion.id",
        "net.shinyfrog.bear",
        "md.obsidian",
    ]

    static let terminalBundles: Set<String> = [
        // Terminals are also in codeEditorBundles above for tone purposes;
        // the .terminal category exists for callers that need to
        // distinguish for code-token formatting decisions.
    ]

    // MARK: - Browser URL via AppleScript (bounded)

    /// Map a known browser bundleId to the AppleScript snippet that
    /// returns the active-tab URL. Silently returns nil for browsers
    /// we don't have a recipe for.
    private static func appleScriptForBrowserURL(bundleId: String) -> String? {
        switch bundleId {
        case "com.apple.Safari":
            return #"tell application "Safari" to return URL of front document"#
        case "com.google.Chrome", "com.google.Chrome.canary":
            return #"tell application "Google Chrome" to return URL of active tab of front window"#
        case "com.brave.Browser":
            return #"tell application "Brave Browser" to return URL of active tab of front window"#
        case "company.thebrowser.Browser":
            return #"tell application "Arc" to return URL of active tab of front window"#
        case "com.microsoft.edgemac":
            return #"tell application "Microsoft Edge" to return URL of active tab of front window"#
        case "com.vivaldi.Vivaldi":
            return #"tell application "Vivaldi" to return URL of active tab of front window"#
        // Firefox doesn't expose a stable AppleScript URL accessor.
        // Skip — bundleId alone tells the model "browser" which is
        // already useful.
        default:
            return nil
        }
    }

    /// Run the matching AppleScript with a 0.3s timeout, return the URL
    /// string or nil. Bounded so a sticky AppleScript handler can never
    /// stall the dictation pipeline.
    private static func frontBrowserURL(bundleId: String) -> String? {
        guard let script = appleScriptForBrowserURL(bundleId: bundleId) else { return nil }
        let sem = DispatchSemaphore(value: 0)
        var result: String?
        // NSAppleScript's compile/execute can briefly block; do it on
        // a utility queue and bail if it doesn't return in 300ms.
        DispatchQueue.global(qos: .userInitiated).async {
            var errInfo: NSDictionary?
            if let osa = NSAppleScript(source: script) {
                let descriptor = osa.executeAndReturnError(&errInfo)
                if errInfo == nil, let s = descriptor.stringValue, !s.isEmpty {
                    result = s
                }
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 0.3)
        return result
    }
}
