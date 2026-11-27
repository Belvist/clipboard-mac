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
            self.insertPreservingPins(item)
            self.debounceSave()
            NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
        }
    }

    private func ingestImage(_ image: NSImage, rawData: Data) {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "Unknown"
        let bundleID = frontApp?.bundleIdentifier ?? ""
        let project = ProjectDetector.detectProject(app: appName, bundle: bundleID)

        let pngData = Self.optimizedPNG(for: image) ?? rawData

        DispatchQueue.main.async {
            let item = ClipItem(
                text: "[Image \(Int(image.size.width))x\(Int(image.size.height))]",
                sourceApp: appName, sourceBundle: bundleID,
                contentType: .image, projectTag: project, imageData: pngData
            )
            self.insertPreservingPins(item)
            self.debounceSave()
            NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
        }
    }

    /// Downscales large images (max 1600px on the long edge) and re-encodes as PNG
    /// to keep history.json small. Returns nil if encoding fails.
    private static func optimizedPNG(for image: NSImage) -> Data? {
        let maxEdge: CGFloat = 1600
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let scale = min(1, maxEdge / max(size.width, size.height))
        let targetSize = NSSize(width: size.width * scale, height: size.height * scale)

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep = rep else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
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
        // Keep pinned items at the top, ordered by recency.
        updated.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.timestamp > b.timestamp
        }
        items = updated
        save()
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
    }

    func removeItem(_ item: ClipItem) {
        items = items.filter { $0.id != item.id }
        save()
    }

    func clearAll() {
        // Keep every pinned item (including pinned images); drop the rest.
        items = items.filter { $0.pinned }
        save()
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
    }

    /// Inserts a new item at the top while never evicting pinned items.
    /// If the list is full, the oldest unpinned item is removed instead.
    private func insertPreservingPins(_ item: ClipItem) {
        var next = [item] + items
        let pinnedCount = next.filter { $0.pinned }.count

        if next.count > maxItems {
            // How many unpinned slots remain after reserving room for pins.
            let unpinnedAllowed = max(0, maxItems - pinnedCount)
            var keptUnpinned = 0
            next = next.filter { element in
                if element.pinned { return true }
                keptUnpinned += 1
                return keptUnpinned <= unpinnedAllowed
            }
        }
        items = next
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
