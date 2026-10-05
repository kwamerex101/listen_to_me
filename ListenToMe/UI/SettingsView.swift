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

/// One row of the settings search index. Search is a jump-to list: picking
/// a result switches to the owning tab, it does not scroll to the row.
struct SettingsSearchEntry {
    let title: String
    let keywords: String
    let tab: SettingsTab

    /// Hand-maintained: add an entry when a settings row is added.
    static let all: [SettingsSearchEntry] = [
        .init(title: "Your name", keywords: "greeting home profile", tab: .general),
        .init(title: "Dictation hotkey", keywords: "shortcut key fn push to talk hold", tab: .general),
        .init(title: "Theme", keywords: "appearance dark light mode", tab: .general),
        .init(title: "Sound cues", keywords: "audio tones beep chime", tab: .general),
        .init(title: "Pill position", keywords: "floating pill move reset drag", tab: .general),
        .init(title: "Launch at login", keywords: "startup open at sign in", tab: .general),
        .init(title: "Accessibility", keywords: "permission insert text paste", tab: .general),
        .init(title: "Automatically check for updates", keywords: "auto update sparkle version", tab: .general),
        .init(title: "Check for updates", keywords: "last checked check now sparkle", tab: .general),
        .init(title: "Microphone", keywords: "input device audio", tab: .dictation),
        .init(title: "Language", keywords: "english locale", tab: .dictation),
        .init(title: "Max recording duration", keywords: "limit auto stop length", tab: .dictation),
        .init(title: "Output destination", keywords: "where text goes notes paste", tab: .dictation),
        .init(title: "Note mode", keywords: "apple notes append daily", tab: .dictation),
        .init(title: "Note name", keywords: "apple notes title", tab: .dictation),
        .init(title: "Notes folder", keywords: "apple notes", tab: .dictation),
        .init(title: "Notes permission", keywords: "apple notes automation", tab: .dictation),
        .init(title: "AI cleanup mode", keywords: "polish when smart", tab: .dictation),
        .init(title: "Cleanup intensity", keywords: "light aggressive edits", tab: .dictation),
        .init(title: "Cloud backend", keywords: "claude cli api cleanup", tab: .dictation),
        .init(title: "Anthropic API key", keywords: "claude secret token", tab: .dictation),
        .init(title: "Cleanup timeout", keywords: "polish seconds slow", tab: .dictation),
        .init(title: "Cleanup engine", keywords: "on-device local cloud llm polish", tab: .dictation),
        .init(title: "On-device cleanup model", keywords: "gemma local llm download", tab: .dictation),
        .init(title: "Transcription engine", keywords: "whisper parakeet linked", tab: .models),
        .init(title: "Parakeet version", keywords: "v2 v3 languages", tab: .models),
        .init(title: "Parakeet model", keywords: "download neural engine", tab: .models),
        .init(title: "Boost dictionary terms", keywords: "vocabulary ctc", tab: .models),
        .init(title: "Whisper model", keywords: "download size", tab: .models),
        .init(title: "Model status", keywords: "downloaded delete download", tab: .models),
        .init(title: "Accuracy", keywords: "beam search", tab: .models),
        .init(title: "Live partial transcripts", keywords: "streaming preview", tab: .models),
        .init(title: "History retention", keywords: "delete old transcripts days", tab: .privacy),
        .init(title: "Encrypt history at rest", keywords: "aes encryption", tab: .privacy),
        .init(title: "Context-aware tone", keywords: "browser url apple event", tab: .privacy),
        .init(title: "Voice commands", keywords: "shell log today open run", tab: .privacy),
        .init(title: "Diagnostics log", keywords: "debug logging", tab: .privacy),
        .init(title: "Version", keywords: "build about", tab: .about),
        .init(title: "Processing", keywords: "on-device privacy", tab: .about),
        .init(title: "Engine benchmark", keywords: "a/b compare speed", tab: .about),
        .init(title: "Uninstall and delete all data", keywords: "remove erase", tab: .about),
    ]
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
    @State private var automaticallyChecksForUpdates: Bool = Updater.shared.automaticallyChecks
    @State private var lastUpdateCheck: Date? = Updater.shared.lastCheck
    @State private var historyRetentionDays: Double = Double(Preferences.shared.historyRetentionDays)
    @State private var historyEncryptionEnabled: Bool = Preferences.shared.historyEncryptionEnabled
    @State private var contextAwareToneEnabled: Bool = Preferences.shared.contextAwareToneEnabled
    @State private var voiceCommandsEnabled: Bool = Preferences.shared.voiceCommandsEnabled
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
    @State private var parakeetVocabBoost: Bool = Preferences.shared.parakeetVocabBoost
    @State private var parakeetModel: Preferences.ParakeetModel = Preferences.shared.parakeetModel
    @State private var outputDestination: OutputDestination = Preferences.shared.outputDestination
    @State private var noteMode: NoteMode = Preferences.shared.noteMode
    @State private var noteTitleDraft: String = Preferences.shared.noteTitle
    @State private var noteFolderDraft: String = Preferences.shared.noteFolder
    @State private var userNameDraft: String = Preferences.shared.userName

