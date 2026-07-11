import XCTest
@testable import ClipHistoryCore

final class UpdateCheckerTests: XCTestCase {

    func testIsNewer() {
        XCTAssertTrue(UpdateChecker.isNewer(latest: "1.1", current: "1.0"))
        XCTAssertTrue(UpdateChecker.isNewer(latest: "2.0", current: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer(latest: "1.0", current: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer(latest: "", current: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer(latest: "1.1", current: ""))
    }

    func testCurrentVersionReadsBundle() {
        // currentVersion should report whatever CFBundleShortVersionString the
        // running bundle provides (the test bundle happens to have one).
        let uc = UpdateChecker()
        let expected = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        XCTAssertEqual(uc.currentVersion, expected)
        XCTAssertFalse(uc.currentVersion.isEmpty)
    }

    func testInitialState() {
        let uc = UpdateChecker()
        XCTAssertFalse(uc.hasUpdate)
        XCTAssertFalse(uc.isChecking)
        XCTAssertFalse(uc.isDownloading)
        XCTAssertEqual(uc.latestVersion, "")
        XCTAssertEqual(uc.downloadURL, "")
    }
}
