import SwiftUI

struct HomeView: View {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var state = AppState.shared
    @Environment(\.windowWidth) private var windowWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the dashboard entrance choreography (number roll-up,
    /// gauge sweep, sparkline draw). Flipped once on first appear;
    /// under reduce-motion everything starts in its final state.
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.space7) {
                Text("Welcome back, Rex")
                    .font(DT.pageTitle)

                heroCard

                statsRow

                heatmapCard

                appUsageCard

                todaySection
            }
            .padding(.top, DT.safeAreaTop)
            .padding(.horizontal, isNarrow ? DT.space6 : DT.space10)
            .padding(.bottom, DT.space10)
            // Cap the content width on very wide screens so the page reads
            // as a focused dashboard instead of stretching infinitely. The
            // outer ScrollView still fills the window; only the content
            // column has a max width.
            .frame(maxWidth: DT.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.9)) {
                    appeared = true
                }
            }
        }
    }

    private var isNarrow: Bool { windowWidth < DT.narrowBreakpoint }
    private var isCompact: Bool { windowWidth < DT.compactBreakpoint }

    // MARK: - Hero

    private var heroCard: some View {
        let showDecorWaveform = !isNarrow

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
        }
        .frame(height: 220)
        .animation(.easeInOut(duration: 0.18), value: showDecorWaveform)
    }

    private var heroCTA: some View {
        Button(action: { state.onStartTap?() }) {
            HStack(spacing: 8) {
                if case .recording = state.phase {
                    Circle().fill(DT.statusRecording).frame(width: 7, height: 7)
                    Text("Recording…")
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Dictate now")
                }
            }
        }
        .buttonStyle(.primary)
        .disabled({
            if case .idle = state.phase { return false }
            if case .recording = state.phase { return false }
            return true
        }())
        .animation(.easeInOut(duration: 0.15), value: state.phase)
    }

    private var heroWaveform: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(0..<18, id: \.self) { i in
                    HeroBar(index: i, maxHeight: geo.size.height, animate: !reduceMotion)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// One decorative hero bar. Each bar slowly breathes between its base
    /// height and a slightly taller one on its own phase-shifted cadence,
    /// so the waveform reads as alive without drawing attention. Driven
    /// by Core Animation repeatForever (GPU-cheap, no per-frame SwiftUI
    /// re-evaluation). Static under reduce-motion.
    private struct HeroBar: View {
        let index: Int
        let maxHeight: CGFloat
        let animate: Bool
        @State private var up = false

        private var baseFrac: Double { 0.30 + 0.50 * abs(sin(Double(index) / 18.0 * .pi * 2)) }

        var body: some View {
            let base = max(8, maxHeight * baseFrac)
            Capsule()
                .fill(Color.white.opacity(0.55))
                .frame(width: 4, height: base)
                .scaleEffect(y: up ? 1.18 : 0.92, anchor: .center)
                .onAppear {
                    guard animate else { return }
                    withAnimation(
                        .easeInOut(duration: 1.4 + Double(index % 5) * 0.13)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.09)
                    ) {
                        up = true
                    }
                }
        }
    }

    // MARK: - Stats row (rich KPIs)

    private var statsRow: some View {
        Group {
            if isCompact {
                VStack(spacing: DT.space4) {
                    wpmCard
                    totalWordsCard
                }
            } else {
                HStack(spacing: DT.space4) {
                    wpmCard
                    totalWordsCard
                }
                // Force every tile in the row to the tallest tile's height
                // so the gauge, sparkline, and streak cells all line up.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// WPM tile — gauge arc showing the user's average WPM on a fixed
    /// 0–200 scale with a single pace word in the center. (The old
    /// pseudo-percentile "25%" read as a third competing number with no
    /// clear meaning; one scale + one word is the whole story.)
    private var wpmCard: some View {
        let wpm = history.averageWPM
        return VStack(alignment: .leading, spacing: DT.space3) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.teal)
                Text("WORDS PER MINUTE")
                    .font(DT.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }

            rollupNumber(wpm)

            // Gauge fills the rest of the card so the KPI tiles end up
            // the same height in the row. Sweeps in from zero on appear.
            ZStack {
                GaugeArc(value: appeared ? wpmGaugeValue : 0, tint: .teal)
                VStack(spacing: 2) {
                    Spacer().frame(height: 28)
                    Text(paceLabel(for: wpm))
                        .font(.system(size: 16, weight: .bold))
                    Text("of 200 wpm")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: DT.kpiTileMinHeight, alignment: .topLeading)
        .padding(DT.space5)
        .card()
    }

    /// Big KPI number that rolls up from zero on first appear via the
    /// numeric-text content transition. Under reduce-motion `appeared`
    /// starts true-without-animation, so it renders the final value.
    private func rollupNumber(_ value: Int) -> some View {
        Text(formatBigNumber(appeared ? value : 0))
            .font(DT.statNumber)
            .contentTransition(.numericText(value: Double(appeared ? value : 0)))
    }

    /// Total words tile — large number + week-over-week growth chip if
    /// there's enough data, plus a daily-word-count sparkline that fills
    /// the rest of the card so it lines up with the WPM gauge.
    private var totalWordsCard: some View {
        let metrics = history.dailyMetrics(lastDays: 14)
        let growth = history.weekOverWeekGrowth
        return VStack(alignment: .leading, spacing: DT.space3) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.accent)
                Text("TOTAL WORDS")
                    .font(DT.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                if let g = growth {
                    growthChip(g)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: growth != nil)

            rollupNumber(history.totalWords)

            Text("Last 14 days")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, DT.space1)

            // Sparkline fills the remaining height so this tile matches
            // the WPM card's vertical extent. Draws in left-to-right.
            Sparkline(values: metrics.map { Double($0.words) }, tint: DT.accent,
                      progress: appeared ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: DT.kpiTileMinHeight, alignment: .topLeading)
        .padding(DT.space5)
        .card()
    }

    /// Small label/value chip used in the heatmap card footer.
    private func metricChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(DT.captionStrong.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Heatmap card (GitHub-style)

    private var heatmapCard: some View {
        // Show more weeks on wider windows so the heatmap genuinely fills
        // the card. 12 at compact, up to 26 at the widest.
        let weeks: Int = {
            switch windowWidth {
            case ..<DT.compactBreakpoint: return 12
            case ..<1100:                 return 16
            case ..<1320:                 return 20
            default:                      return 26
            }
        }()

        let week = Array(history.dailyMetrics(lastDays: 7))
        let streak = history.dayStreak
        let activeThisWeek = week.filter { $0.isActive }.count
        let wordsThisWeek = week.reduce(0) { $0 + $1.words }

        return VStack(alignment: .leading, spacing: DT.space4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity")
                    .font(DT.sectionTitle)
                // Streak lives with the activity history it's derived
                // from — it used to be a third KPI tile that retold the
                // same story as the heatmap's last column.
                if streak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("\(streak)-day streak")
                            .font(DT.captionStrong)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, DT.space2)
                }
                Spacer()
                Text("LAST \(weeks) WEEKS")
                    .font(DT.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }

            // The heatmap sizes its own cells based on the available width
            // (see ActivityHeatmap GeometryReader) so it fills horizontally.
            ActivityHeatmap(metrics: history.heatmapMetrics(weeks: weeks), weeks: weeks)
                .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Text("Less")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(ActivityHeatmap.color(forIntensity: Double(level) / 4.0))
                        .frame(width: 10, height: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(DT.separator, lineWidth: 0.5)
                        )
                }
                Text("More")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                metricChip(label: "this week", value: "\(activeThisWeek)/7 days")
                metricChip(label: "words 7d", value: formatBigNumber(wordsThisWeek))
                metricChip(label: "best day", value: "\(history.bestDayWords)w")
            }
        }
        .padding(DT.space5)
        .card()
    }

    // MARK: - Per-app usage

    /// "Where you dictate" — horizontal-bar breakdown by target app over
    /// the last 30 days. Hidden when there's no data yet (legacy users
    /// without `bundleId` history wouldn't see anything useful).
    @ViewBuilder
    private var appUsageCard: some View {
        let usage = history.appUsageBreakdown(lastDays: 30)
        if !usage.isEmpty {
            let topByWords = max(usage.first?.words ?? 1, 1)
            let totalDictations = usage.reduce(0) { $0 + $1.dictations }

            VStack(alignment: .leading, spacing: DT.space4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Where you dictate")
                        .font(DT.sectionTitle)
                    Spacer()
                    Text("LAST 30 DAYS · \(totalDictations) DICTATIONS")
                        .font(DT.eyebrow)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: DT.space2) {
                    ForEach(usage.prefix(8)) { u in
                        appUsageRow(u, scale: topByWords)
                    }
                }
            }
            .padding(DT.space5)
            .card()
        }
    }

    private func appUsageRow(_ usage: HistoryStore.AppUsage, scale: Int) -> some View {
        let (name, tint) = appDisplay(for: usage.bundleId)
        let pct = Double(usage.words) / Double(scale)
        return HStack(spacing: DT.space3) {
            // Tint dot — keeps this row's app identity at a glance.
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            Text(name)
                .font(DT.body)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            // Bar — fills proportional to the row's share of the top app.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DT.surfaceElevated)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint.opacity(0.85))
                        .frame(width: max(8, geo.size.width * pct))
                }
            }
            .frame(height: 12)

            Text("\(usage.words)w")
                .font(DT.monoCaption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            Text("·")
                .foregroundStyle(.tertiary)

            Text("\(usage.dictations)")
                .font(DT.monoCaption)
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    /// Shared resolver — see AppDisplay in RecordRow.swift.
    private func appDisplay(for bundleId: String?) -> (String, Color) {
        AppDisplay.nameAndTint(for: bundleId)
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
                            Divider().background(DT.separator)
                        }
                    }
                }
                .card()
            }
        }
    }

    private var emptyTodayState: some View {
        HStack(spacing: DT.space3) {
            Image(systemName: "waveform")
                .font(.system(size: 13))
                .foregroundStyle(DT.accent)
            Text("Nothing yet today. Hold Fn + ⌘ anywhere to dictate.")
                .font(DT.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DT.space5)
        .padding(.vertical, DT.space5)
        .card()
    }

    // MARK: - Helpers

    private func formatBigNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Map WPM to a 0..1 gauge value. 200 wpm pegs the gauge.
    private var wpmGaugeValue: Double {
        min(1.0, max(0.0, Double(history.averageWPM) / 200.0))
    }

    /// Coarse pace word. Matches common "typing speed" intuition — an
    /// encouraging band, not a claimed percentile.
    private func paceLabel(for wpm: Int) -> String {
        switch wpm {
        case ..<60:  return "Steady"
        case ..<90:  return "Solid"
        case ..<120: return "Fast"
        default:     return "Top speed"
        }
    }

    private func growthChip(_ g: Double) -> some View {
        let positive = g >= 0
        let pct = Int(abs(g) * 100)
        return HStack(spacing: 4) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text("\(pct)%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
            Text("vs prev wk")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(positive ? Color.green : Color.red)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill((positive ? Color.green : Color.red).opacity(0.12))
        )
    }
}

