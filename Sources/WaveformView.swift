import SwiftUI

struct WaveformBars: View {
    var isPlaying: Bool
    var seed: String = ""

    @State private var phases: [CGFloat] = [0.3, 0.5, 0.2, 0.6, 0.4]
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: max(2, phases[i] * 14))
                    .animation(.easeInOut(duration: 0.12), value: phases[i])
            }
        }
        .frame(width: 18, height: 14)
        .onChange(of: seed) { _ in
            phases = Self.basePhases(for: seed)
        }
        .onChange(of: isPlaying) { playing in
            if playing { startAnim() } else { stopAnim() }
        }
        .onAppear {
            phases = Self.basePhases(for: seed)
            if isPlaying { startAnim() }
        }
        .onDisappear { stopAnim() }
    }

    private func startAnim() {
        timer?.invalidate()
        let base = Self.basePhases(for: seed)
        var t: CGFloat = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
            t += 0.35
            withAnimation(.linear(duration: 0.06)) {
                for i in 0..<5 {
                    let offset = CGFloat(i) * 0.9
                    let wave = sin(t + offset) * 0.35 + sin(t * 1.7 + offset) * 0.15
                    let target = base[i] + wave
                    phases[i] = max(0.12, min(1.0, target))
                }
            }
        }
    }

    private func stopAnim() {
        timer?.invalidate()
        timer = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            for i in 0..<5 { phases[i] = 0.12 }
        }
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
