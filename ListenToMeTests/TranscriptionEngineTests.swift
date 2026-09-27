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
        Preferences.testDefaults.removeObject(forKey: Self.testKey)
    }
    override func tearDown() {
        Preferences.testDefaults.removeObject(forKey: Self.testKey)
        super.tearDown()
    }

    func test_default_is_parakeet_for_unset_pref() {
        // PR C: the getter's own unset-fallback is now .parakeet (new
        // installs try the faster on-device engine first). Whether an
        // *existing* user stays on .server is decided separately, by the
        // one-time migration in PreferencesEngineMigrationTests below.
        // This test only covers the raw getter with nothing stored.
        XCTAssertEqual(Preferences.shared.transcriptionEngine, .parakeet)
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

    func test_unknown_raw_value_falls_back_to_parakeet() {
        // If a future build adds a new engine and a downgrade reads
        // a raw value the current build doesn't recognize, Preferences
        // should return the current default rather than crashing.
        Preferences.testDefaults.set("future-engine-x", forKey: Self.testKey)
        XCTAssertEqual(Preferences.shared.transcriptionEngine, .parakeet)
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
        Preferences.testDefaults.removeObject(forKey: Self.key)
    }
    override func tearDown() {
        Preferences.testDefaults.removeObject(forKey: Self.key)
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
        Preferences.testDefaults.set("turbo-ludicrous", forKey: Self.key)
        XCTAssertEqual(Preferences.shared.transcriptionAccuracy, .fast)
    }

    func test_beam_size_mapping() {
        XCTAssertEqual(Preferences.TranscriptionAccuracy.fast.beamSize, 1)
        XCTAssertEqual(Preferences.TranscriptionAccuracy.accurate.beamSize, 5)
    }
}

/// Tests for the PR C engine-default migration: existing users must keep
/// their engine when the unset-fallback flips from `.server` to
/// `.parakeet`. `defaultEngineForMigration` is the pure decision function;
/// `migrateEngineDefaultIfNeeded` is the UserDefaults-touching wrapper
/// around it, run once at launch.
final class PreferencesEngineMigrationTests: XCTestCase {

    private static let engineKey = "wf.transcriptionEngine"
    private static let migratedKey = "wf.engineDefaultMigrated"
    private static let onboardingKey = "wf.hasCompletedOnboarding"
    private static let userNameKey = "wf.userName"

    override func setUp() {
        super.setUp()
        Preferences.testDefaults.removeObject(forKey: Self.engineKey)
        Preferences.testDefaults.removeObject(forKey: Self.migratedKey)
        Preferences.testDefaults.removeObject(forKey: Self.onboardingKey)
        Preferences.testDefaults.removeObject(forKey: Self.userNameKey)
    }
    override func tearDown() {
        Preferences.testDefaults.removeObject(forKey: Self.engineKey)
        Preferences.testDefaults.removeObject(forKey: Self.migratedKey)
        Preferences.testDefaults.removeObject(forKey: Self.onboardingKey)
        Preferences.testDefaults.removeObject(forKey: Self.userNameKey)
        super.tearDown()
    }

    // MARK: - Pure decision function

    func test_noSignals_decidesParakeet() {
        XCTAssertEqual(Preferences.defaultEngineForMigration(
            hasCompletedOnboarding: false, hasStoredUserName: false,
            hasStoredEngineChoice: false, hasDownloadedWhisperModel: false,
            hasHistoryDatabase: false), .parakeet)
    }

    func test_onboardingCompleted_decidesServer() {
        XCTAssertEqual(Preferences.defaultEngineForMigration(
            hasCompletedOnboarding: true, hasStoredUserName: false,
            hasStoredEngineChoice: false, hasDownloadedWhisperModel: false,
            hasHistoryDatabase: false), .server)
    }

    func test_storedUserNameAlone_decidesServer() {
        XCTAssertEqual(Preferences.defaultEngineForMigration(
            hasCompletedOnboarding: false, hasStoredUserName: true,
            hasStoredEngineChoice: false, hasDownloadedWhisperModel: false,
            hasHistoryDatabase: false), .server)
    }

    func test_storedEngineChoiceAlone_decidesServer() {
        XCTAssertEqual(Preferences.defaultEngineForMigration(
            hasCompletedOnboarding: false, hasStoredUserName: false,
            hasStoredEngineChoice: true, hasDownloadedWhisperModel: false,
            hasHistoryDatabase: false), .server)
    }

    func test_downloadedWhisperModelAlone_decidesServer() {
        XCTAssertEqual(Preferences.defaultEngineForMigration(
            hasCompletedOnboarding: false, hasStoredUserName: false,
            hasStoredEngineChoice: false, hasDownloadedWhisperModel: true,
            hasHistoryDatabase: false), .server)
    }

    func test_historyDatabaseAlone_decidesServer() {
        XCTAssertEqual(Preferences.defaultEngineForMigration(
            hasCompletedOnboarding: false, hasStoredUserName: false,
            hasStoredEngineChoice: false, hasDownloadedWhisperModel: false,
            hasHistoryDatabase: true), .server)
    }

    // MARK: - migrateEngineDefaultIfNeeded

    func test_migration_pinsExistingOnboardedUser_toServer() {
        Preferences.shared.hasCompletedOnboarding = true
        // Engine pref left unset, as a real existing user would have it
        // before this migration ever ran.
        Preferences.shared.migrateEngineDefaultIfNeeded()
        XCTAssertEqual(Preferences.shared.transcriptionEngine, .server)
    }

