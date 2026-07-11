import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case en, ru

    var label: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        }
    }
}

final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: AppLanguage

    private let key = "appLanguage"

    private static let table: [String: [AppLanguage: String]] = [
        "clipboard":              [.en: "Clipboard", .ru: "Буфер обмена"],

        "tab_all":                [.en: "All Items", .ru: "Все записи"],
        "tab_project":            [.en: "By Project", .ru: "По проекту"],
        "tab_sensitive":          [.en: "Sensitive", .ru: "Конфиденциально"],

        "search_ph":              [.en: "Search text, app, project...", .ru: "Поиск по тексту, приложению, проекту..."],

        "empty_title":            [.en: "Empty", .ru: "Пусто"],
        "empty_copy":             [.en: "Copy something to start", .ru: "Скопируйте что-нибудь, чтобы начать"],
        "empty_hotkey":           [.en: "Cmd+Shift+V to open", .ru: "Cmd+Shift+V чтобы открыть"],

        "queue_cancel":           [.en: "Cancel", .ru: "Отмена"],
        "queue_paste_all":        [.en: "Paste All", .ru: "Вставить всё"],
        "queue_selected":         [.en: "%d selected", .ru: "%d выбрано"],

        "queue":                  [.en: "Queue", .ru: "Очередь"],
        "clear":                  [.en: "Clear", .ru: "Очистить"],
        "quit":                   [.en: "Quit", .ru: "Выход"],

        "pasting":                [.en: "Pasting...", .ru: "Вставка..."],
        "pasted":                 [.en: "Pasted!", .ru: "Вставлено!"],

        "downloading":            [.en: "Downloading update...", .ru: "Загрузка обновления..."],

        "quit_title":             [.en: "Quit ClipHistory?", .ru: "Выйти из ClipHistory?"],
        "cancel":                 [.en: "Cancel", .ru: "Отмена"],
        "quit_btn":               [.en: "Quit", .ru: "Выход"],

        "settings":               [.en: "Settings", .ru: "Настройки"],
        "launch_login":           [.en: "Launch at login", .ru: "Запуск при входе"],
        "launch_login_sub":       [.en: "Start when you log in", .ru: "Запуск при входе в систему"],
        "autopaste":              [.en: "Auto-paste (Accessibility)", .ru: "Авто-вставка (Универсальный доступ)"],
        "enabled":                [.en: "Enabled", .ru: "Включено"],
        "needed":                 [.en: "Needed", .ru: "Требуется"],
        "enable":                 [.en: "Enable", .ru: "Включить"],
        "updates":                [.en: "Updates", .ru: "Обновления"],
        "available":              [.en: "v%@ available", .ru: "Доступно v%@"],
        "up_to_date":             [.en: "Up to date", .ru: "Актуально"],
        "checking":               [.en: "Checking...", .ru: "Проверка..."],
        "update_btn":             [.en: "Update", .ru: "Обновить"],
        "privacy":                [.en: "Privacy", .ru: "Приватность"],
        "privacy_sub":            [.en: "100% local, no data sent", .ru: "100% локально, данные не отправляются"],
        "version":                [.en: "Version", .ru: "Версия"],
        "language":               [.en: "Language", .ru: "Язык"],

        "acc_title":              [.en: "Accessibility Access Required", .ru: "Требуется доступ к Универсальному доступу"],
        "acc_msg":                [.en: "ClipHistory needs Accessibility access to paste text into other apps.\n\nGrant access in: System Settings → Privacy & Security → Accessibility",
                                  .ru: "ClipHistory нужен доступ к Универсальному доступу для вставки текста в другие приложения.\n\nРазрешите в: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ"],
        "acc_open":               [.en: "Open Settings", .ru: "Открыть настройки"],
        "acc_later":              [.en: "Later", .ru: "Позже"],

        "update_ready":           [.en: "Update Ready", .ru: "Обновление готово"],
        "update_info":            [.en: "ClipHistory %@ will install and restart now.", .ru: "ClipHistory %@ будет установлен и перезапущен."],
        "restart":                [.en: "Restart", .ru: "Перезапустить"],

        "proj_all":               [.en: "All", .ru: "Все"],
        "proj_development":       [.en: "Development", .ru: "Разработка"],
        "proj_web":               [.en: "Web", .ru: "Веб"],
        "proj_design":            [.en: "Design", .ru: "Дизайн"],
        "proj_communication":     [.en: "Communication", .ru: "Общение"],
        "proj_documents":         [.en: "Documents", .ru: "Документы"],
        "proj_other":             [.en: "Other", .ru: "Прочее"],

        "ct_text":                [.en: "text", .ru: "текст"],
        "ct_code":                [.en: "code", .ru: "код"],
        "ct_password":            [.en: "password", .ru: "пароль"],
        "ct_email":               [.en: "email", .ru: "email"],
        "ct_url":                 [.en: "url", .ru: "ссылка"],
        "ct_phone":               [.en: "phone", .ru: "телефон"],
        "ct_creditCard":          [.en: "card", .ru: "карта"],
        "ct_table":               [.en: "table", .ru: "таблица"],
        "ct_json":                [.en: "json", .ru: "json"],
        "ct_image":               [.en: "image", .ru: "изображение"]
    ]

    init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = AppLanguage(rawValue: saved) {
            self.language = lang
        } else {
            let sys = Locale.current.language.languageCode?.identifier ?? "en"
            self.language = sys.hasPrefix("ru") ? .ru : .en
        }
    }

    func set(_ lang: AppLanguage) {
        language = lang
        UserDefaults.standard.set(lang.rawValue, forKey: key)
    }

    func tr(_ key: String) -> String {
        if let pair = L10n.table[key], let value = pair[language] {
            return value
        }
        return key
    }

    func projectLabel(_ tag: String) -> String {
        let map = ["All": "proj_all", "Development": "proj_development", "Web": "proj_web",
                   "Design": "proj_design", "Communication": "proj_communication",
                   "Documents": "proj_documents", "Other": "proj_other"]
        if let k = map[tag] { return tr(k) }
        return tag
    }

    func contentTypeLabel(_ ct: ContentType) -> String {
        let map = ["text": "ct_text", "code": "ct_code", "password": "ct_password",
                   "email": "ct_email", "url": "ct_url", "phone": "ct_phone",
                   "creditCard": "ct_creditCard", "table": "ct_table", "json": "ct_json",
                   "image": "ct_image"]
        return tr(map[ct.rawValue] ?? "ct_text")
    }
}
