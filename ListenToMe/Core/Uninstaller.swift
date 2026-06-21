import AppKit
import Foundation

/// Full local removal of ListenToMe: app data, downloaded models, history,
/// dictionary, settings, Keychain keys, and the app bundle (to Trash).
///
/// What it CANNOT remove: macOS TCC permission grants (Microphone /
/// Accessibility / Automation) live in the system privacy database and can
/// only be cleared by the user in System Settings — we deep-link them there.
enum Uninstaller {

    static var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListenToMe", isDirectory: true)
    }

    static var dailyNotesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/daily", isDirectory: true)
    }

    /// The paths that exist and would be deleted. Pure — no side effects.
    static func removalPlan(includeDailyNotes: Bool) -> [URL] {
        var urls: [URL] = []
        let fm = FileManager.default
        if fm.fileExists(atPath: appSupportURL.path) { urls.append(appSupportURL) }
        if includeDailyNotes, fm.fileExists(atPath: dailyNotesURL.path) {
            urls.append(dailyNotesURL)
        }
        return urls
    }

    /// Destructive: wipe data + settings + Keychain + login item, move the app
    /// to Trash, point the user at System Settings for the leftover TCC grants,
    /// then quit. Runs on the main actor.
    @MainActor
    static func performUninstall(includeDailyNotes: Bool) {
        let fm = FileManager.default

        // 1. Delete data directories (models, history, dictionary, SQLite, logs).
        for url in removalPlan(includeDailyNotes: includeDailyNotes) {
            do { try fm.removeItem(at: url) }
            catch { NSLog("[ListenToMe] uninstall: failed to remove \(url.path): \(error)") }
        }

        // 2. Keychain — drop both stored secrets.
        do { try Keychain.delete(account: Preferences.anthropicAPIKeyAccount) }
        catch { NSLog("[ListenToMe] uninstall: failed to delete API key from Keychain: \(error)") }
        do { try Keychain.delete(account: HistoryCipher.keychainAccount) }
        catch { NSLog("[ListenToMe] uninstall: failed to delete encryption key from Keychain: \(error)") }

        // 3. UserDefaults — clear the whole persistent domain.
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }

        // 4. Login item.
        LaunchAtLogin.setEnabled(false)

        // 5. Move the app bundle to Trash (reversible; safe while running).
        //    Then open System Settings → Privacy and quit from the completion.
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([appURL]) { _, _ in
            DispatchQueue.main.async {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                    NSWorkspace.shared.open(url)
                }
                NSApp.terminate(nil)
            }
        }
    }
}