    func test_migration_matchesPureFunction_whenOnboardingNotCompleted() {
        // hasCompletedOnboarding is only one of several existing-user
        // signals now: the others (a downloaded Whisper model, a history
        // database) read the real Application Support directory, which
        // this dev machine may already have populated. Compute the same
        // signals the wrapper reads instead of assuming a "fresh install"
        // outcome, so this test stays deterministic on any machine.
        Preferences.shared.hasCompletedOnboarding = false
        let expected = Preferences.defaultEngineForMigration(
            hasCompletedOnboarding: false,
            hasStoredUserName: !Preferences.shared.userName.isEmpty,
            hasStoredEngineChoice: false,
            hasDownloadedWhisperModel: FileManager.default.fileExists(atPath: WhisperRunner.modelURL.path),
            hasHistoryDatabase: Preferences.historyDatabaseExists()
        )
        Preferences.shared.migrateEngineDefaultIfNeeded()
        XCTAssertEqual(Preferences.shared.transcriptionEngine, expected)
        if expected == .parakeet {
            // Nothing needed to be written: the getter's own fallback
            // already resolves to .parakeet.
            XCTAssertNil(Preferences.testDefaults.object(forKey: Self.engineKey))
        }
    }

    func test_migration_neverOverridesAnExplicitlyStoredValue() {
        Preferences.shared.hasCompletedOnboarding = true
        Preferences.shared.transcriptionEngine = .linked
        Preferences.shared.migrateEngineDefaultIfNeeded()
        XCTAssertEqual(Preferences.shared.transcriptionEngine, .linked)
    }

    func test_migration_runsOnlyOnce() {
        Preferences.shared.hasCompletedOnboarding = true
        Preferences.shared.migrateEngineDefaultIfNeeded()
        XCTAssertEqual(Preferences.shared.transcriptionEngine, .server)

        // A later run must not re-derive from hasCompletedOnboarding.
        // Simulate the user explicitly picking Parakeet afterward, then
        // confirm a second migration call leaves it alone.
        Preferences.shared.transcriptionEngine = .parakeet
        Preferences.shared.migrateEngineDefaultIfNeeded()
        XCTAssertEqual(Preferences.shared.transcriptionEngine, .parakeet)
    }
}

/// Guard test for the production incident this fixed: the test host runs
/// inside the app (TEST_HOST), so `UserDefaults.standard` there IS the real
/// user's `com.rexdanquah.listentome` domain. `Preferences` must always be
/// backed by the isolated test suite while a test run is in progress.
final class PreferencesTestIsolationTests: XCTestCase {
    func test_backingStore_isNeverStandardDefaults_underTests() {
        XCTAssertTrue(RuntimeEnvironment.isRunningUnderTests)
        XCTAssertFalse(Preferences.shared.backingDefaultsForTesting === UserDefaults.standard,
                       "Preferences must not read/write UserDefaults.standard while tests are running")
    }
}

/// Tests for `Preferences.ParakeetModel` (PR C): the version picker's
/// mapping to FluidAudio's `AsrModelVersion`, display names, and default.
final class ParakeetModelPrefTests: XCTestCase {

    private static let key = "wf.parakeetModel"

    override func setUp() {
        super.setUp()
        Preferences.testDefaults.removeObject(forKey: Self.key)
    }
    override func tearDown() {
        Preferences.testDefaults.removeObject(forKey: Self.key)
        super.tearDown()
    }

    func test_default_is_v3() {
        // v3 stays the default so nothing changes for anyone already using
        // Parakeet.
        XCTAssertEqual(Preferences.shared.parakeetModel, .v3)
    }

    func test_persists_across_reads() {
        Preferences.shared.parakeetModel = .v2
        XCTAssertEqual(Preferences.shared.parakeetModel, .v2)
        Preferences.shared.parakeetModel = .v3
        XCTAssertEqual(Preferences.shared.parakeetModel, .v3)
    }

    func test_unknown_raw_value_falls_back_to_v3() {
        Preferences.testDefaults.set("tdt-v99", forKey: Self.key)
        XCTAssertEqual(Preferences.shared.parakeetModel, .v3)
    }

    func test_maps_to_fluidAudio_version() {
        XCTAssertEqual(Preferences.ParakeetModel.v3.asrModelVersion, .v3)
        XCTAssertEqual(Preferences.ParakeetModel.v2.asrModelVersion, .v2)
    }

    func test_all_cases_have_non_empty_labels() {
        for model in Preferences.ParakeetModel.allCases {
            XCTAssertFalse(model.label.isEmpty, "\(model.rawValue) has empty label")
            XCTAssertFalse(model.shortLabel.isEmpty, "\(model.rawValue) has empty shortLabel")
        }
    }

    func test_v2_label_signals_englishOnly() {
        XCTAssertTrue(Preferences.ParakeetModel.v2.label.lowercased().contains("english"))
    }

    func test_v3_label_signals_multilingual() {
        XCTAssertTrue(Preferences.ParakeetModel.v3.label.lowercased().contains("language"))
    }

    func test_shortLabels_used_by_benchmark_are_short() {
        // ParakeetEngine.modelDisplayName surfaces this in the benchmark's
        // compact model-name column, so keep it terse.
        XCTAssertEqual(Preferences.ParakeetModel.v3.shortLabel, "TDT v3")
        XCTAssertEqual(Preferences.ParakeetModel.v2.shortLabel, "TDT v2")
    }
}
