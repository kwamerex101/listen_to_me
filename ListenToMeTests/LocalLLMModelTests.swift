import XCTest
@testable import ListenToMe

/// Unit tests for the on-device LLM Preferences surface (no model on disk
/// required) plus a GGUF-gated integration test that runs a real Gemma
/// transform when the E2B model is present.
@MainActor
final class LocalLLMModelTests: XCTestCase {

    // MARK: - Preferences enums

    func test_llmBackend_defaults_to_cloud() {
        // rawValue round-trips and cloud is the conservative default.
        XCTAssertEqual(Preferences.LLMBackend(rawValue: "cloud"), .cloud)
        XCTAssertEqual(Preferences.LLMBackend(rawValue: "local"), .local)
        XCTAssertNil(Preferences.LLMBackend(rawValue: "bogus"))
    }

    func test_e2b_is_default_and_lighter_than_12b() {
        XCTAssertEqual(Preferences.LocalLLMModel.gemma4E2B.minRAMGB, 8)
        XCTAssertEqual(Preferences.LocalLLMModel.gemma4_12B.minRAMGB, 16)
        XCTAssertLessThan(Preferences.LocalLLMModel.gemma4E2B.expectedMinBytes,
                          Preferences.LocalLLMModel.gemma4_12B.expectedMinBytes)
    }

    func test_model_filenames_and_urls_are_gguf() {
        for m in Preferences.LocalLLMModel.allCases {
            XCTAssertTrue(m.filename.hasSuffix(".gguf"), "\(m) filename")
            XCTAssertTrue(m.downloadURL.absoluteString.hasSuffix(".gguf"), "\(m) url")
            XCTAssertEqual(m.downloadURL.scheme, "https")
        }
    }

    func test_modelURL_matches_engine_location() {
        let m = Preferences.LocalLLMModel.gemma4E2B
        let url = LocalLLMEngine.modelURL(for: m.filename)
        XCTAssertTrue(url.path.contains("ListenToMe/llm"))
        XCTAssertEqual(url.lastPathComponent, m.filename)
    }

    // MARK: - Integration (requires the E2B GGUF on disk)

    func test_real_transform_polishes_text() async throws {
        let file = Preferences.LocalLLMModel.gemma4E2B.filename
        let engine = LocalLLMEngine.shared
        try XCTSkipUnless(engine.isReady(modelFile: file),
                          "E2B GGUF not downloaded — skipping live transform test")

        engine.shutdown()
        engine.activeModelPath = LocalLLMEngine.modelURL(for: file).path

        let system = "You are a dictation cleanup tool. Fix grammar, punctuation, and "
            + "capitalization. Remove filler words. Return ONLY the cleaned text, nothing else."
        let raw = "um so i think we should uh ship the feature on monday you know"

        let cleaned = try await engine.transform(system: system, user: raw, maxTokens: 128)

        XCTAssertFalse(cleaned.isEmpty, "transform returned empty")
        // Filler removal is the headline behaviour — at least one should go.
        let lower = cleaned.lowercased()
        XCTAssertFalse(lower.contains(" um ") || lower.hasPrefix("um "),
                       "expected filler 'um' removed; got: \(cleaned)")
        // Content should survive — the core noun must remain.
        XCTAssertTrue(lower.contains("monday"), "lost content; got: \(cleaned)")
        engine.shutdown()
    }
}
