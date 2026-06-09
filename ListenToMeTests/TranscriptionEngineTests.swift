import XCTest
@testable import ListenToMe

/// Tests for the `Preferences.TranscriptionEngine` enum and its
/// integration points. The actual whisper.cpp call is exercised
/// manually via the running app (no fixture WAV in the test target);
/// these tests cover the surface area that's deterministic in pure
/// Swift: enum coverage, label content, default selection, persistence
/// round-trip via UserDefaults.
final class TranscriptionEngineTests: XCTestCase {

    private static let testKey = "wf.transcriptionEngine"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.testKey)
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.testKey)
        super.tearDown()
    }

    func test_default_is_server() {
        // When no preference has ever been written, default is .server
        // — preserves the warm path that ships in v0.13.0.
        XCTAssertEqual(Preferences.shared.transcriptionEngine, .server)
    }

    func test_persists_across_reads() {
        Preferences.shared.transcriptionEngine = .linked
        XCTAssertEqual(Preferences.shared.transcriptionEngine, .linked)
        Preferences.shared.transcriptionEngine = .server
        XCTAssertEqual(Preferences.shared.transcriptionEngine, .server)
    }

    func test_all_cases_have_distinct_raw_values() {
        let raws = Set(Preferences.TranscriptionEngine.allCases.map(\.rawValue))
        XCTAssertEqual(raws.count, Preferences.TranscriptionEngine.allCases.count)
    }

    func test_all_cases_have_non_empty_labels() {
        for eng in Preferences.TranscriptionEngine.allCases {
            XCTAssertFalse(eng.label.isEmpty, "\(eng.rawValue) has empty label")
        }
    }

    func test_label_marks_default() {
        // The Settings menu picker reads `.label` directly; the .server
        // entry should signal it's the safe default so users know what
        // they're toggling away from.
        let serverLabel = Preferences.TranscriptionEngine.server.label.lowercased()
        XCTAssertTrue(serverLabel.contains("default"),
                      "server label '\(Preferences.TranscriptionEngine.server.label)' should signal it's the default")
    }

    func test_linked_label_signals_streaming_capability() {
        // The whole reason for the linked engine is that whisper-server
        // can't stream — the .linked label should mention it so users
        // understand what the toggle gives them.
        let linkedLabel = Preferences.TranscriptionEngine.linked.label.lowercased()
        XCTAssertTrue(linkedLabel.contains("stream") || linkedLabel.contains("in-process"),
                      "linked label '\(Preferences.TranscriptionEngine.linked.label)' should signal its capability")
    }

    func test_unknown_raw_value_falls_back_to_server() {
        // If a future build adds a new engine and a downgrade reads
        // a raw value the current build doesn't recognize, Preferences
        // should return .server rather than crashing.
        UserDefaults.standard.set("future-engine-x", forKey: Self.testKey)
        XCTAssertEqual(Preferences.shared.transcriptionEngine, .server)
    }
}

/// Tests for `WhisperModelManager.coreMLPackageInstalled`. We only
/// validate the path-check semantics here — actually downloading the
/// .mlmodelc package would require network and ~50 MB of disk.
final class WhisperModelManagerCoreMLTests: XCTestCase {

    @MainActor
    func test_coreMLPackageURL_is_under_app_support_models() {
        let url = WhisperModelManager.coreMLPackageURL
        XCTAssertTrue(url.path.hasSuffix("/ggml-base.en-encoder.mlmodelc"))
        XCTAssertTrue(url.path.contains("/Library/Application Support/ListenToMe/models/"),
                      "Core ML package must live next to the .bin model — got: \(url.path)")
    }

    func test_coreMLPackageInstalled_is_a_bool() async {
        // Just verify it returns without crashing — actual presence
        // depends on whether the user ran scripts/setup.sh after the
        // Core ML support landed.
        let result = await MainActor.run { WhisperModelManager.shared.coreMLPackageInstalled }
        XCTAssertTrue(result == true || result == false)
    }
}

/// Tests for the transcription-accuracy preference and its beam mapping.
final class TranscriptionAccuracyPrefTests: XCTestCase {

    private static let key = "wf.transcriptionAccuracy"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        super.tearDown()
    }

    @MainActor
    func test_default_is_fast() {
        XCTAssertEqual(Preferences.shared.transcriptionAccuracy, .fast)
    }

    @MainActor
    func test_persists_across_reads() {
        Preferences.shared.transcriptionAccuracy = .accurate
        XCTAssertEqual(Preferences.shared.transcriptionAccuracy, .accurate)
        Preferences.shared.transcriptionAccuracy = .fast
        XCTAssertEqual(Preferences.shared.transcriptionAccuracy, .fast)
    }

    @MainActor
    func test_unknown_raw_value_falls_back_to_fast() {
        UserDefaults.standard.set("turbo-ludicrous", forKey: Self.key)
        XCTAssertEqual(Preferences.shared.transcriptionAccuracy, .fast)
    }

    func test_beam_size_mapping() {
        XCTAssertEqual(Preferences.TranscriptionAccuracy.fast.beamSize, 1)
        XCTAssertEqual(Preferences.TranscriptionAccuracy.accurate.beamSize, 5)
    }
}
