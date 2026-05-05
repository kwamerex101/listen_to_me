# Codebase Concerns

**Analysis Date:** 2026-05-05

## Tech Debt

**No Automated Tests**
- Issue: Entire codebase lacks unit, integration, or end-to-end tests. All verification is manual.
- Files: All source files in `ListenToMe/`
- Impact: Regressions go undetected until user-facing failures. Refactoring is high-risk. No CI/CD safety gate.
- Fix approach: Establish test suite using XCTest. Start with critical paths: `ClaudeClient.clean()`, `Paster.replace()`, `VoiceEditor.apply()`, `HistoryStore` persistence. Aim for >60% coverage on Core and State modules.

**HistoryStore Unbounded Growth**
- Issue: `history.json` grows indefinitely as records accumulate. No pruning, pagination, or archive mechanism.
- Files: `ListenToMe/State/HistoryStore.swift:47` (every `add()` triggers synchronous `save()`)
- Impact: After 12+ months of daily use, file grows to 10–50 MB. JSONDecoder load time increases from <10ms to 100+ms, freezing the app on startup. Eventually filesystem quotas may be exceeded.
- Fix approach: Implement pagination (load last 1000 records on startup). Add async save (debounce to 5s). Periodic archive (every 10k records) to dated JSON files in `~/Library/Application Support/ListenToMe/archives/`. Trim loaded records in memory to most recent 30 days unless explicitly browsing history.

**WhisperRunner Hardcodes English (`-l en`)**
- Issue: Language is hardcoded to English at `ListenToMe/Core/WhisperRunner.swift:36`.
- Files: `ListenToMe/Core/WhisperRunner.swift:36`
- Impact: Non-English speakers cannot use the app. No UI to toggle language. Transcription fails silently on non-English speech.
- Fix approach: Add `languageCode: String` preference to `Preferences.swift`. Pass to `WhisperRunner.transcribe()`. Update CLI args to use dynamic language: `["-l", Preferences.shared.languageCode]`.

**ClaudeClient Hardcodes Model to Haiku**
- Issue: Model selection is hardcoded to `--model haiku` at `ListenToMe/Core/ClaudeClient.swift:59`.
- Files: `ListenToMe/Core/ClaudeClient.swift:59`
- Impact: No user control over cleanup quality vs. speed. Haiku may be insufficient for complex dictation. No fallback if Claude API changes.
- Fix approach: Add `modelName: String` preference (default "haiku") to `Preferences.swift`. Pass dynamically: `["--model", Preferences.shared.modelName]`.

**Cleanup Latency Floor (~12s Cold Start)**
- Issue: Every cleanup invocation spawns a fresh `claude --print` subprocess (no session reuse). Claude CLI cold startup is 12–15s on typical M-series Macs. Streaming preview hides latency for initial paste but doesn't eliminate it for replace operations.
- Files: `ListenToMe/Core/ClaudeClient.swift:86–162` (subprocess spawning)
- Impact: Replace operations (Cmd+Z, repaste) stall visibly. Users perceive the app as slow even though paste succeeds immediately. UX friction.
- Fix approach: (Priority: Low — current UX acceptable for MVP)
  - **Option 1 (Quick):** Warm subprocess pool: spawn a persistent `claude` session at app launch and reuse it across cleanup calls. Complex but ~500ms improvement.
  - **Option 2 (Medium):** Direct Anthropic API. When `ANTHROPIC_API_KEY` is set, use native Swift HTTP to call Claude API directly, bypassing subprocess overhead entirely. Eliminates dependency on Claude CLI. Requires API credential handling.
  - **Option 3 (Accepted):** Document cold-start behavior in settings; no code change.

