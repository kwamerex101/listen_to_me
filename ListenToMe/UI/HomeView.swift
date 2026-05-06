import SwiftUI

struct HomeView: View {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var state = AppState.shared

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: DT.space7) {
                    Text("Welcome back, Rex")
                        .font(DT.pageTitle)

                    heroCard(width: geo.size.width)

                    statsRow(width: geo.size.width)

                    todaySection
                }
                .padding(.top, 60)
                // Margins shrink at narrow widths so the content stays
                // well-proportioned instead of feeling cramped.
                .padding(.horizontal, geo.size.width < 720 ? DT.space6 : DT.space10)
                .padding(.bottom, DT.space10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Hero

    /// `width` is the available horizontal space for the page content area.
    /// We use it to collapse decorative chrome (the right-edge waveform) at
    /// narrow widths so the headline never gets squeezed.
    private func heroCard(width: CGFloat) -> some View {
        let showDecorWaveform = width >= 720

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DT.radiusXl, style: .continuous)
                .fill(DT.heroGradient)

            RoundedRectangle(cornerRadius: DT.radiusXl, style: .continuous)
                .fill(DT.heroGlow)
                .allowsHitTesting(false)

            if showDecorWaveform {
                HStack {
                    Spacer()
                    heroWaveform
                        .frame(width: 220, height: 100)
                        .padding(.trailing, DT.space8)
                        .opacity(0.55)
                }
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: DT.space4) {
                Text("Speak once, ship clean text.")
                    .font(DT.heroDisplay)
                    .italic()
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("Hold Fn + ⌘ anywhere and dictate. AI cleans up automatically.")
                    .font(DT.body)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)

                heroCTA
                    .padding(.top, DT.space2)
            }
            .padding(DT.space7)
            // Constrain text column width when the waveform is visible so
            // the headline never collides with the decoration.
            .frame(
                maxWidth: showDecorWaveform ? max(width - 280, 360) : .infinity,
                alignment: .leading
            )
        }
        .frame(height: 220)
        .animation(.easeInOut(duration: 0.18), value: showDecorWaveform)
    }

    private var heroCTA: some View {
        Button(action: { state.onStartTap?() }) {
            HStack(spacing: 8) {
                if case .recording = state.phase {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                    Text("Recording…")
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Dictate now")
                }
            }
            .font(DT.bodyStrong)
            .foregroundStyle(DT.onAccent)
            .padding(.horizontal, DT.space5)
            .padding(.vertical, 11)
            .background(
                Capsule().fill(DT.accent)
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: DT.accent.opacity(0.35), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.pressable)
        .disabled({
            if case .idle = state.phase { return false }
            if case .recording = state.phase { return false }
            return true
        }())
        .animation(.easeInOut(duration: 0.15), value: state.phase)
    }

    /// Static, decorative waveform — 18 vertical bars whose heights follow a
    /// gentle sine curve. Pure SwiftUI, no Canvas, no work per frame.
    private var heroWaveform: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(0..<18, id: \.self) { i in
                    let phase = Double(i) / 18.0
                    let h = 0.30 + 0.50 * abs(sin(phase * .pi * 2))
                    Capsule()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 4, height: max(8, geo.size.height * h))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Stats row

    /// Stats reflow at narrow widths so each card stays readable:
    /// - ≥780pt → 3 columns
    /// - 560–779pt → 2 columns + 1 wrapping below
    /// - <560pt → single column
    @ViewBuilder
    private func statsRow(width: CGFloat) -> some View {
        let cards: [(String, Color, String, String)] = [
            ("text.alignleft",     DT.accent,    formatBigNumber(history.totalWords), "total words"),
            ("gauge.with.needle",  .purple,      "\(history.averageWPM)",             "wpm avg"),
            ("flame.fill",         .orange,      "\(history.dayStreak)",              "day streak"),
        ]

        if width >= 780 {
            HStack(spacing: DT.space4) {
                ForEach(0..<cards.count, id: \.self) { i in
                    statCard(icon: cards[i].0, tint: cards[i].1, value: cards[i].2, unit: cards[i].3)
                }
            }
        } else if width >= 560 {
            VStack(spacing: DT.space4) {
                HStack(spacing: DT.space4) {
                    statCard(icon: cards[0].0, tint: cards[0].1, value: cards[0].2, unit: cards[0].3)
                    statCard(icon: cards[1].0, tint: cards[1].1, value: cards[1].2, unit: cards[1].3)
                }
                statCard(icon: cards[2].0, tint: cards[2].1, value: cards[2].2, unit: cards[2].3)
            }
        } else {
            VStack(spacing: DT.space4) {
                ForEach(0..<cards.count, id: \.self) { i in
                    statCard(icon: cards[i].0, tint: cards[i].1, value: cards[i].2, unit: cards[i].3)
                }
            }
        }
    }

    private func statCard(icon: String, tint: Color, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: DT.space2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(unit.uppercased())
                    .font(DT.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(DT.statNumber)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DT.space5)
        .background(
            RoundedRectangle(cornerRadius: DT.radiusLg, style: .continuous)
                .fill(DT.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.radiusLg, style: .continuous)
                .strokeBorder(DT.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: DT.space3) {
            HStack(spacing: DT.space3) {
                Text("TODAY")
                    .font(DT.eyebrow)
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Rectangle()
                    .fill(DT.separator)
                    .frame(height: 1)
            }

            if history.todayRecords.isEmpty {
                emptyTodayState
            } else {
                VStack(spacing: 0) {
                    ForEach(history.todayRecords) { record in
                        RecordRow(record: record)
                        if record.id != history.todayRecords.last?.id {
                            Divider()
                                .background(DT.separator)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: DT.radiusLg, style: .continuous)
                        .fill(DT.surfaceCard.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.radiusLg, style: .continuous)
                        .strokeBorder(DT.separator, lineWidth: 0.5)
                )
            }
        }
    }

    private var emptyTodayState: some View {
        HStack(spacing: DT.space3) {
            Image(systemName: "waveform")
                .font(.system(size: 13))
                .foregroundStyle(DT.accent)
            Text("Nothing yet. Hold Fn + ⌘ anywhere to dictate.")
                .font(DT.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DT.space5)
        .padding(.vertical, DT.space5)
        .background(
            RoundedRectangle(cornerRadius: DT.radiusLg, style: .continuous)
                .fill(DT.surfaceCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.radiusLg, style: .continuous)
                .strokeBorder(DT.separator, lineWidth: 0.5)
        )
    }

    private func formatBigNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

private struct RecordRow: View {
    let record: TranscriptRecord
    @ObservedObject private var history = HistoryStore.shared
    @State private var hovered = false
    @State private var copied = false

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: DT.space5) {
            Text(Self.fmt.string(from: record.timestamp))
                .font(DT.monoCaption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
                .padding(.top, 2)

            if record.dismissed {
                Text("This transcription was dismissed.")
                    .font(DT.body)
                    .foregroundStyle(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(record.finalText)
                    .font(DT.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !record.dismissed {
                HStack(spacing: 4) {
                    actionButton(
                        icon: copied ? "checkmark" : "doc.on.doc",
                        help: copied ? "Copied" : "Copy transcript",
                        action: copyText
                    )
                    actionButton(
                        icon: "trash",
                        help: "Delete transcript",
                        action: { history.remove(id: record.id) }
                    )
                }
                .opacity(hovered ? 1 : 0.32)
                .animation(.easeInOut(duration: 0.12), value: hovered)
            }
        }
        .padding(.horizontal, DT.space5)
        .padding(.vertical, DT.space4)
        .background(
            // Subtle accent-tinted hover so the eye lands on the active row
            // without losing the row's neutral "data" feeling.
            hovered
                ? DT.accent.opacity(0.06)
                : Color.clear
        )
        .overlay(alignment: .leading) {
            // Leading-edge accent bar, only visible on hover. Adds visual
            // anchor without permanently colouring the row.
            Rectangle()
                .fill(DT.accent)
                .frame(width: hovered ? 3 : 0)
                .animation(.easeInOut(duration: 0.12), value: hovered)
        }
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }

    private func actionButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovered ? 0.07 : 0))
                )
        }
        .buttonStyle(.pressable)
        .help(help)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.finalText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
