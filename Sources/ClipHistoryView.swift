import Cocoa
import SwiftUI
import ServiceManagement

struct ClipPopoverContent: View {
    @StateObject private var clipboard = ClipboardManager.shared
    @StateObject private var pasteQueue = PasteQueue.shared
    @StateObject private var updater = UpdateChecker()
    @State private var searchText = ""
    @State private var copiedId: UUID?
    @State private var showQuitConfirm = false
    @State private var showSettings = false
    @State private var selectedProject = "All"
    @State private var selectedTab = 0
    @State private var queueSelected: Set<UUID> = []
    @State private var isQueueMode = false
    var onSelect: (ClipItem) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    var filteredItems: [ClipItem] {
        var list = clipboard.items
        if selectedProject != "All" {
            list = list.filter { $0.projectTag == selectedProject }
        }
        let sorted = list.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.timestamp > b.timestamp
        }
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.text.localizedCaseInsensitiveContains(searchText) ||
            $0.sourceApp.localizedCaseInsensitiveContains(searchText) ||
            $0.projectTag.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                tabBar
                searchBar
                projectFilter
                itemsList
                queueBar
                footer
            }
            .frame(width: 400, height: 520)
            .background(WindowBackground())

            if copiedId != nil { copiedToast }
            if showQuitConfirm { quitConfirm }
            if showSettings { settingsOverlay }
            if updater.isDownloading { downloadOverlay }
        }
        .onAppear {
            updater.checkForUpdates()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
            Text("Clipboard")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()

            if updater.hasUpdate {
                Button(action: { updater.downloadAndUpdate() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 9))
                        Text("v\(updater.latestVersion)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange))
                }
                .buttonStyle(.plain)
            }

            Text("\(clipboard.items.count)/\(clipboard.maxItems)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("All Items", icon: "list.bullet", tag: 0)
            tabButton("By Project", icon: "folder", tag: 1)
            tabButton("Sensitive", icon: "lock.shield", tag: 2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tabButton(_ title: String, icon: String, tag: Int) -> some View {
        Button(action: { selectedTab = tag }) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(title).font(.system(size: 10, weight: selectedTab == tag ? .bold : .medium, design: .rounded))
            }
            .foregroundColor(selectedTab == tag ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == tag ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(.secondary)
            TextField("Search text, app, project...", text: $searchText)
                .textFieldStyle(.plain).font(.system(size: 13, design: .rounded))
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var projectFilter: some View {
        Group {
            if selectedTab == 1 && !clipboard.projects.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        projectChip("All")
                        ForEach(clipboard.projects, id: \.self) { project in
                            projectChip(project)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func projectChip(_ project: String) -> some View {
        Button(action: { selectedProject = project }) {
            Text(project)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(selectedProject == project ? Color.accentColor : Color.primary.opacity(0.08)))
                .foregroundColor(selectedProject == project ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var itemsList: some View {
        Group {
            if filteredItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Empty").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(.secondary)
                    Text("Copy something to start").font(.system(size: 11, design: .rounded)).foregroundColor(.secondary.opacity(0.7))
                    Text("Cmd+Shift+V to open").font(.system(size: 10, design: .rounded)).foregroundColor(.secondary.opacity(0.5))
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            ClipItemRow(item: item, clipboard: clipboard, copiedId: $copiedId,
                                       isQueueMode: isQueueMode, queueSelected: $queueSelected, onSelect: onSelect)
                            if item.id != filteredItems.last?.id {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }.padding(.vertical, 4)
                }.frame(maxHeight: .infinity)
            }
        }
    }

    private var queueBar: some View {
        Group {
            if isQueueMode {
                HStack {
                    Button(action: { isQueueMode = false; queueSelected.removeAll() }) {
                        Image(systemName: "xmark").font(.system(size: 10))
                        Text("Cancel").font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                    Spacer()
                    Text("\(queueSelected.count) selected")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        let items = filteredItems.filter { queueSelected.contains($0.id) }
                        isQueueMode = false
                        queueSelected.removeAll()
                        onDismiss()
                        PasteQueue.shared.enqueue(items)
                    }) {
                        Image(systemName: "play.fill").font(.system(size: 10))
                        Text("Paste All").font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(queueSelected.isEmpty ? .secondary : .accentColor)
                    .disabled(queueSelected.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.06))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: { isQueueMode.toggle(); queueSelected.removeAll() }) {
                HStack(spacing: 4) {
                    Image(systemName: isQueueMode ? "xmark" : "list.number").font(.system(size: 10))
                    Text(isQueueMode ? "Cancel" : "Queue").font(.system(size: 11, weight: .medium, design: .rounded))
                }.foregroundColor(isQueueMode ? .orange : .secondary)
            }.buttonStyle(.plain)

            Button(action: { clipboard.clearAll() }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash").font(.system(size: 10))
                    Text("Clear").font(.system(size: 11, weight: .medium, design: .rounded))
                }.foregroundColor(.secondary)
            }.buttonStyle(.plain)

            Spacer()

            Button(action: { showQuitConfirm = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "power").font(.system(size: 10))
                    Text("Quit").font(.system(size: 11, weight: .medium, design: .rounded))
                }.foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Overlays

    private var copiedToast: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                    Text(pasteQueue.isActive ? "Pasting..." : "Pasted!")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.green).shadow(color: .black.opacity(0.25), radius: 8, y: 4))
                Spacer()
            }.padding(.bottom, 40)
        }
        .allowsHitTesting(false).transition(.opacity).animation(.easeOut(duration: 0.2), value: copiedId)
    }

    private var downloadOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Downloading update...")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("v\(updater.latestVersion)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(30)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.3), radius: 20, y: 8))
        }
    }

    private var quitConfirm: some View {
        ZStack {
            Color.black.opacity(0.4).onTapGesture { showQuitConfirm = false }
            VStack(spacing: 14) {
                Image(systemName: "power").font(.system(size: 24)).foregroundColor(.secondary)
                Text("Quit ClipHistory?").font(.system(size: 14, weight: .bold, design: .rounded))
                HStack(spacing: 12) {
                    Button(action: { showQuitConfirm = false }) {
                        Text("Cancel").font(.system(size: 12, weight: .medium, design: .rounded))
                            .frame(width: 80).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                    }.buttonStyle(.plain)
                    Button(action: { NSApplication.shared.terminate(nil) }) {
                        Text("Quit").font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(width: 80).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.red)).foregroundColor(.white)
                    }.buttonStyle(.plain)
                }
            }.padding(24)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.3), radius: 20, y: 8))
        }.transition(.opacity)
    }

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).onTapGesture { showSettings = false }
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "gearshape").font(.system(size: 12))
                    Text("Settings").font(.system(size: 14, weight: .bold, design: .rounded))
                    Spacer()
                    Button(action: { showSettings = false }) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
                Divider().padding(.horizontal, 16)

                settingsRow("Launch at login", "Start when you log in") {
                    Toggle("", isOn: Binding(
                        get: { SMAppService.mainApp.status == .enabled },
                        set: { val in try? val ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                    )).toggleStyle(.switch).controlSize(.small)
                }

                Divider().padding(.horizontal, 16)

                settingsRow("Auto-paste (Accessibility)", checkAccessibility() ? "Enabled" : "Needed") {
                    if checkAccessibility() {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 14))
                    } else {
                        Button("Enable") { requestAccessibility() }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor)).foregroundColor(.white)
                        .buttonStyle(.plain)
                    }
                }

                Divider().padding(.horizontal, 16)

                settingsRow("Updates", updater.hasUpdate ? "v\(updater.latestVersion) available" : "Up to date") {
                    if updater.hasUpdate {
                        Button("Update") { updater.downloadAndUpdate() }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange)).foregroundColor(.white)
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 14))
                    }
                }

                Divider().padding(.horizontal, 16)

                settingsRow("Privacy", "100% local, no data sent") {
                    Image(systemName: "lock.shield").foregroundColor(.green).font(.system(size: 14))
                }

                Divider().padding(.horizontal, 16)

                settingsRow("Version", "v1.1") {
                    EmptyView()
                }

                Spacer()
            }
            .frame(width: 320, height: 300)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.3), radius: 20, y: 8))
        }.transition(.opacity)
    }

    private func settingsRow<V: View>(_ title: String, _ subtitle: String, @ViewBuilder value: () -> V) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium, design: .rounded))
                Text(subtitle).font(.system(size: 10, design: .rounded))
                    .foregroundColor(title == "Privacy" ? .green :
                        title == "Auto-paste (Accessibility)" ? (checkAccessibility() ? .green : .orange) :
                        title == "Updates" ? (updater.hasUpdate ? .orange : .green) : .secondary)
            }
            Spacer()
            value()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Row

