import Cocoa

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    @Published var items: [ClipItem] = []
    @Published var currentContent: String = ""

    private var timer: Timer?
    private var lastContent: String = ""
    private var lastImageHash: Int = 0
    private var lastPasteboardChangeCount: Int = 0
    private var saveTimer: Timer?
    let maxItems = 25

    var storageURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClipHistory")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() { load() }

    func startMonitoring() {
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        save()
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pb.changeCount

        if let image_data = pb.data(forType: .tiff),
           let image = NSImage(data: image_data) {
            let hash = image_data.prefix(2048).hashValue &+ image_data.count.hashValue
            if hash != lastImageHash {
                lastImageHash = hash
                lastContent = ""
                let frontApp = NSWorkspace.shared.frontmostApplication
                let appName = frontApp?.localizedName ?? "Unknown"
                let bundleID = frontApp?.bundleIdentifier ?? ""
                let project = ProjectDetector.detectProject(app: appName, bundle: bundleID)

                let pngData: Data?
                if let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    pngData = png
                } else {
                    pngData = image_data
                }

                DispatchQueue.main.async {
                    let item = ClipItem(
                        text: "[Image \(Int(image.size.width))x\(Int(image.size.height))]",
                        sourceApp: appName, sourceBundle: bundleID,
                        contentType: .image, projectTag: project, imageData: pngData
                    )
                    self.items.insert(item, at: 0)
                    if self.items.count > self.maxItems {
                        self.items = Array(self.items.prefix(self.maxItems))
                    }
                    self.debounceSave()
                    NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
                }
            }
            return
        } else {
            lastImageHash = 0
        }

        if let content = pb.string(forType: .string),
           !content.isEmpty,
           content != lastContent {
            lastContent = content
            currentContent = content

            if items.contains(where: { $0.text == content && $0.contentType != .image }) {
                return
            }

            let frontApp = NSWorkspace.shared.frontmostApplication
            let appName = frontApp?.localizedName ?? "Unknown"
            let bundleID = frontApp?.bundleIdentifier ?? ""
            let detection = SensitiveDetector.detect(content)
            let project = ProjectDetector.detectProject(app: appName, bundle: bundleID)

            DispatchQueue.main.async {
                let item = ClipItem(
                    text: content, sourceApp: appName, sourceBundle: bundleID,
                    contentType: detection.type, isSensitive: detection.isSensitive, projectTag: project
                )
                self.items.insert(item, at: 0)
                if self.items.count > self.maxItems {
                    self.items = Array(self.items.prefix(self.maxItems))
                }
                self.debounceSave()
                NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
            }
        }
    }

    func copyToClipboard(_ item: ClipItem) {
        NSPasteboard.general.clearContents()
        if let img = item.nsImage {
            NSPasteboard.general.writeObjects([img])
        } else {
            NSPasteboard.general.setString(item.text, forType: .string)
        }
        syncLastFromPasteboard()
        currentContent = item.text
        lastContent = item.text
    }

    func syncLastFromPasteboard() {
        let pb = NSPasteboard.general
        lastPasteboardChangeCount = pb.changeCount
        if let tiffData = pb.data(forType: .tiff) {
            lastImageHash = tiffData.prefix(2048).hashValue &+ tiffData.count.hashValue
            lastContent = ""
        } else if let content = pb.string(forType: .string), !content.isEmpty {
            lastContent = content
            lastImageHash = 0
        }
    }

    func togglePin(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items
        updated[idx].pinned.toggle()
        items = updated
        save()
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
    }

    func removeItem(_ item: ClipItem) {
        items = items.filter { $0.id != item.id }
        save()
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
    }

    func clearAll() {
        items = items.filter { $0.pinned && $0.contentType != .image }.prefix(maxItems).map { $0 }
        save()
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
    }

    var projects: [String] {
        Array(Set(items.map { $0.projectTag })).sorted()
    }

    private func debounceSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.save()
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(items) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        items = ((try? dec.decode([ClipItem].self, from: data)) ?? []).filter { $0.contentType != .image }
        save()
    }
}