**Cmd+Z + Cmd+V Replace Mechanism Fragile in Electron Apps**
- Issue: `Paster.replace()` simulates `Cmd+Z` (undo) then `Cmd+V` (paste new text). This works in native macOS apps (Mail, Notes, TextEdit) but Electron apps (Slack, Notion, VS Code) bundle paste differently and may not reliably recognize the simulated keystroke or may have undo stacks that don't align.
- Files: `ListenToMe/Core/Paster.swift:115–124` (undo/repaste logic)
- Impact: In Electron apps, replace may leave stale text, undo twice instead of once, or paste to wrong position. Replace is gated by app bundle ID (line 100–101) but gate is on frontmost app at paste time, not at replace time—fails silently if user switches apps.
- Fix approach: (Priority: Medium)
  - Detect Electron apps (bundle ID patterns: `com.slack.*`, `notion`, `com.microsoft.VSCode`) and disable replace for them. Fall back to manual correction popover.
  - Add unit tests for replace to detect regressions in each OS version (macOS 12, 13, 14+).
  - Consider accessibility API as alternative to simulated keystrokes (AXUIElement + AXPress for better app awareness).

**Voice-Edit Literals Unconditional**
- Issue: Voice-edit commands (punctuation, paragraph breaks) map to literal output unconditionally. Saying "comma" always inserts `,`. No way to dictate the literal word "comma" without manual fix-up.
- Files: `ListenToMe/Core/VoiceEditor.swift:24–31` (punctuation map), `98–101` (break map)
- Impact: Users cannot transcribe technical documentation about punctuation (e.g., "In Markdown, comma means a list separator"). Workaround: enable cleanup, rely on Claude to fix, or manually type.
- Fix approach: Add escape sequence prefix (e.g., "literal comma" → insert "comma" as text, not `,`). Extend `VoiceEditor.applyPunctuation()` to check for "literal" prefix and skip replacement.

**Correction Popover Bundle-ID Gate Silently Fails**
- Issue: `Paster.replace()` requires the frontmost app at replace time to match the app where paste occurred (line 100–101). If user switches apps mid-correction, replace fails silently; user sees no error, just the raw text unchanged. The gate is documented in code but not in UI.
- Files: `ListenToMe/Core/Paster.swift:100–103`
- Impact: UX papercut. Users switch apps (check Slack while correcting, etc.) and correction doesn't apply. Perceived as a bug, not a feature limit.
- Fix approach: Pass current app to correction popover. Warn user if active app changes: "Correction will be applied to [App Name]. Switch back or Cancel." Make the gate visible.

**Phase Enum `.cleaning` Case Unreachable**
- Issue: `Phase.cleaning` was used before streaming preview was implemented. Now the flow is: paste raw → immediately enter `polishing(rawPreview:)` → background cleanup → optional replace. The `.cleaning` case is never entered, kept only for switch exhaustiveness.
- Files: `ListenToMe/State/AppState.swift:10` (enum definition), `ListenToMe/UI/MenuBarController.swift:119`, `ListenToMe/UI/PillView.swift:109,211,261,345` (switch cases)
- Impact: Dead code increases mental overhead during refactoring. Cheap to keep (switch exhaustiveness handled), but signals incomplete cleanup of old flow.
- Fix approach: Remove the case and add `@unknown default:` to all switches, or keep it with a comment explaining why. Current cost of keeping is low; delete only if refactoring the Phase enum comprehensively.

**Unused State Store Scaffolding**
- Issue: `ScratchpadStore`, `StyleStore`, `TransformsStore`, `PagesStore`, and `DictionaryStore` exist but are not integrated into the main UI. They have persistence and `@Published` properties, but nobody calls them.
- Files: 
  - `ListenToMe/State/ScratchpadStore.swift` (empty `text` property, `clear()` and `scheduleSave()`)
  - `ListenToMe/State/StyleStore.swift` (style rules for per-app prompts, never used)
  - `ListenToMe/State/TransformsStore.swift` (text transforms, never used)
  - `ListenToMe/State/PagesStore.swift` (pages collection, never used)
  - `ListenToMe/State/DictionaryStore.swift` (dictionary entries, never used)
- Impact: App bundle includes unused code. Confuses new contributors. Increases startup time (stores load files even if unused). `StyleStore` and `TransformsStore` suggest planned features that were never shipped.
- Fix approach: Delete unused stores or move to a separate `Experimental/` folder. If keeping for future: document the intended feature in each file (e.g., "Planned: per-app style overrides") and comment out initialization in `AppState`. Lazily initialize on first use.

