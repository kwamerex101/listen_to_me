import SwiftUI

struct SettingsView: View {
    @State private var cleanupMode: CleanupMode = Preferences.shared.cleanupMode
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var accessibilityGranted: Bool = HotkeyMonitor.isAccessibilityGranted()
    @State private var hotkey: HotkeyBinding = Preferences.shared.hotkeyBinding
    @State private var soundEnabled: Bool = Preferences.shared.soundEnabled
    @State private var appearance: AppearanceMode = Preferences.shared.appearance
    @State private var maxRecordingSec: Double = Double(Preferences.shared.maxRecordingSec)
    @State private var cleanupTimeoutSec: Double = Double(Preferences.shared.cleanupTimeoutSec)
    @State private var cleanupBackend: Preferences.CleanupBackend = Preferences.shared.cleanupBackend
    @State private var apiKeyDraft: String = Preferences.shared.anthropicAPIKey ?? ""
    @State private var apiKeySaved: Bool = (Preferences.shared.anthropicAPIKey?.isEmpty == false)
    @State private var diagnosticsEnabled: Bool = Preferences.shared.diagnosticsEnabled
    @State private var historyRetentionDays: Double = Double(Preferences.shared.historyRetentionDays)
    @State private var historyEncryptionEnabled: Bool = Preferences.shared.historyEncryptionEnabled
    @State private var transcriptionEngine: Preferences.TranscriptionEngine = Preferences.shared.transcriptionEngine
    @State private var streamingPartialsEnabled: Bool = Preferences.shared.streamingPartialsEnabled
    @State private var inputDeviceUID: String = Preferences.shared.inputDeviceUID ?? ""
    @State private var availableInputs: [AudioInputDevice] = []
    @ObservedObject private var modelManager = WhisperModelManager.shared

