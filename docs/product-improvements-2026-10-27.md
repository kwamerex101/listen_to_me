# Product improvements verification

Date: 2026-10-27. Branch: `codex/dictation-readiness-polish`. Prepared for pull-request review. The installed app in `/Applications` is unchanged.

## Product changes
- Settings commands open the existing main window at Settings.
- Parakeet callers share selected-model loading; invalidated loads cannot install stale results.
- Onboarding follows the selected engine and offers explicit retry or Whisper fallback.
- Active-app polish has an explicit bypass with one delivery and one history record.
- Home leads with readiness, selected microphone/output, and recoverable text; statistics remain below.
- Persistent review uses Cmd+Shift+R, edits a copy, and copies only on request.
- Review preserves explicit edits across source updates and disables copying deleted source records.
- Home recreates selectable transcript text when its content changes to avoid stale accessibility text.
- Pill feedback is quieter, saved anchors persist, and Reduce Motion has a static alternative.
- A finite dictation example is available during onboarding, from View demo, and from Help.
- Session-only timing stores durations and outcomes without transcripts or audio.
- WPM uses recording duration and excludes transcription/polish time.
- Configured polish timeouts are unchanged; the explicit bypass handles long waits.

## Automated verification

| Check | Result |
|---|---|
| Original checkout baseline (`7d204d4`) | 468 tests |
| Rebased main baseline (`f7d23b0`) | 474 tests |
| Final Debug suite | 527 tests, 0 failures, 3 skips |
| Opt-in performance checks, separate run | 3 tests, 0 failures, 0 skips |
| Final post-rebase Release build | Succeeded |
| Final benchmark log | No `GGML_ASSERT` |

The full-suite skips comprise two opt-in performance cases and one existing skipped test.
The native fixture uses its own NSTextView, clicks bypass twice, awaits late cleanup, and asserts one insertion/history record.

## Pre-PR review
Standards found no hard violations or consequential smells; Spec found no deviations.
Adversarial and Edge passes found a P2 concurrent shared-load failure bug. It was fixed
with four regressions; the prior helper fails the concurrent-failure case. No review blockers remain.

## Runtime checks
- [x] Cmd+, opens Settings in the signed final preview.
- [x] Signed post-rebase preview: Settings search for “response” selects the new Models section; Cmd+1 returns Home. Upstream sidebar and date formatting remain intact.
- [x] Home readiness, selected microphone, engine, output, and latest transcript visually checked.
- [x] The refreshed preview exposes the current latest transcript through external accessibility inspection.
- [x] Cmd+Shift+R opens review; repeated shortcuts preserve the edited draft; Esc closes it without saving history.
- [x] View demo and Help open the guide; completion, replay, and closing during playback were checked. Reduce Motion is covered by playback tests.
Preview: `/tmp/listentome-product-final-preview/ListenToMe.app`.

## Measured fixture results, latest post-rebase run

Environment: Apple M5 Pro, 48 GB memory, macOS 27.0.1, Xcode 27.1, Debug build.
Fixture: synthetic macOS Samantha speech, 37 words, 12.293 seconds; no microphone capture.

| Measurement | Observed result |
|---|---|
| Parakeet TDT v2 fresh in-process model-handle load | 554.5 ms |
| Warm ASR, 20 runs | Median 252.2 ms; 95th percentile 291.0 ms |
| Local Gemma E2B polish, 3 runs | 826.3, 972.0, 953.9 ms |
| Raw native delivery, one attempt | Target 1076.7 ms; dispatch 608.1 ms |
| Polished native delivery, one attempt | Target 2029.5 ms; dispatch 1975.8 ms |
| Explicit bypass, one attempt | Target 298.6 ms; dispatch 248.8 ms |

The load reused existing model files with warm disk cache. WER was zero on this one fixture
repeated 20 times; this is not evidence of general transcription accuracy. Native attempts
had different warm/load conditions and do not establish a direct speedup comparison.
An earlier pre-rebase run had a 93.7 ms ASR median under different warm/background conditions. These uncontrolled runs establish neither a regression nor a relative speedup.
Dispatch timing ends at the delivery request; it is distinct from text appearing in the target.
A synthetic fixture bypasses hardware acquisition, so hotkey-to-mic-ready timing remains unbenchmarked.
Production instrumentation can collect that interval during future real dictations.

Animation Hitches capture (5 seconds) and eight `top` samples were attempted. Concurrent dictation
made the comparison uncontrolled. There is no valid idle CPU/FPS improvement claim from these captures.
A separate settled Home capture stayed in the ready state: seven one-second CPU samples were
0.0, 0.2, 0.1, 0.1, 0.2, 0.2, and 0.1 percent of one core (median 0.1%). This is a short observation, not a battery-life or FPS benchmark.
Numeric outputs: [engine](verification/2026-10-27/latency.engine.json), [native](verification/2026-10-27/latency.native.json).

## Reproduction
Generate the project with `xcodegen generate`, then run the full suite:

```sh
xcodebuild test -project ListenToMe.xcodeproj -scheme ListenToMe -configuration Debug -destination 'platform=macOS'
```

For performance checks, supply a synthetic 16 kHz mono WAV and install the required Parakeet v2
and Gemma E2B models first. Native insertion requires an already authorized, stably signed test host.
Set test-runner variables `LTM_RUN_PRODUCT_BENCHMARKS=1`, `LTM_BENCHMARK_WAV`,
`LTM_BENCHMARK_POLISH=1`, and `LTM_BENCHMARK_REPORT`; pass them through the Xcode scheme
or the corresponding `TEST_RUNNER_` shell prefixes. Add
`-only-testing:ListenToMeTests/ProductLatencyBenchmarks` to the command above.
`LTM_BENCHMARK_REFERENCE` optionally enables fixture WER calculation.
See [ProductLatencyBenchmarks.swift](../ListenToMeTests/ProductLatencyBenchmarks.swift) for prerequisites and checks.