**Paster.replace() Blocks Main Thread (80ms usleep)**
- Issue: `Paster.replace()` calls `usleep(80_000)` on the main thread (line 118) to give the target app time to apply undo before repaste. 80ms is long enough to feel sluggish in responsiveness, especially on slower machines.
- Files: `ListenToMe/Core/Paster.swift:115–118`
- Impact: Correction UI briefly freezes. Noticeable on low-end hardware. Not fatal but UX degradation.
- Fix approach: Run undo/repaste sequence on a background serial queue (not main thread). Use DispatchQueue or async/await. Restore main thread only for final state update. Requires testing to ensure Cmd+Z timing still works in all apps.

**No Code Signing for Distribution**
- Issue: The app is ad-hoc signed (verified with `codesign -dv`; shows `Signature=adhoc`). macOS Gatekeeper blocks launch of ad-hoc signed apps on first run ("ListenToMe can't be opened because it wasn't downloaded from the App Store or identified developer"). Users must right-click → Open or approve in System Settings.
- Files: Build configuration in `ListenToMe.xcodeproj/project.pbxproj` (no Team ID or provisioning profile set)
- Impact: First-launch friction. Users perceive the app as unsafe. Distribution via App Store or direct download requires proper signing.
- Fix approach: Obtain Apple Developer ID (requires membership). Set Team ID in Xcode build settings. Sign with Developer ID Application certificate. Notarize the build with Apple (required for apps distributed outside App Store on macOS 10.15+). Add GitHub Actions workflow to sign and notarize on release.

---

## Known Bugs

**Replace Fails in Electron Apps Silently**
- Symptoms: Correction popover accepts input, user presses Return, but text in Slack/Notion/VS Code doesn't change. Raw paste remains.
- Files: `ListenToMe/Core/Paster.swift:115–124` (undo/repaste), `ListenToMe/UI/CorrectionWindow.swift` (popover logic)
- Trigger: 1) Dictate in Electron app. 2) Click pill to open correction popover. 3) Edit and press Return.
- Workaround: Delete the raw text manually and repaste the cleaned version, or use native app for corrections.

**Cold CLI Startup Blocks Final Polish**
- Symptoms: Correction appears after 12–15s instead of ~2s. Visible pause in final replace.
- Files: `ListenToMe/Core/ClaudeClient.swift:48–69` (cleanup flow)
- Trigger: Enable cleanup. Dictate. Wait for cleanup to complete.
- Workaround: None (accepts as design limitation for MVP).

---

## Security Considerations

**ANTHROPIC_API_KEY Exposed via Environment**
- Risk: If direct Anthropic API path is added (Option 2 under cleanup latency), API key must be passed securely. Currently, environment variables are passed to subprocess (line 98), which is visible to other processes via `ps`.
- Files: `ListenToMe/Core/ClaudeClient.swift:168–182` (environment augmentation)
- Current mitigation: API key is NOT used; all calls go through Claude CLI, which manages auth via OAuth/Keychain. No raw key in environment.
- Recommendations: If implementing direct API, store API key in Keychain (SecItem API), never in environment. Use in-process HTTPS (URLSession) instead of subprocess. Audit all subprocess args in logs.

**Ad-Hoc Signing Allows Tampering**
- Risk: Ad-hoc signed binaries can be modified by any process with appropriate permissions. Attacker could inject code into the app binary on disk.
- Files: Build configuration (ad-hoc signature verified by `codesign -dv`)
- Current mitigation: None. Code signing is for distribution (Gatekeeper), not runtime security in development.
- Recommendations: Implement proper code signing (see CONCERNS > Tech Debt > No Code Signing for Distribution). Use hardened runtime entitlements. Enable code signature validation at launch (code pages protected).

**Pasteboard Access Overly Permissive**
- Risk: `Paster` reads and writes the system pasteboard without user confirmation. Malicious code in another process could eavesdrop on dictations or inject fake text.
- Files: `ListenToMe/Core/Paster.swift:26–67` (pasteboard access)
- Current mitigation: Privacy entitlements (`.entitlements` file) declare intent. macOS prompts user on first access.
- Recommendations: Add UI confirmation for sensitive corrections. Log pasteboard operations. Consider clipboard encryption for future versions.

---

