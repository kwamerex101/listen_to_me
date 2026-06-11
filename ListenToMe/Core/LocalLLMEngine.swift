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
    private var isBusy = false

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

    /// Free the model. Idempotent. Wire from applicationWillTerminate.
    func shutdown() {
        if let model { llama_bridge_free(model) }
        model = nil
        loadedModelPath = nil
        isBusy = false
    }

    /// system + user text → cleaned text. Non-streaming, deterministic.
    /// Throws `.busy` if a transform is already in flight (one decode loop
    /// per model at a time).
    func transform(system: String, user: String, maxTokens: Int = 512) async throws -> String {
        guard !isBusy else { throw LLMError.busy }
        try ensureModel()
        guard let model else { throw LLMError.loadFailed }
        isBusy = true
        defer { isBusy = false }

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
        if model != nil, loadedModelPath != path {
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
