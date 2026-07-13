import SwiftUI
import ServiceManagement

private let bg = Color(red: 0.04, green: 0.04, blue: 0.04)
private let cardBg = Color(red: 0.08, green: 0.08, blue: 0.08)
private let edgeColor = Color(red: 0.15, green: 0.15, blue: 0.15)
private let edgeColorLight = Color(red: 0.2, green: 0.2, blue: 0.2)
private let textPrimary = Color.white
private let textSecondary = Color(red: 0.5, green: 0.5, blue: 0.5)
private let textTertiary = Color(red: 0.35, green: 0.35, blue: 0.35)

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
                if isQueueMode { queueBar }
                footer
            }
            .frame(width: 380, height: 500)
            .background(bg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(edgeColor, lineWidth: 0.5)
            )

            if copiedId != nil { CopiedToast(copiedId: copiedId) }
            if showQuitConfirm { QuitConfirm(show: $showQuitConfirm) }
            if showSettings { SettingsOverlay(updater: updater, show: $showSettings) }
            if updater.isDownloading { DownloadOverlay(updater: updater) }
            if let err = updater.updateError { UpdateErrorToast(error: err, updater: updater) }
        }
        .onAppear { updater.checkForUpdates() }
        .onChange(of: clipboard.items.count) { _ in listVersion += 1 }
        .onChange(of: clipboard.items.map { "\($0.id):\($0.pinned)" }) { _ in listVersion += 1 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textSecondary)
            Text(lang.tr("clipboard"))
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(textPrimary)
            Spacer()

            if updater.hasUpdate {
                Button(action: { updater.downloadAndUpdate() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 9))
                        Text("v\(updater.latestVersion)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange))
                }
                .buttonStyle(.plain)
            }

            Text("\(clipboard.items.count)/\(clipboard.maxItems)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(textTertiary)

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(textTertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12).padding(.bottom, 8)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(lang.tr("tab_all"), tag: 0)
            tabButton(lang.tr("tab_project"), tag: 1)
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func tabButton(_ title: String, tag: Int) -> some View {
        Button(action: { withAnimation(.easeOut(duration: 0.15)) { selectedTab = tag } }) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: selectedTab == tag ? .medium : .regular, design: .default))
                    .foregroundColor(selectedTab == tag ? textPrimary : textTertiary)
                Rectangle()
                    .fill(selectedTab == tag ? textPrimary : Color.clear)
                    .frame(height: 1)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(textTertiary)
            TextField(lang.tr("search_ph"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(textPrimary)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(edgeColor, lineWidth: 0.5)
        )
        .padding(.horizontal, 16).padding(.bottom, 8)
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
                .padding(.bottom, 8)
            }
        }
    }

    private func projectChip(_ project: String) -> some View {
        Button(action: { selectedProject = project }) {
            Text(lang.projectLabel(project))
                .font(.system(size: 10, weight: .regular, design: .default))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selectedProject == project ? textPrimary.opacity(0.1) : cardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selectedProject == project ? textPrimary.opacity(0.3) : edgeColor, lineWidth: 0.5)
                )
                .foregroundColor(selectedProject == project ? textPrimary : textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Items List

    private var itemsList: some View {
        Group {
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(textTertiary.opacity(0.4))
                    VStack(spacing: 4) {
                        Text(lang.tr("empty_title"))
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(textSecondary)
                        Text(lang.tr("empty_copy"))
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundColor(textTertiary)
                    }
                    Text(lang.tr("empty_hotkey"))
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundColor(textTertiary.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredItems) { item in
                            ClipItemRow(itemId: item.id, clipboard: clipboard, copiedId: $copiedId,
                                       isQueueMode: isQueueMode, queueSelected: $queueSelected, onSelect: onSelect)
                        }
                    }
                    .id(listVersion)
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Queue Bar

    private var queueBar: some View {
        HStack {
            Button(action: { isQueueMode = false; queueSelected.removeAll() }) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                Text(lang.tr("queue_cancel"))
                    .font(.system(size: 10, weight: .regular, design: .default))
            }
            .buttonStyle(.plain).foregroundColor(textTertiary)
            Spacer()
            Text("\(queueSelected.count) \(lang.tr("queue_selected"))")
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundColor(textTertiary)
            Spacer()
            Button(action: {
                let items = filteredItems.filter { queueSelected.contains($0.id) }
                isQueueMode = false
                queueSelected.removeAll()
                onDismiss()
                PasteQueue.shared.enqueue(items)
            }) {
                Image(systemName: "play.fill").font(.system(size: 9, weight: .medium))
                Text(lang.tr("queue_paste_all"))
                    .font(.system(size: 10, weight: .medium, design: .default))
            }
            .buttonStyle(.plain)
            .foregroundColor(queueSelected.isEmpty ? textTertiary : textPrimary)
            .disabled(queueSelected.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(cardBg)
        .overlay(
            Rectangle()
                .fill(edgeColor)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            Button(action: { isQueueMode.toggle(); queueSelected.removeAll() }) {
                HStack(spacing: 4) {
                    Image(systemName: isQueueMode ? "xmark" : "list.number")
                        .font(.system(size: 10, weight: .regular))
                    Text(isQueueMode ? lang.tr("queue_cancel") : lang.tr("queue"))
                        .font(.system(size: 10, weight: .regular, design: .default))
                }
                .foregroundColor(isQueueMode ? .orange : textTertiary)
            }
            .buttonStyle(.plain)

            Button(action: { clipboard.clearAll() }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .regular))
                    Text(lang.tr("clear"))
                        .font(.system(size: 10, weight: .regular, design: .default))
                }
                .foregroundColor(textTertiary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: { showQuitConfirm = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .regular))
                    Text(lang.tr("quit"))
                        .font(.system(size: 10, weight: .regular, design: .default))
                }
                .foregroundColor(textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
