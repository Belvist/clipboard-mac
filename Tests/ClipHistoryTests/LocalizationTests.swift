import XCTest
@testable import ClipHistoryCore

final class LocalizationTests: XCTestCase {

    override func tearDown() {
        // restore to English so other tests are deterministic
        L10n.shared.set(.en)
        super.tearDown()
    }

    func testEnglishTranslations() {
        L10n.shared.set(.en)
        XCTAssertEqual(L10n.shared.tr("clipboard"), "Clipboard")
        XCTAssertEqual(L10n.shared.tr("settings"), "Settings")
        XCTAssertEqual(L10n.shared.tr("quit"), "Quit")
        XCTAssertEqual(L10n.shared.tr("clear"), "Clear")
    }

    func testRussianTranslations() {
        L10n.shared.set(.ru)
        XCTAssertEqual(L10n.shared.tr("clipboard"), "Буфер обмена")
        XCTAssertEqual(L10n.shared.tr("settings"), "Настройки")
        XCTAssertEqual(L10n.shared.tr("quit"), "Выход")
    }

    func testMissingKeyReturnsKey() {
        L10n.shared.set(.en)
        XCTAssertEqual(L10n.shared.tr("this_key_does_not_exist"), "this_key_does_not_exist")
    }

    func testProjectLabel() {
        L10n.shared.set(.en)
        XCTAssertEqual(L10n.shared.projectLabel("Development"), "Development")
        XCTAssertEqual(L10n.shared.projectLabel("Web"), "Web")
        XCTAssertEqual(L10n.shared.projectLabel("Other"), "Other")
        XCTAssertEqual(L10n.shared.projectLabel("UnknownTag"), "UnknownTag")
    }

    func testProjectLabelRussian() {
        L10n.shared.set(.ru)
        XCTAssertEqual(L10n.shared.projectLabel("Development"), "Разработка")
        XCTAssertEqual(L10n.shared.projectLabel("Web"), "Веб")
    }

    func testContentTypeLabel() {
        L10n.shared.set(.en)
        XCTAssertEqual(L10n.shared.contentTypeLabel(.password), "password")
        XCTAssertEqual(L10n.shared.contentTypeLabel(.url), "url")
        XCTAssertEqual(L10n.shared.contentTypeLabel(.image), "image")
        XCTAssertEqual(L10n.shared.contentTypeLabel(.text), "text")
    }

    func testContentTypeLabelRussian() {
        L10n.shared.set(.ru)
        XCTAssertEqual(L10n.shared.contentTypeLabel(.password), "пароль")
        XCTAssertEqual(L10n.shared.contentTypeLabel(.url), "ссылка")
    }

    func testLanguagePersistence() {
        L10n.shared.set(.ru)
        XCTAssertEqual(L10n.shared.language, .ru)
        // simulate a fresh instance reading from UserDefaults
        let fresh = L10n()
        XCTAssertEqual(fresh.language, .ru)
        L10n.shared.set(.en)
    }

    func testLanguageLabels() {
        XCTAssertEqual(AppLanguage.en.label, "English")
        XCTAssertEqual(AppLanguage.ru.label, "Русский")
        XCTAssertEqual(AppLanguage.allCases.count, 2)
    }
}
