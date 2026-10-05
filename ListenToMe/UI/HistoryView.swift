import SwiftUI

/// Full transcript browser — every dictation HistoryStore retains,
/// newest first, grouped by day, filterable by text and target app.
/// Rows reuse the shared RecordRow (copy / delete / transform), with
/// the app identity shown since History spans many targets.
struct HistoryView: View {
    @ObservedObject private var history = HistoryStore.shared

    @State private var query = ""
    /// `query` after a short pause; filtering reads this so each keystroke
    /// doesn't re-walk the whole record set.
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    /// nil = all apps; "__other__" matches records with no bundleId.
    @State private var appFilter: String?
    /// How many matching records are currently rendered. Grows in pages as
    /// the user scrolls so a large history isn't all built into the view
    /// tree at once. Reset to one page whenever the filter changes.
    @State private var visibleCount = Self.pageSize
    @State private var showClearConfirm = false
    @FocusState private var searchFocused: Bool
    @StateObject private var undo = UndoCenter()

    // Memoized filter + grouping results, refreshed by `recompute()` only
    // when records, the debounced query, the app filter or the page window
    // change, not on every body evaluation.
    @State private var groups: [DayGroup] = []
    @State private var matchCount = 0
    @State private var shownCount = 0
    @State private var total = 0
    @State private var computed = false

    private static let pageSize = 50

    var body: some View {
        let hasMore = matchCount > shownCount

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: DT.space6) {
                PageHeader(
                    title: "History",
                    subtitle: "Everything you've dictated",
                    icon: "clock",
                    iconTint: .orange
                )

                filterBar(matchCount: matchCount, total: total)

                if computed && matchCount == 0 {
                    emptyState
                } else {
                    ForEach(groups, id: \.day) { group in
                        daySection(group)
                    }
                    if hasMore {
                        loadMoreFooter(shown: shownCount, total: matchCount)
                    }
                }
            }
            .padding(.top, DT.safeAreaTop)
            .padding(.horizontal, DT.space10)
            .padding(.bottom, DT.space10)
            .frame(maxWidth: DT.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .titleBarScrollEdge()
        .undoToast(undo)
        // Cmd+F focuses the search field. Invisible rather than `.hidden()`,
        // which can drop the shortcut.
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        .onAppear { recompute() }
        .onChange(of: history.records) { _, _ in recompute() }
        .onChange(of: query) { _, newValue in scheduleDebounce(newValue) }
        // A filter change resets the window — otherwise a search that matches
        // few records would still report a stale large visibleCount.
        .onChange(of: debouncedQuery) { _, _ in
            visibleCount = Self.pageSize
            recompute()
        }
        .onChange(of: appFilter) { _, _ in
            visibleCount = Self.pageSize
            recompute()
        }
        .onChange(of: visibleCount) { _, _ in recompute() }
        .confirmationDialog(
            "Clear all history?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) {
                HistoryStore.shared.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every dictation record. This can't be undone.")
        }
    }

    /// Delete with a short undo window; restore re-inserts the exact record.
    private func delete(_ record: TranscriptRecord) {
        history.remove(id: record.id)
        undo.show("Transcript deleted") { history.restore(record) }
    }

