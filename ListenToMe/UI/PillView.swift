import SwiftUI

/// Horizontal-translation shake for the error state. Standard SwiftUI
/// recipe — animates `animatableData` and emits a sin-wave displacement.
private struct Shake: GeometryEffect {
    var amount: CGFloat = 5
    var shakesPerUnit: CGFloat = 4
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = amount * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

struct PillView: View {
    @ObservedObject var state: AppState = .shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var levelBuffer: [Float] = Array(repeating: 0, count: 16)

    // Idle motion — border opacity + body scale, both autoreversed.
    @State private var idleBreathOn: Bool = false

    // Recording motion — red-dot heartbeat, separate from level reactivity.
    @State private var recordPulse: Bool = false

    // Permission card icon spring-in.
    @State private var permissionIconPop: Bool = false

    // Press-pop on entering recording: 1.0 → 1.06 → 1.0.
    @State private var pressPop: CGFloat = 1.0

    // Error shake — increment to fire one shake animation.
    @State private var shakeTrigger: CGFloat = 0

    // Success halo — ripples out behind the checkmark.
    @State private var haloScale: CGFloat = 0.6
    @State private var haloOpacity: Double = 0

    // Dismissal exhale — flipped on idle entry to soften the disappearance.
    @State private var exhaleY: CGFloat = 0
    @State private var exhaleOpacity: Double = 1

    // Silence-dim (POLISH-04a) — fade waveform after sustained quiet,
    // wake instantly on speech return. Replaces (does not stack on) the
    // level-reactive scale, honouring the perf-budget cap of 2 concurrent
    // infinite springs (heartbeat + record-pulse).
    @State private var silenceTimer: Timer?
    @State private var silenceDimmed: Bool = false

    // Promotion-flash (POLISH-04c) — gold ring overlay fired when the
    // dictionary auto-promotes (or the user manually accepts) a candidate.
    @State private var promotionScale: CGFloat = 0.6
    @State private var promotionOpacity: Double = 0.0

