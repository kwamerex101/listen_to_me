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
        HStack(spacing: 3) {
            ForEach(0..<levels.count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 3, height: barHeight(levels[i]))
                    .animation(.easeOut(duration: 0.06), value: levels[i])
            }
        }
        .frame(height: 24)
    }

    private func barHeight(_ v: Float) -> CGFloat {
        return 3 + perceptualLevel(v) * 21
    }
}

/// Small waveform used in the compact recording pill. Thinner bars, smaller max height.
struct CompactWaveformView: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<levels.count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: barHeight(levels[i]))
                    .animation(.easeOut(duration: 0.06), value: levels[i])
            }
        }
        .frame(height: 16)
    }

    private func barHeight(_ v: Float) -> CGFloat {
        return 2 + perceptualLevel(v) * 12
    }
}
