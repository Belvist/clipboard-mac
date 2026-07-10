import Cocoa
import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Models

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    var pinned: Bool
    var sourceApp: String
    var sourceBundle: String
    var contentType: ContentType
    var isSensitive: Bool
    var projectTag: String

    init(text: String, pinned: Bool = false, sourceApp: String = "", sourceBundle: String = "", contentType: ContentType = .text, isSensitive: Bool = false, projectTag: String = "") {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.pinned = pinned
        self.sourceApp = sourceApp
        self.sourceBundle = sourceBundle
        self.contentType = contentType
        self.isSensitive = isSensitive
        self.projectTag = projectTag
    }

    var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool { lhs.id == rhs.id }
}

enum ContentType: String, Codable {
    case text, code, password, email, url, phone, creditCard, table, json
}

// MARK: - Sensitive Data Detector

struct SensitiveDetector {
    static func detect(_ text: String) -> (isSensitive: Bool, type: ContentType) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if isPassword(trimmed) { return (true, .password) }
        if isCreditCard(trimmed) { return (true, .creditCard) }
        if isEmail(trimmed) { return (false, .email) }
        if isURL(trimmed) { return (false, .url) }
        if isPhone(trimmed) { return (false, .phone) }
        if isCode(trimmed) { return (false, .code) }
        if isJSON(trimmed) { return (false, .json) }
        if isTable(trimmed) { return (false, .table) }

        return (false, .text)
    }

    private static func isPassword(_ s: String) -> Bool {
        let patterns = [
            "(?i)(password|passwd|pwd|pass|secret|token|api[_-]?key|access[_-]?key)\\s*[:=]\\s*['\"]?\\S+",
            "(?i)(bearer|basic)\\s+[a-zA-Z0-9\\-._~+/]+=*",
            "^[a-zA-Z0-9+/]{40,}={0,2}$"
        ]
        return patterns.contains { s.range(of: $0, options: .regularExpression) != nil }
    }

    private static func isCreditCard(_ s: String) -> Bool {
        let cleaned = s.replacingOccurrences(of: "[\\s-]", with: "", options: .regularExpression)
        return cleaned.count >= 13 && cleaned.count <= 19 && cleaned.allSatisfy(\.isNumber)
    }

    private static func isEmail(_ s: String) -> Bool {
        s.range(of: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", options: .regularExpression) != nil
    }

    private static func isURL(_ s: String) -> Bool {
        s.hasPrefix("http://") || s.hasPrefix("https://") || s.hasPrefix("www.")
    }

    private static func isPhone(_ s: String) -> Bool {
        let cleaned = s.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        return cleaned.count >= 7 && cleaned.count <= 15 && (s.contains("+") || s.contains("("))
    }

    private static func isCode(_ s: String) -> Bool {
        let codePatterns = ["func ", "class ", "import ", "const ", "let ", "var ", "def ", "function(",
                           "return ", "if (", "for (", "while (", "#include", "// ", "/* ", "=>", "->"]
        return codePatterns.contains { s.contains($0) }
    }

    private static func isJSON(_ s: String) -> Bool {
        (s.hasPrefix("{") && s.hasSuffix("}")) || (s.hasPrefix("[") && s.hasSuffix("]"))
    }

    private static func isTable(_ s: String) -> Bool {
        let lines = s.components(separatedBy: "\n")
        guard lines.count >= 2 else { return false }
        let tabCount = lines.filter { $0.contains("\t") }.count
        let pipeCount = lines.filter { $0.contains("|") }.count
        return tabCount >= 2 || pipeCount >= 2
    }
}

// MARK: - Project Detector

struct ProjectDetector {
    static func detectProject(app: String, bundle: String) -> String {
        let devBundles = ["com.apple.dt.Xcode", "com.jetbrains.intellij", "com.jetbrains.WebStorm",
                         "com.microsoft.VSCode", "com.sublimetext.4", "com.github.atom",
                         "io.hyper.Hyper", "com.apple.Terminal", "com.googlecode.iterm2"]
        let browserBundles = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
                             "com.microsoft.edgemac", "com.opera.Opera"]
        let designBundles = ["com.adobe.Photoshop", "com.sketch.SKetch", "com.figma.Desktop"]

