import AppKit

@MainActor
final class MenuBarController {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private weak var statusLabel: NSMenuItem?
    private weak var hotkeyLabel: NSMenuItem?
    private weak var accessibilityItem: NSMenuItem?
    private weak var cleanupItem: NSMenuItem?
    private weak var claudeStatusItem: NSMenuItem?
    private weak var launchAtLoginItem: NSMenuItem?

    private init() {}

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "ListenToMe")
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.delegate = MenuDelegate.shared   // refresh on open

        let status = NSMenuItem(title: "ListenToMe — Idle", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusLabel = status

        menu.addItem(.separator())

        let openWindow = NSMenuItem(
            title: "Open ListenToMe…",
            action: #selector(openMainWindow),
            keyEquivalent: ","
        )
        openWindow.target = self
        menu.addItem(openWindow)

        let hk = NSMenuItem(title: "Hotkey: Fn + ⌘", action: nil, keyEquivalent: "")
        hk.isEnabled = false
        menu.addItem(hk)
        hotkeyLabel = hk

        menu.addItem(.separator())

        let ax = NSMenuItem(
            title: "Accessibility: checking…",
            action: #selector(openAccessibilityPrefs),
            keyEquivalent: ""
        )
        ax.target = self
        menu.addItem(ax)
        accessibilityItem = ax

        menu.addItem(.separator())

        let cleanupParent = NSMenuItem(title: "AI Cleanup", action: nil, keyEquivalent: "")
        let cleanupSub = NSMenu()
        for mode in CleanupMode.allCases {
            let item = NSMenuItem(
                title: mode.label,
                action: #selector(selectCleanupMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            cleanupSub.addItem(item)
        }
        cleanupParent.submenu = cleanupSub
        menu.addItem(cleanupParent)
        cleanupItem = cleanupParent
        refreshCleanupChecks()

        let claude = NSMenuItem(
            title: "Claude CLI: checking…",
            action: #selector(openClaudeInstallDocs),
            keyEquivalent: ""
        )
        claude.target = self
        menu.addItem(claude)
        claudeStatusItem = claude

        let launch = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launch.target = self
        launch.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launch)
        launchAtLoginItem = launch

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit ListenToMe",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu
        statusItem = item

        MenuDelegate.shared.refresh = { [weak self] in self?.refresh() }

        NotificationCenter.default.addObserver(
            forName: .phaseChanged, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }

        refresh()
    }

    func refresh() {
        switch AppState.shared.phase {
        case .idle: statusLabel?.title = "ListenToMe — Idle"
        case .recording: statusLabel?.title = "ListenToMe — Recording"
        case .transcribing: statusLabel?.title = "ListenToMe — Transcribing"
        case .cleaning: statusLabel?.title = "ListenToMe — Cleaning up"
        case .polishing: statusLabel?.title = "ListenToMe — Polishing"
        case .success: statusLabel?.title = "ListenToMe — Done"
        case .error(let m): statusLabel?.title = "ListenToMe — Error: \(m)"
        case .correcting: statusLabel?.title = "ListenToMe — Correcting"
        }

        let trusted = HotkeyMonitor.isAccessibilityGranted()
        let tapActive = HotkeyMonitor.shared.isActive

        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off

        if trusted && tapActive {
            accessibilityItem?.title = "Accessibility: Granted ✓"
            accessibilityItem?.action = nil
            hotkeyLabel?.title = "Hotkey: Fn + ⌘ (ready)"
        } else if trusted && !tapActive {
            accessibilityItem?.title = "Accessibility: Granted — restart app to activate"
            accessibilityItem?.action = #selector(restartApp)
            accessibilityItem?.target = self
            hotkeyLabel?.title = "Hotkey: Fn + ⌘ (restart required)"
        } else {
            accessibilityItem?.title = "⚠ Grant Accessibility Permission…"
            accessibilityItem?.action = #selector(openAccessibilityPrefs)
            accessibilityItem?.target = self
            hotkeyLabel?.title = "Hotkey: Fn + ⌘ (needs permission)"
        }

        // Claude CLI status — only loud when cleanup is wanted but unavailable.
        let cleanupOn = Preferences.shared.cleanupMode != .off
        if AppState.shared.claudeAvailable {
            claudeStatusItem?.title = "Claude CLI: Installed ✓"
            claudeStatusItem?.action = nil
        } else if cleanupOn {
            claudeStatusItem?.title = "⚠ Claude CLI not found — cleanup disabled"
            claudeStatusItem?.action = #selector(openClaudeInstallDocs)
            claudeStatusItem?.target = self
        } else {
            claudeStatusItem?.title = "Claude CLI: not installed (cleanup off)"
            claudeStatusItem?.action = #selector(openClaudeInstallDocs)
            claudeStatusItem?.target = self
        }
    }

    @objc private func openClaudeInstallDocs() {
        if let url = URL(string: "https://claude.com/claude-code") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openAccessibilityPrefs() {
        HotkeyMonitor.promptAccessibility()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openMainWindow() {
        MainWindowController.shared.open()
    }

    @objc private func toggleLaunchAtLogin() {
        let target = !LaunchAtLogin.isEnabled
        let ok = LaunchAtLogin.setEnabled(target)
        if ok {
            launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
        }
    }

    @objc private func selectCleanupMode(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let mode = CleanupMode(rawValue: raw)
        else { return }
        Preferences.shared.cleanupMode = mode
        refreshCleanupChecks()
    }

    private func refreshCleanupChecks() {
        guard let sub = cleanupItem?.submenu else { return }
        let current = Preferences.shared.cleanupMode
        for item in sub.items {
            if let raw = item.representedObject as? String, raw == current.rawValue {
                item.state = .on
            } else {
                item.state = .off
            }
        }
        cleanupItem?.title = "AI Cleanup: \(current.label)"
    }

    @objc private func restartApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

@MainActor
private final class MenuDelegate: NSObject, NSMenuDelegate {
    static let shared = MenuDelegate()
    var refresh: (() -> Void)?
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in self.refresh?() }
    }
}

extension Notification.Name {
    static let phaseChanged = Notification.Name("ListenToMePhaseChanged")
}
