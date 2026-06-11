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
#include <mutex>

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

// Format `system` + `user` as one user turn via the model's embedded chat
// template. Returns false on failure.
bool format_prompt(const llama_model *model,
                   const std::string &system,
                   const std::string &user,
                   std::string &out) {
    std::string merged = system.empty() ? user : system + "\n\n" + user;

    const char *tmpl = llama_model_chat_template(model, /*name*/ nullptr);

    llama_chat_message msg{ "user", merged.c_str() };
    std::vector<char> buf(std::max<size_t>(2048, merged.size() * 2));
    int32_t n = llama_chat_apply_template(tmpl, &msg, 1, /*add_ass*/ true,
                                          buf.data(), (int32_t)buf.size());
    if (n < 0) return false;
    if ((size_t)n > buf.size()) {
        buf.resize((size_t)n + 1);
        n = llama_chat_apply_template(tmpl, &msg, 1, true, buf.data(),
                                      (int32_t)buf.size());
        if (n < 0) return false;
    }
    out.assign(buf.data(), (size_t)n);
    return true;
}

std::vector<llama_token> tokenize(const llama_vocab *vocab,
                                  const std::string &text) {
    int32_t cap = (int32_t)text.size() + 8;
    std::vector<llama_token> toks(cap);
    int32_t n = llama_tokenize(vocab, text.data(), (int32_t)text.size(),
                               toks.data(), (int32_t)toks.size(),
                               /*add_special*/ true, /*parse_special*/ true);
    if (n < 0) {
        toks.resize((size_t)(-n));
        n = llama_tokenize(vocab, text.data(), (int32_t)text.size(),
                           toks.data(), (int32_t)toks.size(), true, true);
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

char *llama_bridge_transform(llama_bridge_model handle,
                             const char *system,
                             const char *user,
                             int max_tokens) {
    if (!handle) return nullptr;
    auto *model = static_cast<llama_model *>(handle);

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = 4096;
    cparams.n_batch = 512;
    llama_context *ctx = llama_init_from_model(model, cparams);
    if (!ctx) return nullptr;

    const llama_vocab *vocab = llama_model_get_vocab(model);

    std::string formatted;
    if (!format_prompt(model, system ? system : "", user ? user : "", formatted)) {
        llama_free(ctx);
        return nullptr;
    }

    std::vector<llama_token> tokens = tokenize(vocab, formatted);
    if (tokens.empty()) {
        llama_free(ctx);
        return dup_cstring("");
    }

    llama_sampler *smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(smpl, llama_sampler_init_greedy());

    const int n_ctx = (int)llama_n_ctx(ctx);
    std::string output;
    bool failed = false;

    // First decode: the whole prompt. batch.pos == NULL → llama_decode
    // advances position from the KV cache for subsequent single-token batches.
    llama_batch batch = llama_batch_get_one(tokens.data(), (int32_t)tokens.size());
    if (llama_decode(ctx, batch) != 0) {
        failed = true;
    }

    int n_decoded = 0;
    while (!failed && n_decoded < max_tokens) {
        llama_token id = llama_sampler_sample(smpl, ctx, -1);
        if (llama_vocab_is_eog(vocab, id)) break;

        output += token_to_piece(vocab, id);
        n_decoded++;

        if ((int)tokens.size() + n_decoded >= n_ctx) break;

        batch = llama_batch_get_one(&id, 1);
        if (llama_decode(ctx, batch) != 0) { failed = true; break; }
    }

    llama_sampler_free(smpl);
    llama_free(ctx);

    if (failed) return nullptr;

    // Trim leading/trailing whitespace.
    size_t b = output.find_first_not_of(" \t\r\n");
    size_t e = output.find_last_not_of(" \t\r\n");
    std::string trimmed = (b == std::string::npos) ? "" : output.substr(b, e - b + 1);
    return dup_cstring(trimmed);
}

void llama_bridge_string_free(char *s) { std::free(s); }

} // extern "C"
