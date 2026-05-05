# Testing Patterns

**Analysis Date:** 2026-05-05

## Current State: No Automated Tests

**Status:** No XCTest suite exists. No `.swift` test files in the codebase.

**Finding:** Testing is entirely manual and verification-driven.

## Manual Verification Approach

**Build Verification:**
- Script: `./scripts/build.sh`
- Command: `xcodegen generate` → `xcodebuild`
- Output: Debug app at `build/Build/Products/Debug/ListenToMe.app`

**End-to-End Smoke Testing:**
Each feature ships with a "Verification" section in its planning document (stored locally in `.planning/plans/*`, not committed).

**Real-App Testing:**
Features are tested against live applications:
- TextEdit (system text field)
- Slack (message compose)
- Notion (rich text editor)

**Process:**
1. Build the app via `./scripts/build.sh`
2. Launch: `open "build/Build/Products/Debug/ListenToMe.app"`
3. Test dictation flow in real target apps
4. Verify transcript accuracy, cleanup quality, and UI phase transitions
5. Verify error handling (mic permission, model missing, cleanup timeout, etc.)
6. Check pill animations and state feedback

## Testing Gaps

**Not Covered:**
- Unit tests for pure functions (`VoiceEditor`, `ClaudeClient.sanitize`, `CommandRouter.parse`)
- Integration tests for subprocess spawning (`WhisperRunner`, `ClaudeClient`, `CommandRouter`)
- UI snapshot tests for different phase states
- Error handling paths (timeout, binary not found, process failure)
- Edge cases in regex-based transformations (voice editing, snippet expansion)

**High-Priority Test Candidates:**
1. **VoiceEditor.apply** (`Core/VoiceEditor.swift`):
   - Pure function; ideal for unit tests
   - Tests should cover: punctuation substitution, "scratch that" resolution, paragraph breaks, tidying
   - Edge cases: multiple "scratch that" commands, empty input, sentence boundary detection

2. **ClaudeClient.sanitize** (`Core/ClaudeClient.swift`):
   - Defensive output filtering; high-value unit tests
   - Tests should cover: quote stripping, code fence removal, preamble detection, word count explosion
   - Edge cases: empty output, hallucinated expansion, smart quotes, markdown variations

3. **CommandRouter.parse** (`Core/CommandRouter.swift`):
   - Stateless command parsing; easy to unit test
   - Tests should cover: "log today:", "shell:", "open" patterns
   - Edge cases: case insensitivity, punctuation handling, whitespace normalization

4. **PasteToken Validation** (`Core/Paster.swift`):
   - Token age checking, changeCount drift detection
   - High-impact correctness testing (prevents silent paste failures)

5. **Process Error Paths**:
   - `WhisperRunner`: binary not found, model missing, process failure with stderr
   - `ClaudeClient`: timeout, binary not found, process failure
   - `CommandRouter.runProcess`: file not found, shell execution failure

## Test Infrastructure Needed

**Framework:**
- XCTest (built into Xcode)
- No third-party test libraries currently in use

**Proposed Setup:**
1. Create `ListenToMeTests` target in Xcode project (via xcodegen in `project.yml`)
2. Add test files alongside source: `Core/VoiceEditorTests.swift`, `Core/ClaudeClientTests.swift`, etc.
3. Set up basic fixtures for common test data (raw transcripts, error conditions)
4. Run via: `xcodebuild test -scheme ListenToMe -destination generic/platform=macOS`