    /// Which downloaded model the user has asked to delete. Non-nil drives the
    /// confirmation dialog; deletion only runs once they confirm.
    @State private var pendingDelete: DeletableModel?
    @State private var showUninstallSheet = false
    @State private var uninstallIncludesDailyNotes = false
    @State private var uninstallConfirmText = ""

    /// Jump-to search over the settings index (see `SettingsSearchEntry`).
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool

    /// The on-disk models a user can reclaim space from.
    private enum DeletableModel: String, Identifiable {
        case whisper, cleanup, parakeet
        var id: String { rawValue }
        var label: String {
            switch self {
            case .whisper:  return "Whisper model"
            case .cleanup:  return "on-device cleanup model"
            case .parakeet: return "Parakeet model"
            }
        }
    }

    /// Sticky tab selection — survives navigating away and relaunch.
    @AppStorage("wf.settingsTab") private var selectedTabRaw: String = SettingsTab.general.rawValue
    private var selectedTab: SettingsTab { SettingsTab(rawValue: selectedTabRaw) ?? .general }
    @Namespace private var chipNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                searchField

                if isSearching {
                    searchResultsList
                        .frame(maxWidth: 720, alignment: .leading)
                } else {
                    tabBar
                }

                Group {
                    if !isSearching {
                        switch selectedTab {
                        case .general:   generalTab
                        case .dictation: dictationTab
                        case .models:    modelsTab
                        case .privacy:   privacyTab
                        case .about:     aboutTab
                        }
                    }
                }
                .id(selectedTab)
                .transition(.opacity)
                .animation(reduceMotion ? nil : Motion.selection, value: selectedTab)
                // Settings forms shouldn't sprawl on wide windows — cap the
                // content column so labels and controls don't drift apart.
                .frame(maxWidth: 720, alignment: .leading)
            }
            .padding(.top, DT.safeAreaTop)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .onAppear {
            hydrateFromPreferences(includeDrafts: true)
        }
        // Prefs can change outside this view (menu bar cleanup mode,
        // onboarding hotkey). Re-sync while the page is open; drafts and
        // OS-backed state are left alone so typing is never overwritten.
        .onReceive(
            NotificationCenter.default
                .publisher(for: UserDefaults.didChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            hydrateFromPreferences(includeDrafts: false)
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.label ?? "model")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { model in
            Button("Delete", role: .destructive) { performDelete(model) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This frees up disk space. You can re-download it anytime.")
        }
    }

    /// Assigns only when the value differs, so re-hydration never triggers
    /// an `.onChange` write-back for a value that is already current.
    private func sync<T: Equatable>(_ state: Binding<T>, _ value: T) {
        if state.wrappedValue != value { state.wrappedValue = value }
    }

    /// Pulls Preferences into the @State mirrors. `includeDrafts` is true
    /// only on appear: text-field drafts (name, note title/folder, API key)
    /// and OS/keychain-backed state (login item, Accessibility, input
    /// devices) are not touched by the UserDefaults-driven refresh, since
    /// overwriting a half-typed draft or re-running a side-effecting
    /// `.onChange` would fight the user.
    private func hydrateFromPreferences(includeDrafts: Bool) {
        let p = Preferences.shared
        sync($cleanupMode, p.cleanupMode)
        sync($cleanupIntensity, p.cleanupIntensity)
        sync($hotkey, p.hotkeyBinding)
        sync($soundEnabled, p.soundEnabled)
        sync($appearance, p.appearance)
        sync($maxRecordingSec, Double(p.maxRecordingSec))
        sync($cleanupTimeoutSec, Double(p.cleanupTimeoutSec))
        sync($cleanupBackend, p.cleanupBackend)
        sync($diagnosticsEnabled, p.diagnosticsEnabled)
        sync($automaticallyChecksForUpdates, Updater.shared.automaticallyChecks)
        sync($lastUpdateCheck, Updater.shared.lastCheck)
        sync($historyRetentionDays, Double(p.historyRetentionDays))
        sync($historyEncryptionEnabled, p.historyEncryptionEnabled)
        sync($contextAwareToneEnabled, p.contextAwareToneEnabled)
        sync($voiceCommandsEnabled, p.voiceCommandsEnabled)
        sync($transcriptionEngine, p.transcriptionEngine)
        sync($parakeetVocabBoost, p.parakeetVocabBoost)
        sync($parakeetModel, p.parakeetModel)
        sync($outputDestination, p.outputDestination)
        sync($noteMode, p.noteMode)
        sync($streamingPartialsEnabled, p.streamingPartialsEnabled)
        sync($selectedWhisperModel, p.selectedWhisperModel)
        sync($transcriptionAccuracy, p.transcriptionAccuracy)
        sync($llmBackend, p.llmBackend)
        sync($selectedLocalLLMModel, p.selectedLocalLLMModel)

        guard includeDrafts else { return }
        accessibilityGranted = HotkeyMonitor.isAccessibilityGranted()
        launchAtLogin = LaunchAtLogin.isEnabled
        apiKeyDraft = p.anthropicAPIKey ?? ""
        apiKeySaved = !apiKeyDraft.isEmpty
        noteTitleDraft = p.noteTitle
        noteFolderDraft = p.noteFolder
        userNameDraft = p.userName
        availableInputs = AudioInputDevices.available()
        let savedUID = p.inputDeviceUID ?? ""
        inputDeviceUID = (savedUID.isEmpty || availableInputs.contains(where: { $0.uid == savedUID })) ? savedUID : ""
        modelManager.refreshStatus()
    }

    private func performDelete(_ model: DeletableModel) {
        switch model {
        case .whisper:  modelManager.deleteModel()
        case .cleanup:  llmManager.deleteModel()
        case .parakeet: parakeet.deleteModel()
        }
        pendingDelete = nil
    }

    // MARK: - Search

    private var trimmedQuery: String { searchQuery.trimmingCharacters(in: .whitespaces) }
    private var isSearching: Bool { !trimmedQuery.isEmpty }

    private var searchResults: [SettingsSearchEntry] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        return Array(
            SettingsSearchEntry.all.filter {
                $0.title.localizedCaseInsensitiveContains(q)
                    || $0.keywords.localizedCaseInsensitiveContains(q)
            }.prefix(8)
        )
    }

    private func jump(to entry: SettingsSearchEntry) {
        searchQuery = ""
        searchFocused = false
        if reduceMotion {
            selectedTabRaw = entry.tab.rawValue
        } else {
            withAnimation(Motion.selection) { selectedTabRaw = entry.tab.rawValue }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search settings", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit {
                    if let first = searchResults.first { jump(to: first) }
                }
                .onExitCommand { searchQuery = "" }
            if isSearching {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            // Hidden ⌘F target; the field itself has no shortcut hook.
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .formField()
        .frame(maxWidth: 320, alignment: .leading)
    }

    @ViewBuilder
    private var searchResultsList: some View {
        let results = searchResults
        if results.isEmpty {
            Text("No settings match “\(trimmedQuery)”")
                .font(DT.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.offset) { _, entry in
                    Button { jump(to: entry) } label: {
                        HStack {
                            Text(entry.title).font(DT.bodyStrong)
                            Spacer(minLength: DT.space5)
                            Text(entry.tab.label)
                                .font(DT.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, DT.space4)
                        .padding(.vertical, DT.space3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverableRow()
                }
            }
            .card()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                let selected = tab == selectedTab
                Button {
                    if reduceMotion {
                        selectedTabRaw = tab.rawValue
                    } else {
                        withAnimation(Motion.selection) {
                            selectedTabRaw = tab.rawValue
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .medium))
                        Text(tab.label)
                            .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    // Only the selected chip carries a fill — presence vs.
                    // absence reads faster than two faint fills. A single
                    // matched-geometry capsule slides between chips.
                    .background {
                        if selected {
                            Capsule(style: .continuous)
                                .fill(DT.accent.opacity(0.22))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(DT.accent.opacity(0.5), lineWidth: 1)
                                )
                                .matchedGeometryEffect(id: "settingsTabChip", in: chipNamespace)
                        }
                    }
                    .foregroundStyle(selected ? DT.accent : Color.primary.opacity(0.7))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: DT.space6) {
            section(title: "You") {
                row(label: "Your name",
                    description: "Used to greet you on the Home screen.") {
                    TextField("", text: $userNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onChange(of: userNameDraft) { _, new in Preferences.shared.userName = new }
                        .onSubmit { Preferences.shared.userName = userNameDraft }
                }
            }

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
                            .buttonStyle(.bordered)
                            .controlSize(.small)
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
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .animation(Motion.tabFade, value: accessibilityGranted)
                }
                .hoverableRow()
            }

            section(title: "Updates") {
                row(label: "Automatically check for updates",
                    description: "Checks github.com for a newer signed version. Sends your app version; no other data.") {
                    Toggle("", isOn: $automaticallyChecksForUpdates)
                        .labelsHidden()
                        .onChange(of: automaticallyChecksForUpdates) { _, new in
                            guard new != Updater.shared.automaticallyChecks else { return }
                            Updater.shared.automaticallyChecks = new
                        }
                }
                row(label: "Last checked") {
                    HStack(spacing: 10) {
                        Text(lastCheckedLabel)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Button("Check Now") {
                            Updater.shared.checkForUpdates()
                            lastUpdateCheck = Updater.shared.lastCheck
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!Updater.shared.canCheck)
                    }
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

            outputSection

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
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(apiKeyDraft == (Preferences.shared.anthropicAPIKey ?? ""))
                        if apiKeySaved {
                            Button("Clear") {
                                _ = Preferences.shared.setAnthropicAPIKey(nil)
                                apiKeyDraft = ""
                                apiKeySaved = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(DT.statusError)
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

            onDevicePolishSection
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
                        guard new != Preferences.shared.transcriptionEngine else { return }
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
                    row(label: "Parakeet version",
                        description: "v2 is English only and a little more accurate. v3 also understands 24 other European languages.") {
                        Picker("", selection: $parakeetModel) {
                            ForEach(Preferences.ParakeetModel.allCases, id: \.self) { model in
                                Text(model.label).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: DT.controlPickerWidth)
                        .onChange(of: parakeetModel) { _, new in
                            guard new != Preferences.shared.parakeetModel else { return }
                            Preferences.shared.parakeetModel = new
                            // Mirrors the Whisper-model switch below: drop the
                            // loaded version so the next call downloads/loads
                            // the newly-selected one instead of staying warm
                            // on the old model.
                            ParakeetEngine.shared.shutdown()
                            Task { try? await ParakeetEngine.shared.ensureReady() }
                        }
                    }
                    row(label: "Parakeet model") {
                        parakeetStatusView
                    }
                    .hoverableRow()
                    row(label: "Boost dictionary terms",
                        description: "Favor your dictionary words during transcription (CTC word-spotting). Downloads a small extra model; slightly slower.") {
                        Toggle("", isOn: $parakeetVocabBoost)
                            .labelsHidden()
                            .onChange(of: parakeetVocabBoost) { _, new in
                                Preferences.shared.parakeetVocabBoost = new
                            }
                    }
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
                            guard new != Preferences.shared.selectedWhisperModel else { return }
                            Preferences.shared.selectedWhisperModel = new
                            WhisperLib.shared.shutdown()
                            WhisperServer.shared.shutdown()
                            modelManager.refreshStatus()
                        }
                    }
                    row(label: "Status") {
                        modelStatusView
                    }
                    .hoverableRow()
                }
                // Beam search + live partials only apply on the in-process
                // Linked engine; the whole row dims when another engine is
                // active (the "requires" reason lives in the description).
                row(label: "Accuracy",
                    description: transcriptionEngine == .linked
                        ? "Beam search trades a little speed for fewer errors."
                        : "Requires the Whisper · Linked engine.",
                    enabled: transcriptionEngine == .linked) {
                    Picker("", selection: $transcriptionAccuracy) {
                        ForEach(Preferences.TranscriptionAccuracy.allCases, id: \.self) { acc in
                            Text(acc.label).tag(acc)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: DT.controlPickerWidth)
                    .onChange(of: transcriptionAccuracy) { _, new in
                        Preferences.shared.transcriptionAccuracy = new
                    }
                }
                row(label: "Live partial transcripts",
                    description: transcriptionEngine == .linked
                        ? "Preview words as you speak."
                        : "Requires the Whisper · Linked engine.",
                    enabled: transcriptionEngine == .linked) {
                    Toggle("", isOn: $streamingPartialsEnabled)
                        .labelsHidden()
                        .onChange(of: streamingPartialsEnabled) { _, new in
                            Preferences.shared.streamingPartialsEnabled = new
                        }
                }
            }
            .animation(Motion.tabFade, value: transcriptionEngine)
        }
    }

    /// Where finished dictations land. Apple Notes reveals mode/title/folder
    /// controls and an Automation-permission note.
    private var outputSection: some View {
        section(title: "Output") {
            row(label: "Destination",
                description: "Where dictated text goes when you finish speaking.") {
                Picker("", selection: $outputDestination) {
                    ForEach(OutputDestination.allCases, id: \.self) { dest in
                        Text(dest.label).tag(dest)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: DT.controlPickerWidth)
                .onChange(of: outputDestination) { _, new in
                    Preferences.shared.outputDestination = new
                }
            }
            if outputDestination == .appleNotes {
                row(label: "Note mode",
                    description: "Append to one note, start a new note each time, or keep a daily note.") {
                    Picker("", selection: $noteMode) {
                        ForEach(NoteMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: DT.controlPickerWidth)
                    .onChange(of: noteMode) { _, new in
                        Preferences.shared.noteMode = new
                    }
                }
                if noteMode == .appendToDefault {
                    row(label: "Note name",
                        description: "The note your dictations are appended to.") {
                        TextField("ListenToMe", text: $noteTitleDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onChange(of: noteTitleDraft) { _, new in Preferences.shared.noteTitle = new }
                            .onSubmit { Preferences.shared.noteTitle = noteTitleDraft }
                    }
                    .hoverableRow()
                }
                row(label: "Folder",
                    description: "Apple Notes folder to write into. Created if it doesn't exist.") {
                    TextField("ListenToMe", text: $noteFolderDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onChange(of: noteFolderDraft) { _, new in Preferences.shared.noteFolder = new }
                        .onSubmit { Preferences.shared.noteFolder = noteFolderDraft }
                }
                .hoverableRow()
                row(label: "Permission",
                    description: "Writing to Notes asks macOS once to let ListenToMe control Notes. Nothing leaves your Mac.") {
                    EmptyView()
                }
            }
        }
        .animation(Motion.tabFade, value: outputDestination)
    }

    /// On-Device Polish — lives on the Dictation tab next to AI Cleanup
    /// (it's the cleanup engine, same pipeline stage).
    private var onDevicePolishSection: some View {
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
                    guard new != Preferences.shared.llmBackend else { return }
                    Preferences.shared.llmBackend = new
                    if new == .local {
                        let file = selectedLocalLLMModel.filename
                        LocalLLMEngine.shared.activeModelPath =
                            LocalLLMEngine.modelURL(for: file).path
                        if LocalLLMEngine.shared.isReady(modelFile: file) {
                            LocalLLMEngine.shared.preload(modelFile: file)
                        }
                        llmManager.refreshStatus()
                    } else {
                        // Switching to cloud: probe the CLI now so the menu
                        // warning is accurate (the launch probe is skipped for
                        // non-cloud users to avoid a network-volume prompt).
                        Task {
                            let available = await ClaudeClient.shared.isAvailable()
                            await MainActor.run {
                                AppState.shared.claudeAvailable = available
                                NotificationCenter.default.post(name: .phaseChanged, object: nil)
                            }
                        }
                    }
                }
            }
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
                        guard new != Preferences.shared.selectedLocalLLMModel else { return }
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
                    row(label: "Gemma 4 12B",
                        description: "Needs ≥16 GB RAM — this Mac has \(installedRAMGB) GB.") {
                        EmptyView()
                    }
                }
            }
        }
        .animation(Motion.tabFade, value: llmBackend)
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
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                row(label: "Encrypt history at rest",
                    description: "AES-GCM encryption for transcripts stored on disk.") {
                    Toggle("", isOn: $historyEncryptionEnabled)
                        .labelsHidden()
                        .onChange(of: historyEncryptionEnabled) { _, new in
                            guard new != Preferences.shared.historyEncryptionEnabled else { return }
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

            section(title: "Permissions") {
                row(label: "Context-aware tone",
                    description: "Reads the active browser tab's URL to match cleanup tone to what you're writing. Sends an Apple Event to the browser, so macOS asks to \"control\" it. Off keeps tone based on the app alone.") {
                    Toggle("", isOn: $contextAwareToneEnabled)
                        .labelsHidden()
                        .onChange(of: contextAwareToneEnabled) { _, new in
                            Preferences.shared.contextAwareToneEnabled = new
                        }
                }
            }

            section(title: "Voice commands") {
                row(label: "Voice commands",
                    description: "Recognize spoken commands like \"log today: …\", \"open …\", and \"shell: …\". \"Log today\" writes to your Documents folder and \"shell\" runs a terminal command, so this is off by default.") {
                    Toggle("", isOn: $voiceCommandsEnabled)
                        .labelsHidden()
                        .onChange(of: voiceCommandsEnabled) { _, new in
                            Preferences.shared.voiceCommandsEnabled = new
                        }
                }
                Text("Lets spoken commands write files and run terminal commands on your Mac. Only enable if you trust everyone who can speak near it.")
                    .font(DT.caption)
                    .foregroundStyle(DT.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DT.space4)
                    .padding(.bottom, DT.space3)
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

            // The A/B benchmark is a diagnostic tool, not a setting — lives
            // here rather than overloading the Models tab.
            section(title: "Engine Benchmark (A/B)") {
                BenchmarkSection()
                    .padding(.vertical, DT.space3)
            }

            section(title: "Remove ListenToMe") {
                row(label: "Uninstall & delete all data",
                    description: "Removes downloaded models, history, dictionary, settings, and stored keys, and moves the app to the Trash.") {
                    Button("Remove…") { showUninstallSheet = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(DT.statusError)
                }
                .hoverableRow()
            }
        }
        .sheet(isPresented: $showUninstallSheet) { uninstallSheet }
    }

    // MARK: - Uninstall sheet

    private var uninstallSheet: some View {
        VStack(alignment: .leading, spacing: DT.space4) {
            Text("Remove ListenToMe?")
                .font(.system(size: 17, weight: .semibold))
            Text("This permanently deletes your data and moves the app to the Trash. It cannot be undone, and history is not recoverable.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                ForEach([
                    "Downloaded models, history, and dictionary",
                    "Settings and the login item",
                    "API and encryption keys in your Keychain",
                    "The app itself (moved to the Trash)"
                ], id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(item)
                    }
                    .font(.system(size: 13))
                }
            }
            Toggle("Also delete my daily notes (~/Documents/daily)", isOn: $uninstallIncludesDailyNotes)
                .font(.system(size: 13))
            Text("macOS permission grants (Microphone, Accessibility, Automation) can't be removed automatically. We'll open System Settings so you can clear them.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Type REMOVE to confirm", text: $uninstallConfirmText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            HStack {
                Spacer()
                Button("Cancel") {
                    showUninstallSheet = false
                    uninstallIncludesDailyNotes = false
                    uninstallConfirmText = ""
                }
                .keyboardShortcut(.cancelAction)
                Button("Remove everything", role: .destructive) {
                    showUninstallSheet = false
                    uninstallConfirmText = ""
                    Uninstaller.performUninstall(includeDailyNotes: uninstallIncludesDailyNotes)
                }
                .buttonStyle(.borderedProminent)
                .tint(DT.statusError)
                .disabled(uninstallConfirmText.trimmingCharacters(in: .whitespaces) != "REMOVE")
            }
        }
        .padding(20)
        .frame(width: 440)
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
                deleteButton(.whisper)
            }
        case .missing:
            HStack(spacing: 10) {
                Text("Not downloaded (\(selectedWhisperModel.displayName))")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusWarning)
                Button("Download") { modelManager.startDownload() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        case .failed(let message):
            HStack(spacing: 10) {
                Text("⚠ \(message)")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusError)
                    .lineLimit(2)
                Button("Retry") { modelManager.startDownload() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    /// "Never checked" until Sparkle has actually run a check, then a short
    /// relative timestamp ("2 hours ago").
    private var lastCheckedLabel: String {
        guard let lastUpdateCheck else { return "Never checked" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUpdateCheck, relativeTo: Date())
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.0f MB", mb)
    }

    /// Compact "Delete" affordance shown next to a downloaded model. Opens the
    /// confirmation dialog rather than deleting immediately.
    private func deleteButton(_ model: DeletableModel) -> some View {
        Button("Delete") { pendingDelete = model }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(DT.statusError)
    }

    @ViewBuilder
    private var llmModelStatusView: some View {
        switch llmManager.status {
        case .ready(let bytes):
            HStack(spacing: 10) {
                Text("Downloaded ✓ (\(formatBytes(bytes)))")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusSuccess)
                deleteButton(.cleanup)
            }
        case .missing:
            HStack(spacing: 10) {
                Text("Not downloaded (\(selectedLocalLLMModel.displayName))")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusWarning)
                Button("Download") { llmManager.startDownload() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        case .failed(let message):
            HStack(spacing: 10) {
                Text("⚠ \(message)")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusError)
                    .lineLimit(2)
                Button("Retry") { llmManager.startDownload() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var parakeetStatusView: some View {
        switch parakeet.status {
        case .ready:
            HStack(spacing: 10) {
                Text("Loaded ✓ (Neural Engine)")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusSuccess)
                deleteButton(.parakeet)
            }
        case .missing:
            HStack(spacing: 10) {
                Text("Not downloaded (~600 MB)")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.statusWarning)
                Button("Download") { Task { try? await parakeet.ensureReady() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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

    /// Settings row: bold label, optional one-line benefit description
    /// underneath (Eloquent copy pattern), control trailing. When `enabled`
    /// is false the WHOLE row dims (macOS convention — a disabled control
    /// dims its label too) and stops taking hits.
    private func row<Trailing: View>(
        label: String,
        description: String? = nil,
        enabled: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DT.bodyStrong)
                if let description {
                    Text(description)
                        .font(DT.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DT.space5)
            trailing()
        }
        .padding(.horizontal, DT.space4)
        .padding(.vertical, DT.space3)
        .opacity(enabled ? 1 : 0.5)
        .allowsHitTesting(enabled)
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
