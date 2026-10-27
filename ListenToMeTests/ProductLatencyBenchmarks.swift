import AppKit
import ApplicationServices
import FluidAudio
import XCTest
@testable import ListenToMe

/// Explicit opt-in, synthetic audio only. Does not request OS permissions.
@MainActor
final class ProductLatencyBenchmarks: XCTestCase {
    private let env = ProcessInfo.processInfo.environment

    private func withCleanup(_ cleanup: () -> Void,
                             operation: () async throws -> Void) async rethrows {
        defer { cleanup() }
        try await operation()
    }

    private func withBenchmarkScope(_ operation: () async throws -> Void) async throws {
        let preferences = Preferences.shared
        let parakeetModel = preferences.parakeetModel
        let transcriptionEngine = preferences.transcriptionEngine
        let outputDestination = preferences.outputDestination
        let voiceCommandsEnabled = preferences.voiceCommandsEnabled
        let llmBackend = preferences.llmBackend
        let selectedLocalLLMModel = preferences.selectedLocalLLMModel
        let cleanupMode = preferences.cleanupMode
        let modelPath = LocalLLMEngine.shared.activeModelPath
        try await withCleanup({
            LocalLLMEngine.shared.shutdown()
            ParakeetEngine.shared.shutdown()
            preferences.parakeetModel = parakeetModel
            preferences.transcriptionEngine = transcriptionEngine
            preferences.outputDestination = outputDestination
            preferences.voiceCommandsEnabled = voiceCommandsEnabled
            preferences.llmBackend = llmBackend
            preferences.selectedLocalLLMModel = selectedLocalLLMModel
            preferences.cleanupMode = cleanupMode
            LocalLLMEngine.shared.activeModelPath = modelPath
        }, operation: operation)
    }

    func testBenchmarkCleanupRunsAfterErrorsAndSkips() async {
        struct FixtureError: Error {}
        let failures: [Error] = [FixtureError(), XCTSkip("Synthetic skip")]
        for failure in failures {
            var released = false
            do {
                try await withCleanup({ released = true }) { throw failure }
                XCTFail("The fixture should throw")
            } catch {}
            XCTAssertTrue(released, "Model cleanup must run when a benchmark throws or skips")
        }
    }

    private func fixture() throws -> URL {
        try XCTSkipUnless(env["LTM_RUN_PRODUCT_BENCHMARKS"] == "1", "Set LTM_RUN_PRODUCT_BENCHMARKS=1 for local fixture checks")
        let input = try XCTUnwrap(env["LTM_BENCHMARK_WAV"], "Set LTM_BENCHMARK_WAV to a synthetic 16 kHz mono WAV")
        let url = URL(fileURLWithPath: input)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "Synthetic WAV not found")
        try XCTSkipUnless(AsrModels.modelsExist(at: ParakeetEngine.modelsDirectory, version: .v2),
                          "Parakeet v2 is not fully installed; benchmark will not download models")
        Preferences.shared.parakeetModel = .v2
        return url
    }

    private func copiedFixture(_ source: URL) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("product-fixture-\(UUID().uuidString).wav")
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    private func report(_ values: [String: Any], suffix: String) throws {
        guard let path = env["LTM_BENCHMARK_REPORT"] else { return }
        let base = URL(fileURLWithPath: path)
        let destination = base.deletingPathExtension().appendingPathExtension("\(suffix).json")
        let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination)
    }

    func testInstalledParakeetLatency() async throws {
        try await withBenchmarkScope { try await self.runInstalledParakeetLatency() }
    }

    private func runInstalledParakeetLatency() async throws {
        let source = try fixture()
        let engine = ParakeetEngine.shared
        engine.shutdown()
        let started = ProcessInfo.processInfo.systemUptime
        try await engine.ensureReady()
        let firstLoadMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        var times: [Double] = []
        var wordErrors: [Double] = []
        for _ in 0..<20 {
            let start = ProcessInfo.processInfo.systemUptime
            let samples = try WhisperWAVReader.samples(at: source)
            let result = try await engine.transcribe(samples: samples)
            let text = TranscriptHygiene.stripNonSpeechMarkers(result.text)
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertFalse(text.isEmpty)
            if let reference = env["LTM_BENCHMARK_REFERENCE"] {
                wordErrors.append(WERCalculator.wer(reference: reference, hypothesis: text))
            }
        }
        var result: [String: Any] = [
            "engine": "Parakeet TDT v2", "iterations": times.count,
            "firstModelLoadMs": firstLoadMs, "warmAsrMs": times,
            "warmAsrMedianMs": DictationTimingLedger.median(of: times)!,
            "warmAsrP95Ms": DictationTimingLedger.percentile(0.95, of: times)!,
            "measurement": "WAV read, transcription and deterministic transcript hygiene; excludes microphone capture and paste"
        ]
        if !wordErrors.isEmpty { result["wordErrorRates"] = wordErrors }
        if env["LTM_BENCHMARK_POLISH"] == "1" {
            let llm = LocalLLMEngine.shared
            let model = Preferences.LocalLLMModel.gemma4E2B
            try XCTSkipUnless(llm.isReady(modelFile: model.filename), "Local Gemma E2B is missing; no model download")
            Preferences.shared.llmBackend = .local
            Preferences.shared.selectedLocalLLMModel = model
            llm.activeModelPath = LocalLLMEngine.modelURL(for: model.filename).path
            var polishTimes: [Double] = []
            for _ in 0..<3 {
                let start = ProcessInfo.processInfo.systemUptime
                _ = try await ClaudeClient.shared.clean(env["LTM_BENCHMARK_REFERENCE"] ?? "Please send the updated design tomorrow morning.",
                                                       bundleId: nil, timeout: 30)
                polishTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            }
            result["localPolishMs"] = polishTimes
        }
        try report(result, suffix: "engine")
    }

