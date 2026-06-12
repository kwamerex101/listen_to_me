import AppKit
import SwiftUI

/// Settings page — tabbed layout (Wave 8 UX refresh).
///
/// Ten stacked sections had outgrown a single scroll. Per the Wave 7
/// settings-pattern research (superwhisper's v2 regression: merging
/// everything into one scroll is the anti-pattern), settings are grouped
/// into five tabs with a chip bar. Rows follow the Eloquent copy pattern:
/// short label + optional one-line benefit description underneath.
enum SettingsTab: String, CaseIterable {
    case general, dictation, models, privacy, about

    var label: String {
        switch self {
        case .general:   return "General"
        case .dictation: return "Dictation"
        case .models:    return "Models"
        case .privacy:   return "Privacy"
        case .about:     return "About"
        }
    }

    var icon: String {
        switch self {
        case .general:   return "slider.horizontal.3"
        case .dictation: return "mic"
        case .models:    return "cpu"
        case .privacy:   return "lock.shield"
        case .about:     return "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var cleanupMode: CleanupMode = Preferences.shared.cleanupMode
    @State private var cleanupIntensity: Preferences.CleanupIntensity = Preferences.shared.cleanupIntensity
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
    @State private var selectedWhisperModel: Preferences.WhisperModel = Preferences.shared.selectedWhisperModel
    @State private var transcriptionAccuracy: Preferences.TranscriptionAccuracy = Preferences.shared.transcriptionAccuracy
    @State private var streamingPartialsEnabled: Bool = Preferences.shared.streamingPartialsEnabled
    @State private var inputDeviceUID: String = Preferences.shared.inputDeviceUID ?? ""
    @State private var availableInputs: [AudioInputDevice] = []
    @ObservedObject private var modelManager = WhisperModelManager.shared
    @State private var llmBackend: Preferences.LLMBackend = Preferences.shared.llmBackend
    @State private var selectedLocalLLMModel: Preferences.LocalLLMModel = Preferences.shared.selectedLocalLLMModel
    @ObservedObject private var llmManager = LLMModelManager.shared
    @ObservedObject private var parakeet = ParakeetEngine.shared

    /// Sticky tab selection — survives navigating away and relaunch.
    @AppStorage("wf.settingsTab") private var selectedTabRaw: String = SettingsTab.general.rawValue
    private var selectedTab: SettingsTab { SettingsTab(rawValue: selectedTabRaw) ?? .general }

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

                tabBar

                Group {
                    switch selectedTab {
                    case .general:   generalTab
                    case .dictation: dictationTab
                    case .models:    modelsTab
                    case .privacy:   privacyTab
                    case .about:     aboutTab
                    }
                }
                .id(selectedTab)
                .transition(.opacity)
                .animation(Motion.tabFade, value: selectedTab)
            }
            .padding(.top, DT.safeAreaTop)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .onAppear {
            accessibilityGranted = HotkeyMonitor.isAccessibilityGranted()
            launchAtLogin = LaunchAtLogin.isEnabled
            cleanupMode = Preferences.shared.cleanupMode
            cleanupIntensity = Preferences.shared.cleanupIntensity
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
            selectedWhisperModel = Preferences.shared.selectedWhisperModel
            transcriptionAccuracy = Preferences.shared.transcriptionAccuracy
            availableInputs = AudioInputDevices.available()
            let savedUID = Preferences.shared.inputDeviceUID ?? ""
            inputDeviceUID = (savedUID.isEmpty || availableInputs.contains(where: { $0.uid == savedUID })) ? savedUID : ""
            modelManager.refreshStatus()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                let selected = tab == selectedTab
                Button {
                    selectedTabRaw = tab.rawValue
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .medium))
                        Text(tab.label)
                            .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(selected ? DT.accent.opacity(0.16) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(selected ? DT.accent.opacity(0.45) : Color.clear, lineWidth: 1)
                    )
                    .foregroundStyle(selected ? DT.accent : Color.primary.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .animation(Motion.tabFade, value: selectedTabRaw)
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: DT.space6) {
            section(title: "Shortcuts") {
                row(label: "Dictation hotkey",
                    description: "Hold to dictate into any app.") {
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
                row(label: "Sound cues",
                    description: "Soft tones when recording starts and text lands.") {
                    Toggle("", isOn: $soundEnabled)
                        .labelsHidden()
                        .onChange(of: soundEnabled) { _, new in
                            Preferences.shared.soundEnabled = new
                        }
                }
                row(label: "Pill position",
                    description: "Drag the floating pill anywhere on screen.") {
                    HStack(spacing: 10) {
                        Text(Preferences.shared.pillAnchor == nil
                             ? "Default (bottom-center)"
                             : "Custom")
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
                .hoverableRow()
            }

            section(title: "System") {
                row(label: "Launch at login",
                    description: "Start ListenToMe automatically when you sign in.") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, new in
                            LaunchAtLogin.setEnabled(new)
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                }
                row(label: "Accessibility",
                    description: "Required to insert text into other apps.") {
                    HStack(spacing: 10) {
                        Text(accessibilityGranted ? "Granted ✓" : "Not granted")
                            .foregroundStyle(accessibilityGranted ? DT.statusSuccess : DT.statusWarning)
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
                    .animation(Motion.tabFade, value: accessibilityGranted)
                }
                .hoverableRow()
            }
        }
    }

    // MARK: - Dictation

    private var dictationTab: some View {
        VStack(alignment: .leading, spacing: DT.space6) {
            section(title: "Input") {
                row(label: "Microphone") {
                    Picker("", selection: $inputDeviceUID) {
                        Text("System default").tag("")
                        ForEach(availableInputs, id: \.uid) { dev in
                            Text(dev.name).tag(dev.uid)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: DT.controlPickerWidth)
                    .onChange(of: inputDeviceUID) { _, new in
                        Preferences.shared.inputDeviceUID = new.isEmpty ? nil : new
                    }
                }
                row(label: "Language") {
                    Text("English")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                row(label: "Max recording duration",
                    description: "Dictation auto-stops after this long.") {
                    HStack(spacing: 10) {
                        Slider(value: $maxRecordingSec, in: 30...600, step: 30)
                            .frame(width: DT.controlSliderWidth)
                            .onChange(of: maxRecordingSec) { _, new in
                                Preferences.shared.maxRecordingSec = Int(new)
                            }
                        Text("\(Int(maxRecordingSec))s")
                            .font(DT.monoCaption)
                            .foregroundStyle(.secondary)
                            .frame(width: DT.controlValueLabelWidth, alignment: .trailing)
                    }
                }
            }

            section(title: "AI Cleanup") {
                row(label: "Mode",
                    description: "When the polish pass runs after transcription.") {
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
                row(label: "Intensity",
                    description: "How aggressively cleanup edits. Light keeps every word.") {
                    Picker("", selection: $cleanupIntensity) {
                        ForEach(Preferences.CleanupIntensity.allCases, id: \.self) { lvl in
                            Text(lvl.label).tag(lvl)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: DT.controlPickerWidth)
                    .onChange(of: cleanupIntensity) { _, new in
                        Preferences.shared.cleanupIntensity = new
                    }
                }
                row(label: "Cloud backend",
                    description: "Used when the cleanup engine is Claude (cloud).") {
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
                    // Clear button appears/disappears with save state —
                    // fade instead of snapping the row layout.
                    .animation(Motion.tabFade, value: apiKeySaved)
                }
                .hoverableRow()
                row(label: "Cleanup timeout",
                    description: "Raw text stands if polishing takes longer.") {
                    HStack(spacing: 10) {
                        Slider(value: $cleanupTimeoutSec, in: 5...60, step: 5)
                            .frame(width: DT.controlSliderWidth)
                            .onChange(of: cleanupTimeoutSec) { _, new in
                                Preferences.shared.cleanupTimeoutSec = Int(new)
                            }
                        Text("\(Int(cleanupTimeoutSec))s")
                            .font(DT.monoCaption)
                            .foregroundStyle(.secondary)
                            .frame(width: DT.controlValueLabelWidth, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Models

    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: DT.space6) {
            section(title: "Transcription") {
                row(label: "Engine",
                    description: "Parakeet runs on the Neural Engine — fastest. Whisper is the offline default.") {
                    Picker("", selection: $transcriptionEngine) {
                        ForEach(Preferences.TranscriptionEngine.allCases, id: \.self) { eng in
                            Text(eng.label).tag(eng)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: DT.controlPickerWidth)
                    .onChange(of: transcriptionEngine) { _, new in
                        Preferences.shared.transcriptionEngine = new
                        // Pre-fetch/warm Parakeet so the first dictation isn't
                        // blocked on the model download/load.
                        if new == .parakeet {
                            Task { try? await ParakeetEngine.shared.ensureReady() }
                        }
                    }
                }
                // Parakeet model status (download lives here, like Whisper's).
                if transcriptionEngine == .parakeet {
                    row(label: "Parakeet model") {
                        parakeetStatusView
                    }
                    .hoverableRow()
                }
                // Whisper-only model controls.
                if transcriptionEngine.isWhisper {
                    row(label: "Whisper model") {
                        Picker("", selection: $selectedWhisperModel) {
                            ForEach(Preferences.WhisperModel.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: selectedWhisperModel) { _, new in
                            Preferences.shared.selectedWhisperModel = new
                            WhisperLib.shared.shutdown()
                            modelManager.refreshStatus()
                        }
                    }
                    row(label: "Status") {
                        modelStatusView
                    }
                    .hoverableRow()
                }
                row(label: "Accuracy") {
                    HStack(spacing: 10) {
                        Picker("", selection: $transcriptionAccuracy) {
                            ForEach(Preferences.TranscriptionAccuracy.allCases, id: \.self) { acc in
                                Text(acc.label).tag(acc)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        // Beam search only applies on the in-process
                        // linked engine; server/CLI decode with their
                        // own defaults. Same gating pattern as the
                        // streaming-partials toggle below.
                        .disabled(transcriptionEngine != .linked)
                        .onChange(of: transcriptionAccuracy) { _, new in
                            Preferences.shared.transcriptionAccuracy = new
                        }
                        if transcriptionEngine != .linked {
                            Text("Requires Linked engine")
                                .font(DT.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .animation(Motion.tabFade, value: transcriptionEngine)
                }
                row(label: "Live partial transcripts",
                    description: "Preview words as you speak.") {
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
                    .animation(Motion.tabFade, value: transcriptionEngine)
                }
            }
            .animation(Motion.tabFade, value: transcriptionEngine)

            section(title: "On-Device Polish") {
                row(label: "Cleanup engine",
                    description: "On-device keeps every transcript on this Mac.") {
                    Picker("", selection: $llmBackend) {
                        ForEach(Preferences.LLMBackend.allCases, id: \.self) { b in
                            Text(b.label).tag(b)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: DT.controlPickerWidth)
                    .onChange(of: llmBackend) { _, new in
                        Preferences.shared.llmBackend = new
                        if new == .local {
                            let file = selectedLocalLLMModel.filename
                            LocalLLMEngine.shared.activeModelPath =
                                LocalLLMEngine.modelURL(for: file).path
                            if LocalLLMEngine.shared.isReady(modelFile: file) {
                                LocalLLMEngine.shared.preload(modelFile: file)
                            }
                            llmManager.refreshStatus()
                        }
                    }
                }
                // Model picker + download only matter for the local engine —
                // mirror the partials/accuracy gating pattern.
                if llmBackend == .local {
                    row(label: "Model") {
                        Picker("", selection: $selectedLocalLLMModel) {
                            ForEach(Preferences.LocalLLMModel.allCases, id: \.self) { m in
                                Text(m.displayName).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: DT.controlPickerWidth)
                        .disabled(!modelFitsRAM(selectedLocalLLMModel) && selectedLocalLLMModel == .gemma4_12B)
                        .onChange(of: selectedLocalLLMModel) { _, new in
                            Preferences.shared.selectedLocalLLMModel = new
                            LocalLLMEngine.shared.shutdown()
                            LocalLLMEngine.shared.activeModelPath =
                                LocalLLMEngine.modelURL(for: new.filename).path
                            llmManager.refreshStatus()
                        }
                    }
                    row(label: "Status") {
                        llmModelStatusView
                    }
                    .hoverableRow()
                    if !modelFitsRAM(.gemma4_12B) {
                        row(label: "") {
                            Text("Gemma 4 12B needs ≥16 GB RAM — this Mac has \(installedRAMGB) GB.")
                                .font(DT.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .animation(Motion.tabFade, value: llmBackend)

            section(title: "Engine Benchmark (A/B)") {
                BenchmarkSection()
                    .padding(.vertical, DT.space3)
            }
        }
    }

    // MARK: - Privacy

    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: DT.space6) {
            section(title: "History") {
                row(label: "History retention",
                    description: "Transcripts older than this are deleted automatically.") {
                    HStack(spacing: 10) {
                        Slider(value: $historyRetentionDays, in: 0...365, step: 30)
                            .frame(width: DT.controlSliderWidth)
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
                row(label: "Encrypt history at rest",
                    description: "AES-GCM encryption for transcripts stored on disk.") {
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

            section(title: "Diagnostics") {
                row(label: "Diagnostics log",
                    description: "Local-only logs to help debug issues. Never includes transcripts.") {
                    Toggle("", isOn: $diagnosticsEnabled)
                        .labelsHidden()
                        .onChange(of: diagnosticsEnabled) { _, new in
                            Preferences.shared.diagnosticsEnabled = new
                        }
                }
            }
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: DT.space6) {
            section(title: "About") {
                row(label: "Version") {
                    Text(Self.versionString)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                row(label: "Processing",
                    description: "Speech recognition runs entirely on this Mac.") {
                    Text("On-device")
                        .font(.system(size: 13))
                        .foregroundStyle(DT.statusSuccess)
                }
            }
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
                    .foregroundStyle(DT.statusSuccess)
            }
        case .missing:
            HStack(spacing: 10) {
                Text("Not downloaded (\(selectedWhisperModel.displayName))")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusWarning)
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
                    .foregroundStyle(DT.statusError)
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

    @ViewBuilder
    private var llmModelStatusView: some View {
        switch llmManager.status {
        case .ready(let bytes):
            Text("Downloaded ✓ (\(formatBytes(bytes)))")
                .font(.system(size: 13))
                .foregroundStyle(DT.statusSuccess)
        case .missing:
            HStack(spacing: 10) {
                Text("Not downloaded (\(selectedLocalLLMModel.displayName))")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusWarning)
                Button("Download") { llmManager.startDownload() }
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
                Button("Cancel") { llmManager.cancelDownload() }
                    .buttonStyle(.pressable)
            }
        case .failed(let message):
            HStack(spacing: 10) {
                Text("⚠ \(message)")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusError)
                    .lineLimit(2)
                Button("Retry") { llmManager.startDownload() }
                    .buttonStyle(.pressable)
            }
        }
    }

    @ViewBuilder
    private var parakeetStatusView: some View {
        switch parakeet.status {
        case .ready:
            Text("Loaded ✓ (Neural Engine)")
                .font(.system(size: 13))
                .foregroundStyle(DT.statusSuccess)
        case .missing:
            HStack(spacing: 10) {
                Text("Not downloaded (~600 MB)")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusWarning)
                Button("Download") { Task { try? await parakeet.ensureReady() } }
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
            }
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading model…").font(DT.caption).foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack(spacing: 10) {
                Text("⚠ \(message)")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusError)
                    .lineLimit(2)
                Button("Retry") { Task { try? await parakeet.ensureReady() } }
                    .buttonStyle(.pressable)
            }
        }
    }

    /// Installed unified memory in GB (rounded).
    private var installedRAMGB: Int {
        Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
    }

    private func modelFitsRAM(_ model: Preferences.LocalLLMModel) -> Bool {
        installedRAMGB >= model.minRAMGB
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

    /// Settings row: short label, optional one-line benefit description
    /// underneath (Eloquent copy pattern), control trailing.
    private func row<Trailing: View>(
        label: String,
        description: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DT.body)
                if let description {
                    Text(description)
                        .font(DT.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
