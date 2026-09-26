import CryptoKit
import XCTest
@testable import ListenToMe

/// Tests for the model-download integrity fixes: every downloadable model
/// (Whisper GGML and on-device LLM GGUF) must carry a real SHA-256 and a
/// download URL pinned to a specific commit rather than mutable
/// `resolve/main`, and the streaming hasher used to verify a downloaded
/// file must produce a correct digest without loading the file into memory.
@MainActor
final class ModelIntegrityTests: XCTestCase {

    // MARK: - Every model has a pinned URL + a real hash

    func test_every_whisper_model_has_hash_and_pinned_url() {
        for m in Preferences.WhisperModel.allCases {
            guard let sha = m.sha256 else {
                XCTFail("\(m) has no sha256")
                continue
            }
            assertIsSixtyFourHexChars(sha, label: "\(m)")
            XCTAssertFalse(m.downloadURL.absoluteString.contains("/resolve/main/"),
                           "\(m) download URL is not pinned to a commit: \(m.downloadURL)")
        }
    }

    func test_every_local_llm_model_has_hash_and_pinned_url() {
        for m in Preferences.LocalLLMModel.allCases {
            guard let sha = m.sha256 else {
                XCTFail("\(m) has no sha256")
                continue
            }
            assertIsSixtyFourHexChars(sha, label: "\(m)")
            XCTAssertFalse(m.downloadURL.absoluteString.contains("/resolve/main/"),
                           "\(m) download URL is not pinned to a commit: \(m.downloadURL)")
        }
    }

    private func assertIsSixtyFourHexChars(_ s: String, label: String) {
        XCTAssertEqual(s.count, 64, "\(label) hash isn't 64 chars: \(s)")
        XCTAssertTrue(s.allSatisfy(\.isHexDigit), "\(label) hash isn't hex: \(s)")
    }

    // MARK: - downloadDestination pure helpers

    func test_whisperModelManager_downloadDestination_keyedByModel_notSelection() {
        for m in Preferences.WhisperModel.allCases {
            let dest = WhisperModelManager.downloadDestination(for: m)
            XCTAssertEqual(dest.lastPathComponent, m.filename)
            XCTAssertTrue(dest.path.contains("ListenToMe/models"))
        }
    }

    func test_llmModelManager_downloadDestination_keyedByModel_notSelection() {
        for m in Preferences.LocalLLMModel.allCases {
            let dest = LLMModelManager.downloadDestination(for: m)
            XCTAssertEqual(dest.lastPathComponent, m.filename)
        }
    }

    // MARK: - Streaming SHA-256

    func test_streaming_sha256_matches_known_digest() throws {
        let data = "the quick brown fox jumps over the lazy dog".data(using: .utf8)!
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelIntegrityTests-\(UUID().uuidString).bin")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let actual = WhisperModelManager.sha256(of: tmp)
        XCTAssertEqual(actual, expected)
    }

    func test_streaming_sha256_multiChunk_matches_known_digest() throws {
        // Bigger than the 1 MB chunk size the hasher reads in, so this
        // exercises the loop crossing a chunk boundary.
        var data = Data()
        for i in 0..<3_000_000 { data.append(UInt8(i % 251)) }
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelIntegrityTests-\(UUID().uuidString).bin")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let actual = WhisperModelManager.sha256(of: tmp)
        XCTAssertEqual(actual, expected)
    }

    func test_streaming_sha256_missingFile_returnsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelIntegrityTests-does-not-exist-\(UUID().uuidString).bin")
        XCTAssertNil(WhisperModelManager.sha256(of: missing))
    }
}