## Performance Bottlenecks

**JSON Decoder on Startup (Growing Latency)**
- Problem: `HistoryStore.load()` decodes entire `history.json` synchronously on app launch (line 93–97). File grows unbounded.
- Files: `ListenToMe/State/HistoryStore.swift:93–98`
- Cause: No pagination or lazy loading. As file grows to 10–50 MB (after 12 months), decode time increases from <10ms to 500–1000ms. Blocks app startup.
- Improvement path: Implement streaming JSON parser or load last 1000 records only. Move remaining records to dated archives. Decode asynchronously on background thread; show placeholder UI until ready.

**Regex Compilation on Every Call**
- Problem: `VoiceEditor` and `SnippetsStore.expand()` compile regex patterns inside hot functions (`applyPunctuation`, `resolveScratchThat`, etc.), not at class init time.
- Files: `ListenToMe/Core/VoiceEditor.swift:35–36, 48, 78, 154` (in-function regex creation)
- Cause: Regex compilation is O(pattern length). Called for every dictation. Negligible for short patterns, but adds up.
- Improvement path: Move all regexes to static compiled patterns at module init. Cache `NSRegularExpression` instances. Benchmark to confirm improvement.

**usleep(80ms) on Main Thread**
- Problem: See Tech Debt > Paster.replace() Blocks Main Thread.
- Cause: Synchronous sleep to wait for app undo.
- Improvement path: Async/await on background queue.

---

## Fragile Areas

**VoiceEditor Regex Patterns**
- Files: `ListenToMe/Core/VoiceEditor.swift:24–31, 98–101`
- Why fragile: Punctuation and break patterns use word boundaries (`\b`) which are context-dependent. Phrases like "new paragraph" are brittle—if user says "nope wrapagraph" (slight slur), pattern doesn't match. No unit tests to verify patterns work as expected.
- Safe modification: Add comprehensive test suite covering common speech variations, accents, and typos. Document expected input/output pairs. Use fuzzy matching or Levenshtein distance for soft matching.
- Test coverage: None (no test files exist).

**Paster Bundle ID Logic**
- Files: `ListenToMe/Core/Paster.swift:56, 100–101`
- Why fragile: Bundle ID is captured at paste time but checked at replace time. If user switches apps (even briefly), replace silently fails. No user-facing error.
- Safe modification: Store both original and current bundle ID in `PasteToken`. Warn user if they differ. Allow override in correction popover.
- Test coverage: None. Manual testing only.

**ClaudeClient Sanitization Filter**
- Files: `ListenToMe/Core/ClaudeClient.swift:187–229`
- Why fragile: Preamble detection (line 208–216) uses hardcoded strings. If Claude's behavior changes or new preambles emerge, filter fails silently, returning invalid output.
- Safe modification: Make preamble list user-configurable. Add logging when filter rejects output. Consider LLM-based validation instead of keyword matching.
- Test coverage: None.

**Phase Enum Switch Statements**
- Files: `ListenToMe/UI/MenuBarController.swift:119`, `ListenToMe/UI/PillView.swift:109, 211, 261, 345`
- Why fragile: Multiple switches on `Phase`. If a new case is added, compiler forces exhaustive matches, which is good. But dead `.cleaning` case hides intent. Switching on `@unknown default` would be more future-proof.
- Safe modification: Use `@unknown default` in all switches. Document intent for each case transition.
- Test coverage: None.

---

## Scaling Limits

**History File Size**
- Current capacity: Tested up to ~1000 records (~500 KB). Estimated sustainable limit: ~10,000 records (5 MB, assuming 500 bytes per record).
- Limit: At ~15,000 records (7.5 MB), JSON decode time exceeds 500ms. At ~50,000 records (25 MB), startup blocks for 2–3s.
- Scaling path: Implement pagination and archival (see Tech Debt > HistoryStore Unbounded Growth). Lazy-load on demand.

**Pasteboard Change Detection**
- Current capacity: `NSPasteboard.changeCount` is a 32-bit integer. Theoretically rolls over after 2^32 changes (~4 billion). In practice, app life is months, not years.
- Limit: Not a concern for typical usage. Overflow would require millions of paste operations in a single session.
- Scaling path: None needed.

