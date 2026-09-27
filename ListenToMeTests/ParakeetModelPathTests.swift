import XCTest
@testable import ListenToMe

/// `ParakeetEngine.modelFolders(in:)` must name the folders FluidAudio really
/// writes. It downloads into SIBLINGS of the directory we pass (parent + repo
/// folder name), which is why "Delete Parakeet model" used to remove an empty
/// `ListenToMe/parakeet` and leave ~460 MB behind.
final class ParakeetModelPathTests: XCTestCase {

    private let modelsDirectory = URL(fileURLWithPath: "/tmp/AppSupport/ListenToMe/parakeet",
                                      isDirectory: true)

    private var paths: [String] {
        ParakeetEngine.modelFolders(in: modelsDirectory).map(\.standardizedFileURL.path)
    }

    func test_includesBothTDTVersionsAsSiblings() {
        XCTAssertTrue(paths.contains("/tmp/AppSupport/ListenToMe/parakeet-tdt-0.6b-v3"))
        XCTAssertTrue(paths.contains("/tmp/AppSupport/ListenToMe/parakeet-tdt-0.6b-v2"))
    }

    func test_includesVocabularyBoostCTCModel() {
        XCTAssertTrue(paths.contains("/tmp/AppSupport/ListenToMe/parakeet-ctc-110m-coreml"))
    }

    func test_includesTheLegacyModelsDirectory() {
        XCTAssertTrue(paths.contains("/tmp/AppSupport/ListenToMe/parakeet"))
    }

    /// Guards against a folder name that climbs out of the app's own tree
    /// (e.g. an empty name resolving to ListenToMe itself), which would make
    /// "Delete Parakeet model" wipe history and settings.
    func test_everyFolderIsADistinctChildOfListenToMe() {
        for path in paths {
            XCTAssertEqual((path as NSString).deletingLastPathComponent,
                           "/tmp/AppSupport/ListenToMe", path)
            XCTAssertNotEqual(path, "/tmp/AppSupport/ListenToMe")
        }
        XCTAssertEqual(Set(paths).count, paths.count)
    }
}
