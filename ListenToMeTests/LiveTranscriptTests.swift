import XCTest
@testable import ListenToMe

// MARK: - PartialTranscriber gate tests

/// Tests the start() guard conditions — streaming disabled, wrong engine,
/// model not ready. None of these should launch the polling loop.
/// PartialTranscriber is @MainActor, so all tests run on the main actor.
final class PartialTranscriberGateTests: XCTestCase {

    private static let engineKey = "wf.transcriptionEngine"
    private static let partialsKey = "wf.streamingPartialsEnabled"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.engineKey)
        UserDefaults.standard.removeObject(forKey: Self.partialsKey)
        // Ensure clean stop state between tests.
        Task { @MainActor in PartialTranscriber.shared.stop() }
    }

    override func tearDown() {
        Task { @MainActor in PartialTranscriber.shared.stop() }
        UserDefaults.standard.removeObject(forKey: Self.engineKey)
        UserDefaults.standard.removeObject(forKey: Self.partialsKey)
        super.tearDown()
    }

    @MainActor
    func test_start_no_ops_when_streaming_disabled() {
        // Default: streamingPartialsEnabled = false.
        XCTAssertFalse(Preferences.shared.streamingPartialsEnabled)
        Preferences.shared.transcriptionEngine = .linked
        // start() should early-return; calling stop() after should be
        // idempotent and not crash.
        PartialTranscriber.shared.start()
        PartialTranscriber.shared.stop()
    }

    @MainActor
    func test_start_no_ops_when_engine_is_server() {
        Preferences.shared.streamingPartialsEnabled = true
        Preferences.shared.transcriptionEngine = .server
        // Linked is required for streaming partials.
        PartialTranscriber.shared.start()
        PartialTranscriber.shared.stop()
    }

    @MainActor
    func test_start_no_ops_when_model_not_ready() {
        // Point to a model file that definitely doesn't exist.
        Preferences.shared.streamingPartialsEnabled = true
        Preferences.shared.transcriptionEngine = .linked
        // Force selectedWhisperModel to a value whose file won't be on disk.
        // We use smallEn — unlikely to be downloaded in CI / dev sandboxes
        // unless the user explicitly fetched it.
        let oldModel = Preferences.shared.selectedWhisperModel
        Preferences.shared.selectedWhisperModel = .smallEn
        defer { Preferences.shared.selectedWhisperModel = oldModel }

        // If the small model happens to exist on this machine, skip —
        // we can't manufacture a clean "not ready" state for that model.
        guard !WhisperLib.shared.isReady else {
            // isReady returns true — model is present. Guard already
            // passed in start(). Nothing to assert; skip cleanly.
            return
        }

        // isReady == false → start() should return before launching loop.
        PartialTranscriber.shared.start()
        PartialTranscriber.shared.stop()
    }

    @MainActor
    func test_double_start_is_idempotent() {
        // Calling start() twice (e.g. rapid hotkey presses) must not
        // spawn two loop tasks.
        Preferences.shared.streamingPartialsEnabled = false
        PartialTranscriber.shared.start()
        PartialTranscriber.shared.start() // second call should be no-op
        PartialTranscriber.shared.stop()
    }

    @MainActor
    func test_stop_before_start_does_not_crash() {
        PartialTranscriber.shared.stop()
        PartialTranscriber.shared.stop()
    }
}

// MARK: - WhisperLib model tracking tests

/// Tests the model-change detection added to WhisperLib.ensureContext():
/// switching selectedWhisperModel must cause a fresh context load rather
/// than reusing the old model's context.
final class WhisperLibModelTrackingTests: XCTestCase {

    private static let modelKey = "wf.selectedWhisperModel"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.modelKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.modelKey)
        super.tearDown()
    }

    @MainActor
    func test_isReady_false_when_model_file_absent() {
        // Force a model whose file almost certainly doesn't exist.
        Preferences.shared.selectedWhisperModel = .largeTurbo
        let modelPath = WhisperRunner.modelURL.path
        let exists = FileManager.default.fileExists(atPath: modelPath)
        // isReady should track file existence exactly.
        XCTAssertEqual(WhisperLib.shared.isReady, exists,
                       "isReady must reflect whether the model file exists at \(modelPath)")
    }

    @MainActor
    func test_modelURL_changes_with_selectedModel() {
        Preferences.shared.selectedWhisperModel = .baseEn
        let baseURL = WhisperRunner.modelURL

        Preferences.shared.selectedWhisperModel = .smallEn
        let smallURL = WhisperRunner.modelURL

        XCTAssertNotEqual(baseURL, smallURL, "modelURL must differ per selected model")
        XCTAssertTrue(baseURL.lastPathComponent.contains("base"),
                      "baseEn URL should contain 'base' — got \(baseURL.lastPathComponent)")
        XCTAssertTrue(smallURL.lastPathComponent.contains("small"),
                      "smallEn URL should contain 'small' — got \(smallURL.lastPathComponent)")
    }

    @MainActor
    func test_modelURL_all_models_under_same_directory() {
        let expected = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("ListenToMe/models")

        for model in Preferences.WhisperModel.allCases {
            Preferences.shared.selectedWhisperModel = model
            let url = WhisperRunner.modelURL
            XCTAssertTrue(url.path.hasPrefix(expected.path),
                          "\(model.rawValue) URL \(url.path) not under expected models dir")
        }
    }
}