    private func scheduleDebounce(_ newValue: String) {
        debounceTask?.cancel()
        if newValue.isEmpty {
            debouncedQuery = ""
            return
        }
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            debouncedQuery = newValue
        }
    }

    private func clearQuery() {
        debounceTask?.cancel()
        query = ""
        debouncedQuery = ""
    }

    private func recompute() {
        let filtered = self.filtered
        // Window to the current page before grouping/rendering. prefix is
        // cheap; the win is not building views for the off-window records.
        let windowed = Array(filtered.prefix(visibleCount))
        matchCount = filtered.count
        shownCount = windowed.count
        total = history.records.reduce(0) { $0 + ($1.dismissed ? 0 : 1) }
        groups = dayGroups(from: windowed)
        computed = true
    }

    /// Bottom sentinel: auto-loads the next page when it scrolls into view
    /// (infinite scroll), with a manual button as a fallback.
    private func loadMoreFooter(shown: Int, total: Int) -> some View {
        HStack {
            Spacer()
            Button {
                visibleCount += Self.pageSize
            } label: {
                Text("Load more — showing \(shown) of \(total)")
                    .font(DT.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.pressable)
            Spacer()
        }
        .padding(.vertical, DT.space4)
        .onAppear { visibleCount += Self.pageSize }
    }

    // MARK: - Filtering

    private var filtered: [TranscriptRecord] {
        history.records.filter { record in
            // History is the archive — dismissed dictations are noise
            // here. (Home's Today section deliberately still shows them
            // as same-day feedback that a dictation was discarded.)
            if record.dismissed { return false }
            if let appFilter {
                let key = record.bundleId ?? "__other__"
                if key != appFilter { return false }
            }
            if !debouncedQuery.isEmpty {
                return record.finalText.localizedCaseInsensitiveContains(debouncedQuery)
            }
            return true
        }
    }

    /// Distinct apps present in (undismissed) history, ordered by record
    /// count, for the filter menu.
    private var appsInHistory: [(key: String, name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for r in history.records where !r.dismissed {
            counts[r.bundleId ?? "__other__", default: 0] += 1
        }
        return counts
            .map { (key: $0.key,
                    name: $0.key == "__other__" ? "Other" : AppDisplay.nameAndTint(for: $0.key).0,
                    count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private struct DayGroup {
        let day: Date
        let records: [TranscriptRecord]
    }

    /// Newest-day-first groups; records inside each day stay newest-first
    /// (HistoryStore inserts at the front).
    private func dayGroups(from filtered: [TranscriptRecord]) -> [DayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.timestamp) }
        return grouped
            .map { DayGroup(day: $0.key, records: $0.value) }
            .sorted { $0.day > $1.day }
    }

    // MARK: - Filter bar

    private func filterBar(matchCount: Int, total: Int) -> some View {
        HStack(spacing: DT.space3) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Search transcripts", text: $query)
                    .textFieldStyle(.plain)
                    .font(DT.body)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button {
                        clearQuery()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, DT.space3)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DT.radiusMd, style: .continuous)
                    .fill(DT.surfaceElevated)
            )
            .frame(maxWidth: 360)

            appFilterMenu

            Spacer()

            Text("\(matchCount) of \(total)")
                .font(DT.monoCaption)
                .foregroundStyle(.tertiary)

            if total > 0 {
                Button {
                    showClearConfirm = true
                } label: {
                    Text("Clear all")
                        .font(DT.captionStrong)
                        .foregroundStyle(DT.statusError)
                }
                .buttonStyle(.pressable)
            }
        }
        .animation(Motion.tabFade, value: query.isEmpty)
    }

    private var appFilterMenu: some View {
        Menu {
            Button("All apps") { appFilter = nil }
            Divider()
            ForEach(appsInHistory, id: \.key) { app in
                Button {
                    appFilter = app.key
                } label: {
                    Text("\(app.name)  (\(app.count))")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12))
                Text(appFilterLabel)
                    .font(DT.captionStrong)
                    .lineLimit(1)
            }
            .foregroundStyle(appFilter == nil ? Color.secondary : DT.accent)
            .padding(.horizontal, DT.space3)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DT.radiusMd, style: .continuous)
                    .fill(DT.surfaceElevated)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var appFilterLabel: String {
        guard let appFilter else { return "All apps" }
        return appFilter == "__other__" ? "Other" : AppDisplay.nameAndTint(for: appFilter).0
    }

    // MARK: - Day section

    private func daySection(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: DT.space3) {
            HStack(spacing: DT.space3) {
                Text(dayTitle(group.day))
                    .font(DT.eyebrow)
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Rectangle()
                    .fill(DT.separator)
                    .frame(height: 1)
                Text("\(group.records.count)")
                    .font(DT.monoCaption)
                    .foregroundStyle(.tertiary)
            }

            LazyVStack(spacing: 0) {
                ForEach(group.records) { record in
                    RecordRow(record: record, showApp: true, onDelete: delete)
                    if record.id != group.records.last?.id {
                        Divider().background(DT.separator)
                    }
                }
            }
            .card()
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "TODAY" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        return Self.dayFmt.string(from: day).uppercased()
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f
    }()

    // MARK: - Empty state

    private var emptyState: some View {
        let isFiltered = !debouncedQuery.isEmpty || appFilter != nil
        return EmptyState(
            icon: isFiltered ? "magnifyingglass" : "clock",
            title: isFiltered ? "No transcripts match" : "No dictations yet",
            subtitle: isFiltered
                ? nil
                : "Hold \(Preferences.shared.hotkeyBinding.label) anywhere to start.",
            actionTitle: isFiltered ? "Clear filters" : nil,
            action: isFiltered ? {
                clearQuery()
                appFilter = nil
            } : nil
        )
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}
