#ifndef LLAMA_BRIDGE_H
#define LLAMA_BRIDGE_H

// Thin C shim over llama.cpp. Exposes ONLY opaque pointers and C strings —
// no ggml/llama types — so Swift never imports llama.cpp's ggml headers.
// This is what keeps llama's ggml (>=0.15) from colliding with whisper's
// ggml (0.9.8) at the Clang-module level: only this header reaches Swift,
// while the implementation TU includes llama.h/ggml.h in isolation.

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a loaded model (a `llama_model *` underneath).
typedef void *llama_bridge_model;

/// Initialise the llama backend. Idempotent; safe to call repeatedly.
void llama_bridge_init(void);

/// Load a GGUF model from `path`. Returns NULL on failure. All layers are
/// offloaded to Metal.
llama_bridge_model llama_bridge_load(const char *path);

/// Free a model handle. NULL-safe.
void llama_bridge_free(llama_bridge_model model);

/// Run a single deterministic (greedy) transform: `system` + `user` are
/// merged into one chat turn, formatted with the model's embedded chat
/// template, and decoded up to `max_tokens`. Returns a malloc'd, NUL-
/// terminated C string the caller must release with
/// `llama_bridge_string_free`, or NULL on any failure.
char *llama_bridge_transform(llama_bridge_model model,
                             const char *system,
                             const char *user,
                             int max_tokens);

/// Release a string returned by `llama_bridge_transform`. NULL-safe.
void llama_bridge_string_free(char *s);

#ifdef __cplusplus
}
#endif

#endif // LLAMA_BRIDGE_H
