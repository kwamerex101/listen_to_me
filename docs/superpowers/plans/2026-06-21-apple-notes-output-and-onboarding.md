# Apple Notes Output Destinations + First-Run Onboarding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a user-selectable output destination that can write dictations into Apple Notes (append-to-default-note, new-note-each-time, or daily-note), plus a four-screen first-run onboarding flow, both configurable in Settings.

**Architecture:** A new `OutputDestination` model in `Preferences` selects where a finished dictation lands. When it is `.activeApp` (default) the existing paste-tracked → cleanup → replace pipeline in `AppDelegate.handleRelease` runs unchanged. When it is `.appleNotes`, a new branch routes the *cleaned* text through `NotesWriter`, an AppleScript bridge modeled on the bounded `NSAppleScript` pattern in `AppContext.frontBrowserURL`. A new `OnboardingWindow` (an `NSPanel`, mirroring `CorrectionWindow`) hosts five SwiftUI screens (practice → speech-model download → permissions → hotkey & mic → output) and is shown once on first launch, gated by a new `hasCompletedOnboarding` preference. The speech-model screen kicks off the Whisper Base download via the existing `WhisperModelManager`, which continues in the background while the user completes the remaining screens.

**Tech Stack:** Swift 5.9 / SwiftUI / AppKit, macOS 14+, XCTest, XcodeGen (`project.yml`), ad-hoc signed bundle. AppleScript via `NSAppleScript`.

## Global Constraints

- **Version bump policy:** every shippable change bumps BOTH `CFBundleShortVersionString` (patch +1) and `CFBundleVersion` (+1) in `project.yml`. Current: `0.14.8` / build `35` → target `0.14.9` / build `36`.
- **Privacy contract:** no transcript leaves the device unless cloud cleanup is explicitly selected. Apple Notes writing is local IPC (Apple Events) — it does not send text off-device.
- **TCC discipline:** controlling Notes.app is a *new* Automation grant. NEVER probe Notes on launch. Only send an Apple Event to Notes when the user has actively selected an Apple Notes destination (or confirmed it in onboarding). This mirrors the existing opt-in gating of `contextAwareToneEnabled` and `voiceCommandsEnabled`.
- **Test framework:** XCTest, `@testable import ListenToMe`. Test files live in `ListenToMeTests/`, registered to the `ListenToMeTests` target via XcodeGen source globbing.
- **Build/test commands:**
  - Regenerate project after adding files: `xcodegen generate`
  - Run tests: `xcodebuild test -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'`
- **Scope:** output destinations covered here are `.activeApp` (existing behavior), `.clipboard` (copy only, no paste), and `.appleNotes`. User-authored Styles and a Notes-backed note picker are explicitly OUT of scope.
- **Copy style:** settings rows use the Eloquent pattern — short label + one-line benefit description. Sentence case. No Title Case.
- **AppleScript safety:** every `NSAppleScript` execution runs off the main actor with a hard timeout (5s for Notes — it is NOT in the latency-critical paste path), and fails silently/with a surfaced error rather than blocking the pipeline (per the `AppContext.frontBrowserURL` precedent).

---

## Execution Progress

> Live tracker. Branch `feat/notes-output-onboarding` off `6af80c2`. Updated as each task's review comes back clean.

| Task | Title | Status |
|------|-------|--------|
| 1 | Output destination & note-mode model | ✅ complete |
| 2 | NotesWriter pure helpers | ⬜ not started |
| 3 | NotesWriter executor | ⬜ not started |
| 4 | OutputRouter + pipeline wiring (paste/clipboard/notes) | ⬜ not started |
| 5 | Settings Output section | ⬜ not started |
| 6 | OnboardingWindow | ⬜ not started |
| 7 | OnboardingView — 5 screens | ⬜ not started |
| 8 | Present onboarding on first launch | ⬜ not started |
| 9 | Info.plist + version bump + docs | ⬜ not started |
| — | Final whole-branch review | ⬜ not started |

Status legend: ⬜ not started · 🟡 in progress · 🔵 in review · ✅ complete · 🔴 blocked

### Issues Log

_Issues found during build are appended here (task, severity, description, resolution)._

