import XCTest
@testable import ListenToMe

/// Tests for the on-device LLM engine that don't require a multi-GB GGUF on
/// disk — path construction, readiness, and the no-model error path. The
/// actual decode is exercised manually / in an integration target with a
/// downloaded model.
@MainActor
final class LocalLLMEngineTests: XCTestCase {

    func test_modelURL_lives_under_appSupport_llm() {
        let url = LocalLLMEngine.modelURL(for: "gemma-4-E2B-it-Q4_K_M.gguf")
        XCTAssertTrue(url.path.contains("ListenToMe/llm"))
        XCTAssertEqual(url.lastPathComponent, "gemma-4-E2B-it-Q4_K_M.gguf")
    }

    func test_isReady_false_for_missing_model() {
        XCTAssertFalse(LocalLLMEngine.shared.isReady(modelFile: "definitely-not-here.gguf"))
    }

    func test_transform_throws_when_no_model_path() async {
        let engine = LocalLLMEngine.shared
        engine.shutdown()           // ensure no model/path
        engine.activeModelPath = nil
        do {
            _ = try await engine.transform(system: "Polish:", user: "hello")
            XCTFail("expected loadFailed")
        } catch {
            XCTAssertEqual(error as? LocalLLMEngine.LLMError, .loadFailed)
        }
    }

    func test_transform_throws_modelNotFound_for_bad_path() async {
        let engine = LocalLLMEngine.shared
        engine.shutdown()
        engine.activeModelPath = "/tmp/listentome-nonexistent-\(UUID().uuidString).gguf"
        defer { engine.activeModelPath = nil }
        do {
            _ = try await engine.transform(system: "Polish:", user: "hello")
            XCTFail("expected modelNotFound")
        } catch let LocalLLMEngine.LLMError.modelNotFound(path) {
            XCTAssertTrue(path.contains("listentome-nonexistent"))
        } catch {
            XCTFail("expected modelNotFound, got \(error)")
        }
    }
}
