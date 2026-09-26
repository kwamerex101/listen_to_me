// Implementation of the llama.cpp C shim. This TU includes llama.h/ggml.h
// (llama's ggml >= 0.15) in isolation — it is the only place those headers
// are parsed, so they never collide with CWhisper's ggml 0.9.8 in the Swift
// module graph.

#include "llama_bridge.h"
#include "llama.h"

#include <string>
#include <vector>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <mutex>

// Failure diagnostics — logs only the failing STAGE name, never transcript
// content (PII hygiene). Quiet on the success path.
#define LB_LOG(stage) fprintf(stderr, "[llama_bridge] FAIL: %s\n", stage)

namespace {

std::once_flag g_backend_once;

void ensure_backend() {
    std::call_once(g_backend_once, [] { llama_backend_init(); });
}

// Duplicate a std::string into a malloc'd C string for the Swift caller.
char *dup_cstring(const std::string &s) {
    char *out = static_cast<char *>(std::malloc(s.size() + 1));
    if (!out) return nullptr;
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

// Format `system` + `user` as one Gemma user turn. We format manually rather
// than via llama_chat_apply_template: the library's built-in template applier
// only recognises a fixed set of templates and returns -1 on Gemma 4's Jinja
// template (the --jinja path lives in common/, outside the C API). Gemma has
// no system role, so system content is merged into the single user turn. Turn
// tokens are parsed as specials at tokenize time (parse_special=true); BOS is
// added by tokenize's add_special, so it is NOT included here.
bool format_prompt(const llama_model *model,
                   const std::string &system,
                   const std::string &user,
                   std::string &out) {
    (void)model;
    std::string merged = system.empty() ? user : system + "\n\n" + user;
    out = "<start_of_turn>user\n" + merged + "<end_of_turn>\n<start_of_turn>model\n";
    return true;
}

std::vector<llama_token> tokenize(const llama_vocab *vocab,
                                  const std::string &text,
                                  bool add_special = true) {
    int32_t cap = (int32_t)text.size() + 8;
    std::vector<llama_token> toks(cap);
    int32_t n = llama_tokenize(vocab, text.data(), (int32_t)text.size(),
                               toks.data(), (int32_t)toks.size(),
                               add_special, /*parse_special*/ true);
    if (n < 0) {
        toks.resize((size_t)(-n));
        n = llama_tokenize(vocab, text.data(), (int32_t)text.size(),
                           toks.data(), (int32_t)toks.size(), add_special, true);
        if (n < 0) return {};
    }
    toks.resize((size_t)n);
    return toks;
}

std::string token_to_piece(const llama_vocab *vocab, llama_token token) {
    char buf[256];
    int32_t n = llama_token_to_piece(vocab, token, buf, (int32_t)sizeof(buf),
                                     /*lstrip*/ 0, /*special*/ false);
    if (n <= 0) return {};
    return std::string(buf, (size_t)n);
}

} // namespace

extern "C" {

void llama_bridge_init(void) { ensure_backend(); }

llama_bridge_model llama_bridge_load(const char *path) {
    ensure_backend();
    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 99; // offload all layers to Metal
    llama_model *model = llama_model_load_from_file(path, mparams);
    return static_cast<llama_bridge_model>(model);
}

void llama_bridge_free(llama_bridge_model model) {
    if (model) llama_model_free(static_cast<llama_model *>(model));
}

int llama_bridge_plan(int n_prompt_tokens, int n_user_tokens, int requested_max,
                      int n_ctx_cap, int *out_n_ctx, int *out_max_tokens) {
    if (n_prompt_tokens <= 0 || n_user_tokens < 0 || n_ctx_cap <= 0 ||
        !out_n_ctx || !out_max_tokens) {
        return -1;
    }
    // Auto budget: a cleanup pass is roughly the length of the input, with
    // 2x headroom for the model to expand contractions/punctuation plus a
    // fixed floor so short utterances still get room to breathe.
    int max_tokens = requested_max > 0 ? requested_max : (2 * n_user_tokens + 64);
    int n_ctx = n_prompt_tokens + max_tokens + 8;
    if (n_ctx > n_ctx_cap) {
        // Doesn't fit at the requested/auto budget: shrink the output budget
        // to what's left after the prompt, then bail if that's not even
        // enough room to hold the cleaned user text back out.
        max_tokens = n_ctx_cap - n_prompt_tokens - 8;
        if (max_tokens < n_user_tokens + 16) {
            return -1;
        }
        n_ctx = n_prompt_tokens + max_tokens + 8;
    }
    *out_n_ctx = n_ctx;
    *out_max_tokens = max_tokens;
    return 0;
}

char *llama_bridge_transform(llama_bridge_model handle,
                             const char *system,
                             const char *user,
                             int max_tokens) {
    if (!handle) return nullptr;
    auto *model = static_cast<llama_model *>(handle);
    const llama_vocab *vocab = llama_model_get_vocab(model);

    std::string formatted;
    if (!format_prompt(model, system ? system : "", user ? user : "", formatted)) {
        LB_LOG("format_prompt");
        return nullptr;
    }

    // Tokenize the formatted prompt (system + user + template, what actually
    // gets decoded) AND the user text alone (add_special=false — no BOS,
    // just the raw content) so llama_bridge_plan can size the context and
    // output budget before a llama_context is created.
    std::vector<llama_token> tokens = tokenize(vocab, formatted);
    if (tokens.empty()) {
        LB_LOG("tokenize_empty");
        return dup_cstring("");
    }
    std::vector<llama_token> user_tokens =
        tokenize(vocab, user ? user : "", /*add_special*/ false);

    // Cap the context at the model's trained size (or 16384, whichever is
    // smaller) — going past what the model was trained on degrades quality
    // long before it would ever help.
    int32_t n_ctx_train = llama_model_n_ctx_train(model);
    int n_ctx_cap = (n_ctx_train > 0 && n_ctx_train < 16384) ? (int)n_ctx_train : 16384;

    int n_ctx = 0, planned_max = 0;
    if (llama_bridge_plan((int)tokens.size(), (int)user_tokens.size(), max_tokens,
                          n_ctx_cap, &n_ctx, &planned_max) != 0) {
        LB_LOG("prompt_too_long");
        return nullptr;
    }

    llama_context_params cparams = llama_context_default_params();
    // The pinned llama.cpp asserts GGML_ASSERT(n_tokens_all <= cparams.n_batch)
    // in llama_context::decode (src/llama-context.cpp:1748), which aborts the
    // whole process rather than returning an error. We decode the entire
    // formatted prompt in one llama_batch_get_one call below, so n_batch must
    // be at least as large as the prompt — setting it equal to n_ctx (which
    // llama_bridge_plan already sized to fit prompt + planned_max + 8)
    // satisfies that unconditionally. n_ubatch is left at its default; llama
    // splits internally into ubatches for the actual compute, so this doesn't
    // change how much work happens per step.
    cparams.n_ctx = n_ctx;
    cparams.n_batch = n_ctx;
    llama_context *ctx = llama_init_from_model(model, cparams);
    if (!ctx) { LB_LOG("init_from_model==null"); return nullptr; }

    llama_sampler *smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(smpl, llama_sampler_init_greedy());

    std::string output;
    bool failed = false;
    // True only when the model itself signalled end-of-generation. If we
    // exit the loop for any other reason (max tokens reached, context
    // exhausted), the output is a mid-thought truncation that can still read
    // as plausible text and slip past MeaningGuard — better to fail the
    // whole transform than silently drop the tail of the dictation.
    bool hit_eog = false;

    // First decode: the whole prompt. batch.pos == NULL → llama_decode
    // advances position from the KV cache for subsequent single-token batches.
    llama_batch batch = llama_batch_get_one(tokens.data(), (int32_t)tokens.size());
    if (llama_decode(ctx, batch) != 0) {
        LB_LOG("decode_prompt");
        failed = true;
    }

    int n_decoded = 0;
    while (!failed && n_decoded < planned_max) {
        llama_token id = llama_sampler_sample(smpl, ctx, -1);
        if (llama_vocab_is_eog(vocab, id)) { hit_eog = true; break; }

        output += token_to_piece(vocab, id);
        n_decoded++;

        // Gemma sometimes spells its turn delimiter out as ordinary text
        // pieces instead of emitting the EOG token (ClaudeClient.sanitize
        // strips the leftovers). Treat the spelled-out marker as the end of
        // generation too, or those replies would count as truncated.
        static const std::string kEndOfTurn = "<end_of_turn>";
        if (output.size() >= kEndOfTurn.size() &&
            output.compare(output.size() - kEndOfTurn.size(), kEndOfTurn.size(), kEndOfTurn) == 0) {
            output.erase(output.size() - kEndOfTurn.size());
            hit_eog = true;
            break;
        }

        if ((int)tokens.size() + n_decoded >= n_ctx) break;

        batch = llama_batch_get_one(&id, 1);
        if (llama_decode(ctx, batch) != 0) { failed = true; break; }
    }

    llama_sampler_free(smpl);
    llama_free(ctx);

    if (failed) return nullptr;
    if (!hit_eog) {
        LB_LOG("truncated");
        return nullptr;
    }

    // Trim leading/trailing whitespace.
    size_t b = output.find_first_not_of(" \t\r\n");
    size_t e = output.find_last_not_of(" \t\r\n");
    std::string trimmed = (b == std::string::npos) ? "" : output.substr(b, e - b + 1);
    return dup_cstring(trimmed);
}

void llama_bridge_string_free(char *s) { std::free(s); }

} // extern "C"
