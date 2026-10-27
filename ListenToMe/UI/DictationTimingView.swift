import SwiftUI

struct DictationTimingView: View {
    @ObservedObject private var timing = DictationTiming.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DT.space3) {
            if let latest = timing.samples.last(where: { $0.deliveryMs != nil }) {
                HStack(spacing: DT.space6) {
                    metric("Latest", latest.deliveryMs)
                    metric("Median", timing.medianDeliveryMs)
                    metric("95th percentile", timing.p95DeliveryMs)
                }
                HStack(spacing: DT.space6) {
                    metric("Mic ready", latest.recordingReadyMs)
                    metric("Transcription", latest.transcriptionMs)
                    metric(latest.bypassedPolish ? "Wait before bypass" : "Polish", latest.polishMs)
                }
            } else {
                Text("Dictate once to see how long transcription and delivery take.")
                    .font(DT.body)
                    .foregroundStyle(.secondary)
            }
            Text("This session only. Measures release to delivery request; the receiving app may take longer to display text. Keeps up to 50 attempts without transcripts or audio.")
                .font(DT.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DT.space4)
    }

    private func metric(_ label: String, _ milliseconds: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(DT.caption).foregroundStyle(.secondary)
            Text(milliseconds.map { String(format: "%.0f ms", $0) } ?? "Not used")
                .font(DT.bodyStrong).monospacedDigit()
        }
    }
}
