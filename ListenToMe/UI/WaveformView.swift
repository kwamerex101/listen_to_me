import SwiftUI
import Foundation

/// Map a linear amplitude (0…1) to a perceptual height scalar (0…1) on a
/// log/dB curve. Hearing is logarithmic — a linear meter slumps at speech
/// volumes and saturates on bursts. This maps roughly -40dBFS…0dBFS into
/// the visible range so conversational audio actually moves the bars.
private func perceptualLevel(_ v: Float) -> CGFloat {
    let clamped = max(0.0001, min(1, Double(v)))
    let db = 20 * log10(clamped)        // ≤ 0 dBFS
    let normalized = (db + 40) / 40     // -40dB → 0, 0dB → 1
    return CGFloat(max(0, min(1, normalized)))
}

struct WaveformView: View {
    let levels: [Float]        // N samples, each 0…1

    var body: some View {
        BarsCanvas(levels: levels, barWidth: 3, spacing: 3,
                   minHeight: 3, heightRange: 21, opacity: 0.9)
            .frame(height: 24)
            .accessibilityHidden(true)   // decorative; the pill carries the label
    }
}

/// Small waveform used in the compact recording pill. Thinner bars, smaller max height.
struct CompactWaveformView: View {
    let levels: [Float]

    var body: some View {
        BarsCanvas(levels: levels, barWidth: 2, spacing: 2,
                   minHeight: 2, heightRange: 12, opacity: 0.85)
            .frame(height: 16)
            .accessibilityHidden(true)   // decorative; the pill carries the label
    }
}

/// Draws the bars in one `Canvas` pass. The levels update ~30Hz inside the
/// glass pill, so this avoids diffing and animating a view per bar.
private struct BarsCanvas: View {
    let levels: [Float]
    let barWidth: CGFloat
    let spacing: CGFloat
    let minHeight: CGFloat
    let heightRange: CGFloat
    let opacity: Double

    var body: some View {
        Canvas { ctx, size in
            let n = levels.count
            guard n > 0 else { return }
            let total = CGFloat(n) * barWidth + CGFloat(n - 1) * spacing
            var x = (size.width - total) / 2
            for v in levels {
                let h = minHeight + perceptualLevel(v) * heightRange
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                         with: .color(.white.opacity(opacity)))
                x += barWidth + spacing
            }
        }
    }
}
