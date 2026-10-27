import SwiftUI

struct PillView: View {
    @ObservedObject var state: AppState = .shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var levelBuffer: [Float] = Array(repeating: 0, count: 16)

    // Promotion-flash (POLISH-04c) — gold ring overlay fired when the
    // dictionary auto-promotes (or the user manually accepts) a candidate.
    @State private var promotionScale: CGFloat = 0.6
    @State private var promotionOpacity: Double = 0.0

    // Pointer feedback changes the border without moving the controls.
    @State private var hovered: Bool = false

    // Auto-shrink-to-dot (Wispr-style). When the pill sits in idle for
    // sustained time (no hover, no dictation), collapse to a tiny 10pt
    // dot so it disappears into the background. Wakes back to full
    // idle size on hover or any phase change.
    @State private var isShrunkToDot: Bool = false
    private let shrinkAfter: TimeInterval = 5.0


    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            partialPreviewIfNeeded
            pill
                .frame(width: pillWidth, height: pillHeight)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    hovered = isHovering
                    // Success stays available while the pointer is over the pill.
                    state.pillHovered = isHovering
                    // Hover wakes the pill from dot-mode and restarts
                    // the shrink countdown when the cursor leaves.
                    if isHovering { wakeFromShrink() }
                }
                .onTapGesture {
                    if isPillTappable { state.onPillTap?() }
                }
                // Drag to reposition the floating pill across screen edges.
                // 6pt minimum keeps tap-on-button gestures intact; the
                // simultaneousGesture composition lets the cancel/stop X
                // still receive their clicks via the SwiftUI Button below.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .global)
                        .onChanged { value in
                            PillWindow.shared.applyDrag(translation: value.translation, isFinal: false)
                        }
                        .onEnded { value in
                            PillWindow.shared.applyDrag(translation: value.translation, isFinal: true)
                        }
                )
                .accessibilityElement(children: isPillTappable ? .ignore : .contain)
                .accessibilityLabel(accessibilityLabelForCurrentPhase)
                .accessibilityHint(accessibilityHintForCurrentPhase)
                .accessibilityAddTraits(isPillTappable ? .isButton : [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .onChange(of: state.level) { _, newValue in
            levelBuffer.removeFirst()
            levelBuffer.append(newValue)
        }
        .onChange(of: phaseID) { _, _ in
            handlePhaseChange()
        }
        .task(id: canAutoShrink) {
            guard canAutoShrink else { return }
            do { try await Task.sleep(nanoseconds: UInt64(shrinkAfter * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled, canAutoShrink else { return }
            withAnimation(reduceMotion ? nil : Motion.phaseSize) { isShrunkToDot = true }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { promotionOpacity = 0 }
        }
        .onDisappear { state.pillHovered = false }
        .onChange(of: state.flashPromotion) { _, isFlashing in
            triggerPromotionFlash(if: isFlashing)
        }
    }

    // MARK: - Phase and idle state

    private func handlePhaseChange() {
        wakeFromShrink()
        if state.phase == .recording {
            levelBuffer = Array(repeating: 0, count: 16)
        }
    }

    private var canAutoShrink: Bool { isIdleAndCalm && !hovered }

    private func wakeFromShrink() {
        // Functional size changes stay immediate under Reduce Motion.
        withAnimation(reduceMotion ? nil : Motion.phaseSize) { isShrunkToDot = false }
    }

    // MARK: - Promotion flash (POLISH-04c)

    private func triggerPromotionFlash(if isFlashing: Bool) {
        guard isFlashing, !reduceMotion else { return }
        // Snap to start state (no animation), then animate to faded-out
        // larger ring for a vocabulary update.
        promotionScale = 0.6
        promotionOpacity = 1.0
        withAnimation(Motion.promotionFlash) {
            promotionScale = 1.4
            promotionOpacity = 0.0
        }
    }

    // MARK: - Pill body

    private var pill: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            // macOS 26: interactive Liquid Glass body (refracts the app behind
            // the transparent pill window); older: solid-black fill. Hairline
            // stroke folds in either way.
            .pillGlassBackground(cornerRadius: cornerRadius, borderOpacity: borderOpacity)
            // A brief ring acknowledges a vocabulary update.
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.84, blue: 0.0),    // gold
                                     Color(red: 1.0, green: 0.65, blue: 0.0)],   // amber
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .scaleEffect(promotionScale)
                    .opacity(promotionOpacity)
                    .allowsHitTesting(false)
            )
            // No drop shadow — the Liquid Glass body provides its own edge
            // and depth, and a cast shadow over arbitrary app content reads
            // as heavy/dated next to the glass.
            .padding(.bottom, 4)
    }

    private var isIdleAndCalm: Bool {
        if case .idle = state.phase, !state.showPermissionPrompt { return true }
        return false
    }

    /// True when clicking the pill should open the correction popover.
    /// Only `.success` qualifies, during `.polishing` (clean-first)
    /// nothing has pasted yet, so tapping there would open correction on
    /// the PREVIOUS dictation's token. Keep in sync with
    /// `AppDelegate.handlePillTap`.
    private var isPillTappable: Bool {
        switch state.phase {
        case .success: return true
        case .error(let message): return PillErrorAction.forMessage(message) != nil
        default: return false
        }
    }

    /// VoiceOver label per phase. The pill is the only fixed UI element
    /// of the app for users navigating with VO; without this it reads as
    /// an opaque container.
    private var accessibilityLabelForCurrentPhase: String {
        if state.showPermissionPrompt {
            return "ListenToMe — accessibility permission required"
        }
        switch state.phase {
        case .idle:         return "ListenToMe — idle"
        case .recording:    return "ListenToMe — recording"
        case .transcribing: return "ListenToMe — transcribing"
        case .cleaning:     return "ListenToMe — cleaning up transcript"
        case .polishing:    return "ListenToMe — polishing transcript"
        case .success:      return "ListenToMe — success"
        case .error(let m): return "ListenToMe — error: \(m)"
        case .noSpeech:     return "ListenToMe — no speech detected"
        case .correcting:   return "ListenToMe — editing transcript"
        case .suggestion:   return "ListenToMe — style suggestion available"
        }
    }

    /// VoiceOver hint — what tapping the pill will do, when relevant.
    private var accessibilityHintForCurrentPhase: String {
        switch state.phase {
        case .success: return "Activate to edit the just-pasted transcript"
        case .error(let message):
            if let action = PillErrorAction.forMessage(message) {
                return "Activate to \(action.hint.lowercased())"
            }
            return ""
        case .recording, .transcribing, .cleaning:
            return "Use the cancel button to abort"
        case .polishing:
            return state.canInsertWithoutPolish
                ? "Insert without polish now, or cancel to discard"
                : "Use the cancel button to discard"
        case .suggestion: return "Use Keep or Dismiss to respond"
        default: return ""
        }
    }

    private var borderOpacity: Double { hovered ? 0.65 : 0.45 }

    // MARK: - Sizing

    private var pillWidth: CGFloat {
        PillMetrics.pillWidth(phase: state.phase,
                              showPermissionPrompt: state.showPermissionPrompt,
                              shrunkToDot: isShrunkToDot,
                              hovered: hovered,
                              canInsertWithoutPolish: state.canInsertWithoutPolish)
    }

    private var pillHeight: CGFloat {
        PillMetrics.pillHeight(phase: state.phase,
                               showPermissionPrompt: state.showPermissionPrompt,
                               shrunkToDot: isShrunkToDot)
    }

    private var cornerRadius: CGFloat {
        if state.showPermissionPrompt { return 22 }
        if isShrunkToDot, case .idle = state.phase { return 5 }   // round dot
        if case .idle = state.phase { return 6 }
        if case .correcting = state.phase { return 6 }
        return 17
    }

    private var horizontalPadding: CGFloat {
        if state.showPermissionPrompt { return 18 }
        if isCompact { return 0 }
        return 6
    }

    private var verticalPadding: CGFloat {
        if state.showPermissionPrompt { return 16 }
        return 0
    }

    private var isCompact: Bool {
        PillMetrics.isCompact(phase: state.phase)
    }

    /// Key for the content transition. Prompt takes priority over phase.
    private var visualID: Int {
        if state.showPermissionPrompt { return 100 }
        return phaseID
    }

    private var phaseID: Int {
        switch state.phase {
        case .idle: return 0
        case .recording: return 1
        case .transcribing: return 2
        case .cleaning: return 3
        case .polishing: return 6
        case .success: return 4
        case .error: return 5
        case .correcting: return 7
        case .suggestion: return 8
        case .noSpeech: return 9
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        Group {
            if state.showPermissionPrompt {
                permissionContent.id(100).transition(.opacity)
            } else {
                phaseContent.id(phaseID).transition(.opacity)
            }
        }
        // Geometry changes immediately with the panel. Only content fades,
        // and recording feedback never waits for a transition.
        .animation(reduceMotion || state.phase == .recording ? nil : Motion.phaseSwap,
                   value: visualID)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .idle:
            Color.clear

        case .recording:
            HStack(spacing: 8) {
                Button(action: { AppState.shared.onCancelTap?() }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 24, height: 24)
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Cancel recording")

                CompactWaveformView(levels: reduceMotion
                                    ? Array(repeating: 0.04, count: levelBuffer.count) : levelBuffer)
                    .frame(maxWidth: .infinity)

                Button(action: { AppState.shared.onStopTap?() }) {
                    ZStack {
                        Circle()
                            .fill(DT.statusRecording)
                            .frame(width: 24, height: 24)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 9, height: 9)
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Stop recording")

            }

        case .transcribing:
            HStack(spacing: 12) {
                if reduceMotion {
                    Image(systemName: "hourglass").foregroundStyle(.white)
                } else {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text("Transcribing…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                cancelInflightButton
            }

        case .cleaning:
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(DT.statusProcessing)
                Text("Cleaning up…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                cancelInflightButton
            }

        case .polishing(let rawPreview):
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.statusProcessing.opacity(0.9))
                    .accessibilityHidden(true)
                Text(state.canInsertWithoutPolish ? "Polishing…" : rawPreview)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                PolishingDots()
                    .accessibilityHidden(true)
                if state.canInsertWithoutPolish {
                    Button("Insert without polish") { state.onInsertWithoutPolish?() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                        .buttonStyle(PressableStyle())
                        .fixedSize()
                        .help("Insert the transcript now and stop polishing")
                        .accessibilityLabel("Insert without polish")
                }
                cancelInflightButton
            }

        case .success(let preview):
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DT.statusSuccess)
                if hovered {
                    Text("Edit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : Motion.phaseSwap, value: hovered)
            .help(preview)

        case .error(let message):
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DT.statusWarning)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(message)
                Spacer(minLength: 0)
                if let action = PillErrorAction.forMessage(message) {
                    HStack(spacing: 3) {
                        Text(action.hint)
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                } else {
                    Button("Settings") { MainWindowController.shared.openSettings() }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open ListenToMe settings")
                }
            }

        case .noSpeech:
            // Calm, non-alarming cue — no orange/red, no shake. Blank audio
            // isn't a failure, just nothing to paste.
            HStack(spacing: 10) {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                Text("No speech")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
            }

        case .correcting:
            // Correction popover handles the UI; pill stays minimal so it
            // doesn't compete with the floating edit window.
            Color.clear

        case .suggestion(let bundleId, let tone):
            suggestionContent(bundleId: bundleId, tone: tone)
        }
    }

    @ViewBuilder
    private func suggestionContent(bundleId: String, tone: InferredTone) -> some View {
        let appName = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId)
            .first?.localizedName ?? bundleId
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggesting \(tone.displayLabel) tone for \(appName)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Keep or dismiss")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
            Button(action: { AppState.shared.onSuggestionKeep?() }) {
                Text("Keep")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(PressableStyle())
            Button(action: { AppState.shared.onSuggestionDismiss?() }) {
                Text("Dismiss")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 14)
    }

    /// M5' streaming-partial preview — sits above the pill during
    /// `.recording` / `.transcribing` when the linked engine has
    /// produced a non-empty partial. Empty otherwise (zero layout
    /// impact). Subtle by design: the user is dictating, not reading;
    /// the preview is a confidence cue, not the main UI.
    @ViewBuilder
    private var partialPreviewIfNeeded: some View {
        let visible: Bool = {
            if state.partialText.isEmpty { return false }
            switch state.phase {
            case .recording, .transcribing: return true
            default: return false
            }
        }()
        if visible {
            Text(state.partialText)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
                // Crossfade between partial updates instead of a hard
                // text swap — each 1.5s tick replaces the whole string,
                // and the cut read as flicker.
                .contentTransition(.opacity)
                .lineLimit(2)
                .truncationMode(.head)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: 360)
                .previewGlassBackground(cornerRadius: 10)
                .padding(.bottom, 8)
                .transition(.opacity)
                .animation(reduceMotion ? nil : Motion.phaseSwap, value: state.partialText)
                .accessibilityLabel("Live partial transcript")
                .accessibilityValue(state.partialText)
        }
    }

    /// Compact X button used in `.transcribing`, `.cleaning`, and
    /// `.polishing` so the user can bail on a long-running cleanup or
    /// stuck whisper without waiting for it to time out. Routes through
    /// the same `onCancelTap` callback as the recording-X — AppDelegate
    /// dispatches per-phase.
    private var cancelInflightButton: some View {
        Button(action: { AppState.shared.onCancelTap?() }) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 22, height: 22)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .buttonStyle(PressableStyle())
        .help("Cancel")
        .accessibilityLabel("Cancel")
    }

    // MARK: - Permission card content (rendered inside the morphed pill)

    @ViewBuilder
    private var permissionContent: some View {
        if state.permissionJustGranted {
            permissionGrantedContent
        } else {
            permissionRequiredContent
        }
    }

    /// Brief confirmation beat shown the moment Accessibility is granted,
    /// before the card collapses — so the grant doesn't register as the card
    /// silently vanishing.
    private var permissionGrantedContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(DT.statusSuccess)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Granted")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("You're all set — hold the hotkey to dictate.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }

    private var permissionRequiredContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.red, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    Text("!")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.red)
                }


                VStack(alignment: .leading, spacing: 6) {
                    Text("Accessibility Permission Required")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("ListenToMe needs accessibility access to work properly.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(action: {
                    AppState.shared.showPermissionPrompt = false
                    PillWindow.shared.setInteractive(false)
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 22, height: 22)
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .buttonStyle(PressableStyle())
            }

            HStack {
                Spacer()
                Button(action: {
                    HotkeyMonitor.promptAccessibility()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Open Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableStyle(pressedScale: 0.96, pressedOpacity: 0.85))
            }
        }
    }
}

/// A processing cue with no timeline under Reduce Motion.
private struct PolishingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            dots(lit: nil)
        } else {
            TimelineView(.periodic(from: .now, by: 0.45)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.45)
                dots(lit: step % 3)
            }
        }
    }

    /// `lit == nil` renders all three dots statically at a middle opacity.
    private func dots(lit: Int?) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(DT.statusProcessing.opacity(lit == nil ? 0.6 : (lit == i ? 0.95 : 0.35)))
                    .frame(width: 4, height: 4)
                    .animation(reduceMotion ? nil : Motion.phaseSwap, value: lit)
            }
        }
    }
}
