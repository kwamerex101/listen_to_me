import SwiftUI

struct HomeView: View {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var state = AppState.shared
    @Environment(\.windowWidth) private var windowWidth

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.space7) {
                Text("Welcome back, Rex")
                    .font(DT.pageTitle)

                heroCard

                statsRow

                heatmapCard

                todaySection
            }
            .padding(.top, 60)
            .padding(.horizontal, isNarrow ? DT.space6 : DT.space10)
            .padding(.bottom, DT.space10)
            // Cap the content width on very wide screens so the page reads
            // as a focused dashboard instead of stretching infinitely. The
            // outer ScrollView still fills the window; only the content
            // column has a max width.
            .frame(maxWidth: DT.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    Circle().fill(Color.red).frame(width: 7, height: 7)
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

    // MARK: - Stats row (rich KPIs)

    private var statsRow: some View {
        Group {
            if isCompact {
                VStack(spacing: DT.space4) {
                    wpmCard
                    totalWordsCard
                    streakCard
                }
            } else {
                HStack(spacing: DT.space4) {
                    wpmCard
                    totalWordsCard
                    streakCard
                }
                // Force every tile in the row to the tallest tile's height
                // so the gauge, sparkline, and streak cells all line up.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// WPM tile — gauge arc showing the user's average WPM and a label
    /// indicating their position in a coarse percentile band.
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

            Text("\(wpm)")
                .font(DT.statNumber)

            // Gauge fills the rest of the card so all three KPI tiles end
            // up the same height in the row.
            ZStack {
                GaugeArc(value: wpmGaugeValue, tint: .teal)
                VStack(spacing: 0) {
                    Spacer().frame(height: 28)
                    Text(percentileLabel(for: wpm))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(percentileNumber(for: wpm))
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: DT.kpiTileMinHeight, alignment: .topLeading)
        .padding(DT.space5)
        .card()
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
                }
            }

            Text(formatBigNumber(history.totalWords))
                .font(DT.statNumber)

            Text("Last 14 days")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, DT.space1)

            // Sparkline fills the remaining height so this tile matches
            // the WPM card's vertical extent.
            Sparkline(values: metrics.map { Double($0.words) }, tint: DT.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: DT.kpiTileMinHeight, alignment: .topLeading)
        .padding(DT.space5)
        .card()
    }

    /// Streak tile — current count + the past week as day-cells + a
    /// "this week" total below to fill the card and balance with the
    /// other KPIs.
    private var streakCard: some View {
        let week = Array(history.dailyMetrics(lastDays: 7))
        let streak = history.dayStreak
        let activeThisWeek = week.filter { $0.isActive }.count
        let wordsThisWeek = week.reduce(0) { $0 + $1.words }

        return VStack(alignment: .leading, spacing: DT.space3) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("DAY STREAK")
                    .font(DT.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(streak)")
                    .font(DT.statNumber)
                Text(streak == 1 ? "day" : "days")
                    .font(DT.captionStrong)
                    .foregroundStyle(.secondary)
            }

            // Past 7 days as day-cells (filled when active). Cells expand
            // horizontally so the row spans the card.
            GeometryReader { geo in
                let count = week.count
                let gap: CGFloat = 6
                let totalGap = gap * CGFloat(max(count - 1, 0))
                let cellW = max(12, (geo.size.width - totalGap) / CGFloat(max(count, 1)))
                HStack(spacing: gap) {
                    ForEach(week.indices, id: \.self) { i in
                        let active = week[i].isActive
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(active ? Color.orange.opacity(0.85) : DT.surfaceElevated)
                            .frame(width: cellW, height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(DT.separator, lineWidth: 0.5)
                            )
                    }
                }
            }
            .frame(height: 30)

            Spacer(minLength: 0)

            // Footer row — fills remaining vertical space and gives the
            // tile body a balanced bottom edge.
            HStack(spacing: DT.space4) {
                metricChip(
                    label: "this week",
                    value: "\(activeThisWeek)/7 days"
                )
                metricChip(
                    label: "words 7d",
                    value: formatBigNumber(wordsThisWeek)
                )
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DT.kpiTileMinHeight, alignment: .topLeading)
        .padding(DT.space5)
        .card()
    }

    /// Small label/value chip used in the streak tile footer.
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

        return VStack(alignment: .leading, spacing: DT.space4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity")
                    .font(DT.sectionTitle)
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
                Text("Best day: \(history.bestDayWords) words")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(DT.space5)
        .card()
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

    /// Coarse band copy. Labels match common "typing speed" intuition; the
    /// app makes no claim to a real percentile, just an encouraging band.
    private func percentileLabel(for wpm: Int) -> String {
        switch wpm {
        case ..<60:  return "Steady"
        case ..<90:  return "Solid"
        case ..<120: return "Fast"
        case ..<150: return "Top"
        default:     return "Top"
        }
    }
    private func percentileNumber(for wpm: Int) -> String {
        switch wpm {
        case ..<60:  return ""
        case ..<90:  return "50%"
        case ..<120: return "25%"
        case ..<150: return "10%"
        default:     return "5%"
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
private struct GaugeArc: View {
    var value: Double            // 0...1
    var tint: Color = .teal

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
/// crisp KPI feel — nothing fancy, deliberately undersized.
private struct Sparkline: View {
    var values: [Double]
    var tint: Color = .teal

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count >= 2 {
                    // Area fill
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
                    // Line
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
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
                                let intensity = Double(day.words) / Double(topWords)
                                let isToday = cal.isDateInToday(day.date)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Self.color(forIntensity: intensity))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .strokeBorder(
                                                isToday ? Color.orange : DT.separator,
                                                lineWidth: isToday ? 1.5 : 0.5
                                            )
                                    )
                                    .frame(width: cell, height: cell)
                                    .help("\(formattedDate(day.date)) — \(day.words) words")
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
    private func formattedDate(_ d: Date) -> String { Self.displayFmt.string(from: d) }
}

// MARK: - Today record row

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
        .background(hovered ? DT.accent.opacity(0.06) : Color.clear)
        .overlay(alignment: .leading) {
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
