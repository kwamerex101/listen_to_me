import SwiftUI

struct WaveformView: View {
    let levels: [Float]        // N samples, each 0…1

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<levels.count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 3, height: barHeight(levels[i]))
                    .animation(.easeOut(duration: 0.08), value: levels[i])
            }
        }
        .frame(height: 24)
    }

    private func barHeight(_ v: Float) -> CGFloat {
        let clamped = max(0, min(1, CGFloat(v)))
        return 3 + clamped * 21
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
                    .animation(.easeOut(duration: 0.08), value: levels[i])
            }
        }
        .frame(height: 16)
    }

    private func barHeight(_ v: Float) -> CGFloat {
        let clamped = max(0, min(1, CGFloat(v)))
        return 2 + clamped * 12
    }
}
