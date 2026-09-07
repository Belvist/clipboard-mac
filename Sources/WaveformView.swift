import SwiftUI

struct WaveformBars: View {
    var isPlaying: Bool
    var seed: String = ""

    var body: some View {
        if isPlaying {
            TimelineView(.animation(minimumInterval: 0.1)) { ctx in
                waveform(t: CGFloat(ctx.date.timeIntervalSinceReferenceDate) * 5.0)
            }
        } else {
            StaticBars(seed: seed)
        }
    }

    private func waveform(t: CGFloat) -> some View {
        let base = Self.basePhases(for: seed)
        return HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let offset = CGFloat(i) * 0.9
                let wave = sin(t + offset) * 0.35 + sin(t * 1.7 + offset) * 0.15
                let level = max(0.12, min(1.0, base[i] + wave))
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: max(2, level * 14))
            }
        }
        .frame(width: 18, height: 14)
    }

    private static func basePhases(for seed: String) -> [CGFloat] {
        let n = Int(seed) ?? abs(seed.hashValue)
        return (0..<5).map { i in
            let h = (n &+ 1) &* (i &+ 1) &* 2654435761
            let val = CGFloat(abs(h) % 100) / 100.0
            return 0.3 + val * 0.7
        }
    }
}

private struct StaticBars: View {
    var seed: String

    var body: some View {
        let base = WaveformBars.basePhasesPublic(for: seed)
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 2, height: max(2, base[i] * 14))
            }
        }
        .frame(width: 18, height: 14)
    }
}

extension WaveformBars {
    static func basePhasesPublic(for seed: String) -> [CGFloat] {
        let n = Int(seed) ?? abs(seed.hashValue)
        return (0..<5).map { i in
            let h = (n &+ 1) &* (i &+ 1) &* 2654435761
            let val = CGFloat(abs(h) % 100) / 100.0
            return 0.3 + val * 0.7
        }
    }
}
