import XCTest
@testable import ClipHistoryCore

final class PasteQueueTests: XCTestCase {

    override func tearDown() {
        PasteQueue.shared.stop()
        super.tearDown()
    }

    func testStopResetsState() {
        let q = PasteQueue.shared
        q.stop()
        XCTAssertFalse(q.isActive)
        XCTAssertEqual(q.items.count, 0)
        XCTAssertEqual(q.currentIndex, 0)
    }

    func testEnqueueSetsState() {
        let q = PasteQueue.shared
        q.stop()
        let items = [ClipItem(text: "one"), ClipItem(text: "two")]
        q.enqueue(items)

        XCTAssertTrue(q.isActive)
        XCTAssertEqual(q.items.count, 2)
        XCTAssertEqual(q.currentIndex, 0)

        q.stop()
        XCTAssertFalse(q.isActive)
    }
}
