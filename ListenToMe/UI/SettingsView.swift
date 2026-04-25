import SwiftUI

struct SettingsView: View {
    @State private var cleanupMode: CleanupMode = Preferences.shared.cleanupMode
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var accessibilityGranted: Bool = HotkeyMonitor.isAccessibilityGranted()
    @State private var hotkey: HotkeyBinding = Preferences.shared.hotkeyBinding
    @State private var soundEnabled: Bool = Preferences.shared.soundEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings")
                    .font(.system(size: 24, weight: .semibold))

                section(title: "Shortcuts") {
                    row(label: "Dictation hotkey") {
                        Picker("", selection: $hotkey) {
                            ForEach(HotkeyBinding.allCases, id: \.self) { binding in
                                Text(binding.label).tag(binding)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: hotkey) { _, new in
                            Preferences.shared.hotkeyBinding = new
                        }
                    }
                }

                section(title: "AI Cleanup") {
                    row(label: "Mode") {
                        Picker("", selection: $cleanupMode) {
                            ForEach(CleanupMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: cleanupMode) { _, new in
                            Preferences.shared.cleanupMode = new
                        }
                    }
                }

                section(title: "Audio") {
                    row(label: "Sound cues") {
                        Toggle("", isOn: $soundEnabled)
                            .labelsHidden()
                            .onChange(of: soundEnabled) { _, new in
                                Preferences.shared.soundEnabled = new
                            }
                    }
                }

                section(title: "System") {
                    row(label: "Launch at login") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .onChange(of: launchAtLogin) { _, new in
                                LaunchAtLogin.setEnabled(new)
                                launchAtLogin = LaunchAtLogin.isEnabled
                            }
                    }
                    row(label: "Accessibility") {
                        HStack(spacing: 10) {
                            Text(accessibilityGranted ? "Granted ✓" : "Not granted")
                                .foregroundStyle(accessibilityGranted ? .green : .orange)
                                .font(.system(size: 13))
                            if !accessibilityGranted {
                                Button("Grant…") {
                                    HotkeyMonitor.promptAccessibility()
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                        }
                    }
                    row(label: "Microphone") {
                        Text("Built-in microphone")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    row(label: "Language") {
                        Text("English")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                section(title: "About") {
                    row(label: "Version") {
                        Text("0.1.0")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 60)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .onAppear {
            accessibilityGranted = HotkeyMonitor.isAccessibilityGranted()
            launchAtLogin = LaunchAtLogin.isEnabled
            cleanupMode = Preferences.shared.cleanupMode
            hotkey = Preferences.shared.hotkeyBinding
            soundEnabled = Preferences.shared.soundEnabled
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    private func row<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func kbd(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