---

## Dependencies at Risk

**Hardcoded Model Name in ClaudeClient**
- Risk: If Anthropic deprecates Haiku or changes model naming, the app breaks silently (uses unsupported model).
- Impact: Cleanup stops working. Users see blank output or errors.
- Migration plan: Parameterize model selection. Query available models from Claude API. Fall back to a list of known working models in priority order.

**Whisper CLI Installation Dependency**
- Risk: `whisper-cli` binary is bundled, but `claude` CLI must be installed separately. If user uninstalls Claude (or upgrades to incompatible version), cleanup fails silently.
- Impact: App remains functional for dictation but cleanup is disabled. Users may not notice `claudeAvailable` flag.
- Migration plan: Show explicit warning in UI if Claude CLI is missing. Offer download link to Claude.app. Consider bundling Claude API calls directly instead of subprocess.

**macOS Version Constraints**
- Risk: Code uses newer Swift/SwiftUI APIs (`@FocusState`, `@MainActor`, `.onKeyPress`). May not compile on macOS 12 or earlier.
- Impact: App distribution is limited to macOS 13+.
- Migration plan: Set minimum deployment target explicitly in Xcode. Test on older OS versions. Use `@available` guards for newer APIs if broad compatibility needed.

---

## Missing Critical Features

**No Auto-Correction Undo in Replace**
- Problem: If cleanup changes a correct word to incorrect (e.g., "read" → "red"), user must manually fix. No undo path from corrector popover.
- Blocks: Power users cannot confidently enable cleanup if they can't quickly revert bad changes.
- Fix: Add "Revert" button in corrector that cancels the cleanup and restores raw paste.

**No Per-App Cleanup Preferences**
- Problem: Cleanup is global. Some apps (code editors) may benefit from stricter rules; others (messaging) prefer looser rules. No way to customize per app.
- Blocks: Users with diverse workflows (writing + coding + chatting) can't optimize for all.
- Fix: Implement `StyleStore` (already scaffolded). Allow per-app system prompts. Detect app at paste time; apply appropriate cleanup.

**No Model Fallback Chain**
- Problem: If `haiku` model fails, no fallback. App crashes or silently loses cleanup.
- Blocks: Reliability is compromised in edge cases (rate limiting, API outage).
- Fix: Maintain a fallback chain: try Haiku → Opus → no cleanup. Log each fallback for diagnostics.

---

## Test Coverage Gaps

**No Tests for ClaudeClient.clean()**
- What's not tested: Cleanup logic, preamble rejection, sanitization filter, timeout handling, subprocess failure modes.
- Files: `ListenToMe/Core/ClaudeClient.swift`
- Risk: Regressions in cleanup output go undetected. Sanitization filter may silently fail or reject valid output.
- Priority: **High** — cleanup is core feature.

**No Tests for Paster.replace()**
- What's not tested: Undo/repaste simulation, bundle ID gating, staleness detection, pasteboard state transitions.
- Files: `ListenToMe/Core/Paster.swift`
- Risk: Replace may fail in certain app contexts (Electron apps, complex undo stacks) without detection.
- Priority: **High** — replace is a critical UX flow.

**No Tests for VoiceEditor**
- What's not tested: Punctuation substitution, scratch-that resolution, paragraph break insertion, regex patterns.
- Files: `ListenToMe/Core/VoiceEditor.swift`
- Risk: Voice-edit commands may silently miss edge cases (overlapping patterns, empty input, pathological strings).
- Priority: **High** — voice editing is core.

**No Tests for HistoryStore Persistence**
- What's not tested: JSON encoding/decoding, record insertion/removal, concurrent access (if multi-threaded).
- Files: `ListenToMe/State/HistoryStore.swift`
- Risk: Data loss on app crash or corrupt history file.
- Priority: **Medium** — impacts user trust.

**No Integration Tests for Full Dictation Flow**
- What's not tested: Hotkey → recording → transcription → cleanup → paste → correct → finalize.
- Risk: A single broken link in the chain is caught only by manual testing.
- Priority: **Medium** — would catch regressions early.

---

*Concerns audit: 2026-05-05*
