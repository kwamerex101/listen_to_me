import SwiftUI

// Phase 4 Task 3 will populate this with per-app inferred-tone rows.
// Stub kept lean during Task 1 (schema migration) so the project still builds.
struct StyleView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.system(size: 24, weight: .semibold))
            Text("Per-app inferred tones will appear here once Phase 4 finishes wiring.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
