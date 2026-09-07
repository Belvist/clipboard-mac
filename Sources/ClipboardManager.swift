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
    private var pollInterval: TimeInterval = 0.5
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
        schedulePoll(after: pollInterval)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        saveTimer?.invalidate()
        saveTimer = nil
        save()
    }

    private func schedulePoll(after interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        let changed = pb.changeCount != lastPasteboardChangeCount

        if changed {
            pollInterval = 0.35
            processPasteboard(pb)
        } else {
            pollInterval = min(pollInterval + 0.15, 2.0)
        }

        schedulePoll(after: pollInterval)
    }

    private func processPasteboard(_ pb: NSPasteboard) {
        lastPasteboardChangeCount = pb.changeCount

        if let image_data = pb.data(forType: .tiff),
           let image = NSImage(data: image_data) {
            let hash = image_data.prefix(2048).hashValue &+ image_data.count.hashValue
            if hash != lastImageHash {
                lastImageHash = hash
                lastContent = ""
                ingestImage(image, rawData: image_data)
            }
            return
        }
        lastImageHash = 0

        guard let content = pb.string(forType: .string),
              !content.isEmpty,
              content != lastContent else { return }

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
            self.items = ([item] + self.items).prefix(self.maxItems).map { $0 }
            self.debounceSave()
            NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
        }
    }

    private func ingestImage(_ image: NSImage, rawData: Data) {
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
            pngData = rawData
        }

        DispatchQueue.main.async {
            let item = ClipItem(
                text: "[Image \(Int(image.size.width))x\(Int(image.size.height))]",
                sourceApp: appName, sourceBundle: bundleID,
                contentType: .image, projectTag: project, imageData: pngData
            )
            self.items = ([item] + self.items).prefix(self.maxItems).map { $0 }
            self.debounceSave()
            NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
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
    }

    func removeItem(_ item: ClipItem) {
        items = items.filter { $0.id != item.id }
        save()
    }

    func clearAll() {
        items = items.filter { $0.pinned && $0.contentType != .image }.prefix(maxItems).map { $0 }
        save()
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
        items = (try? dec.decode([ClipItem].self, from: data)) ?? []
    }
}
