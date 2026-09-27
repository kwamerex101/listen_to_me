import AppKit
import Sparkle

/// Sparkle auto-update, wired for a background (accessory) app.
///
/// Consent model: `SUEnableAutomaticChecks` is deliberately absent from
/// Info.plist, so Sparkle shows its own one-time permission prompt on the
/// second launch instead of checking (and contacting github.com) before the
/// user agrees. This type never calls `checkForUpdates()` on its own.
/// Sparkle's scheduler and consent prompt are the only things that trigger a
/// check unless the user hits "Check for Updates…" or the Settings button.
///
/// `supportsGentleScheduledUpdateReminders` opts into Sparkle's gentle-
/// reminders flow (see `standardUserDriverWillHandleShowingUpdate` below):
/// without it, a scheduled check that finds an update can pop its alert
/// while ListenToMe (an LSUIElement app with no Dock icon) is hidden behind
/// whatever the user is currently looking at.
@MainActor
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    /// The unit tests run inside the app (TEST_HOST), so without this every
    /// test run would start Sparkle's scheduler: on a second run it shows the
    /// consent prompt mid-test and, once allowed, contacts GitHub.
    static let isRunningUnderTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// `lazy` so the controller's init (which needs `userDriverDelegate:
    /// self`) runs only once `self` is fully initialized: `self` can't be
    /// passed as a delegate before `super.init()` returns.
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: !Updater.isRunningUnderTests,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    private override init() {
        super.init()
        // Force the lazy controller to build now, on this first (and only)
        // access to `.shared`, so `SPUStandardUpdaterController`'s
        // `startingUpdater:` flag actually starts Sparkle's scheduler at
        // launch rather than on whatever call happens to touch `controller`
        // first. This does not itself trigger an update check: only
        // Sparkle's own scheduler/consent flow or an explicit
        // `checkForUpdates()` call does that.
        _ = controller
    }

    /// Explicit checked-for-updates entry point, used by the menu item and
    /// the Settings "Check Now" button. Never called automatically.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheck: Bool {
        controller.updater.canCheckForUpdates
    }

    var lastCheck: Date? {
        controller.updater.lastUpdateCheckDate
    }

    // MARK: - SPUStandardUserDriverDelegate (gentle reminders)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Called right before Sparkle shows an update alert. For a scheduled
    /// (non-user-initiated) check, bring the app forward so the alert isn't
    /// hidden behind other windows. This is an accessory app with no Dock
    /// icon, so without this the user may never notice the alert appeared.
    /// User-initiated checks already bring their own focus, so this only
    /// acts on the background case.
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
}
