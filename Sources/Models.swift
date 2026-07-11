import Cocoa

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
    var imageData: Data?

    init(text: String, pinned: Bool = false, sourceApp: String = "", sourceBundle: String = "",
         contentType: ContentType = .text, isSensitive: Bool = false, projectTag: String = "", imageData: Data? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.pinned = pinned
        self.sourceApp = sourceApp
        self.sourceBundle = sourceBundle
        self.contentType = contentType
        self.isSensitive = isSensitive
        self.projectTag = projectTag
        self.imageData = imageData
    }

    var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }

    var nsImage: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool { lhs.id == rhs.id }
}

enum ContentType: String, Codable {
    case text, code, password, email, url, phone, creditCard, table, json, image
}

extension Notification.Name {
    static let toggleClipWindow = Notification.Name("toggleClipWindow")
}