        if devBundles.contains(bundle) { return "Development" }
        if browserBundles.contains(bundle) { return "Web" }
        if designBundles.contains(bundle) { return "Design" }
        if app.lowercased().contains("mail") || app.lowercased().contains("message") { return "Communication" }
        if app.lowercased().contains("word") || app.lowercased().contains("pages") || app.lowercased().contains("notion") { return "Documents" }
        return "Other"
    }
}

// MARK: - Paste Queue

class PasteQueue: ObservableObject {
    static let shared = PasteQueue()

    @Published var items: [ClipItem] = []
    @Published var isActive = false
    @Published var currentIndex = 0

    private var timer: Timer?

    func enqueue(_ items: [ClipItem]) {
        self.items = items
        self.currentIndex = 0
        self.isActive = true
        pasteNext()
    }

    func pasteNext() {
        guard currentIndex < items.count else {
            stop()
            return
        }

        let item = items[currentIndex]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let src = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
                keyUp?.flags = .maskCommand
                keyUp?.post(tap: .cghidEventTap)

                self.currentIndex += 1
                if self.currentIndex < self.items.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.pasteNext()
                    }
                } else {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        isActive = false
        items = []
        currentIndex = 0
    }
}

// MARK: - Clipboard Manager

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published var items: [ClipItem] = []
    @Published var currentContent: String = ""

    private var timer: Timer?
    private var lastContent: String = ""
    let maxItems = 50

    private let storageURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClipHistory")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() { load() }

    func startMonitoring() {
        checkClipboard()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        save()
    }

    private func checkClipboard() {
        guard let content = NSPasteboard.general.string(forType: .string),
              !content.isEmpty,
              content != lastContent else { return }

        lastContent = content
        currentContent = content

        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "Unknown"
        let bundleID = frontApp?.bundleIdentifier ?? ""
        let detection = SensitiveDetector.detect(content)
        let project = ProjectDetector.detectProject(app: appName, bundle: bundleID)

        DispatchQueue.main.async {
            let item = ClipItem(
                text: content,
                sourceApp: appName,
                sourceBundle: bundleID,
                contentType: detection.type,
                isSensitive: detection.isSensitive,
                projectTag: project
            )
            self.items.insert(item, at: 0)
            if self.items.count > self.maxItems {
                self.items = Array(self.items.prefix(self.maxItems))
            }
            self.save()
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastContent = text
        currentContent = text
    }

    func togglePin(_ item: ClipItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].pinned.toggle()
            save()
        }
    }

    func removeItem(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearAll() {
        items = items.filter { $0.pinned }.prefix(maxItems).map { $0 }
        save()
    }

    func items(for project: String) -> [ClipItem] {
        items.filter { $0.projectTag == project }
    }

    var projects: [String] {
        Array(Set(items.map { $0.projectTag })).sorted()
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

// MARK: - Accessibility

func isAccessibilityEnabled() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

// MARK: - Hotkey

class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKeyRef: EventHotKeyRef?

    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .toggleClipWindow, object: nil)
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey),
                           EventHotKeyID(signature: OSType(0x4348_4B31), id: 1),
                           GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
    }
}

// MARK: - Auto Update

class UpdateChecker: ObservableObject {
    @Published var hasUpdate = false
    @Published var latestVersion = ""
    @Published var downloadURL = ""

    private let repoOwner = "earflow"
    private let repoName = "barkill"
    private let currentVersion = "1.0"

    func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            DispatchQueue.main.async {
                self.latestVersion = tagName.replacingOccurrences(of: "v", with: "")
                self.hasUpdate = self.latestVersion != self.currentVersion

                if let assets = json["assets"] as? [[String: Any]],
                   let asset = assets.first,
                   let browserURL = asset["browser_download_url"] as? String {
                    self.downloadURL = browserURL
                }
            }
        }.resume()
    }

    func openDownloadPage() {
        if let url = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension Notification.Name {
    static let toggleClipWindow = Notification.Name("toggleClipWindow")
}
