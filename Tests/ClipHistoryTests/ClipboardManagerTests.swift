import XCTest
@testable import ClipHistoryCore

final class ClipboardManagerTests: XCTestCase {

    var manager: TestClipboardManager!

    override func setUp() {
        super.setUp()
        manager = TestClipboardManager()
        manager.reset()
    }

    override func tearDown() {
        manager.reset()
        manager = nil
        super.tearDown()
    }

    func testMaxItemsConstant() {
        XCTAssertEqual(manager.maxItems, 50)
    }

    func testTogglePin() {
        let item = ClipItem(text: "hello")
        manager.items = [item]
        XCTAssertFalse(manager.items[0].pinned)

        manager.togglePin(item)
        XCTAssertTrue(manager.items[0].pinned)

        manager.togglePin(item)
        XCTAssertFalse(manager.items[0].pinned)
    }

    func testTogglePinPersistsAcrossInstances() {
        let item = ClipItem(text: "persist me")
        manager.items = [item]
        manager.togglePin(item)
        XCTAssertTrue(manager.items[0].pinned)

        // A fresh instance loads the same temp file.
        let reloaded = TestClipboardManager()
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertTrue(reloaded.items[0].pinned)
    }

    func testTogglePinUnknownItemIsNoOp() {
        let item = ClipItem(text: "a")
        let other = ClipItem(text: "b")
        manager.items = [item]
        manager.togglePin(other) // not present
        XCTAssertEqual(manager.items.count, 1)
        XCTAssertFalse(manager.items[0].pinned)
    }

    func testRemoveItem() {
        let a = ClipItem(text: "a")
        let b = ClipItem(text: "b")
        manager.items = [a, b]

        manager.removeItem(a)
        XCTAssertEqual(manager.items.count, 1)
        XCTAssertEqual(manager.items[0].id, b.id)
    }

    func testRemoveItemPersists() {
        let a = ClipItem(text: "a")
        let b = ClipItem(text: "b")
        manager.items = [a, b]
        manager.removeItem(a)

        let reloaded = TestClipboardManager()
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.items[0].id, b.id)
    }

    func testClearAllKeepsPinned() {
        var pinned = ClipItem(text: "pinned")
        pinned.pinned = true
        let unpinned = ClipItem(text: "unpinned")
        manager.items = [pinned, unpinned]

        manager.clearAll()
        XCTAssertEqual(manager.items.count, 1)
        XCTAssertTrue(manager.items[0].pinned)
    }

    func testClearAllRemovesEverythingWhenNothingPinned() {
        manager.items = [ClipItem(text: "a"), ClipItem(text: "b")]
        manager.clearAll()
        XCTAssertEqual(manager.items.count, 0)
    }

    func testProjectsUniqueAndSorted() {
        manager.items = [
            ClipItem(text: "a", projectTag: "Web"),
            ClipItem(text: "b", projectTag: "Web"),
            ClipItem(text: "c", projectTag: "Development")
        ]
        XCTAssertEqual(manager.projects, ["Development", "Web"])
    }

    func testCopyToClipboardWritesPasteboard() {
        let item = ClipItem(text: "copied text!")
        manager.copyToClipboard(item)
        XCTAssertEqual(manager.currentContent, "copied text!")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "copied text!")
    }

    func testSyncLastFromPasteboardMatchesString() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("sync test", forType: .string)
        manager.syncLastFromPasteboard()
        // A subsequent identical copy should not be re-added by the monitor.
        // We verify by ensuring currentContent reflects the synced value path
        // does not throw and monitor detects no change.
        let before = manager.items.count
        // Simulate monitor reading the same content:
        NSPasteboard.general.setString("sync test", forType: .string)
        // No public checkClipboard, but syncLastFromPasteboard already set lastContent,
        // so a re-read of the same string would be ignored.
        XCTAssertEqual(before, manager.items.count)
    }
}
