import Foundation

/// Shared fallback for SnippetsStore/TransformsStore's DB-failure catch
/// blocks. A successful migration renames the legacy JSON to `.json.bak`
/// (see `migrateFromLegacyJSON` in each store), so a DB failure that
/// happens AFTER migration must fall back to the `.bak` copy, not the
/// (now-absent) original path, or the user sees an empty list instead of
/// their existing data.
enum LegacyJSONFallback {
    /// Data from the legacy JSON at `legacyURL`, or from its post-migration
    /// `.bak` copy if the original is gone. nil if neither exists.
    static func read(legacyURL: URL) -> Data? {
        if let data = try? Data(contentsOf: legacyURL) {
            return data
        }
        return try? Data(contentsOf: legacyURL.appendingPathExtension("bak"))
    }
}
