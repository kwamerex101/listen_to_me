import CryptoKit
import Foundation

/// AES-GCM authenticated encryption for the per-line NDJSON history
/// file. Each line is encrypted independently so the constant-time
/// append property of the NDJSON layout is preserved — turning on
/// encryption does not turn `add()` into an O(N) full-file rewrite.
///
/// Wire format per line:
///     base64( nonce(12) || ciphertext || tag(16) )
///
/// `AES.GCM.SealedBox.combined` already serializes those three pieces
/// in that exact order; we just base64 it so the NDJSON file remains
/// newline-delimited UTF-8.
///
/// Threat model: another user on this Mac with file-system access (no
/// FileVault) sees only ciphertext. They cannot decrypt without the
/// Keychain-stored key, which is protected by their inability to
/// unlock this user's login keychain. This is a pragmatic single-user
/// defense — not a defense against malware running as the user.
enum HistoryCipher {
    enum CipherError: Error {
        case keychainFailure(OSStatus)
        case malformedCiphertext
        case base64DecodeFailed
    }

    /// Keychain account where the AES-GCM key lives. Service is the
    /// shared `com.rexdanquah.listentome` from `Keychain.swift`.
    static let keychainAccount = "history_encryption_key"

    /// Fetch the symmetric key, or generate + persist a fresh 256-bit
    /// one if the Keychain has no entry yet. Idempotent across calls.
    static func keyOrCreate() throws -> SymmetricKey {
        if let raw = try Keychain.get(account: keychainAccount),
           let data = Data(base64Encoded: raw),
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        let fresh = SymmetricKey(size: .bits256)
        let raw = fresh.withUnsafeBytes { Data($0) }.base64EncodedString()
        try Keychain.set(raw, account: keychainAccount)
        return fresh
    }

    /// Fetch the existing symmetric key, or nil if none is stored. Unlike
    /// `keyOrCreate()`, this NEVER generates/persists a key — used by the
    /// read/load path so opening history can't silently create a key (and
    /// touch the Keychain) when the user never enabled encryption.
    static func existingKey() throws -> SymmetricKey? {
        guard let raw = try Keychain.get(account: keychainAccount),
              let data = Data(base64Encoded: raw),
              data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    /// Remove the persisted key. Used by the "disable encryption"
    /// migration path AFTER the file has been rewritten to plaintext —
    /// otherwise a partial migration would lock the user out of their
    /// own history.
    static func dropKey() throws {
        try Keychain.delete(account: keychainAccount)
    }

    /// Encrypt a single JSON line (raw bytes, no trailing newline).
    /// Returns the base64-encoded sealed-box payload — caller appends
    /// the `\n` separator.
    static func encryptLine(_ plaintext: Data, key: SymmetricKey) throws -> String {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw CipherError.malformedCiphertext
        }
        return combined.base64EncodedString()
    }

    /// Decrypt a single base64-encoded sealed-box payload back to its
    /// original JSON bytes.
    static func decryptLine(_ base64Line: String, key: SymmetricKey) throws -> Data {
        guard let combined = Data(base64Encoded: base64Line) else {
            throw CipherError.base64DecodeFailed
        }
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    /// Heuristic: a base64-encoded GCM line starts with characters in
    /// `[A-Za-z0-9+/]` and is at least 28 chars (12-byte nonce + 0
    /// ciphertext + 16-byte tag → 28 base64 chars). A plaintext NDJSON
    /// line starts with `{`. Used by the load path to auto-detect
    /// which mode the on-disk file is in, surviving partial migrations.
    static func looksEncrypted(_ line: Substring) -> Bool {
        guard let first = line.first else { return false }
        return first != "{" && first != "[" && line.count >= 28
    }
}