    // Hover lift — cursor over the pill triggers a subtle scale, border,
    // and shadow bump so the pill feels reactive even when not in a
    // click-bearing phase.
    @State private var hovered: Bool = false


    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            pill
                .frame(width: pillWidth, height: pillHeight)
                .scaleEffect(rootScale)
                .opacity(exhaleOpacity)
                .offset(y: exhaleY)
                .modifier(Shake(animatableData: shakeTrigger))
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabelForCurrentPhase)
                .accessibilityHint(accessibilityHintForCurrentPhase)
                .accessibilityAddTraits(isPillTappable ? .isButton : [])
                .animation(Motion.phaseSize, value: pillWidth)
                .animation(Motion.phaseSize, value: pillHeight)
                .animation(Motion.phaseSwap, value: visualID)
                .animation(Motion.hoverLift, value: hovered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: state.level) { _, newValue in
            levelBuffer.removeFirst()
            levelBuffer.append(newValue)
            updateSilenceState()
        }
        .onChange(of: phaseID) { _, _ in
            handlePhaseChange()
        }
        .onChange(of: state.flashPromotion) { _, isFlashing in
            triggerPromotionFlash(if: isFlashing)
        }
    }

    // MARK: - Phase-driven motion triggers

    private func handlePhaseChange() {
        // Always clear any silence-dim state when leaving recording —
        // mitigates T-05-03 (timer leak on phase exit).
        if state.phase != .recording {
            silenceTimer?.invalidate()
            silenceTimer = nil
            silenceDimmed = false
        }

        switch state.phase {
        case .recording:
            levelBuffer = Array(repeating: 0, count: 16)
            triggerPressPop()
            cancelExhale()
        case .success:
            triggerSuccessHalo()
            cancelExhale()
        case .error:
            withAnimation(Motion.shake) { shakeTrigger += 1 }
            cancelExhale()
        case .idle:
            // Only exhale if we're returning from a meaningful phase, not on
            // app launch (where pill starts in idle).
            triggerExhale()
        case .transcribing, .cleaning, .polishing, .correcting, .suggestion:
            cancelExhale()
        }
    }

    // MARK: - Promotion flash (POLISH-04c)

    private func triggerPromotionFlash(if isFlashing: Bool) {
        guard isFlashing else { return }
        // Snap to start state (no animation), then animate to faded-out
        // larger ring. Mirrors the success-halo shape — sibling overlay.
        promotionScale = 0.6
        promotionOpacity = 1.0
        withAnimation(Motion.promotionFlash) {
            promotionScale = 1.4
            promotionOpacity = 0.0
        }
    }

    // MARK: - Silence-dim (POLISH-04a / Wispr W4)

    /// Smoothed, unsigned RMS over the most recent buffer slice. Mirrors
    /// `smoothedLevel` but bounded to the tail so it tracks live silence.
    private var silenceSmoothed: Float {
        let tail = levelBuffer.suffix(8)
        guard !tail.isEmpty else { return 0 }
        return tail.reduce(0, +) / Float(tail.count)
    }

    private func updateSilenceState() {
        guard state.phase == .recording else { return }
        let smoothed = silenceSmoothed

        if smoothed < 0.02 {
            // Sustained quiet — arm the dim timer (5s) if not already running
            // and not already dimmed.
            if !silenceDimmed, silenceTimer == nil {
                silenceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                    Task { @MainActor in
                        withAnimation(Motion.silenceDim) {
                            silenceDimmed = true
                        }
                        silenceTimer = nil
                    }
                }
            }
        } else if smoothed > 0.05 {
            // Speech is back — wake instantly, cancel any pending dim.
            silenceTimer?.invalidate()
            silenceTimer = nil
            if silenceDimmed {
                withAnimation(Motion.silenceWake) {
                    silenceDimmed = false
                }
            }
        }
    }


    private func triggerPressPop() {
        withAnimation(Motion.pressUp) { pressPop = 1.06 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(Motion.pressDown) { pressPop = 1.0 }
        }
    }

    private func triggerSuccessHalo() {
        haloScale = 0.6
        haloOpacity = 1
        withAnimation(Motion.halo) {
            haloScale = 1.6
            haloOpacity = 0
        }
    }

    private func triggerExhale() {
        // Brief downward drift + fade, then snap back to 1.0/0 so the next
        // phase entry doesn't inherit a faded state.
        withAnimation(Animation.easeIn(duration: 0.28)) {
            exhaleOpacity = 0
            exhaleY = 4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            exhaleY = 0
            exhaleOpacity = 1
        }
    }

    private func cancelExhale() {
        // If user re-presses mid-exhale, immediately restore visibility.
        if exhaleOpacity < 1 || exhaleY != 0 {
            exhaleOpacity = 1
            exhaleY = 0
        }
    }

    // MARK: - Pill body

    /// Composite scale from press-pop, idle breath, and hover lift.
    /// Hover bump is small (≤4%) so it reads as "alive" rather than "expanding".
    private var rootScale: CGFloat {
        let breathFactor: CGFloat = (isIdleAndCalm && idleBreathOn) ? 0.97 : 1.0
        let hoverFactor:  CGFloat = hovered ? 1.04 : 1.0
        return pressPop * breathFactor * hoverFactor
    }

    private var pill: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
            )
            // POLISH-04(c) — gold promotion-flash ring (sibling to success halo).
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
            // Layered shadow: a crisp inner edge that defines the pill against
            // light backgrounds, plus an ambient cloud that gives depth. Hover
            // intensifies the ambient layer so the pill visibly "lifts".
            .shadow(color: .black.opacity(0.28), radius: 1.0, x: 0, y: 0.5)
            .shadow(
                color: .black.opacity(hovered ? 0.62 : 0.46),
                radius: isCompact ? (hovered ? 14 :  9)
                                  : (hovered ? 26 : 19),
                x: 0,
                y: isCompact ? (hovered ?  7 :  4)
                             : (hovered ? 14 : 10)
            )
            .padding(.bottom, 4)
            .onAppear {
                // Both breath axes share one timeline so they stay in phase.
                // Skip when reduce-motion is on — system honors the user's
                // vestibular preference; an infinite gentle pulse still
                // counts as motion.
                if !reduceMotion {
                    withAnimation(Motion.idleBreath) {
                        idleBreathOn = true
                    }
                }
            }
    }

    private var isIdleAndCalm: Bool {
        if case .idle = state.phase, !state.showPermissionPrompt { return true }
        return false
    }

    /// True when clicking the pill should open the correction popover.
    private var isPillTappable: Bool {
        switch state.phase {
        case .success, .polishing: return true
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
        case .correcting:   return "ListenToMe — editing transcript"
        case .suggestion:   return "ListenToMe — style suggestion available"
        }
    }

    /// VoiceOver hint — what tapping the pill will do, when relevant.
    private var accessibilityHintForCurrentPhase: String {
        switch state.phase {
        case .success, .polishing: return "Activate to edit the just-pasted transcript"
        case .recording, .transcribing, .cleaning:
            return "Use the cancel button to abort"
        case .suggestion: return "Use Keep or Dismiss to respond"
        default: return ""
        }
    }

    /// Border opacity tracks the idle breath but stays visible elsewhere.
    /// Hover adds a small bump so the edge crispens when the cursor enters.
    private var borderOpacity: Double {
        let base: Double
        if isIdleAndCalm {
            base = idleBreathOn ? 0.6 : 0.3
        } else {
            base = 0.45
        }
        return min(base + (hovered ? 0.25 : 0), 0.95)
    }

    // MARK: - Sizing

    private var pillWidth: CGFloat {
        if state.showPermissionPrompt { return 440 }
        switch state.phase {
        case .idle:         return 48
        case .recording:    return 176
        case .transcribing: return 176
        case .cleaning:     return 176
        case .polishing:    return 200
        case .success:      return 60
        case .error:        return 280
        case .correcting:   return 48
        case .suggestion:   return 400
        }
    }

    private var pillHeight: CGFloat {
        if state.showPermissionPrompt { return 170 }
        if case .idle = state.phase { return 12 }
        if case .correcting = state.phase { return 12 }
        if case .suggestion = state.phase { return 56 }
        return 34
    }

    private var cornerRadius: CGFloat {
        if state.showPermissionPrompt { return 22 }
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
        if case .idle = state.phase { return true }
        if case .correcting = state.phase { return true }
        return false
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
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if state.showPermissionPrompt {
            permissionContent
                .id(100)
                .transition(
                    .scale(scale: 0.85, anchor: .center)
                        .combined(with: .opacity)
                )
        } else {
            phaseContent
                .id(phaseID)
                .transition(
                    .scale(scale: 0.7, anchor: .center)
                        .combined(with: .opacity)
                )
        }
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

                ZStack {
                    CompactWaveformView(levels: levelBuffer)
                        .opacity(silenceDimmed ? 0.4 : 1.0)
                    if silenceDimmed {
                        Image(systemName: "mic.slash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: { AppState.shared.onStopTap?() }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 24, height: 24)
                            .scaleEffect(stopButtonScale)
                            .shadow(color: .red.opacity(recordPulse ? 0.55 : 0.15),
                                    radius: recordPulse ? 6 : 2)
                            .animation(Motion.stopReact, value: smoothedLevel)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 9, height: 9)
                    }
                }
                .buttonStyle(PressableStyle())
                .onAppear {
                    recordPulse = false
                    if !reduceMotion {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            recordPulse = true
                        }
                    }
                }
            }

        case .transcribing:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small).tint(.white)
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
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse)
                Text("Cleaning up…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                cancelInflightButton
            }

        case .polishing(let rawPreview):
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green.opacity(0.9))
                Text(rawPreview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                PolishingDots()
                cancelInflightButton
            }

        case .success:
            ZStack {
                // Halo behind the checkmark — green ring expands and fades.
                Circle()
                    .strokeBorder(Color.green.opacity(0.85), lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .scaleEffect(haloScale)
                    .opacity(haloOpacity)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
                    .scaleEffect(haloOpacity > 0 ? 1.0 : 1.0) // placeholder
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }

        case .error(let message):
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
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

    /// Smoothed audio level — average of the level buffer. The buffer is
    /// already updated ~30Hz by the audio recorder, so a flat mean gives
    /// us a stable signal that maps well to a scale modifier.
    private var smoothedLevel: CGFloat {
        let sum = levelBuffer.reduce(0, +)
        return CGFloat(sum) / CGFloat(max(levelBuffer.count, 1))
    }

    /// Composite scale for the recording stop dot:
    /// heartbeat × audio reactivity, capped to a sensible range.
    private var stopButtonScale: CGFloat {
        let heartbeat: CGFloat = recordPulse ? 1.0 : 0.94
        let reactive: CGFloat = 1.0 + (smoothedLevel * 0.18)
        return heartbeat * reactive
    }

    // MARK: - Permission card content (rendered inside the morphed pill)

    private var permissionContent: some View {
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
                .scaleEffect(permissionIconPop ? 1.0 : 0.1)
                .opacity(permissionIconPop ? 1 : 0)
                .onAppear {
                    permissionIconPop = false
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.15)) {
                        permissionIconPop = true
                    }
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

/// Three dots that fade in sequence — the "polishing in background" cue.
/// Quiet on purpose: the user has already moved on, so this is a status
/// glance, not a demand for attention.
private struct PolishingDots: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.purple.opacity(phase == i ? 0.95 : 0.35))
                    .frame(width: 4, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
