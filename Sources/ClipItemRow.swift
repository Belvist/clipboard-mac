import SwiftUI

private let cardBg = Color(red: 0.08, green: 0.08, blue: 0.08)
private let edgeColor = Color(red: 0.15, green: 0.15, blue: 0.15)
private let textPrimary = Color.white
private let textSecondary = Color(red: 0.5, green: 0.5, blue: 0.5)
private let textTertiary = Color(red: 0.35, green: 0.35, blue: 0.35)

struct ClipItemRow: View {
    let itemId: UUID
    @ObservedObject var clipboard: ClipboardManager
    @Binding var copiedId: UUID?
    var isQueueMode: Bool
    @Binding var queueSelected: Set<UUID>
    var onSelect: (ClipItem) -> Void = { _ in }
    @EnvironmentObject private var lang: L10n
    @State private var isHovered = false

    var item: ClipItem? { clipboard.items.first { $0.id == itemId } }

    var isSelected: Bool { queueSelected.contains(itemId) }

    var body: some View {
        if let item = item {
            Button(action: { handleTap(item: item) }) {
                HStack(spacing: 0) {
                    if isQueueMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(isSelected ? textPrimary : textTertiary)
                            .frame(width: 24)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if item.pinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                            if item.isSensitive {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                        }
                        .opacity(item.pinned || item.isSensitive ? 1 : 0)
                        .frame(height: item.pinned || item.isSensitive ? nil : 0)

                        if item.contentType == .image, let img = item.nsImage {
                            imageContent(item: item, img: img)
                        } else {
                            textContent(item: item)
                        }
                    }

                    Spacer(minLength: 8)

                    if !isQueueMode {
                        HStack(spacing: 4) {
                            if isHovered {
                                Button(action: { clipboard.togglePin(item) }) {
                                    Image(systemName: item.pinned ? "pin.slash" : "pin")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(textTertiary)
                                }
                                .buttonStyle(.plain)

                                Button(action: { clipboard.removeItem(item) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(textTertiary)
                                }
                                .buttonStyle(.plain)
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundColor(textTertiary.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? cardBg : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isHovered ? edgeColor : Color.clear, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .onHover { h in withAnimation(.easeOut(duration: 0.1)) { isHovered = h } }
        }
    }

    private func handleTap(item: ClipItem) {
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

    private func textContent(item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.text)
                .font(.system(size: 12, weight: .regular, design: item.contentType == .code ? .monospaced : .default))
                .foregroundColor(item.isSensitive ? .red.opacity(0.8) : textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if !item.sourceApp.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4, weight: .regular))
                        Text(item.sourceApp)
                            .font(.system(size: 10, weight: .regular, design: .default))
                    }
                    .foregroundColor(textTertiary)
                }

                Text(item.timeAgo)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundColor(textTertiary.opacity(0.7))

                if item.contentType != .text {
                    Text(lang.contentTypeLabel(item.contentType))
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundColor(textTertiary.opacity(0.7))
                }
            }
        }
    }

    private func imageContent(item: ClipItem, img: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(height: 60)
                .cornerRadius(6)
                .clipped()

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "photo")
                        .font(.system(size: 8, weight: .regular))
                    Text("\(Int(img.size.width))x\(Int(img.size.height))")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                }
                .foregroundColor(textTertiary)

                if !item.sourceApp.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4, weight: .regular))
                        Text(item.sourceApp)
                            .font(.system(size: 10, weight: .regular, design: .default))
                    }
                    .foregroundColor(textTertiary)
                }

                Text(item.timeAgo)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundColor(textTertiary.opacity(0.7))
            }
        }
    }
}