struct ClipItemRow: View {
    let item: ClipItem
    let clipboard: ClipboardManager
    @Binding var copiedId: UUID?
    var isQueueMode: Bool
    @Binding var queueSelected: Set<UUID>
    var onSelect: (ClipItem) -> Void = { _ in }
    @State private var isHovered = false

    var isSelected: Bool { queueSelected.contains(item.id) }

    var typeIcon: String {
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
        Button(action: {
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
        }) {
            HStack(alignment: .top, spacing: 10) {
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
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Text(item.text)
                            .font(.system(size: 11, design: item.contentType == .code ? .monospaced : .rounded))
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
                                    Text(item.projectTag).font(.system(size: 8, design: .rounded))
                                }
                                .foregroundColor(.accentColor.opacity(0.7))
                            }

                            HStack(spacing: 3) {
                                Image(systemName: typeIcon).font(.system(size: 7))
                                Text(item.contentType.rawValue).font(.system(size: 8, design: .rounded))
                            }
                            .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }

                Spacer(minLength: 4)

                if isHovered && !isQueueMode {
                    HStack(spacing: 4) {
                        rowBtn("pin", active: item.pinned) { clipboard.togglePin(item) }
                        rowBtn("trash", active: false, color: .red) { clipboard.removeItem(item) }
                    }.transition(.opacity)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { isHovered = h } }
    }

    private func rowBtn(_ icon: String, active: Bool = false, color: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(active ? color : color.opacity(0.5))
                .frame(width: 22, height: 22)
                .background(Circle().fill(active ? color.opacity(0.2) : Color.primary.opacity(0.08)))
        }.buttonStyle(.plain)
    }
}

struct WindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.state = .active
        v.blendingMode = .behindWindow
        v.isEmphasized = true
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
