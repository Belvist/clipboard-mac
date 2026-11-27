import SwiftUI

struct ClipItemRow: View {
    let item: ClipItem
    @ObservedObject var clipboard: ClipboardManager
    @Binding var copiedId: UUID?
    var isQueueMode: Bool
    @Binding var queueSelected: Set<UUID>
    var onSelect: (ClipItem) -> Void = { _ in }
    @EnvironmentObject private var lang: L10n
    @State private var isHovered = false

    private var isSelected: Bool { queueSelected.contains(item.id) }
    private var isCopied: Bool { copiedId == item.id }

    var body: some View {
        Button(action: { handleTap() }) {
            HStack(alignment: .top, spacing: 10) {
                if isQueueMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(isSelected ? ClipStyle.label : ClipStyle.tertiary)
                        .frame(width: 22)
                        .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if item.pinned || item.isSensitive {
                        HStack(spacing: 8) {
                            if item.pinned {
                                Label("Закреплено", systemImage: "pin.fill")
                                    .font(ClipStyle.caption.weight(.bold))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.white)
                                    )
                            }
                            if item.isSensitive {
                                Label("Locked", systemImage: "lock.fill")
                                    .font(ClipStyle.caption2)
                                    .foregroundStyle(ClipStyle.tertiary)
                            }
                        }
                    }

                    if item.contentType == .image, let img = item.nsImage {
                        imageContent(img: img)
                    } else {
                        textContent()
                    }

                    metaRow
                }

                Spacer(minLength: 4)

                if !isQueueMode {
                    HStack(spacing: 2) {
                        if isHovered {
                            rowAction("pin", filled: item.pinned) { clipboard.togglePin(item) }
                            rowAction("trash", filled: false) { clipboard.removeItem(item) }
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ClipStyle.tertiary.opacity(0.45))
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(rowBackground)
            .overlay(rowBorder)
            .contentShape(RoundedRectangle(cornerRadius: ClipStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) { isHovered = h }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: ClipStyle.rowRadius, style: .continuous)
            .fill(backgroundFill)
            .overlay(
                // White accent bar on the left edge for pinned rows.
                HStack(spacing: 0) {
                    if item.pinned {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 4)
                            .padding(.vertical, 5)
                    }
                    Spacer()
                }
                .padding(.leading, 3)
            )
    }

    private var backgroundFill: Color {
        if isCopied { return ClipStyle.elevated }
        if isHovered { return ClipStyle.rowHover }
        return ClipStyle.grouped.opacity(0.55)
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: ClipStyle.rowRadius, style: .continuous)
            .strokeBorder(
                isCopied ? Color.white.opacity(0.2) : (isHovered ? ClipStyle.border : Color.clear),
                lineWidth: 0.5
            )
    }

    private func rowAction(_ name: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: filled ? "\(name).fill" : name)
                .font(.system(size: 11))
                .foregroundStyle(ClipStyle.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(ClipStyle.elevated))
        }
        .buttonStyle(.plain)
    }

    private func handleTap() {
        if isQueueMode {
            if isSelected { queueSelected.remove(item.id) }
            else { queueSelected.insert(item.id) }
        } else {
            onSelect(item)
            copiedId = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if copiedId == item.id { copiedId = nil }
            }
        }
    }

    private func textContent() -> some View {
        Text(item.isSensitive ? String(repeating: "•", count: min(item.text.count, 20)) : item.text)
            .font(item.contentType == .code || item.contentType == .json ? ClipStyle.callout.monospaced() : ClipStyle.body)
            .foregroundStyle(item.isSensitive ? ClipStyle.tertiary : ClipStyle.label)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func imageContent(img: NSImage) -> some View {
        Image(nsImage: img)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var metaRow: some View {
        HStack(spacing: 0) {
            if !item.sourceApp.isEmpty {
                Text(item.sourceApp)
                    .font(ClipStyle.caption2)
                    .foregroundStyle(ClipStyle.tertiary)
                    .lineLimit(1)
            }
            if !item.sourceApp.isEmpty && item.contentType != .text {
                Text(" · ")
                    .font(ClipStyle.caption2)
                    .foregroundStyle(ClipStyle.tertiary.opacity(0.5))
            }
            if item.contentType != .text {
                Text(lang.contentTypeLabel(item.contentType))
                    .font(ClipStyle.caption2)
                    .foregroundStyle(ClipStyle.tertiary)
            }
            if item.contentType == .image, let img = item.nsImage {
                Text(" · \(Int(img.size.width))×\(Int(img.size.height))")
                    .font(ClipStyle.mono)
                    .foregroundStyle(ClipStyle.tertiary)
            }
            Spacer(minLength: 8)
            Text(item.timeAgo)
                .font(ClipStyle.caption2)
                .foregroundStyle(ClipStyle.tertiary.opacity(0.75))
                .monospacedDigit()
        }
    }
}
