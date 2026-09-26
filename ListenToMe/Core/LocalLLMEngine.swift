import CLlamaBridge
import Foundation

/// On-device text polish via llama.cpp (Gemma 4 GGUF), through the C shim in
/// CLlamaBridge. Mirrors WhisperLib's lifecycle: the expensive model load
/// runs off-main and is adopted back on the MainActor under a race guard; a
/// fresh context is built and freed inside each transform (handled in the
/// shim). The bundled libllama + its isolated ggml set live in Resources/llm/
/// (see scripts/build-llama.sh).
@MainActor
final class LocalLLMEngine {
    static let shared = LocalLLMEngine()

    enum LLMError: Error, Equatable {
        case modelNotFound(String)
        case loadFailed
        case transformFailed
        case busy
    }

    /// Opaque `llama_model *` handle from the shim. nil until loaded.
    private var model: llama_bridge_model?
    private var loadedModelPath: String?
    /// Guards `model` against a free while a detached transform still holds
    /// its raw pointer (model switch / delete / app quit racing an
    /// in-flight decode). See `InFlightGate`.
    private var gate = InFlightGate()

    private init() {}

    /// Path of the GGUF the engine should load. Set by the routing layer when
    /// the user selects the local backend / a specific model.
    var activeModelPath: String?

    /// Location convention for downloaded GGUFs, mirroring WhisperRunner.
    static func modelURL(for file: String) -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListenToMe/llm", isDirectory: true)
            .appendingPathComponent(file)
    }

    func isReady(modelFile: String) -> Bool {
        FileManager.default.fileExists(atPath: Self.modelURL(for: modelFile).path)
    }

    // MARK: - Lifecycle

    /// Warm the model off-main so the first polish doesn't pay the load cost
    /// synchronously. Guarded re-adoption mirrors WhisperLib.preload.
    func preload(modelFile: String) {
        guard model == nil, isReady(modelFile: modelFile) else { return }
        let path = Self.modelURL(for: modelFile).path
        activeModelPath = path
        Task.detached(priority: .utility) {
            // Carry the raw model pointer across the actor hop as an integer —
            // UnsafeMutableRawPointer isn't Sendable, but the bit pattern is.
            let loadedBits = UInt(bitPattern: llama_bridge_load(path))
            await MainActor.run {
                let loaded = UnsafeMutableRawPointer(bitPattern: loadedBits)
                let e = LocalLLMEngine.shared
                if e.model == nil, e.activeModelPath == path {
                    e.model = loaded
                    e.loadedModelPath = loaded != nil ? path : nil
                } else if let loaded {
                    llama_bridge_free(loaded)
                }
            }
        }
    }

    /// Free the model. Idempotent. Wire from applicationWillTerminate, the
    /// model picker, and deleteModel. If a transform is in flight, the free
    /// is deferred until it finishes (see `InFlightGate`) instead of pulling
    /// the pointer out from under the detached decode task; never resets
    /// `gate`'s busy state, since that transform still owns it.
    func shutdown() {
        if gate.requestRelease() {
            freeNow()
        }
    }

    /// Actually frees the model and clears `loadedModelPath`. Only called
    /// once nothing is in flight — directly from `shutdown()` when idle, or
    /// from a transform's `defer` once `gate.end()` reports a deferred
    /// release.
    private func freeNow() {
        if let model { llama_bridge_free(model) }
        model = nil
        loadedModelPath = nil
    }

    /// system + user text → cleaned text. Non-streaming, deterministic.
    /// `maxTokens <= 0` (the default) auto-sizes the output budget and
    /// context from the user text length (see `llama_bridge_plan`) instead
    /// of a fixed cap, so long dictations get enough room to be cleaned in
    /// one decode instead of aborting the process or getting cut off.
    /// Throws `.busy` if a transform is already in flight (one decode loop
    /// per model at a time).
    func transform(system: String, user: String, maxTokens: Int = 0) async throws -> String {
        try ensureModel()
        guard let model else { throw LLMError.loadFailed }
        guard gate.begin() else { throw LLMError.busy }
        defer { if gate.end() { freeNow() } }

        // Pass the model pointer across the actor hop as a bit pattern
        // (UnsafeMutableRawPointer isn't Sendable; the integer is).
        let modelBits = UInt(bitPattern: model)
        let out: String? = await Task.detached(priority: .userInitiated) {
            let m = UnsafeMutableRawPointer(bitPattern: modelBits)
            guard let raw = llama_bridge_transform(m, system, user, Int32(maxTokens)) else {
                return nil
            }
            defer { llama_bridge_string_free(raw) }
            return String(cString: raw)
        }.value

        guard let out else { throw LLMError.transformFailed }
        return out
    }

    // MARK: - Internals

    private func ensureModel() throws {
        guard let path = loadedModelPath ?? activeModelPath else {
            throw LLMError.loadFailed
        }
        // Model switch: free the stale handle so the new GGUF loads below.
        // Skipped while a transform is in flight — freeing here would race
        // the detached decode still holding the old pointer; gate.begin()
        // below throws .busy in that case, and the switch takes effect on
        // the next call once the pending release (from shutdown()) frees it.
        if model != nil, loadedModelPath != path, !gate.isBusy {
            llama_bridge_free(model!)
            model = nil
            loadedModelPath = nil
        }
        if model != nil { return }
        guard FileManager.default.fileExists(atPath: path) else {
            throw LLMError.modelNotFound(path)
        }
        guard let m = llama_bridge_load(path) else { throw LLMError.loadFailed }
        model = m
        loadedModelPath = path
    }
}
