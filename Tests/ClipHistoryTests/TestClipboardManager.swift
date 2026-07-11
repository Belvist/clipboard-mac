import XCTest
@testable import ClipHistoryCore

// MARK: - Test double

/// ClipboardManager that stores its history in a shared temp file so tests
/// never touch the real user history at ~/Library/Application Support/ClipHistory,
/// and persistence can be verified by creating a second instance.
final class TestClipboardManager: ClipboardManager {
    static let sharedTempDir: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipHistoryTests")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    override var storageURL: URL {
        get { Self.sharedTempDir.appendingPathComponent("history.json") }
        set { }
    }

    override init() {
        super.init()
    }

    /// Clear in-memory state and the backing file.
    func reset() {
        items = []
        try? FileManager.default.removeItem(at: storageURL)
    }
}