**Example Test Structure (Future):**
```swift
import XCTest
@testable import ListenToMe

class VoiceEditorTests: XCTestCase {
    func testPunctuationSubstitution() {
        let input = "what is this question mark"
        let result = VoiceEditor.apply(input)
        XCTAssertTrue(result.contains("?"))
    }
    
    func testScratchThatRemovesPreviousSentence() {
        let input = "Hello world. Scratch that."
        let result = VoiceEditor.apply(input)
        XCTAssertEqual(result, "")
    }
    
    func testMultipleScratchThat() {
        let input = "One. Two. Scratch that. Three. Scratch that."
        let result = VoiceEditor.apply(input)
        XCTAssert(result.contains("One"))
    }
}

class ClaudeClientSanitizeTests: XCTestCase {
    func testRejectsQuotedOutput() {
        let raw = "\"Here is the cleaned text\""
        let original = "raw text"
        let result = ClaudeClient.sanitize(cleaned: raw, original: original)
        XCTAssertEqual(result, original)
    }
    
    func testRejectsPreambles() {
        let raw = "Here is: cleaned output"
        let original = "raw text"
        let result = ClaudeClient.sanitize(cleaned: raw, original: original)
        XCTAssertEqual(result, original)
    }
    
    func testRejectsExplosion() {
        let original = "one two three"
        let raw = String(repeating: "word ", count: 100)
        let result = ClaudeClient.sanitize(cleaned: raw, original: original)
        XCTAssertEqual(result, original)
    }
}

class CommandRouterParseTests: XCTestCase {
    func testParseLogToday() {
        if let cmd = CommandRouter.parse("log today: eat lunch") {
            if case .logToday(let text) = cmd {
                XCTAssertEqual(text, "eat lunch")
            } else {
                XCTFail("Expected logToday")
            }
        } else {
            XCTFail("Failed to parse")
        }
    }
    
    func testParseOpenApp() {
        if let cmd = CommandRouter.parse("open Chrome") {
            if case .openApp(let name) = cmd {
                XCTAssertEqual(name, "Chrome")
            } else {
                XCTFail("Expected openApp")
            }
        }
    }
    
    func testParseShell() {
        if let cmd = CommandRouter.parse("shell: echo hello") {
            if case .shell(let body) = cmd {
                XCTAssertEqual(body, "echo hello")
            } else {
                XCTFail("Expected shell")
            }
        }
    }
}
```

## Manual Testing Checklist

**Use this for validation until automated tests exist:**

**Recording & Transcription:**
- [ ] Hotkey (Fn+Cmd) starts recording in idle state
- [ ] Recording shows waveform and level visualization
- [ ] Stop button (red dot) shows heartbeat + audio reactivity
- [ ] Release stops recording and transitions to transcribing
- [ ] Transcript appears within ~1.5s (streaming preview)

**Voice Editing:**
- [ ] "question mark" → "?"
- [ ] "period" / "full stop" → "."
- [ ] "comma" → ","
- [ ] "new paragraph" → "\n\n"
- [ ] "new line" → "\n"
- [ ] "scratch that" removes preceding sentence
- [ ] Multiple "scratch that" resolve iteratively
- [ ] Empty result (pure undo) shows "(scratched)" success

**Cleanup (LLM Polish):**
- [ ] Cleanup enabled (word count threshold met)
- [ ] Pill shows "checkmark + preview" in polishing state
- [ ] Cleanup completes within ~5s (Haiku model)
- [ ] Final text replaces raw via Cmd+Z+Cmd+V
- [ ] Cleanup failure keeps raw text in place
- [ ] Cleanup timeout (>20s) falls back to raw

**Correction Popover:**
- [ ] Pill tap in success/polishing opens correction window
- [ ] Edit text in popover, apply
- [ ] Replace happens via Cmd+Z+Cmd+V
- [ ] Target app reactivated after apply/cancel
- [ ] Manual edit recorded in history

**Error States:**
- [ ] Mic permission denied → permission card in pill
- [ ] Model missing → error message + auto-reset
- [ ] No audio captured → error message
- [ ] Cleanup binary missing → warning in menu bar

**Permissions & Launch:**
- [ ] App requests mic permission on launch
- [ ] App requests accessibility permission on launch (for hotkey)
- [ ] Settings window accessible
- [ ] Pill always visible in menu bar (even minimized)

**History & Snippets:**
- [ ] Dictations logged in history with raw + final text + duration
- [ ] Stats update (word count, WPM, streak)
- [ ] Snippet expansion works before cleanup
- [ ] Snippet + cleanup both run in correct order

## Build Verification Script

**Location:** `./scripts/build.sh`

**What it does:**
1. Checks `ListenToMe/Resources/whisper-cli` exists
2. Runs `xcodegen generate` to create `.xcodeproj` from `project.yml`
3. Builds Debug configuration with `xcodebuild`
4. Outputs app path: `build/Build/Products/Debug/ListenToMe.app`

**Usage:**
```bash
./scripts/build.sh
open "$(pwd)/build/Build/Products/Debug/ListenToMe.app"
```

## Proposed Test Automation Priority

**Phase 1 (High Impact, Low Effort):**
1. Unit tests for pure functions: `VoiceEditor`, `ClaudeClient.sanitize`, `CommandRouter.parse`
2. No external dependencies, fast execution, covers ~30% of code

**Phase 2 (Medium Effort):**
1. Integration tests for subprocess spawning
2. Mock file system for `CommandRouter` (log-to-daily, shell)
3. Timeout and error path testing

**Phase 3 (High Effort, Low Priority):**
1. UI snapshot tests for pill states
2. End-to-end tests with actual whisper/claude CLIs (slow, flaky)
3. AppKit integration tests (focus app detection, pasteboard tracking)

---

*Testing analysis: 2026-05-05*
