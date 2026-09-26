import XCTest
import CLlamaBridge

/// Tests for `llama_bridge_plan`, the pure sizing function that decides
/// `n_ctx` / max output tokens for a transform before any llama_context is
/// created. This is what fixes the on-device-cleanup crash: the pinned
/// llama.cpp asserts (aborting the process) if the whole prompt doesn't fit
/// in one decode batch, and this function guarantees `n_ctx` (and therefore
/// `n_batch`, set equal to it in llama_bridge_transform) is always large
/// enough for the actual prompt.
final class LlamaBridgePlanTests: XCTestCase {

    private func plan(prompt: Int32, user: Int32, requestedMax: Int32, cap: Int32)
        -> (rc: Int32, nCtx: Int32, maxTokens: Int32) {
        var outCtx: Int32 = 0
        var outMax: Int32 = 0
        let rc = llama_bridge_plan(prompt, user, requestedMax, cap, &outCtx, &outMax)
        return (rc, outCtx, outMax)
    }

    func test_autoBudget_sizesFromUserTokenCount() {
        let r = plan(prompt: 400, user: 120, requestedMax: 0, cap: 16384)
        XCTAssertEqual(r.rc, 0)
        XCTAssertEqual(r.maxTokens, 304)   // 2 * 120 + 64
        XCTAssertEqual(r.nCtx, 712)        // 400 + 304 + 8
    }

    func test_explicitMax_isHonoured() {
        let r = plan(prompt: 400, user: 120, requestedMax: 128, cap: 16384)
        XCTAssertEqual(r.rc, 0)
        XCTAssertEqual(r.maxTokens, 128)
        XCTAssertEqual(r.nCtx, 400 + 128 + 8)
    }

    func test_nCtx_neverExceedsCap() {
        let r = plan(prompt: 4000, user: 3000, requestedMax: 0, cap: 8192)
        XCTAssertEqual(r.rc, 0)
        XCTAssertLessThanOrEqual(r.nCtx, 8192)
    }

    func test_shrinkToFit_succeedsWhenRoomRemainsForUserPlus16() {
        // Auto budget (2*3000+64=6064) would push n_ctx past the cap, but
        // there's still room to shrink to something >= user + 16.
        let r = plan(prompt: 4000, user: 3000, requestedMax: 0, cap: 8192)
        XCTAssertEqual(r.rc, 0)
        XCTAssertGreaterThanOrEqual(r.maxTokens, 3000 + 16)
        XCTAssertEqual(r.nCtx, 4000 + r.maxTokens + 8)
    }

    func test_returnsFailure_whenPromptAloneNearsCap() {
        // Prompt alone leaves no room even for the minimum budget
        // (user + 16) once the cap is applied.
        let r = plan(prompt: 8000, user: 1000, requestedMax: 0, cap: 8192)
        XCTAssertEqual(r.rc, -1)
    }

    func test_nonsenseInputs_returnFailure() {
        XCTAssertEqual(plan(prompt: 0, user: 10, requestedMax: 0, cap: 4096).rc, -1)
        XCTAssertEqual(plan(prompt: 10, user: -1, requestedMax: 0, cap: 4096).rc, -1)
        XCTAssertEqual(plan(prompt: -5, user: 10, requestedMax: 0, cap: 4096).rc, -1)
        XCTAssertEqual(plan(prompt: 10, user: 10, requestedMax: 0, cap: 0).rc, -1)
    }

    func test_emptyUserText_getsTheFloorBudget() {
        // Empty user text is valid (e.g. a transform of whitespace); it gets
        // the fixed 64-token floor rather than failing the whole transform.
        let r = plan(prompt: 50, user: 0, requestedMax: 0, cap: 4096)
        XCTAssertEqual(r.rc, 0)
        XCTAssertEqual(r.maxTokens, 64)
    }

    func test_oldFailureShape_nowPlansContextAtLeastAsBigAsPrompt() {
        // Before this fix, n_batch was a fixed 512 regardless of the
        // formatted prompt size, so a ~900-token prompt (roughly a minute
        // of speech plus the Gemma cleanup system prompt) hit
        // GGML_ASSERT(n_tokens_all <= cparams.n_batch) and aborted the
        // process. n_batch is now set to n_ctx in llama_bridge_transform,
        // so this just needs n_ctx >= the prompt token count.
        let r = plan(prompt: 900, user: 400, requestedMax: 0, cap: 16384)
        XCTAssertEqual(r.rc, 0)
        XCTAssertGreaterThanOrEqual(r.nCtx, 900)
    }
}
