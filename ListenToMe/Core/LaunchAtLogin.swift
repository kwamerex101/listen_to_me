import ServiceManagement

/// Wraps `SMAppService.mainApp` so the main bundle can register itself as a
/// login item. Requires macOS 13+.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("[ListenToMe] LaunchAtLogin failed: \(error)")
            return false
        }
    }
}
