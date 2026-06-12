import XCTest
@testable import ListenToMe

/// Eval harness: runs each cleanup fixture through the REAL local-Gemma
/// cleanup path (engine → sanitize/MeaningGuard) and scores with
/// CleanupMetrics, so prompt/model/threshold changes are measured, not
/// guessed.
///
/// Gated behind `LTM_RUN_EVAL=1` — it loads a multi-GB model and runs slow,
/// nondeterministic inference, so it must not run in normal CI. Run with:
///   LTM_RUN_EVAL=1 xcodebuild test -only-testing:ListenToMeTests/CleanupEvalTests
///
/// It prints a per-fixture table + aggregate so you can eyeball quality, and
/// asserts loose regression floors (mean recall, max hallucination, zero
/// preamble leaks) so a real regression fails the run.
@MainActor
final class CleanupEvalTests: XCTestCase {

    private var shouldRun: Bool {
        ProcessInfo.processInfo.environment["LTM_RUN_EVAL"] == "1"
    }

    func test_eval_local_cleanup() async throws {
        try XCTSkipUnless(shouldRun, "set LTM_RUN_EVAL=1 to run the cleanup eval")

        let file = Preferences.LocalLLMModel.gemma4E2B.filename
        let engine = LocalLLMEngine.shared
        try XCTSkipUnless(engine.isReady(modelFile: file),
                          "E2B GGUF not downloaded — skipping eval")
        engine.shutdown()
        engine.activeModelPath = LocalLLMEngine.modelURL(for: file).path

        let system = ClaudeClient.localCleanupSystemPrompt

        var recalls: [Double] = []
        var hallucs: [Double] = []
        var preambleLeaks = 0
        var rows: [String] = []

        for f in CleanupFixtures.all {
            let out = (try? await engine.transform(system: system, user: f.raw, maxTokens: 160)) ?? ""
            let cleaned = ClaudeClient.sanitize(cleaned: out, original: f.raw)

            let recall = CleanupMetrics.contentWordRecall(candidate: cleaned, reference: f.ideal)
            let halluc = CleanupMetrics.hallucinationRate(candidate: cleaned, raw: f.raw, reference: f.ideal)
            let leaked = looksLikePreamble(cleaned)
            recalls.append(recall)
            hallucs.append(halluc)
            if leaked { preambleLeaks += 1 }

            rows.append(String(format: "  %-22@  recall=%.2f  halluc=%.2f%@\n      → %@",
                               f.id as NSString, recall, halluc,
                               leaked ? "  ⚠PREAMBLE" : "" as NSString,
                               cleaned as NSString))
        }

        let meanRecall = recalls.reduce(0, +) / Double(recalls.count)
        let maxHalluc = hallucs.max() ?? 0

        print("\n=== Cleanup eval (Gemma 4 E2B) ===")
        print(rows.joined(separator: "\n"))
        print(String(format: "--- mean recall %.3f · max halluc %.3f · preamble leaks %d/%d ---",
                     meanRecall, maxHalluc, preambleLeaks, CleanupFixtures.all.count))

        // Loose regression floors — this is a measurement tool, not a tight
        // gate. Tighten as the prompt/model improve.
        XCTAssertGreaterThanOrEqual(meanRecall, 0.70, "mean content-word recall regressed")
        XCTAssertEqual(preambleLeaks, 0, "model leaked preamble past sanitize")
        XCTAssertLessThanOrEqual(maxHalluc, 0.40, "a fixture hallucinated too much content")
    }

    /// Cheap check that the sanitized output still begins with a known
    /// assistant preamble (sanitize should have stripped these).
    private func looksLikePreamble(_ s: String) -> Bool {
        let l = s.lowercased()
        return ["here is", "here's", "sure", "certainly", "of course",
                "output:", "cleaned:", "the cleaned"].contains { l.hasPrefix($0) }
    }
}
