import CryptoKit
import XCTest
@testable import ListenToMe

/// Tests for `HistoryCipher` — the AES-GCM per-line encryption layer
/// behind the optional history at-rest encryption setting. We
/// generate ad-hoc keys per test so we never touch the real Keychain;
/// the `keyOrCreate` Keychain integration is exercised separately at
/// runtime via the Settings toggle.
final class HistoryCipherTests: XCTestCase {

    // MARK: - Round-trip

    func test_roundTrip_returns_original_plaintext() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = #"{"id":"abc","text":"hello world"}"#.data(using: .utf8)!
        let sealed = try HistoryCipher.encryptLine(plaintext, key: key)
        let opened = try HistoryCipher.decryptLine(sealed, key: key)
        XCTAssertEqual(opened, plaintext)
    }

    func test_each_encryption_uses_a_fresh_nonce() throws {
        // GCM safety: never reuse a (key, nonce) pair. Encrypting the
        // same plaintext twice MUST produce different ciphertext.
        let key = SymmetricKey(size: .bits256)
        let pt = "same input".data(using: .utf8)!
        let a = try HistoryCipher.encryptLine(pt, key: key)
        let b = try HistoryCipher.encryptLine(pt, key: key)
        XCTAssertNotEqual(a, b, "AES-GCM must use a fresh nonce per encryption")
    }

    func test_decrypt_with_wrong_key_throws() throws {
        let k1 = SymmetricKey(size: .bits256)
        let k2 = SymmetricKey(size: .bits256)
        let sealed = try HistoryCipher.encryptLine("secret".data(using: .utf8)!, key: k1)
        XCTAssertThrowsError(try HistoryCipher.decryptLine(sealed, key: k2))
    }

    func test_decrypt_tampered_ciphertext_throws() throws {
        // Authenticated encryption: any byte flip in the sealed payload
        // must cause `open` to throw rather than return garbage.
        let key = SymmetricKey(size: .bits256)
        let sealed = try HistoryCipher.encryptLine("important".data(using: .utf8)!, key: key)
        // Flip a byte in the middle of the base64 payload (skip the
        // first chars to stay in the body, not the prefix that's
        // base64-decoded but discarded if too short).
        var bytes = Array(sealed.utf8)
        XCTAssertGreaterThan(bytes.count, 30)
        bytes[20] = bytes[20] == 0x41 ? 0x42 : 0x41   // 'A' ↔ 'B'
        let tampered = String(bytes: bytes, encoding: .utf8)!
        XCTAssertThrowsError(try HistoryCipher.decryptLine(tampered, key: key))
    }

    // MARK: - Encoding shape

    func test_sealed_line_is_pure_base64_no_newlines() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try HistoryCipher.encryptLine("payload".data(using: .utf8)!, key: key)
        XCTAssertFalse(sealed.contains("\n"))
        // Base64 alphabet is [A-Za-z0-9+/=]
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        XCTAssertTrue(sealed.unicodeScalars.allSatisfy { allowed.contains($0) },
                      "sealed line must be pure base64 so NDJSON can split on \\n safely")
    }

    // MARK: - Detection heuristic

    func test_looksEncrypted_detects_base64_payload() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try HistoryCipher.encryptLine("hello".data(using: .utf8)!, key: key)
        XCTAssertTrue(HistoryCipher.looksEncrypted(Substring(sealed)))
    }

    func test_looksEncrypted_rejects_plaintext_json_line() {
        let json = #"{"id":"abc","text":"hello"}"#
        XCTAssertFalse(HistoryCipher.looksEncrypted(Substring(json)))
    }

    func test_looksEncrypted_rejects_empty() {
        XCTAssertFalse(HistoryCipher.looksEncrypted(Substring("")))
    }

    func test_looksEncrypted_rejects_too_short() {
        // 12-byte nonce + 0 ciphertext + 16-byte tag = 28 base64 chars
        // minimum. Anything shorter cannot be a valid AES-GCM payload.
        XCTAssertFalse(HistoryCipher.looksEncrypted("ZmFrZQ=="))
    }

    // MARK: - existingKey — no-create contract

    func test_existingKey_does_not_create_key_when_absent() throws {
        // Strategy: use parseNDJSON(data, key: nil) to prove the load path
        // is safe when no key exists. We cannot safely delete/create real
        // Keychain entries in CI without prompts, so instead we verify the
        // functional contract: when key==nil, encrypted lines are skipped
        // and plaintext lines are returned — exactly the behaviour that
        // matters when existingKey() returns nil (encryption never enabled).
        //
        // This covers the "key absent → load safe" case without touching
        // the login Keychain at all.

        let innerKey = SymmetricKey(size: .bits256)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let plainRec = TranscriptRecord(id: UUID(), timestamp: Date(),
                                        rawText: "plain", finalText: "Plain.",
                                        durationMs: 100, dismissed: false)
        let encRec = TranscriptRecord(id: UUID(), timestamp: Date(),
                                      rawText: "enc", finalText: "Enc.",
                                      durationMs: 200, dismissed: false)

        let plainLine = try encoder.encode(plainRec)
        let cipherLine = try HistoryCipher.encryptLine(try encoder.encode(encRec), key: innerKey)

        var blob = Data()
        blob.append(plainLine);   blob.append(0x0A)
        blob.append(cipherLine.data(using: .utf8)!); blob.append(0x0A)

        // Simulates load() calling parseNDJSON with key==nil (no encryption
        // enabled, existingKey() returned nil): encrypted lines must be
        // dropped, plaintext lines must survive.
        let parsed = HistoryStore.parseNDJSON(blob, key: nil)
        XCTAssertEqual(parsed.count, 1, "encrypted lines skipped when key==nil")
        XCTAssertEqual(parsed.first?.id, plainRec.id, "plaintext line survives")
    }
}