    /// Reads the version straight from the bundle so future bumps don't
    /// require touching this view.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String
        if let build, build != short { return "\(short) (\(build))" }
        return short
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.space6) {
                PageHeader(
                    title: "Settings",
                    subtitle: nil,
                    icon: "gearshape",
                    iconTint: .gray
                )

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
                    row(label: "Backend") {
                        Picker("", selection: $cleanupBackend) {
                            ForEach(Preferences.CleanupBackend.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: cleanupBackend) { _, new in
                            Preferences.shared.cleanupBackend = new
                        }
                    }
                    row(label: "Anthropic API key") {
                        HStack(spacing: 10) {
                            SecureField("sk-ant-…", text: $apiKeyDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                                .disableAutocorrection(true)
                            Button(apiKeySaved && apiKeyDraft == (Preferences.shared.anthropicAPIKey ?? "")
                                   ? "Saved ✓" : "Save") {
                                let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                let ok = Preferences.shared.setAnthropicAPIKey(trimmed.isEmpty ? nil : trimmed)
                                if ok {
                                    apiKeyDraft = trimmed
                                    apiKeySaved = !trimmed.isEmpty
                                }
                            }
                            .buttonStyle(.pressable)
                            .disabled(apiKeyDraft == (Preferences.shared.anthropicAPIKey ?? ""))
                            if apiKeySaved {
                                Button("Clear") {
                                    _ = Preferences.shared.setAnthropicAPIKey(nil)
                                    apiKeyDraft = ""
                                    apiKeySaved = false
                                }
                                .buttonStyle(.pressable)
                            }
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

                section(title: "Appearance") {
                    row(label: "Theme") {
                        Picker("", selection: $appearance) {
                            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: appearance) { _, new in
                            Preferences.shared.appearance = new
                        }
                    }
                }

                section(title: "Whisper Model") {
                    row(label: "Local model") {
                        modelStatusView
                    }
                    .hoverableRow()
                    row(label: "Transcription engine") {
                        Picker("", selection: $transcriptionEngine) {
                            ForEach(Preferences.TranscriptionEngine.allCases, id: \.self) { eng in
                                Text(eng.label).tag(eng)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: transcriptionEngine) { _, new in
                            Preferences.shared.transcriptionEngine = new
                        }
                    }
                    row(label: "Live partial transcripts") {
                        HStack(spacing: 10) {
                            Toggle("", isOn: $streamingPartialsEnabled)
                                .labelsHidden()
                                .disabled(transcriptionEngine != .linked)
                                .onChange(of: streamingPartialsEnabled) { _, new in
                                    Preferences.shared.streamingPartialsEnabled = new
                                }
                            if transcriptionEngine != .linked {
                                Text("Requires Linked engine")
                                    .font(DT.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                                .buttonStyle(.pressable)
                            }
                        }
                    }
                    .hoverableRow()   // only this Settings row is interactive (Grant…)
                    row(label: "Microphone") {
                        Picker("", selection: $inputDeviceUID) {
                            Text("System default").tag("")
                            ForEach(availableInputs, id: \.uid) { dev in
                                Text(dev.name).tag(dev.uid)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 240)
                        .onChange(of: inputDeviceUID) { _, new in
                            Preferences.shared.inputDeviceUID = new.isEmpty ? nil : new
                        }
                    }
                    row(label: "Language") {
                        Text("English")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                section(title: "Advanced") {
                    row(label: "Max recording duration") {
                        HStack(spacing: 10) {
                            Slider(value: $maxRecordingSec, in: 30...600, step: 30)
                                .frame(width: 180)
                                .onChange(of: maxRecordingSec) { _, new in
                                    Preferences.shared.maxRecordingSec = Int(new)
                                }
                            Text("\(Int(maxRecordingSec))s")
                                .font(DT.monoCaption)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    row(label: "Cleanup timeout") {
                        HStack(spacing: 10) {
                            Slider(value: $cleanupTimeoutSec, in: 5...60, step: 5)
                                .frame(width: 180)
                                .onChange(of: cleanupTimeoutSec) { _, new in
                                    Preferences.shared.cleanupTimeoutSec = Int(new)
                                }
                            Text("\(Int(cleanupTimeoutSec))s")
                                .font(DT.monoCaption)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    row(label: "Diagnostics log") {
                        Toggle("", isOn: $diagnosticsEnabled)
                            .labelsHidden()
                            .onChange(of: diagnosticsEnabled) { _, new in
                                Preferences.shared.diagnosticsEnabled = new
                            }
                    }
                    row(label: "Pill position") {
                        HStack(spacing: 10) {
                            Text(Preferences.shared.pillAnchor == nil
                                 ? "Default (bottom-center)"
                                 : "Custom — drag the pill to move")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            if Preferences.shared.pillAnchor != nil {
                                Button("Reset") {
                                    PillWindow.shared.resetPositionToDefault()
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                    }
                    row(label: "History retention") {
                        HStack(spacing: 10) {
                            Slider(value: $historyRetentionDays, in: 0...365, step: 30)
                                .frame(width: 180)
                                .onChange(of: historyRetentionDays) { _, new in
                                    Preferences.shared.historyRetentionDays = Int(new)
                                }
                            Text(historyRetentionDays == 0 ? "Forever" : "\(Int(historyRetentionDays))d")
                                .font(DT.monoCaption)
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                            Button("Apply") {
                                HistoryStore.shared.enforceRetention()
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    row(label: "Encrypt history at rest") {
                        Toggle("", isOn: $historyEncryptionEnabled)
                            .labelsHidden()
                            .onChange(of: historyEncryptionEnabled) { _, new in
                                Preferences.shared.historyEncryptionEnabled = new
                                // Triggers a one-time rewrite of
                                // history.ndjson (encrypt on enable,
                                // decrypt on disable). Cheap on small
                                // histories; debounced via the existing
                                // saveTask path otherwise.
                                HistoryStore.shared.applyEncryptionPreference()
                            }
                    }
                }

                section(title: "About") {
                    row(label: "Version") {
                        Text(Self.versionString)
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
            appearance = Preferences.shared.appearance
            cleanupBackend = Preferences.shared.cleanupBackend
            apiKeyDraft = Preferences.shared.anthropicAPIKey ?? ""
            apiKeySaved = !apiKeyDraft.isEmpty
            diagnosticsEnabled = Preferences.shared.diagnosticsEnabled
            historyRetentionDays = Double(Preferences.shared.historyRetentionDays)
            historyEncryptionEnabled = Preferences.shared.historyEncryptionEnabled
            transcriptionEngine = Preferences.shared.transcriptionEngine
            streamingPartialsEnabled = Preferences.shared.streamingPartialsEnabled
            availableInputs = AudioInputDevices.available()
            let savedUID = Preferences.shared.inputDeviceUID ?? ""
            inputDeviceUID = (savedUID.isEmpty || availableInputs.contains(where: { $0.uid == savedUID })) ? savedUID : ""
            modelManager.refreshStatus()
        }
    }

    /// Compact status view for the Whisper model row — branches on the
    /// manager's current status (ready / missing / downloading / failed).
    @ViewBuilder
    private var modelStatusView: some View {
        switch modelManager.status {
        case .ready(let bytes):
            HStack(spacing: 10) {
                Text("Downloaded ✓ (\(formatBytes(bytes)))")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            }
        case .missing:
            HStack(spacing: 10) {
                Text("Not downloaded (~148 MB)")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                Button("Download") { modelManager.startDownload() }
                    .buttonStyle(.pressable)
            }
        case .downloading(let progress):
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 110)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Cancel") { modelManager.cancelDownload() }
                    .buttonStyle(.pressable)
            }
        case .failed(let message):
            HStack(spacing: 10) {
                Text("⚠ \(message)")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Button("Retry") { modelManager.startDownload() }
                    .buttonStyle(.pressable)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.0f MB", mb)
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DT.space2) {
            SectionEyebrow(title: title)
            VStack(spacing: 0) {
                content()
            }
            .card()
        }
    }

    private func row<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label)
                .font(DT.body)
            Spacer()
            trailing()
        }
        .padding(.horizontal, DT.space4)
        .padding(.vertical, DT.space3)
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
