import XCTest
@testable import ListenToMe

/// Tests that every `claude --print` CLI invocation is isolated: no tools,
/// no MCP servers, no user/project/local settings (so no hooks), no
/// skills. A dictated transcript becomes the prompt to this subprocess, so
/// without these flags a spoken instruction could trigger real tool side
/// effects via the user's own CLAUDE.md/hooks/MCP config.
final class ClaudeClientCLIIsolationTests: XCTestCase {

    func test_cliArgs_containsIsolationFlags() {
        let args = ClaudeClient.cliArgs(systemPrompt: "system prompt text")
        for flag in ClaudeClient.cliIsolationArgs {
            XCTAssertTrue(args.contains(flag), "missing isolation flag \(flag) in \(args)")
        }
    }

    func test_cliArgs_preservesExistingSafetyFlags() {
        let args = ClaudeClient.cliArgs(systemPrompt: "x")
        XCTAssertTrue(args.contains("--no-session-persistence"))
        XCTAssertTrue(args.contains("--disable-slash-commands"))
        XCTAssertFalse(args.contains("--bare"), "must never pass --bare, breaks OAuth subscription auth")
    }

    func test_cliArgs_carriesSystemPrompt() {
        let args = ClaudeClient.cliArgs(systemPrompt: "unique-marker-xyz")
        XCTAssertTrue(args.contains("unique-marker-xyz"))
        XCTAssertTrue(args.contains("--append-system-prompt"))
    }

    func test_cliArgs_isolationFlagsPrecedeModelSelection() {
        // Not load-bearing for correctness (argparse doesn't care about
        // order), but matches the exact verified-working invocation from
        // the review, so a future refactor doesn't silently reorder past
        // a flag that only works before/after another.
        let args = ClaudeClient.cliArgs(systemPrompt: "x")
        guard let toolsIdx = args.firstIndex(of: "--tools"),
              let modelIdx = args.firstIndex(of: "--model") else {
            XCTFail("expected both --tools and --model in \(args)")
            return
        }
        XCTAssertLessThan(toolsIdx, modelIdx)
    }

    func test_isolationArgs_matchVerifiedWorkingSet() {
        XCTAssertEqual(ClaudeClient.cliIsolationArgs,
                       ["--tools", "", "--strict-mcp-config", "--setting-sources", ""])
    }
}