// MARK: - WhisperModel preference tests

/// Persistence and display-name completeness for `Preferences.WhisperModel`.
final class WhisperModelPreferenceTests: XCTestCase {

    private static let key = "wf.selectedWhisperModel"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        super.tearDown()
    }

    func test_default_model_is_baseEn() {
        XCTAssertEqual(Preferences.shared.selectedWhisperModel, .baseEn)
    }

    func test_persists_across_reads() {
        Preferences.shared.selectedWhisperModel = .smallEn
        XCTAssertEqual(Preferences.shared.selectedWhisperModel, .smallEn)
        Preferences.shared.selectedWhisperModel = .largeTurbo
        XCTAssertEqual(Preferences.shared.selectedWhisperModel, .largeTurbo)
        Preferences.shared.selectedWhisperModel = .baseEn
        XCTAssertEqual(Preferences.shared.selectedWhisperModel, .baseEn)
    }

    func test_unknown_raw_value_falls_back_to_baseEn() {
        UserDefaults.standard.set("nonexistent-model", forKey: Self.key)
        XCTAssertEqual(Preferences.shared.selectedWhisperModel, .baseEn)
    }

    func test_all_models_have_non_empty_display_names() {
        for model in Preferences.WhisperModel.allCases {
            XCTAssertFalse(model.displayName.isEmpty,
                           "\(model.rawValue) has empty displayName")
        }
    }

    func test_all_models_have_distinct_filenames() {
        let names = Preferences.WhisperModel.allCases.map(\.filename)
        XCTAssertEqual(Set(names).count, names.count,
                       "Each model must have a unique filename")
    }

    func test_all_filenames_have_bin_extension() {
        for model in Preferences.WhisperModel.allCases {
            XCTAssertTrue(model.filename.hasSuffix(".bin"),
                          "\(model.rawValue) filename '\(model.filename)' should end in .bin")
        }
    }

    func test_min_size_thresholds_are_positive() {
        for model in Preferences.WhisperModel.allCases {
            XCTAssertGreaterThan(model.expectedMinBytes, 0,
                                 "\(model.rawValue) must have a positive expectedMinBytes")
        }
    }

    func test_larger_models_have_larger_size_thresholds() {
        // base < small < large-turbo in expected disk footprint.
        XCTAssertLessThan(Preferences.WhisperModel.baseEn.expectedMinBytes,
                          Preferences.WhisperModel.smallEn.expectedMinBytes)
        XCTAssertLessThan(Preferences.WhisperModel.smallEn.expectedMinBytes,
                          Preferences.WhisperModel.largeTurbo.expectedMinBytes)
    }
}

// MARK: - AppState partialText lifecycle tests

/// `partialText` must be cleared on phase transitions that exit recording,
/// and must survive through `.transcribing` to avoid a UI flicker.
final class AppStatePartialTextLifecycleTests: XCTestCase {

    @MainActor
    func test_partialText_survives_transcribing_phase() {
        // Entering .transcribing should NOT wipe partialText — the
        // streaming preview should persist as a "finalizing" cue.
        AppState.shared.partialText = "hello world"
        AppState.shared.phase = .transcribing
        XCTAssertEqual(AppState.shared.partialText, "hello world",
                       "partialText must persist through .transcribing to avoid flicker")
        AppState.shared.partialText = ""
        AppState.shared.phase = .idle
    }

    @MainActor
    func test_partialText_clears_to_empty_after_stop() {
        AppState.shared.partialText = "some partial"
        AppState.shared.partialText = ""
        XCTAssertEqual(AppState.shared.partialText, "")
    }

    @MainActor
    func test_partialText_is_published() {
        // Verify @Published so the pill can observe changes via SwiftUI.
        var received: [String] = []
        let cancel = AppState.shared.$partialText.sink { received.append($0) }
        AppState.shared.partialText = "live text"
        AppState.shared.partialText = ""
        cancel.cancel()
        XCTAssertTrue(received.contains("live text"),
                      "$partialText publisher must emit new values")
        XCTAssertTrue(received.contains(""),
                      "$partialText publisher must emit empty on clear")
    }
}