#if DEBUG
    func testNativeInsertionAndPolishBypass() async throws {
        try await withBenchmarkScope { try await self.runNativeInsertionAndPolishBypass() }
    }

    private func runNativeInsertionAndPolishBypass() async throws {
        let source = try fixture()
        try XCTSkipUnless(AXIsProcessTrusted(), "Accessibility permission is not granted to this test host; native insertion was not attempted")
        let local = LocalLLMEngine.shared
        let model = Preferences.LocalLLMModel.gemma4E2B
        try XCTSkipUnless(local.isReady(modelFile: model.filename), "Local Gemma E2B is required for the bypass race check; no model download")

        let oldPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 260))
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ListenToMe synthetic dictation test"
        window.contentView = editor
        window.isReleasedWhenClosed = false
        defer {
            window.close()
            NSApp.setActivationPolicy(oldPolicy)
            AppState.shared.phase = .idle
            AppState.shared.canInsertWithoutPolish = false
        }
        Preferences.shared.transcriptionEngine = .parakeet
        Preferences.shared.outputDestination = .activeApp
        Preferences.shared.voiceCommandsEnabled = false
        Preferences.shared.llmBackend = .local
        Preferences.shared.selectedLocalLLMModel = model
        local.activeModelPath = LocalLLMEngine.modelURL(for: model.filename).path

        var results: [[String: Any]] = []
        for mode in ["raw", "polished", "bypass"] {
            let bypass = mode == "bypass"
            editor.string = ""
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(editor)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(200))
            func ownsFocus() -> Bool {
                window.isKeyWindow && window.firstResponder === editor &&
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            }
            try XCTSkipUnless(ownsFocus(), "The fixture window could not acquire focus; no paste attempted")
            let delegate = AppDelegate()
            delegate.configureFixtureDeliveryGuard { ownsFocus() }
            let pasteboard = PasteboardSnapshot.capture(from: .general)
            var cleanup: Task<Void, Never>?
            do {
                Preferences.shared.cleanupMode = mode == "raw" ? .off : .always
                AppState.shared.phase = .transcribing
                DictationTiming.shared.begin(id: 0)
                DictationTiming.shared.mark(.recordingReady, id: 0)
                DictationTiming.shared.mark(.released, id: 0)
                let historyCount = HistoryStore.shared.records.count
                let start = ProcessInfo.processInfo.systemUptime
                delegate.processRecordedAudio(wav: try copiedFixture(source), recordingDurationMs: 12_293, id: 0)
                if mode != "raw" {
                    try await waitUntil { AppState.shared.canInsertWithoutPolish || self.hasError }
                    XCTAssertFalse(hasError, "Pipeline failed before polish bypass became available")
                    cleanup = delegate.fixtureCleanupTask()
                    if bypass {
                        delegate.insertWithoutPolish()
                        delegate.insertWithoutPolish()
                    }
                }
                try await waitUntil { !editor.string.isEmpty || self.hasError }
                XCTAssertFalse(hasError, "Pipeline failed before native insertion")
                XCTAssertFalse(editor.string.isEmpty)
                let insertionMs = (ProcessInfo.processInfo.systemUptime - start) * 1_000
                let inserted = editor.string
                if let cleanup { await cleanup.value }
                try await Task.sleep(for: .milliseconds(750))
                XCTAssertEqual(editor.string, inserted, "Delivery must remain stable after background work finishes")
                XCTAssertEqual(HistoryStore.shared.records.count, historyCount + 1)
                let sample = try XCTUnwrap(DictationTiming.shared.samples.last)
                results.append(["mode": mode, "bypassedPolish": bypass, "targetInsertionMs": insertionMs,
                                "deliveryDispatchMs": sample.deliveryMs ?? -1,
                                "insertedWords": inserted.split(whereSeparator: \.isWhitespace).count])
            } catch {
                cleanup?.cancel()
                await cleanup?.value
                await delegate.finishFixture(restoring: pasteboard)
                throw error
            }
            await delegate.finishFixture(restoring: pasteboard)
        }
        try report(["nativeInsertions": results, "source": "synthetic fixture; own NSTextView only"], suffix: "native")
    }
#endif

    private var hasError: Bool {
        if case .error = AppState.shared.phase { return true }
        return false
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 40
        while !condition() && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard condition() else {
            throw NSError(domain: "ProductLatencyBenchmarks", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for the dictation pipeline"])
        }
    }
}
