import SwiftUI
import AppKit

/// Style tab — lists each app for which a tone has been inferred, shows the
/// current inferred + accepted tones plus a sample-count hint, and exposes a
/// Revert button for any app where a tone was accepted.
struct StyleView: View {
    @ObservedObject private var store = StyleStore.shared
    @ObservedObject private var samples = StyleSamplesStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.space6) {
                PageHeader(
                    title: "Style",
                    subtitle: "ListenToMe learns how you write into each app and adjusts cleanup automatically. After 20 dictations into the same app, a tone is inferred. Keep what fits; revert any that do not.",
                    icon: "textformat",
                    iconTint: .indigo
                )

                if store.entries.isEmpty {
                    EmptyState(
                        icon: "wand.and.stars",
                        title: "No tone inferred yet",
                        subtitle: "Keep dictating — once any app has 20+ dictations, the inferred tone for that app will appear here."
                    )
                } else {
                    list
                }
            }
            .padding(.top, DT.safeAreaTop)
            .padding(.horizontal, DT.space10)
            .padding(.bottom, DT.space10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(store.entries) { entry in
                row(entry)
                if entry.id != store.entries.last?.id {
                    Divider().background(DT.separator)
                }
            }
        }
        .card()
    }

    private func row(_ entry: StyleEntry) -> some View {
        let appName = NSRunningApplication
            .runningApplications(withBundleIdentifier: entry.bundleId)
            .first?.localizedName ?? entry.bundleId
        let count = samples.count(for: entry.bundleId)

        return HStack(alignment: .center, spacing: DT.space4) {
            // App identity column
            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(DT.bodyStrong)
                Text(entry.bundleId)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 220, alignment: .leading)

            Spacer()

            // Inferred tone pill (always visible)
            tonePill(label: "inferred", value: entry.inferredTone.displayLabel, tint: .secondary)

            // Accepted tone pill (only when set, more prominent — accent)
            if let accepted = entry.acceptedTone {
                tonePill(label: "accepted", value: accepted.displayLabel, tint: DT.accent, prominent: true)
            }

            // Sample count
            Text("\(count) samples")
                .font(DT.monoCaption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, DT.space2)

            // Revert button
            if entry.acceptedTone != nil {
                Button("Revert") { store.revert(bundleId: entry.bundleId) }
                    .buttonStyle(.secondary)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, DT.space5)
        .padding(.vertical, DT.space4)
        .hoverableRow(cornerRadius: 0)
    }

    /// Compact label pill — `label` in muted small caps + `value` styled by
    /// the tint. Used for both inferred (secondary) and accepted (accent).
    @ViewBuilder
    private func tonePill(
        label: String,
        value: String,
        tint: Color,
        prominent: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(DT.captionStrong)
                .foregroundStyle(prominent ? tint : .primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(prominent ? tint.opacity(0.14) : DT.surfaceCard)
        )
        .overlay(
            Capsule()
                .strokeBorder(prominent ? tint.opacity(0.30) : DT.separator, lineWidth: 0.5)
        )
    }
}
