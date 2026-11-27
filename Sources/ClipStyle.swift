import SwiftUI

enum ClipStyle {
    static let panelWidth: CGFloat = 380
    static let panelHeight: CGFloat = 500
    static let windowRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let rowRadius: CGFloat = 10

    static let bg = Color(white: 0.06)
    static let grouped = Color(white: 0.10)
    static let elevated = Color(white: 0.14)
    static let rowHover = Color(white: 0.12)
    static let separator = Color.white.opacity(0.07)
    static let border = Color.white.opacity(0.09)

    static let label = Color.white
    static let secondary = Color(white: 0.56)
    static let tertiary = Color(white: 0.38)

    static let pinAccent = Color(red: 1.0, green: 0.72, blue: 0.20)
    static let pinBackground = Color(red: 0.16, green: 0.13, blue: 0.06)

    static let title = Font.system(size: 15, weight: .semibold)
    static let headline = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let callout = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let caption2 = Font.system(size: 10)
    static let mono = Font.system(size: 10, weight: .medium, design: .monospaced)
}

struct ClipPanelBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ClipStyle.windowRadius, style: .continuous)
                .fill(ClipStyle.bg)
            RoundedRectangle(cornerRadius: ClipStyle.windowRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.55)
            RoundedRectangle(cornerRadius: ClipStyle.windowRadius, style: .continuous)
                .strokeBorder(ClipStyle.border, lineWidth: 0.5)
        }
    }
}

struct ClipSeparator: View {
    var body: some View {
        Rectangle().fill(ClipStyle.separator).frame(height: 0.5)
    }
}

struct ClipToolbarButton: View {
    let systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ClipStyle.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(ClipStyle.grouped))
        }
        .buttonStyle(.plain)
    }
}
