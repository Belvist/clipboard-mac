import SwiftUI
import ServiceManagement

struct ClipPopoverContent: View {
    @StateObject private var clipboard = ClipboardManager.shared
    @StateObject private var pasteQueue = PasteQueue.shared
    @ObservedObject private var updater = UpdateChecker.shared
    @EnvironmentObject private var lang: L10n
    @State private var searchText = ""
    @State private var copiedId: UUID?
    @State private var showQuitConfirm = false
    @State private var showSettings = false
    @State private var selectedProject = "All"
    @State private var selectedTab = 0
    @State private var queueSelected: Set<UUID> = []
    @State private var isQueueMode = false
    @State private var listVersion = 0
    var onSelect: (ClipItem) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    init(onSelect: @escaping (ClipItem) -> Void = { _ in }, onDismiss: @escaping () -> Void = {}) {
        self._clipboard = StateObject(wrappedValue: ClipboardManager.shared)
        self._pasteQueue = StateObject(wrappedValue: PasteQueue.shared)
        self._searchText = State(initialValue: "")
        self._copiedId = State(initialValue: nil)
        self._showQuitConfirm = State(initialValue: false)
        self._showSettings = State(initialValue: false)
        self._selectedProject = State(initialValue: "All")
        self._selectedTab = State(initialValue: 0)
        self._queueSelected = State(initialValue: [])
        self._isQueueMode = State(initialValue: false)
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

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

            if copiedId != nil { CopiedToast(copiedId: copiedId) }
            if showQuitConfirm { QuitConfirm(show: $showQuitConfirm) }
            if showSettings { SettingsOverlay(updater: updater, show: $showSettings) }
            if updater.isDownloading { DownloadOverlay(updater: updater) }
            if let err = updater.updateError { UpdateErrorToast(error: err, updater: updater) }
        }
        .onAppear {
            updater.checkForUpdates()
        }
        .onChange(of: clipboard.items.count) { _ in listVersion += 1 }
        .onChange(of: clipboard.items.map { "\($0.id):\($0.pinned)" }) { _ in listVersion += 1 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
            Text(lang.tr("clipboard"))
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

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(lang.tr("tab_all"), icon: "list.bullet", tag: 0)
            tabButton(lang.tr("tab_project"), icon: "folder", tag: 1)
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

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(.secondary)
            TextField(lang.tr("search_ph"), text: $searchText)
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

    // MARK: - Project Filter

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
            Text(lang.projectLabel(project))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(selectedProject == project ? Color.accentColor : Color.primary.opacity(0.08)))
                .foregroundColor(selectedProject == project ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Items List

    private var itemsList: some View {
        Group {
            if filteredItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text(lang.tr("empty_title")).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(.secondary)
                    Text(lang.tr("empty_copy")).font(.system(size: 11, design: .rounded)).foregroundColor(.secondary.opacity(0.7))
                    Text(lang.tr("empty_hotkey")).font(.system(size: 10, design: .rounded)).foregroundColor(.secondary.opacity(0.5))
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            ClipItemRow(itemId: item.id, clipboard: clipboard, copiedId: $copiedId,
                                       isQueueMode: isQueueMode, queueSelected: $queueSelected, onSelect: onSelect)
                            if item.id != filteredItems.last?.id {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }.id(listVersion).padding(.vertical, 4)
                }.frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Queue Bar

    private var queueBar: some View {
        Group {
            if isQueueMode {
                HStack {
                    Button(action: { isQueueMode = false; queueSelected.removeAll() }) {
                        Image(systemName: "xmark").font(.system(size: 10))
                        Text(lang.tr("queue_cancel")).font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: lang.tr("queue_selected"), queueSelected.count))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
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
                        Text(lang.tr("queue_paste_all")).font(.system(size: 10, weight: .bold, design: .rounded))
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

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: { isQueueMode.toggle(); queueSelected.removeAll() }) {
                HStack(spacing: 4) {
                    Image(systemName: isQueueMode ? "xmark" : "list.number").font(.system(size: 10))
                    Text(isQueueMode ? lang.tr("queue_cancel") : lang.tr("queue")).font(.system(size: 11, weight: .medium, design: .rounded))
                }.foregroundColor(isQueueMode ? .orange : .secondary)
            }.buttonStyle(.plain)

            Button(action: { clipboard.clearAll() }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash").font(.system(size: 10))
                    Text(lang.tr("clear")).font(.system(size: 11, weight: .medium, design: .rounded))
                }.foregroundColor(.secondary)
            }.buttonStyle(.plain)

            Spacer()

            Button(action: { showQuitConfirm = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "power").font(.system(size: 10))
                    Text(lang.tr("quit")).font(.system(size: 11, weight: .medium, design: .rounded))
                }.foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
