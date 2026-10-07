import Foundation

/// Interface language: Russian or English (Settings → Language).
enum Lang: String, Codable, CaseIterable, Identifiable, Sendable {
    case ru, en

    var id: String { rawValue }

    static var system: Lang {
        let code = Locale.preferredLanguages.first.map { String($0.prefix(2)).lowercased() } ?? "en"
        return ["ru", "uk", "be", "kk", "ky", "uz"].contains(code) ? .ru : .en
    }

    var nativeName: String { self == .ru ? "Русский" : "English" }
    var locale: Locale { Locale(identifier: self == .ru ? "ru_RU" : "en_US") }
}

/// Translations for code outside views (models, logs, errors). Views use `settings.t(…)`,
/// which re-renders them when the language changes.
enum L10n {
    nonisolated(unsafe) static var lang: Lang = .system
    static func t(_ ru: String, _ en: String) -> String { lang == .ru ? ru : en }
}