// MARK: - Sub-components

/// Half-circle gauge arc that fills a `value` 0...1 fraction. Background
/// arc plus a foreground arc with a rounded line cap. Pure Path drawing.
/// `value` is animatable so the arc sweeps when driven by withAnimation
/// (dashboard entrance) instead of snapping.
private struct GaugeArc: View, Animatable {
    var value: Double            // 0...1
    var tint: Color = .teal

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = min(w / 2 - 6, h - 6)
            let center = CGPoint(x: w / 2, y: h)

            ZStack {
                Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: .degrees(180),
                             endAngle: .degrees(360),
                             clockwise: false)
                }
                .stroke(DT.surfaceElevated, style: StrokeStyle(lineWidth: 12, lineCap: .round))

                Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: .degrees(180),
                             endAngle: .degrees(180 + 180 * value),
                             clockwise: false)
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
            }
        }
    }
}

/// Compact line+area sparkline. Smoothed via straight-line segments for a
/// crisp KPI feel — nothing fancy, deliberately undersized. `progress`
/// (0...1) trims the line left-to-right and fades the area in, so the
/// chart draws itself on dashboard entrance.
private struct Sparkline: View, Animatable {
    var values: [Double]
    var tint: Color = .teal
    var progress: Double = 1

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count >= 2 {
                    // Area fill — fades in as the line draws.
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.30), tint.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .opacity(progress)
                    // Line — trimmed by progress for the draw-in.
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .trimmedPath(from: 0, to: CGFloat(progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let max = (values.max() ?? 1)
        let safeMax = max == 0 ? 1 : max
        let stepX = values.count > 1 ? size.width / CGFloat(values.count - 1) : size.width
        return values.enumerated().map { idx, v in
            let x = CGFloat(idx) * stepX
            let y = size.height - CGFloat(v / safeMax) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}

/// GitHub-style activity heatmap. Each column is one week (Sunday at the
/// top, Saturday at the bottom); each row is a day-of-week. Cells are
/// coloured by intensity (word count relative to the top observed value),
/// and SIZE responsively to fill the available card width.
struct ActivityHeatmap: View {
    let metrics: [HistoryStore.DailyMetric]
    let weeks: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the column-by-column entrance stagger.
    @State private var appeared = false

    /// Map a 0..1 intensity to a discrete colour bucket (4 visible levels +
    /// neutral). Mirrors GitHub's contribution graph palette but in our
    /// accent (teal) so it threads the design language.
    static func color(forIntensity x: Double) -> Color {
        switch x {
        case ..<0.001: return DT.surfaceElevated
        case ..<0.25:  return Color.teal.opacity(0.25)
        case ..<0.50:  return Color.teal.opacity(0.45)
        case ..<0.75:  return Color.teal.opacity(0.70)
        default:       return Color.teal
        }
    }

    /// Day-of-week labels column width. Kept narrow so most of the card
    /// is the actual heatmap.
    private let labelColumnWidth: CGFloat = 28
    private let gap: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            // Lay out by computing a single cell size that fills the
            // available width given `weeks` columns + the label gutter.
            let availableW = geo.size.width - labelColumnWidth
            let totalGap = gap * CGFloat(max(weeks - 1, 0))
            let cell = max(10, min(28, (availableW - totalGap) / CGFloat(max(weeks, 1))))

            let columns = weekColumns()
            let topWords = max(1, metrics.map { $0.words }.max() ?? 1)
            let cal = Calendar.current

            VStack(alignment: .leading, spacing: gap) {
                ForEach(0..<7, id: \.self) { rowIdx in
                    HStack(spacing: gap) {
                        Text(rowIdx % 2 == 1 ? Self.dayLabel(rowIdx) : "")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(width: labelColumnWidth - gap, alignment: .leading)

                        ForEach(columns.indices, id: \.self) { colIdx in
                            let col = columns[colIdx]
                            if rowIdx < col.count {
                                let day = col[rowIdx]
                                HeatCell(
                                    day: day,
                                    intensity: Double(day.words) / Double(topWords),
                                    isToday: cal.isDateInToday(day.date),
                                    size: cell
                                )
                                // Entrance: columns fade in oldest-first.
                                // Reduce-motion renders final state directly.
                                .opacity(appeared ? 1 : 0)
                                .animation(
                                    reduceMotion ? nil :
                                        .easeOut(duration: 0.25).delay(Double(colIdx) * 0.02),
                                    value: appeared
                                )
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Heatmap height = 7 rows × cell + 6 gaps. Compute a sensible
        // intrinsic height so the card doesn't collapse to zero.
        .frame(height: 7 * 22 + 6 * gap)
        .onAppear { appeared = true }
    }

    /// One heatmap day-cell with hover feedback — slight scale + accent
    /// border so the .help tooltip's target feels responsive while the
    /// tooltip delay runs.
    private struct HeatCell: View {
        let day: HistoryStore.DailyMetric
        let intensity: Double
        let isToday: Bool
        let size: CGFloat
        @State private var hovered = false

        var body: some View {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ActivityHeatmap.color(forIntensity: intensity))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            hovered ? DT.accent : (isToday ? Color.orange : DT.separator),
                            lineWidth: (hovered || isToday) ? 1.5 : 0.5
                        )
                )
                .frame(width: size, height: size)
                .scaleEffect(hovered ? 1.15 : 1.0)
                .animation(.spring(response: 0.18, dampingFraction: 0.7), value: hovered)
                .onHover { hovered = $0 }
                .help("\(ActivityHeatmap.displayFmt.string(from: day.date)) — \(day.words) words")
        }
    }

    /// Slice the metric series into columns of length 7 (one per week),
    /// padding the leading week with empty days as needed so day-of-week
    /// alignment matches the row labels (Sun at top → Sat at bottom).
    private func weekColumns() -> [[HistoryStore.DailyMetric]] {
        let cal = Calendar.current
        // We want each column to start on Sunday.
        guard let first = metrics.first else { return [] }
        let firstWeekday = cal.component(.weekday, from: first.date) - 1   // 0 = Sun
        var padded = Array(repeating: HistoryStore.DailyMetric(date: .distantPast, words: 0, wpm: 0), count: firstWeekday)
        padded.append(contentsOf: metrics)

        var out: [[HistoryStore.DailyMetric]] = []
        var i = 0
        while i < padded.count {
            let chunk = Array(padded[i..<min(i + 7, padded.count)])
            out.append(chunk)
            i += 7
        }
        return out
    }

    private static func dayLabel(_ row: Int) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][row]
    }

    private static let displayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