- **Task 1 (Important, resolved):** `OutputDestinationTests` class comment falsely claimed a throwaway UserDefaults suite; tests touch only enum statics. Corrected comment (commit `05e3d0f`).
- **Task 1 (⚠️, resolved/not-a-gap):** reviewer flagged `project.yml` absent from diff. Verified test target uses directory glob (`path: ListenToMeTests`) and `.xcodeproj` is gitignored/generated → new test files auto-included by `xcodegen generate`; no `project.yml` change needed.
- **Task 1 (Minor, deferred):** no `Preferences.shared` UserDefaults round-trip coverage (brief didn't require it). Candidate for future hardening with an injected `UserDefaults(suiteName:)`.
- **Process (resolved):** the Task 1 comment-fix subagent used `git commit -am`, which swept two uncommitted files into `05e3d0f`: the tracker doc and a regenerated `Info.plist`. Not harmful (see next), but going forward fix subagents must use explicit `git add <paths>`, never `-am`, so they don't capture the live tracker file.
- **Discovery → PLAN FIX (Task 9):** `ListenToMe/Info.plist` is GENERATED by XcodeGen from `project.yml` `info.properties`. The tracked copy was stale (0.13.0/build 15); `xcodegen generate` (run during Task 1) corrected it to 0.14.8/35 to match `project.yml` — committed incidentally in `05e3d0f`. Implication: **Task 9 originally said to hand-edit `Info.plist`, which would be clobbered.** Task 9 Step 1 + File Structure updated to edit `project.yml` `NSAppleEventsUsageDescription` instead, then regenerate. Same applies to the version bump (already correctly targets `project.yml`).

---

## File Structure

**New files:**
- `ListenToMe/Core/NotesWriter.swift` — AppleScript bridge: build + run scripts to create/append Notes. Contains a pure script-builder and HTML-escaper (unit-tested) and a bounded executor (not unit-tested).
- `ListenToMe/Core/OutputRouter.swift` — decides what to do with finished text based on the selected destination; the note-delivery entry point called from `AppDelegate`.
- `ListenToMe/UI/OnboardingWindow.swift` — `NSPanel` host for the onboarding flow (mirrors `CorrectionWindow`).
- `ListenToMe/UI/OnboardingView.swift` — the five-screen SwiftUI onboarding flow (includes the speech-model download screen).
- `ListenToMeTests/OutputDestinationTests.swift` — round-trip + default tests for the new prefs.
- `ListenToMeTests/NotesWriterTests.swift` — script-builder + HTML-escape + title-generation tests.

**Modified files:**
- `ListenToMe/State/Preferences.swift` — add `OutputDestination`, `NoteMode` enums + keys/getters + `hasCompletedOnboarding`.
- `ListenToMe/ListenToMeApp.swift` — branch `handleRelease` on destination; present onboarding on first launch.
- `ListenToMe/UI/SettingsView.swift` — add an "Output" section to `dictationTab`.
- `project.yml` `info.properties.NSAppleEventsUsageDescription` — broaden to mention Notes (this is the source; `ListenToMe/Info.plist` is regenerated from it by `xcodegen generate`).
- `project.yml` — version bump.
- `CHANGELOG.md`, `README.md`, `SECURITY.md` — document the feature + the new TCC surface.

---

## Task 1: Output destination & note-mode model

**Files:**
- Modify: `ListenToMe/State/Preferences.swift` (add enums near the other config enums ~line 33; keys ~line 119; getters ~line 379)
- Test: `ListenToMeTests/OutputDestinationTests.swift`

**Interfaces:**
- Produces:
  - `enum OutputDestination: String, CaseIterable { case activeApp, clipboard, appleNotes; var label: String }`
  - `enum NoteMode: String, CaseIterable { case appendToDefault, newEachTime, dailyNote; var label: String }`
  - `Preferences.shared.outputDestination: OutputDestination` (default `.activeApp`)
  - `Preferences.shared.noteMode: NoteMode` (default `.appendToDefault`)
  - `Preferences.shared.noteTitle: String` (default `"ListenToMe"`)
  - `Preferences.shared.noteFolder: String` (default `"ListenToMe"`)
  - `Preferences.shared.hasCompletedOnboarding: Bool` (default `false`)

- [ ] **Step 1: Write the failing test**

Create `ListenToMeTests/OutputDestinationTests.swift`:

```swift
import XCTest
@testable import ListenToMe

/// Round-trip + default tests for the output-destination preferences.
/// Uses a throwaway UserDefaults suite so we never touch the real domain.
final class OutputDestinationTests: XCTestCase {

    func test_outputDestination_defaults_to_activeApp() {
        XCTAssertEqual(OutputDestination.activeApp.rawValue, "activeApp")
        XCTAssertEqual(OutputDestination(rawValue: "clipboard"), .clipboard)
        XCTAssertEqual(OutputDestination(rawValue: "appleNotes"), .appleNotes)
        XCTAssertEqual(OutputDestination.allCases.count, 3)
    }

    func test_noteMode_cases_and_labels_are_distinct() {
        let labels = NoteMode.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, NoteMode.allCases.count)
        XCTAssertEqual(NoteMode.allCases.count, 3)
    }

    func test_outputDestination_labels_are_nonempty() {
        for d in OutputDestination.allCases {
            XCTAssertFalse(d.label.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS' -only-testing:ListenToMeTests/OutputDestinationTests`
Expected: FAIL — `cannot find 'OutputDestination' in scope`.

- [ ] **Step 3: Add the enums to Preferences.swift**

Insert after the `AppearanceMode` enum (after line 86, before `final class Preferences`):

```swift
/// Where a finished dictation is delivered. `.activeApp` (default) keeps the
/// existing paste-tracked → cleanup → replace pipeline. `.appleNotes` routes
/// the cleaned text into Apple Notes via NotesWriter instead of pasting.
enum OutputDestination: String, CaseIterable {
    case activeApp
    case clipboard
    case appleNotes

    var label: String {
        switch self {
        case .activeApp:  return "Active app (paste)"
        case .clipboard:  return "Clipboard (copy only)"
        case .appleNotes: return "Apple Notes"
        }
    }
}

/// How a dictation lands when the destination is Apple Notes.
enum NoteMode: String, CaseIterable {
    case appendToDefault   // append to one running note (noteTitle)
    case newEachTime       // create a fresh note per dictation
    case dailyNote         // append to a note titled with today's date

    var label: String {
        switch self {
        case .appendToDefault: return "Append to one note"
        case .newEachTime:     return "New note each time"
        case .dailyNote:       return "Append to a daily note"
        }
    }
}
```

- [ ] **Step 4: Add the keys to Preferences**

Add to the `private let k…` block (after line 119, `kCleanupIntensity`):

```swift
    private let kOutputDestination = "wf.outputDestination"
    private let kNoteMode = "wf.noteMode"
    private let kNoteTitle = "wf.noteTitle"
    private let kNoteFolder = "wf.noteFolder"
    private let kHasCompletedOnboarding = "wf.hasCompletedOnboarding"
```

- [ ] **Step 5: Add the getters/setters**

Add after the `cleanupIntensity` computed property (after line 379):

```swift
    // MARK: - Output destination (where dictations land)

    var outputDestination: OutputDestination {
        get {
            let raw = defaults.string(forKey: kOutputDestination) ?? OutputDestination.activeApp.rawValue
            return OutputDestination(rawValue: raw) ?? .activeApp
        }
        set { defaults.set(newValue.rawValue, forKey: kOutputDestination) }
    }

    var noteMode: NoteMode {
        get {
            let raw = defaults.string(forKey: kNoteMode) ?? NoteMode.appendToDefault.rawValue
            return NoteMode(rawValue: raw) ?? .appendToDefault
        }
        set { defaults.set(newValue.rawValue, forKey: kNoteMode) }
    }

    /// Title of the running/default note (used by .appendToDefault). Falls back
    /// to "ListenToMe" when unset or blanked.
    var noteTitle: String {
        get {
            let v = defaults.string(forKey: kNoteTitle) ?? ""
            return v.isEmpty ? "ListenToMe" : v
        }
        set { defaults.set(newValue, forKey: kNoteTitle) }
    }

    /// Notes folder the app writes into. Defaults to "ListenToMe" (created on
    /// first write if absent).
    var noteFolder: String {
        get {
            let v = defaults.string(forKey: kNoteFolder) ?? ""
            return v.isEmpty ? "ListenToMe" : v
        }
        set { defaults.set(newValue, forKey: kNoteFolder) }
    }

    /// True once the user has finished (or skipped) the first-run onboarding.
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: kHasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: kHasCompletedOnboarding) }
    }
```

- [ ] **Step 6: Regenerate project so the new test file compiles into the target**

Run: `xcodegen generate`
Expected: `Created project at ListenToMe.xcodeproj`.

- [ ] **Step 7: Run test to verify it passes**

Run: `xcodebuild test -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS' -only-testing:ListenToMeTests/OutputDestinationTests`
Expected: PASS (3 tests).

- [ ] **Step 8: Commit**

```bash
git add ListenToMe/State/Preferences.swift ListenToMeTests/OutputDestinationTests.swift project.yml
git commit -m "feat: add output-destination + note-mode preferences

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: NotesWriter — script builder, HTML escape, title generation (pure logic)

This task delivers only the **pure, testable** parts of `NotesWriter`: HTML escaping, note-title derivation, and AppleScript-source generation. The bounded executor (which actually talks to Notes.app) is added in Task 3 — it cannot run in CI.

**Files:**
- Create: `ListenToMe/Core/NotesWriter.swift`
- Test: `ListenToMeTests/NotesWriterTests.swift`

**Interfaces:**
- Produces (all `static`, on `enum NotesWriter`):
  - `func escapeHTML(_ s: String) -> String`
  - `func bodyParagraph(timestamp: String, text: String) -> String` → one `<div>…</div>` line, HTML-escaped, timestamp bolded.
  - `func noteTitle(mode: NoteMode, defaultTitle: String, text: String, dateString: String) -> String`
  - `func createScript(folder: String, title: String, bodyHTML: String) -> String`
  - `func appendScript(folder: String, title: String, bodyHTML: String) -> String`
- Consumes: `NoteMode` (Task 1).

- [ ] **Step 1: Write the failing test**

Create `ListenToMeTests/NotesWriterTests.swift`:

```swift
import XCTest
@testable import ListenToMe

/// Pure-logic tests for NotesWriter. No Notes.app contact — only the script
/// strings and helpers are exercised here.
final class NotesWriterTests: XCTestCase {

    func test_escapeHTML_escapes_reserved_characters() {
        XCTAssertEqual(
            NotesWriter.escapeHTML("a < b & c > d \"q\""),
            "a &lt; b &amp; c &gt; d &quot;q&quot;"
        )
    }

    func test_escapeHTML_converts_newlines_to_breaks() {
        XCTAssertEqual(NotesWriter.escapeHTML("line1\nline2"), "line1<br>line2")
    }

    func test_bodyParagraph_wraps_and_bolds_timestamp() {
        let html = NotesWriter.bodyParagraph(timestamp: "14:05", text: "hello & hi")
        XCTAssertEqual(html, "<div><b>14:05</b>&nbsp;hello &amp; hi</div>")
    }

    func test_noteTitle_dailyNote_uses_date() {
        let t = NotesWriter.noteTitle(mode: .dailyNote, defaultTitle: "ListenToMe",
                                      text: "anything", dateString: "2026-06-21")
        XCTAssertEqual(t, "2026-06-21")
    }

    func test_noteTitle_appendToDefault_uses_default() {
        let t = NotesWriter.noteTitle(mode: .appendToDefault, defaultTitle: "ListenToMe",
                                      text: "anything at all", dateString: "2026-06-21")
        XCTAssertEqual(t, "ListenToMe")
    }

    func test_noteTitle_newEachTime_uses_first_words() {
        let t = NotesWriter.noteTitle(mode: .newEachTime, defaultTitle: "ListenToMe",
                                      text: "Buy milk eggs bread cheese and a dozen other things",
                                      dateString: "2026-06-21")
        // First 6 words.
        XCTAssertEqual(t, "Buy milk eggs bread cheese and")
    }

    func test_noteTitle_newEachTime_empty_text_falls_back_to_date() {
        let t = NotesWriter.noteTitle(mode: .newEachTime, defaultTitle: "ListenToMe",
                                      text: "   ", dateString: "2026-06-21")
        XCTAssertEqual(t, "2026-06-21")
    }

    func test_createScript_embeds_escaped_folder_and_title() {
        let s = NotesWriter.createScript(folder: "ListenToMe", title: "2026-06-21",
                                         bodyHTML: "<div>hi</div>")
        XCTAssertTrue(s.contains("make new folder with properties {name:\"ListenToMe\"}"))
        XCTAssertTrue(s.contains("make new note at thisFolder with properties {name:\"2026-06-21\", body:\"<div>hi</div>\"}"))
    }

    func test_appendScript_concatenates_body() {
        let s = NotesWriter.appendScript(folder: "ListenToMe", title: "ListenToMe",
                                         bodyHTML: "<div>hi</div>")
        XCTAssertTrue(s.contains("set body of theNote to (body of theNote) & \"<div>hi</div>\""))
    }

    func test_scripts_escape_applescript_quotes_in_title() {
        // A title containing a double-quote must not break the AppleScript literal.
        let s = NotesWriter.createScript(folder: "F", title: "say \"hi\"", bodyHTML: "<div>x</div>")
        XCTAssertTrue(s.contains("name:\"say \\\"hi\\\"\""))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS' -only-testing:ListenToMeTests/NotesWriterTests`
Expected: FAIL — `cannot find 'NotesWriter' in scope`.

- [ ] **Step 3: Create NotesWriter.swift with the pure helpers**

```swift
import Foundation

/// Writes dictations into Apple Notes via AppleScript. The pure helpers
/// (HTML escaping, title derivation, script generation) are testable; the
/// bounded executor `write(text:)` (added separately) talks to Notes.app and
/// is gated so it only runs when the user selected an Apple Notes destination.
///
/// TCC: sending these Apple Events triggers the one-time "ListenToMe wants to
/// control Notes" Automation prompt. We never run the executor on launch.
enum NotesWriter {

    // MARK: - Pure helpers (unit-tested)

    /// Minimal HTML escape for Notes bodies (Notes stores rich-text HTML).
    /// Newlines become <br> so multi-line dictations keep their line breaks.
    static func escapeHTML(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "\n", with: "<br>")
        return out
    }

    /// One timestamped paragraph, mirroring the daily-note bullet format
    /// (`- **HH:mm** — text`) but as Notes HTML.
    static func bodyParagraph(timestamp: String, text: String) -> String {
        "<div><b>\(escapeHTML(timestamp))</b>&nbsp;\(escapeHTML(text))</div>"
    }

    /// Title for the target note given the mode.
    /// - dailyNote → the date string.
    /// - appendToDefault → the configured default title.
    /// - newEachTime → first six words of the dictation, or the date if empty.
    static func noteTitle(mode: NoteMode, defaultTitle: String,
                          text: String, dateString: String) -> String {
        switch mode {
        case .dailyNote:
            return dateString
        case .appendToDefault:
            return defaultTitle
        case .newEachTime:
            let words = text.split(whereSeparator: { $0.isWhitespace }).prefix(6)
            let joined = words.joined(separator: " ")
            return joined.isEmpty ? dateString : joined
        }
    }

    /// Escape a Swift string for embedding inside an AppleScript double-quoted
    /// literal: backslash first, then double-quote.
    private static func escapeAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// AppleScript that ensures `folder` exists, then makes a new note with
    /// `title` + `bodyHTML` inside it.
    static func createScript(folder: String, title: String, bodyHTML: String) -> String {
        let f = escapeAppleScript(folder)
        let t = escapeAppleScript(title)
        let b = escapeAppleScript(bodyHTML)
        return """
        tell application "Notes"
            if not (exists folder "\(f)") then
                make new folder with properties {name:"\(f)"}
            end if
            set thisFolder to folder "\(f)"
            make new note at thisFolder with properties {name:"\(t)", body:"\(b)"}
        end tell
        """
    }

    /// AppleScript that appends `bodyHTML` to the first note named `title`
    /// inside `folder`. Creates the folder + note when missing (so append
    /// modes are self-healing on first use).
    static func appendScript(folder: String, title: String, bodyHTML: String) -> String {
        let f = escapeAppleScript(folder)
        let t = escapeAppleScript(title)
        let b = escapeAppleScript(bodyHTML)
        return """
        tell application "Notes"
            if not (exists folder "\(f)") then
                make new folder with properties {name:"\(f)"}
            end if
            set thisFolder to folder "\(f)"
            if (exists note "\(t)" of thisFolder) then
                set theNote to note "\(t)" of thisFolder
                set body of theNote to (body of theNote) & "\(b)"
            else
                make new note at thisFolder with properties {name:"\(t)", body:"\(b)"}
            end if
        end tell
        """
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS' -only-testing:ListenToMeTests/NotesWriterTests`
Expected: PASS (9 tests).

Note: `test_scripts_escape_applescript_quotes_in_title` expects `name:"say \"hi\""` in the generated source — the `escapeAppleScript` backslash pass produces exactly that.

- [ ] **Step 5: Commit**

```bash
git add ListenToMe/Core/NotesWriter.swift ListenToMeTests/NotesWriterTests.swift
git commit -m "feat: NotesWriter pure helpers (HTML escape, titles, AppleScript builders)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: NotesWriter executor — bounded AppleScript run

Adds the side-effecting method that actually talks to Notes.app, modeled on `AppContext.frontBrowserURL`'s off-main + semaphore-timeout pattern but with a 5s budget (Notes is slower than a URL read and this is not on the paste latency path).

**Files:**
- Modify: `ListenToMe/Core/NotesWriter.swift`

**Interfaces:**
- Produces: `static func write(text: String, mode: NoteMode, folder: String, defaultTitle: String) -> Result<Void, NotesError>`
- Produces: `enum NotesError: Error { case scriptError(String); case timedOut }`

- [ ] **Step 1: Add the executor (no unit test — it requires Notes.app + TCC)**

Append to `NotesWriter` in `ListenToMe/Core/NotesWriter.swift`:

```swift
    // MARK: - Executor (talks to Notes.app — NOT unit-tested)

    enum NotesError: Error {
        case scriptError(String)
        case timedOut
    }

    /// Resolve the target title + script for the mode, then run it with a 5s
    /// timeout off the main thread. Returns .success on a clean run.
    ///
    /// SIDE EFFECT: sends Apple Events to Notes — triggers the Automation TCC
    /// prompt on first use. Callers MUST only invoke this when the user chose
    /// an Apple Notes destination.
    @discardableResult
    static func write(text: String, mode: NoteMode,
                      folder: String, defaultTitle: String) -> Result<Void, NotesError> {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let now = Date()

        let title = noteTitle(mode: mode, defaultTitle: defaultTitle,
                              text: text, dateString: dateFmt.string(from: now))
        let body = bodyParagraph(timestamp: timeFmt.string(from: now), text: text)

        // newEachTime always creates; the append modes append (self-healing).
        let source = (mode == .newEachTime)
            ? createScript(folder: folder, title: title, bodyHTML: body)
            : appendScript(folder: folder, title: title, bodyHTML: body)

        let sem = DispatchSemaphore(value: 0)
        var runResult: Result<Void, NotesError> = .failure(.timedOut)

        DispatchQueue.global(qos: .userInitiated).async {
            var errInfo: NSDictionary?
            if let osa = NSAppleScript(source: source) {
                _ = osa.executeAndReturnError(&errInfo)
                if let errInfo, let msg = errInfo[NSAppleScript.errorMessage] as? String {
                    runResult = .failure(.scriptError(msg))
                } else if errInfo != nil {
                    runResult = .failure(.scriptError("unknown AppleScript error"))
                } else {
                    runResult = .success(())
                }
            } else {
                runResult = .failure(.scriptError("failed to compile AppleScript"))
            }
            sem.signal()
        }

        if sem.wait(timeout: .now() + 5.0) == .timedOut {
            return .failure(.timedOut)
        }
        return runResult
    }
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add ListenToMe/Core/NotesWriter.swift
git commit -m "feat: NotesWriter bounded AppleScript executor (5s timeout)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: OutputRouter + wire the Apple Notes branch into the pipeline

Routes finished text. `.activeApp` keeps the existing pipeline untouched; `.appleNotes` runs cleanup to completion (so the note gets polished text — Notes has no undo-replace affordance) then writes via `NotesWriter` off the main actor.

**Files:**
- Create: `ListenToMe/Core/OutputRouter.swift`
- Modify: `ListenToMe/ListenToMeApp.swift` (`handleRelease`, the post-`expanded` section, lines ~437–484)

**Interfaces:**
- Consumes: `Preferences.outputDestination/noteMode/noteFolder/noteTitle`, `NotesWriter.write`, `CleanupGate.shouldClean`, `ClaudeClient.shared.clean`, `HistoryStore.shared.add`.
- Produces: `enum OutputRouter { static func deliverToNotes(text: String) async -> Result<Void, NotesWriter.NotesError> }`

- [ ] **Step 1: Create OutputRouter.swift**

```swift
import Foundation

/// Delivers finished dictation text to the non-paste destinations. The
/// `.activeApp` path stays in AppDelegate (it owns the paste-token/replace
/// lifecycle); this type owns only the Apple Notes path.
enum OutputRouter {

    /// Write `text` into Apple Notes per the user's note-mode/folder/title
    /// preferences. Runs the blocking NotesWriter executor off the main actor.
    static func deliverToNotes(text: String) async -> Result<Void, NotesWriter.NotesError> {
        let mode = Preferences.shared.noteMode
        let folder = Preferences.shared.noteFolder
        let title = Preferences.shared.noteTitle
        return await Task.detached(priority: .userInitiated) {
            NotesWriter.write(text: text, mode: mode, folder: folder, defaultTitle: title)
        }.value
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodegen generate && xcodebuild build -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Branch handleRelease on the destination**

In `ListenToMe/ListenToMeApp.swift`, locate the block that begins right after the secure-input guard and the comment `// Streaming preview: paste the raw transcript NOW…` (currently line ~453, starting `lastRawTranscript = raw`). Replace the existing `if CleanupGate.shouldClean(...) { … } else { … }` block (lines ~457–484) with a destination switch:

```swift
                lastRawTranscript = raw

                // Route on the user's output destination. .activeApp keeps the
                // streaming paste → background-cleanup → replace pipeline; the
                // Apple Notes path cleans to completion (Notes has no
                // undo-replace) then writes the note off-main.
                switch Preferences.shared.outputDestination {
                case .appleNotes:
                    await self.deliverToNotes(raw: raw, expanded: expanded,
                                              words: words, durMs: durMs)

                case .clipboard:
                    await self.deliverToClipboard(raw: raw, expanded: expanded,
                                                  words: words, durMs: durMs)

                case .activeApp:
                    if CleanupGate.shouldClean(text: expanded, wordCount: words,
                                               mode: Preferences.shared.cleanupMode) {
                        state.lastTranscript = expanded
                        let token = Paster.pasteTracked(expanded)
                        lastPasteToken = token
                        Haptics.success()
                        SoundCue.success()
                        state.phase = .polishing(rawPreview: String(expanded.prefix(40)))
                        PillWindow.shared.setInteractive(true)
                        startCleanupTask(raw: raw, expanded: expanded, durMs: durMs, token: token)
                    } else {
                        state.lastTranscript = expanded
                        let token = Paster.pasteTracked(expanded)
                        lastPasteToken = token
                        scheduleRetypeDetection(token: token)
                        recordStyleSample(token: token, cleaned: expanded)
                        Haptics.success()
                        SoundCue.success()
                        HistoryStore.shared.add(rawText: raw, finalText: expanded,
                                                 durationMs: durMs, bundleId: token.bundleId)
                        state.phase = .success(preview: String(expanded.prefix(30)))
                        PillWindow.shared.setInteractive(true)
                        autoReset(after: 3.0)
                    }
                }
```

(The `.activeApp` body is the existing code verbatim, moved under the new `case`.)

- [ ] **Step 4: Add the deliverToNotes helper**

Add this method to `AppDelegate` (place it just after `handleRelease`, before `startCleanupTask`, ~line 496):

```swift
    /// Apple Notes destination: clean to completion (subject to the gate),
    /// then write the polished text into Notes. No paste, no replace, no
    /// correction popover — Notes is a one-shot sink. History is recorded so
    /// the dashboard/History still reflect the dictation.
    private func deliverToNotes(raw: String, expanded: String,
                                words: Int, durMs: Int) async {
        state.phase = .polishing(rawPreview: String(expanded.prefix(40)))
        PillWindow.shared.setInteractive(true)

        var finalText = expanded
        if CleanupGate.shouldClean(text: expanded, wordCount: words,
                                   mode: Preferences.shared.cleanupMode) {
            do {
                let timeout = TimeInterval(Preferences.shared.cleanupTimeoutSec)
                finalText = try await ClaudeClient.shared.clean(
                    expanded, bundleId: nil, timeout: timeout)
            } catch {
                NSLog("[ListenToMe] notes cleanup failed, raw stands: \(error)")
                finalText = expanded
            }
        }

        let result = await OutputRouter.deliverToNotes(text: finalText)
        switch result {
        case .success:
            state.lastTranscript = finalText
            HistoryStore.shared.add(rawText: raw, finalText: finalText,
                                     durationMs: durMs, bundleId: "com.apple.Notes")
            Haptics.success()
            SoundCue.success()
            state.phase = .success(preview: "Saved to Notes")
            autoReset(after: 2.0)
        case .failure(let err):
            NSLog("[ListenToMe] notes write failed: \(err)")
            state.phase = .error(message: "Notes write failed")
            autoReset()
        }
        PillWindow.shared.setInteractive(false)
    }

    /// Clipboard destination: clean to completion (subject to the gate), copy
    /// to the pasteboard WITHOUT simulating Cmd+V, and record history. The
    /// user pastes when they're ready. No replace, no correction popover.
    private func deliverToClipboard(raw: String, expanded: String,
                                    words: Int, durMs: Int) async {
        state.phase = .polishing(rawPreview: String(expanded.prefix(40)))

        var finalText = expanded
        if CleanupGate.shouldClean(text: expanded, wordCount: words,
                                   mode: Preferences.shared.cleanupMode) {
            do {
                let timeout = TimeInterval(Preferences.shared.cleanupTimeoutSec)
                finalText = try await ClaudeClient.shared.clean(
                    expanded, bundleId: nil, timeout: timeout)
            } catch {
                NSLog("[ListenToMe] clipboard cleanup failed, raw stands: \(error)")
                finalText = expanded
            }
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(finalText, forType: .string)

        state.lastTranscript = finalText
        HistoryStore.shared.add(rawText: raw, finalText: finalText,
                                 durationMs: durMs, bundleId: nil)
        Haptics.success()
        SoundCue.success()
        state.phase = .success(preview: "Copied to clipboard")
        autoReset(after: 2.0)
    }
```

- [ ] **Step 5: Build and verify the pipeline compiles**

Run: `xcodebuild build -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`. (`handleRelease`'s task is already `@MainActor`; `await` inside it is valid.)

- [ ] **Step 6: Run the full existing suite to confirm no regressions**

Run: `xcodebuild test -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'`
Expected: all existing tests PASS (the `.activeApp` path is unchanged).

- [ ] **Step 7: Commit**

```bash
git add ListenToMe/Core/OutputRouter.swift ListenToMe/ListenToMeApp.swift
git commit -m "feat: route dictations to Apple Notes when selected as output destination

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Settings — Output section

Adds an "Output" section to `dictationTab` with the destination picker and, when Apple Notes is chosen, the note-mode picker, note title, and folder fields, plus the "change anytime" and TCC reassurance copy.

**Files:**
- Modify: `ListenToMe/UI/SettingsView.swift` (add `@State` vars ~line 64; add section call in `dictationTab` ~line 448; add the section builder near `onDevicePolishSection` ~line 618)

**Interfaces:**
- Consumes: `OutputDestination`, `NoteMode`, `Preferences.outputDestination/noteMode/noteTitle/noteFolder`, the existing `section`/`row` helpers, `DT`, `Motion`.

- [ ] **Step 1: Add the @State backing properties**

After line 64 (`@State private var parakeetVocabBoost…`) add:

```swift
    @State private var outputDestination: OutputDestination = Preferences.shared.outputDestination
    @State private var noteMode: NoteMode = Preferences.shared.noteMode
    @State private var noteTitleDraft: String = Preferences.shared.noteTitle
    @State private var noteFolderDraft: String = Preferences.shared.noteFolder
```

- [ ] **Step 2: Initialize them in onAppear**

In the `.onAppear` block (after line 151, alongside the other reads) add:

```swift
            outputDestination = Preferences.shared.outputDestination
            noteMode = Preferences.shared.noteMode
            noteTitleDraft = Preferences.shared.noteTitle
            noteFolderDraft = Preferences.shared.noteFolder
```

- [ ] **Step 3: Add the section to dictationTab**

In `dictationTab` (the `VStack` body, after `section(title: "Input") { … }` closes at line ~358 and before `section(title: "AI Cleanup")`), insert `outputSection`:

```swift
            outputSection
```

- [ ] **Step 4: Build the outputSection view**

Add this computed property just before `onDevicePolishSection` (~line 548):

```swift
    /// Where finished dictations land. Apple Notes reveals mode/title/folder
    /// controls and an Automation-permission note.
    private var outputSection: some View {
        section(title: "Output") {
            row(label: "Destination",
                description: "Where dictated text goes when you finish speaking.") {
                Picker("", selection: $outputDestination) {
                    ForEach(OutputDestination.allCases, id: \.self) { dest in
                        Text(dest.label).tag(dest)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: DT.controlPickerWidth)
                .onChange(of: outputDestination) { _, new in
                    Preferences.shared.outputDestination = new
                }
            }
            if outputDestination == .appleNotes {
                row(label: "Note mode",
                    description: "Append to one note, start a new note each time, or keep a daily note.") {
                    Picker("", selection: $noteMode) {
                        ForEach(NoteMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: DT.controlPickerWidth)
                    .onChange(of: noteMode) { _, new in
                        Preferences.shared.noteMode = new
                    }
                }
                if noteMode == .appendToDefault {
                    row(label: "Note name",
                        description: "The note your dictations are appended to.") {
                        TextField("ListenToMe", text: $noteTitleDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onSubmit { Preferences.shared.noteTitle = noteTitleDraft }
                    }
                    .hoverableRow()
                }
                row(label: "Folder",
                    description: "Apple Notes folder to write into. Created if it doesn't exist.") {
                    TextField("ListenToMe", text: $noteFolderDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit { Preferences.shared.noteFolder = noteFolderDraft }
                }
                .hoverableRow()
                row(label: "Permission",
                    description: "Writing to Notes asks macOS once to let ListenToMe control Notes. Nothing leaves your Mac.") {
                    EmptyView()
                }
            }
        }
        .animation(Motion.tabFade, value: outputDestination)
    }
```

- [ ] **Step 5: Build and smoke-launch**

Run: `xcodebuild build -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

Manual check (cannot be unit-tested — UI): launch the built app, open Settings → Dictation, confirm the Output section appears, selecting "Apple Notes" reveals mode/name/folder rows, and changing them persists across a relaunch.

- [ ] **Step 6: Commit**

```bash
git add ListenToMe/UI/SettingsView.swift
git commit -m "feat: Output settings section with Apple Notes destination controls

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: OnboardingWindow — first-run NSPanel host

A floating panel that becomes key (so the practice text field / pickers work), mirroring `CorrectionWindow`. Shown once on launch when `hasCompletedOnboarding == false`.

**Files:**
- Create: `ListenToMe/UI/OnboardingWindow.swift`

**Interfaces:**
- Produces: `final class OnboardingWindow: NSPanel { static let shared; func present(onFinish: @escaping () -> Void); func dismiss() }`
- Consumes: `OnboardingView` (Task 7).

- [ ] **Step 1: Create OnboardingWindow.swift**

```swift
import AppKit
import SwiftUI

/// Hosts the first-run onboarding flow. Like CorrectionWindow it becomes key
/// (the practice screen has an editable field + pickers). Centered, fixed
/// size, dismissed when the user finishes or skips.
final class OnboardingWindow: NSPanel {
    static let shared = OnboardingWindow()

    static let windowSize = NSSize(width: 560, height: 460)

    private var onFinish: (() -> Void)?

    private init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish

        let view = OnboardingView(
            onFinish: { [weak self] in
                self?.onFinish?()
                self?.dismiss()
            }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: Self.windowSize)
        host.autoresizingMask = [.width, .height]
        contentView = host

        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        orderOut(nil)
        onFinish = nil
    }
}
```

- [ ] **Step 2: Build (expect failure — OnboardingView not yet defined)**

Run: `xcodegen generate && xcodebuild build -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'`
Expected: FAIL — `cannot find 'OnboardingView' in scope`. This is resolved by Task 7. (Commit happens at the end of Task 7 so the tree always builds.)

---

## Task 7: OnboardingView — the five screens

A post-streaming SwiftUI stepper: Practice → Speech model → Permissions → Hotkey & Mic → Output. The speech-model screen triggers the Whisper Base download (background, skippable). Reuses existing primitives (`HotkeyBinding`, `AudioInputDevices`, `HotkeyMonitor`, `WhisperModelManager`, `OutputDestination`, `NoteMode`).

**Files:**
- Create: `ListenToMe/UI/OnboardingView.swift`

**Interfaces:**
- Consumes: `HotkeyBinding`, `AudioInputDevice`/`AudioInputDevices.available()`, `HotkeyMonitor.isAccessibilityGranted()` / `.promptAccessibility()`, `AppState.shared.micGranted`, `WhisperModelManager.shared` (`status`, `startDownload()`, `refreshStatus()`), `OutputDestination`, `NoteMode`, `Preferences`.
- Produces: `struct OnboardingView: View { init(onFinish: @escaping () -> Void) }`

- [ ] **Step 1: Create OnboardingView.swift**

```swift
import SwiftUI
import AppKit

/// First-run walkthrough. Four steps with a shared footer (brand pill ·
/// progress dots · primary CTA), modeled on Raycast Dictation's onboarding.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0
    private let stepCount = 5

    @ObservedObject private var modelManager = WhisperModelManager.shared

    // Live config the user can set inline.
    @State private var hotkey: HotkeyBinding = Preferences.shared.hotkeyBinding
    @State private var inputDeviceUID: String = Preferences.shared.inputDeviceUID ?? ""
    @State private var availableInputs: [AudioInputDevice] = []
    @State private var accessibilityGranted = HotkeyMonitor.isAccessibilityGranted()
    @State private var micGranted = AppState.shared.micGranted
    @State private var outputDestination: OutputDestination = Preferences.shared.outputDestination
    @State private var noteMode: NoteMode = Preferences.shared.noteMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)
            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
        .onAppear {
            availableInputs = AudioInputDevices.available()
            accessibilityGranted = HotkeyMonitor.isAccessibilityGranted()
            micGranted = AppState.shared.micGranted
            modelManager.refreshStatus()
        }
    }

    // MARK: - Step content

    @ViewBuilder private var content: some View {
        switch step {
        case 0: practiceStep
        case 1: modelStep
        case 2: permissionsStep
        case 3: hotkeyStep
        default: outputStep
        }
    }

    private var practiceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Try your first dictation")
                .font(.system(size: 20, weight: .semibold))
            Text("Hold your hotkey, say a sentence, and release. Your words land wherever your cursor is.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                stepLine(n: 1, "Hold the hotkey")
                stepLine(n: 2, "Speak naturally")
                stepLine(n: 3, "Release to paste")
            }
            .padding(.top, 8)
        }
    }

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download a speech model")
                .font(.system(size: 20, weight: .semibold))
            Text("Transcription runs entirely on your Mac. Whisper Base is a fast 148 MB model — a great default. You can switch to a larger model or Parakeet later in Settings.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            modelStatusRow
            Text("You can keep going — the download continues in the background.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        // Auto-start the download so "skip" still leaves a model downloading.
        // WhisperRunner does NOT lazily download on first dictation — without
        // this, a skipped onboarding leaves the first dictation erroring with
        // "Model missing". Only kick off when truly absent.
        .onAppear {
            modelManager.refreshStatus()
            if case .missing = modelManager.status {
                modelManager.startDownload()
            }
        }
    }

    @ViewBuilder private var modelStatusRow: some View {
        switch modelManager.status {
        case .ready(let bytes):
            Label("Downloaded · \(bytes / 1_000_000) MB", systemImage: "checkmark.circle")
                .font(.system(size: 14)).foregroundStyle(.green)
        case .missing:
            // Transient — onAppear auto-starts. Manual fallback if it didn't.
            Button {
                modelManager.startDownload()
            } label: {
                Label("Download Whisper Base (148 MB)", systemImage: "arrow.down.circle")
            }
        case .downloading(let progress):
            HStack(spacing: 10) {
                ProgressView(value: progress).progressViewStyle(.linear).frame(width: 200)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                Button("Cancel") { modelManager.cancelDownload() }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("⚠ \(message)").font(.system(size: 13)).foregroundStyle(.red)
                Button("Retry") { modelManager.startDownload() }
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions")
                .font(.system(size: 20, weight: .semibold))
            permissionRow(
                title: "Microphone",
                detail: "Lets ListenToMe capture your voice for transcription.",
                granted: micGranted,
                action: nil)
            permissionRow(
                title: "Accessibility",
                detail: "Lets ListenToMe paste into the focused app. Without it, text is copied to your clipboard.",
                granted: accessibilityGranted,
                action: {
                    HotkeyMonitor.promptAccessibility()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                })
        }
        .onAppear { accessibilityGranted = HotkeyMonitor.isAccessibilityGranted() }
    }

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hotkey & microphone")
                .font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("Hotkey").font(.system(size: 14, weight: .medium))
                Text("Hold to dictate anywhere, without opening the app first.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Picker("", selection: $hotkey) {
                    ForEach(HotkeyBinding.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: hotkey) { _, new in Preferences.shared.hotkeyBinding = new }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Microphone").font(.system(size: 14, weight: .medium))
                Picker("", selection: $inputDeviceUID) {
                    Text("System default").tag("")
                    ForEach(availableInputs, id: \.uid) { Text($0.name).tag($0.uid) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 260)
                .onChange(of: inputDeviceUID) { _, new in
                    Preferences.shared.inputDeviceUID = new.isEmpty ? nil : new
                }
            }
            Text("Tip: keep holding your hotkey to record, release to paste.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var outputStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where should dictations go?")
                .font(.system(size: 20, weight: .semibold))
            Picker("", selection: $outputDestination) {
                ForEach(OutputDestination.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: outputDestination) { _, new in Preferences.shared.outputDestination = new }

            if outputDestination == .appleNotes {
                Text("We'll keep a note called \"\(Preferences.shared.noteTitle)\" for you. Pick how new dictations land:")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Picker("", selection: $noteMode) {
                    ForEach(NoteMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .onChange(of: noteMode) { _, new in Preferences.shared.noteMode = new }
                Text("You can change the note, folder, and mode anytime in Settings.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer + helpers

    private var footer: some View {
        HStack {
            Text("ListenToMe")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            Button(step == stepCount - 1 ? "Start dictating" : "Continue") {
                if step == stepCount - 1 {
                    onFinish()
                } else {
                    withAnimation { step += 1 }
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func stepLine(n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
            Text(text).font(.system(size: 14))
        }
    }

    private func permissionRow(title: String, detail: String,
                               granted: Bool, action: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark")
                    .font(.system(size: 13)).foregroundStyle(.green)
            } else if let action {
                Button("Grant…", action: action)
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild build -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED` (resolves Task 6's forward reference).

Note: if `AudioInputDevice`'s member is not named `name`/`uid`, match the names used in `SettingsView` (it uses `dev.name` and `dev.uid`) — those are the canonical accessors.

- [ ] **Step 3: Commit (OnboardingWindow + OnboardingView together)**

```bash
git add ListenToMe/UI/OnboardingWindow.swift ListenToMe/UI/OnboardingView.swift
git commit -m "feat: first-run onboarding window + four-screen walkthrough

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Present onboarding on first launch

Show the window once after launch when onboarding hasn't been completed; mark it complete on finish.

**Files:**
- Modify: `ListenToMe/ListenToMeApp.swift` (`applicationDidFinishLaunching`, end of the method ~line 197)

**Interfaces:**
- Consumes: `OnboardingWindow.shared`, `Preferences.hasCompletedOnboarding`.

- [ ] **Step 1: Add the presentation call**

At the end of `applicationDidFinishLaunching` (after the `phaseChangeCancellable` assignment closes, ~line 198), add:

```swift
        // First-run onboarding. Deferred one runloop tick so the menu bar +
        // pill are installed before the panel takes key focus. Shown once;
        // completing it (or closing) sets the flag.
        if !Preferences.shared.hasCompletedOnboarding {
            DispatchQueue.main.async {
                OnboardingWindow.shared.present {
                    Preferences.shared.hasCompletedOnboarding = true
                }
            }
        }
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual verification (cannot be unit-tested)**

```bash
# Reset the flag so onboarding shows, then launch the built app.
defaults delete com.<your-bundle-id>.ListenToMe wf.hasCompletedOnboarding 2>/dev/null || true
open build/Build/Products/Debug/ListenToMe.app
```

Confirm: onboarding panel appears centered, all four steps advance, "Start dictating" closes it, and it does NOT reappear on the next launch. (Replace `<your-bundle-id>` with the value of `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.)

- [ ] **Step 4: Commit**

```bash
git add ListenToMe/ListenToMeApp.swift
git commit -m "feat: present first-run onboarding once on launch

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Info.plist usage string, version bump, docs

**Files:**
- Modify: `ListenToMe/Info.plist` (`NSAppleEventsUsageDescription`)
- Modify: `project.yml` (version)
- Modify: `CHANGELOG.md`, `README.md`, `SECURITY.md`

- [ ] **Step 1: Broaden the Apple Events usage description**

⚠️ `ListenToMe/Info.plist` is GENERATED by XcodeGen from `project.yml` → `targets.ListenToMe.info.properties` (~line 83). Editing `Info.plist` directly would be overwritten by the next `xcodegen generate`. Edit the source instead.

In `project.yml`, change `NSAppleEventsUsageDescription` under `info.properties` from:
`ListenToMe uses Apple Events to paste transcripts into the active app.`
to:
`ListenToMe uses Apple Events to paste transcripts into the active app and, when you choose the Apple Notes destination, to save dictations to Notes.`

Then run `xcodegen generate` to regenerate `Info.plist`. Both `project.yml` and the regenerated `ListenToMe/Info.plist` are committed in Step 6.

- [ ] **Step 2: Bump the version**

In `project.yml`, set:
```yaml
        CFBundleShortVersionString: "0.14.9"
        CFBundleVersion: "36"
```

- [ ] **Step 3: Add a CHANGELOG entry**

Prepend under the latest-version heading in `CHANGELOG.md`:

```markdown
## 0.14.9 (build 36)

### Added
- **Apple Notes output destination.** Settings → Dictation → Output lets you send dictations to Apple Notes instead of pasting into the active app. Three modes: append to one note, a new note each time, or a daily note. Note name and folder are configurable.
- **First-run onboarding.** A five-screen walkthrough (practice, speech-model download, permissions, hotkey & microphone, output) shown once on first launch. The speech-model screen downloads Whisper Base in the background so the app is ready to transcribe.

### Notes
- Choosing the Apple Notes destination triggers a one-time macOS prompt to allow ListenToMe to control Notes. Text is written locally via Apple Events — nothing leaves your Mac.
```

- [ ] **Step 4: Update README + SECURITY**

In `README.md`, add Apple Notes output + onboarding to the feature list. In `SECURITY.md`, document the new TCC surface under the Apple Events / Automation section: ListenToMe sends Apple Events to Notes only when the Apple Notes output destination is selected; this is the second Automation grant (after the opt-in browser-URL probe) and is never triggered on launch.

- [ ] **Step 5: Build + full test suite**

Run: `xcodegen generate && xcodebuild test -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`, all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add ListenToMe/Info.plist project.yml CHANGELOG.md README.md SECURITY.md
git commit -m "chore: v0.14.9/build 36 — Apple Notes output + onboarding docs + TCC string

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Manual Verification Checklist (post-implementation)

These exercise the side-effecting paths that cannot be unit-tested:

1. **Notes — append-to-default:** Settings → Output → Apple Notes, mode "Append to one note". Dictate a sentence. Approve the one-time Notes Automation prompt. Confirm a "ListenToMe" note in the "ListenToMe" folder gets a timestamped paragraph. Dictate again → a second paragraph appended to the SAME note.
2. **Notes — new each time:** switch mode. Dictate twice → two separate notes, titled from the first words.
3. **Notes — daily note:** switch mode. Dictate → note titled `yyyy-MM-dd`. Dictate again → appended to the same dated note.
4. **Cleanup applies:** with cleanup mode on, confirm the note text is the polished version, not the raw transcript.
5. **Folder creation:** delete the "ListenToMe" folder in Notes, dictate → it is recreated.
6. **Active-app unchanged:** switch back to "Active app (paste)" → dictation pastes + the correction popover + background replace all still work (regression check on the existing pipeline).
7. **Onboarding once:** reset `wf.hasCompletedOnboarding`, relaunch → onboarding shows; complete it → does not return.
7a. **Onboarding model download:** on a machine with no Whisper model, the speech-model screen auto-starts the Whisper Base download (progress bar appears without tapping anything); advancing through the rest of the onboarding does NOT cancel it; on completion the status flips to "Downloaded". A "Cancel" control is available during download. Confirm that finishing onboarding after the download completes yields a working first dictation.
8. **TCC discipline:** with destination = Active app, dictate repeatedly → NO Notes prompt ever appears.

---

## Self-Review Notes

- **Spec coverage:** Apple Notes output with default-note + user-changeable settings (Tasks 1–5), three landing modes (Task 1/2), onboarding modeled on the Raycast walkthrough (Tasks 6–8), version + docs + TCC string (Task 9). ✅
- **Type consistency:** `OutputDestination` / `NoteMode` names are identical across Preferences (T1), NotesWriter (T2/3), OutputRouter (T4), SettingsView (T5), OnboardingView (T7). `NotesWriter.write` signature `(text:mode:folder:defaultTitle:)` matches its caller in `OutputRouter.deliverToNotes`. `deliverToNotes(raw:expanded:words:durMs:)` in AppDelegate matches its call site in `handleRelease`.
- **Bundle id for Notes history:** writes use `bundleId: "com.apple.Notes"` so History/dashboard attribute them sensibly without a real paste target.
- **Clipboard destination:** added per scope decision — `.clipboard` copies cleaned text to the pasteboard without Cmd+V (Task 1 enum/test, Task 4 `deliverToClipboard`). It appears automatically in the Settings + onboarding pickers (both iterate `allCases`); no extra UI rows.
- **Out of scope (flagged):** user-authored Styles, per-style output overrides, picking an existing note via a Notes-backed picker (current UI uses a free-text note name). These are natural follow-ups but not in this plan.
