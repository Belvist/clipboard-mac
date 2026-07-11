import XCTest
@testable import ClipHistoryCore

final class ProjectDetectorTests: XCTestCase {

    func testDevelopmentBundle() {
        XCTAssertEqual(ProjectDetector.detectProject(app: "Xcode", bundle: "com.apple.dt.Xcode"), "Development")
        XCTAssertEqual(ProjectDetector.detectProject(app: "IntelliJ", bundle: "com.jetbrains.intellij"), "Development")
        XCTAssertEqual(ProjectDetector.detectProject(app: "Code", bundle: "com.microsoft.VSCode"), "Development")
    }

    func testWebBundle() {
        XCTAssertEqual(ProjectDetector.detectProject(app: "Safari", bundle: "com.apple.Safari"), "Web")
        XCTAssertEqual(ProjectDetector.detectProject(app: "Chrome", bundle: "com.google.Chrome"), "Web")
    }

    func testDesignBundle() {
        XCTAssertEqual(ProjectDetector.detectProject(app: "Figma", bundle: "com.figma.Desktop"), "Design")
        XCTAssertEqual(ProjectDetector.detectProject(app: "Photoshop", bundle: "com.adobe.Photoshop"), "Design")
    }

    func testCommunicationByAppName() {
        XCTAssertEqual(ProjectDetector.detectProject(app: "Mail", bundle: "com.apple.Mail"), "Communication")
        XCTAssertEqual(ProjectDetector.detectProject(app: "Messages", bundle: "com.apple.iChat"), "Communication")
    }

    func testDocumentsByAppName() {
        XCTAssertEqual(ProjectDetector.detectProject(app: "Microsoft Word", bundle: "com.microsoft.Word"), "Documents")
        XCTAssertEqual(ProjectDetector.detectProject(app: "Notion", bundle: "notion.id"), "Documents")
    }

    func testOtherFallback() {
        XCTAssertEqual(ProjectDetector.detectProject(app: "Calculator", bundle: "com.apple.calculator"), "Other")
    }
}
