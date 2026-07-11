import XCTest
@testable import ClipHistoryCore

final class SensitiveDetectorTests: XCTestCase {

    func testPasswordKeyValue() {
        let (sensitive, type) = SensitiveDetector.detect("password: secret123")
        XCTAssertTrue(sensitive)
        XCTAssertEqual(type, .password)

        let r2 = SensitiveDetector.detect("api_key=\"abc123def456\"")
        XCTAssertTrue(r2.isSensitive)
        XCTAssertEqual(r2.type, .password)

        let r3 = SensitiveDetector.detect("access_key = XYZ123")
        XCTAssertTrue(r3.isSensitive)
    }

    func testBearerToken() {
        let (sensitive, type) = SensitiveDetector.detect("Bearer eyJhbGciOiJIUzI1NiIsInR5")
        XCTAssertTrue(sensitive)
        XCTAssertEqual(type, .password)
    }

    func testBase64Secret() {
        let long = String(repeating: "a", count: 44)
        let (sensitive, type) = SensitiveDetector.detect(long)
        XCTAssertTrue(sensitive)
        XCTAssertEqual(type, .password)
    }

    func testCreditCard() {
        let (sensitive, type) = SensitiveDetector.detect("4111 1111 1111 1111")
        XCTAssertTrue(sensitive)
        XCTAssertEqual(type, .creditCard)

        let (s2, t2) = SensitiveDetector.detect("5500-0000-0000-0004")
        XCTAssertTrue(s2)
        XCTAssertEqual(t2, .creditCard)
    }

    func testNotCreditCard() {
        // too short
        let (sensitive, _) = SensitiveDetector.detect("123")
        XCTAssertFalse(sensitive)
    }

    func testEmail() {
        let (sensitive, type) = SensitiveDetector.detect("user@example.com")
        XCTAssertFalse(sensitive)
        XCTAssertEqual(type, .email)
    }

    func testURL() {
        let (sensitive, type) = SensitiveDetector.detect("https://example.com/page")
        XCTAssertFalse(sensitive)
        XCTAssertEqual(type, .url)

        let (s2, t2) = SensitiveDetector.detect("www.example.com")
        XCTAssertFalse(s2)
        XCTAssertEqual(t2, .url)
    }

    func testPhone() {
        let (sensitive, type) = SensitiveDetector.detect("+1 (202) 555-0123")
        XCTAssertFalse(sensitive)
        XCTAssertEqual(type, .phone)

        let (s2, t2) = SensitiveDetector.detect("(800) 123-4567")
        XCTAssertFalse(s2)
        XCTAssertEqual(t2, .phone)
    }

    func testCode() {
        let (sensitive, type) = SensitiveDetector.detect("func hello() { return 1 }")
        XCTAssertFalse(sensitive)
        XCTAssertEqual(type, .code)

        let (s2, t2) = SensitiveDetector.detect("import Foundation")
        XCTAssertFalse(s2)
        XCTAssertEqual(t2, .code)
    }

    func testJSON() {
        let (sensitive, type) = SensitiveDetector.detect("{\"a\": 1, \"b\": 2}")
        XCTAssertFalse(sensitive)
        XCTAssertEqual(type, .json)
    }

    func testTable() {
        let (sensitive, type) = SensitiveDetector.detect("a\tb\tc\nd\te\tf")
        XCTAssertFalse(sensitive)
        XCTAssertEqual(type, .table)

        let (s2, t2) = SensitiveDetector.detect("a|b|c\nd|e|f")
        XCTAssertFalse(s2)
        XCTAssertEqual(t2, .table)
    }

    func testPlainText() {
        let (sensitive, type) = SensitiveDetector.detect("just some ordinary text")
        XCTAssertFalse(sensitive)
        XCTAssertEqual(type, .text)
    }

    func testEmptyAndWhitespace() {
        let (sensitive, type) = SensitiveDetector.detect("   ")
        XCTAssertFalse(sensitive)
        XCTAssertEqual(type, .text)
    }
}
