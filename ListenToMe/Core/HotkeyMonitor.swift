import AppKit

/// Monitors a modifier combo globally and fires press/release callbacks.
/// Current combo: Fn + Command. Requires Accessibility permission.
/// Retries tap creation automatically until permission is granted — no app relaunch needed.
@MainActor
final class HotkeyMonitor {
    static let shared = HotkeyMonitor()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// CORR-01: Fires when the user taps the hotkey briefly (press +
    /// release within `shortTapWindow`). AppDelegate uses this to open
    /// the correction popover without needing a click on the pill.
    var onShortTap: (() -> Void)?

    private(set) var isActive: Bool = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false
    private var pressedAt: Date?
    private var retryTimer: Timer?

    /// Maximum hold-time that still counts as a short tap. Above this, the
    /// gesture is a normal press-and-hold dictation. 220ms is comfortably
    /// above accidental brushes but below any deliberate hold.
    private let shortTapWindow: TimeInterval = 0.22

    private init() {}

    func start() {
        if tryStartTap() { return }
        NSLog("[ListenToMe] Accessibility not granted yet — will retry every 2s")
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { t.invalidate(); return }
                if self.tryStartTap() {
                    NSLog("[ListenToMe] Accessibility granted — hotkey tap active")
                    t.invalidate()
                    self.retryTimer = nil
                    AppState.shared.showPermissionPrompt = false
                    PillWindow.shared.setInteractive(false)
                    NotificationCenter.default.post(name: .phaseChanged, object: nil)
                }
            }
        }
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
        retryTimer?.invalidate()
        retryTimer = nil
    }

    @discardableResult
    private func tryStartTap() -> Bool {
        guard eventTap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard type == .flagsChanged, let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { monitor.handle(event: event) }
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            return false
        }
        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
        return true
    }

    /// Modifier-combo detection driven by the user-selected binding.
    /// Tracks press timestamp so a release within `shortTapWindow` can
    /// dispatch `onShortTap` instead of (or in addition to) `onRelease`.
    private func handle(event: CGEvent) {
        let combo = Preferences.shared.hotkeyBinding.matches(flags: event.flags)

        if combo && !isDown {
            isDown = true
            pressedAt = Date()
            onPress?()
        } else if !combo && isDown {
            isDown = false
            let pressed = pressedAt
            pressedAt = nil
            onRelease?()
            if let pressed, Date().timeIntervalSince(pressed) <= shortTapWindow {
                onShortTap?()
            }
        }
    }

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the system accessibility dialog (only if not already granted).
    static func promptAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
