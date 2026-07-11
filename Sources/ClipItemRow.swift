import SwiftUI

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

    var typeIcon: String {
        guard let item = item else { return "doc.text" }
        switch item.contentType {
        case .password: return "lock.fill"
        case .email: return "envelope"
        case .url: return "link"
        case .phone: return "phone"
        case .creditCard: return "creditcard"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .json: return "curlybraces"
        case .table: return "tablecells"
        case .text: return "doc.text"
        case .image: return "photo"
        }
    }

    var body: some View {
        if let item = item {
            HStack(alignment: .top, spacing: 0) {
                rowContent(item: item)
                    .onTapGesture { handleRowTap(item: item) }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Button {
                        clipboard.togglePin(item)
                    } label: {
                        Image(systemName: item.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(item.pinned ? .orange : .secondary.opacity(0.5))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(item.pinned ? Color.orange.opacity(0.15) : Color.clear))
                    }
                    .buttonStyle(.plain)

                    Button {
                        clipboard.removeItem(item)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.red.opacity(0.5))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { isHovered = h } }
        }
    }

    private func handleRowTap(item: ClipItem) {
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

    private func rowContent(item: ClipItem) -> some View {
        Group {
            if isQueueMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.4))
                    .frame(width: 20)
            }

            if item.contentType == .image, let img = item.nsImage {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if item.pinned {
                            Image(systemName: "pin.fill").font(.system(size: 7, weight: .bold)).foregroundColor(.orange)
                        }
                        Image(systemName: "photo").font(.system(size: 7, weight: .bold)).foregroundColor(.blue)
                        Text(item.timeAgo)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 60)
                        .cornerRadius(6)
                        .clipped()
                    HStack(spacing: 3) {
                        Image(systemName: "app.fill").font(.system(size: 7))
                        Text(item.sourceApp.isEmpty ? "Unknown" : item.sourceApp)
                            .font(.system(size: 8, design: .rounded))
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if item.pinned {
                            Image(systemName: "pin.fill").font(.system(size: 7, weight: .bold)).foregroundColor(.orange)
                        }
                        if item.isSensitive {
                            Image(systemName: typeIcon).font(.system(size: 7, weight: .bold)).foregroundColor(.red)
                        }
                        Text(item.timeAgo)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Text(item.text)
                        .font(.system(size: 13, design: item.contentType == .code ? .monospaced : .rounded))
                        .foregroundColor(item.isSensitive ? .red.opacity(0.9) : .primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: item.sourceApp.isEmpty ? "questionmark.circle" : "app.fill")
                                .font(.system(size: 7))
                            Text(item.sourceApp.isEmpty ? "Unknown" : item.sourceApp)
                                .font(.system(size: 8, design: .rounded))
                        }
                        .foregroundColor(.secondary.opacity(0.6))

                        if item.projectTag != "Other" {
                            HStack(spacing: 3) {
                                Image(systemName: "folder.fill").font(.system(size: 7))
                                Text(lang.projectLabel(item.projectTag)).font(.system(size: 8, design: .rounded))
                            }
                            .foregroundColor(.accentColor.opacity(0.7))
                        }

                        HStack(spacing: 3) {
                            Image(systemName: typeIcon).font(.system(size: 7))
                            Text(lang.contentTypeLabel(item.contentType)).font(.system(size: 8, design: .rounded))
                        }
                        .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }
        }
    }
}