/// Verifies the HistoryStore NDJSON layer correctly round-trips
/// encrypted lines via the auto-detect path in `parseNDJSON(_:key:)`.
final class HistoryStoreEncryptedNDJSONTests: XCTestCase {

    func test_writeAll_with_key_then_parseNDJSON_with_key_round_trips() {
        let key = SymmetricKey(size: .bits256)
        let records = (0..<3).map { i in
            TranscriptRecord(id: UUID(), timestamp: Date(),
                             rawText: "raw-\(i)", finalText: "Final-\(i).",
                             durationMs: 1000, dismissed: false,
                             bundleId: i.isMultiple(of: 2) ? "com.apple.mail" : nil)
        }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("listentome-enc-\(UUID().uuidString).ndjson")
        defer { try? FileManager.default.removeItem(at: target) }

        HistoryStore.writeAll(records, to: target, key: key)
        let blob = try! Data(contentsOf: target)
        // Each line on disk must be base64 (encrypted), not raw JSON.
        let firstLine = String(data: blob, encoding: .utf8)!
            .split(separator: "\n").first!
        XCTAssertTrue(HistoryCipher.looksEncrypted(firstLine))

        // Decryption with the correct key recovers the records.
        let parsed = HistoryStore.parseNDJSON(blob, key: key).reversed()
        XCTAssertEqual(Array(parsed).map(\.id), records.map(\.id))
        XCTAssertEqual(Array(parsed).map(\.finalText), records.map(\.finalText))
    }

    func test_parseNDJSON_handles_mixed_encrypted_and_plaintext_lines() {
        // Survives a partial migration from a previous launch that
        // crashed mid-rewrite — half the file is encrypted, half
        // plaintext, both should decode under the same parse call.
        let key = SymmetricKey(size: .bits256)
        let recA = TranscriptRecord(id: UUID(), timestamp: Date(),
                                    rawText: "a", finalText: "A.",
                                    durationMs: 100, dismissed: false)
        let recB = TranscriptRecord(id: UUID(), timestamp: Date(),
                                    rawText: "b", finalText: "B.",
                                    durationMs: 200, dismissed: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plainLine = try! encoder.encode(recA)
        let cipherLine = try! HistoryCipher.encryptLine(try! encoder.encode(recB), key: key)
        var blob = Data()
        blob.append(plainLine)
        blob.append(0x0A)
        blob.append(cipherLine.data(using: .utf8)!)
        blob.append(0x0A)

        let parsed = HistoryStore.parseNDJSON(blob, key: key)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertTrue(parsed.contains { $0.id == recA.id })
        XCTAssertTrue(parsed.contains { $0.id == recB.id })
    }

    func test_parseNDJSON_skips_encrypted_lines_when_key_missing() {
        // load() passes nil when encryption is disabled — encrypted
        // lines (left over from a previous enabled session that the
        // user just turned off) should be skipped, not crash.
        let key = SymmetricKey(size: .bits256)
        let rec = TranscriptRecord(id: UUID(), timestamp: Date(),
                                   rawText: "x", finalText: "X.",
                                   durationMs: 100, dismissed: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let cipherLine = try! HistoryCipher.encryptLine(try! encoder.encode(rec), key: key)
        var blob = Data()
        blob.append(cipherLine.data(using: .utf8)!)
        blob.append(0x0A)

        let parsed = HistoryStore.parseNDJSON(blob, key: nil)
        XCTAssertEqual(parsed.count, 0)
    }
}
