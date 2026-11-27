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
    @FocusState private var searchFocused: Bool
    var onSelect: (ClipItem) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    init(onSelect: @escaping (ClipItem) -> Void = { _ in }, onDismiss: @escaping () -> Void = {}) {
        self._clipboard = StateObject(wrappedValue: ClipboardManager.shared)
        self._pasteQueue = StateObject(wrappedValue: PasteQueue.shared)
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
                ClipSeparator().padding(.horizontal, 16)
                tabBar
                searchBar
                projectFilter
                itemsList
                if isQueueMode { queueBar }
                ClipSeparator()
                footer
            }
            .frame(width: ClipStyle.panelWidth, height: ClipStyle.panelHeight)
            .background(ClipPanelBackground())
            .clipShape(RoundedRectangle(cornerRadius: ClipStyle.windowRadius, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)

            if copiedId != nil { CopiedToast(copiedId: copiedId) }
            if showQuitConfirm { QuitConfirm(show: $showQuitConfirm) }
            if showSettings { SettingsOverlay(updater: updater, show: $showSettings) }
            if updater.isDownloading { DownloadOverlay(updater: updater) }
            if let err = updater.updateError { UpdateErrorToast(error: err, updater: updater) }
        }
        .onAppear { updater.checkForUpdates() }
        .onChange(of: clipboard.items.count) { _ in listVersion += 1 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.tr("clipboard"))
                    .font(ClipStyle.title)
                    .foregroundStyle(ClipStyle.label)
                Text("\(clipboard.items.count) of \(clipboard.maxItems)")
                    .font(ClipStyle.caption2)
                    .foregroundStyle(ClipStyle.tertiary)
                    .monospacedDigit()
            }

            Spacer()

            if updater.hasUpdate {
                Button(action: { updater.downloadAndUpdate() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                        Text("v\(updater.latestVersion)")
                            .font(ClipStyle.mono)
                    }
                    .foregroundStyle(ClipStyle.label)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(ClipStyle.elevated))
                }
                .buttonStyle(.plain)
            }

            ClipToolbarButton(systemName: "gearshape") { showSettings = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14).padding(.bottom, 12)
    }

    // MARK: - Tabs (segmented)

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabSegment(lang.tr("tab_all"), tag: 0)
            tabSegment(lang.tr("tab_project"), tag: 1)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: ClipStyle.controlRadius, style: .continuous)
                .fill(ClipStyle.grouped)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12).padding(.bottom, 10)
    }

    private func tabSegment(_ title: String, tag: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { selectedTab = tag }
        } label: {
            Text(title)
                .font(ClipStyle.caption.weight(selectedTab == tag ? .semibold : .regular))
                .foregroundStyle(selectedTab == tag ? ClipStyle.label : ClipStyle.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selectedTab == tag ? ClipStyle.elevated : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ClipStyle.tertiary)
            TextField(lang.tr("search_ph"), text: $searchText)
                .textFieldStyle(.plain)
                .font(ClipStyle.callout)
                .foregroundStyle(ClipStyle.label)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ClipStyle.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: ClipStyle.controlRadius, style: .continuous)
                .fill(ClipStyle.grouped)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClipStyle.controlRadius, style: .continuous)
                .strokeBorder(searchFocused ? ClipStyle.border.opacity(1.6) : ClipStyle.border, lineWidth: 0.5)
        )
        .padding(.horizontal, 16).padding(.bottom, 10)
        .animation(.easeOut(duration: 0.15), value: searchFocused)
    }

    // MARK: - Project filter

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
                .padding(.bottom, 8)
            }
        }
    }

    private func projectChip(_ project: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) { selectedProject = project }
        } label: {
            Text(lang.projectLabel(project))
                .font(ClipStyle.caption2)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(selectedProject == project ? ClipStyle.elevated : ClipStyle.grouped)
                )
                .foregroundStyle(selectedProject == project ? ClipStyle.label : ClipStyle.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var itemsList: some View {
        Group {
            if filteredItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(ClipStyle.tertiary.opacity(0.45))
                        .symbolRenderingMode(.hierarchical)
                    Text(lang.tr("empty_title"))
                        .font(ClipStyle.headline)
                        .foregroundStyle(ClipStyle.secondary)
                    Text(lang.tr("empty_copy"))
                        .font(ClipStyle.caption)
                        .foregroundStyle(ClipStyle.tertiary)
                    Text(lang.tr("empty_hotkey"))
                        .font(ClipStyle.caption2)
                        .foregroundStyle(ClipStyle.tertiary.opacity(0.7))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(ClipStyle.grouped))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredItems) { item in
                            ClipItemRow(
                                item: item,
                                clipboard: clipboard,
                                copiedId: $copiedId,
                                isQueueMode: isQueueMode,
                                queueSelected: $queueSelected,
                                onSelect: onSelect
                            )
                        }
                    }
                    .id(listVersion)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Queue

    private var queueBar: some View {
        HStack {
            Button(action: { isQueueMode = false; queueSelected.removeAll() }) {
                Label(lang.tr("queue_cancel"), systemImage: "xmark")
                    .font(ClipStyle.caption2)
            }
            .buttonStyle(.plain).foregroundStyle(ClipStyle.tertiary)
            Spacer()
            Text("\(queueSelected.count) \(lang.tr("queue_selected"))")
                .font(ClipStyle.caption2)
                .foregroundStyle(ClipStyle.secondary)
                .monospacedDigit()
            Spacer()
            Button(action: {
                let items = filteredItems.filter { queueSelected.contains($0.id) }
                isQueueMode = false
                queueSelected.removeAll()
                onDismiss()
                PasteQueue.shared.enqueue(items)
            }) {
                Label(lang.tr("queue_paste_all"), systemImage: "play.fill")
                    .font(ClipStyle.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(queueSelected.isEmpty ? ClipStyle.tertiary : ClipStyle.label)
            .disabled(queueSelected.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(ClipStyle.grouped)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 18) {
            footerAction(
                icon: isQueueMode ? "xmark" : "list.number",
                title: isQueueMode ? lang.tr("queue_cancel") : lang.tr("queue"),
                active: isQueueMode
            ) { isQueueMode.toggle(); queueSelected.removeAll() }

            footerAction(icon: "trash", title: lang.tr("clear"), active: false) {
                clipboard.clearAll()
            }

            Spacer()

            footerAction(icon: "power", title: lang.tr("quit"), active: false) {
                showQuitConfirm = true
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func footerAction(icon: String, title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(ClipStyle.caption2)
                .foregroundStyle(active ? ClipStyle.label : ClipStyle.tertiary)
        }
        .buttonStyle(.plain)
    }
}
