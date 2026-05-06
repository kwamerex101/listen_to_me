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
            VStack(alignment: .leading, spacing: 16) {
                header
                if store.entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Style")
                .font(.system(size: 22, weight: .semibold))
            Text("ListenToMe learns how you write into each app and adjusts cleanup automatically. After 20 dictations into the same app, a tone is inferred. Keep what fits; revert any that do not.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        Text("No tone inferred yet. Keep dictating — once any app has 20+ dictations, an inferred tone will appear here.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(store.entries) { entry in
                row(entry)
                Divider()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func row(_ entry: StyleEntry) -> some View {
        let appName = NSRunningApplication
            .runningApplications(withBundleIdentifier: entry.bundleId)
            .first?.localizedName ?? entry.bundleId
        let count = samples.count(for: entry.bundleId)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.system(size: 14, weight: .medium))
                Text(entry.bundleId)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("inferred: \(entry.inferredTone.displayLabel)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if let accepted = entry.acceptedTone {
                Text("accepted: \(accepted.displayLabel)")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                    )
            }
            Text("\(count) samples")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            if entry.acceptedTone != nil {
                Button("Revert") { store.revert(bundleId: entry.bundleId) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.20))
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
