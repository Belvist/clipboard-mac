import SwiftUI

// MARK: - Display Mode

enum NotchContentMode: Equatable {
    case clipboard(count: Int, wave: Bool, preview: String)
    case music
    case combined(count: Int, wave: Bool, preview: String)

    var showsMusic: Bool {
        switch self {
        case .music, .combined: return true
        case .clipboard: return false
        }
    }
}

// MARK: - Host View

class NotchHostView: NSHostingView<NotchPanelView> {
    var onClicked: (() -> Void)?

    override func mouseDown(with event: NSEvent) { onClicked?() }
}

// MARK: - Shape

struct NotchShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Panel View

struct NotchPanelView: View {
    var mode: NotchContentMode
    var expanded: Bool = false
    @ObservedObject private var music = MediaRemoteHelper.shared

    private static let timeFmt: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.unitsStyle = .positional
        f.zeroFormattingBehavior = .pad
        return f
    }()

    private var elapsedText: String {
        guard music.elapsed.isFinite, music.elapsed >= 0 else { return "0:00" }
        return Self.timeFmt.string(from: music.elapsed) ?? "0:00"
    }

    var body: some View {
        ZStack {
            NotchShape(cornerRadius: 14)
                .fill(Color.black)

            if expanded && mode.showsMusic && music.hasMusic {
                expandedMusicContent
            } else {
                compactContent
            }
        }
        .clipShape(NotchShape(cornerRadius: 14))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: expanded)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if music.isPlaying { music.tickElapsed() }
        }
    }

    // MARK: Compact

    @ViewBuilder
    private var compactContent: some View {
        HStack(spacing: 8) {
            leadingIcon
            if mode.showsMusic && music.hasMusic {
                musicCompactInfo
            } else if case .clipboard(let count, let wave, let preview) = mode, count > 0 {
                clipboardCompactInfo(count: count, wave: wave, preview: preview)
            } else if case .combined(let count, let wave, let preview) = mode {
                combinedCompact(count: count, wave: wave, preview: preview)
            }
            Spacer(minLength: 0)
            trailingBadge
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if mode.showsMusic, let art = music.artwork {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    @ViewBuilder
    private var musicCompactInfo: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(music.title.isEmpty ? "Now Playing" : music.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !music.artist.isEmpty {
                    Text(music.artist)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: expanded ? 160 : 100, alignment: .leading)

            if music.isPlaying {
                WaveformBars(isPlaying: true, seed: music.title)
            }
        }
    }

    private func clipboardCompactInfo(count: Int, wave: Bool, preview: String) -> some View {
        HStack(spacing: 6) {
            if wave {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text(preview.isEmpty ? "Copied" : preview)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
            }
        }
    }

    private func combinedCompact(count: Int, wave: Bool, preview: String) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(music.title.isEmpty ? "Now Playing" : music.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: 80, alignment: .leading)
            if music.isPlaying {
                WaveformBars(isPlaying: true, seed: music.title)
            }
            if wave {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private var trailingBadge: some View {
        HStack(spacing: 6) {
            if mode.showsMusic && music.isPlaying {
                Text(elapsedText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
            }

            if let count = clipCount {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        .frame(width: 18, height: 18)
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var clipCount: Int? {
        switch mode {
        case .clipboard(let count, _, _):
            return count > 0 ? count : nil
        case .combined(let count, _, _):
            return count > 0 ? count : nil
        case .music:
            return nil
        }
    }

    // MARK: Expanded Music

    private var expandedMusicContent: some View {
        HStack(spacing: 10) {
            if let art = music.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(music.title.isEmpty ? "Now Playing" : music.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(music.artist.isEmpty ? " " : music.artist)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: 120, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 14) {
                Button(action: { music.previousTrack() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                Button(action: { music.togglePlayPause() }) {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button(action: { music.nextTrack() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            if music.isPlaying {
                WaveformBars(isPlaying: true, seed: music.title)
            }

            Text(elapsedText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }
}
