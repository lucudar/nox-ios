import Foundation

/// Numbers and units in the current language (decimal comma in Russian).
enum Fmt {
    static func dec(_ v: Double, _ digits: Int = 1, _ lang: Lang = L10n.lang) -> String {
        let s = String(format: "%.\(max(0, digits))f", v)
        return lang == .ru ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    static func speedUnit(_ lang: Lang) -> String { lang == .ru ? "Мбит/с" : "Mbps" }
    static func msUnit(_ lang: Lang) -> String { lang == .ru ? "мс" : "ms" }
    static func gbUnit(_ lang: Lang) -> String { lang == .ru ? "ГБ" : "GB" }

    static func ms(_ v: Int, _ lang: Lang) -> String { "\(v) \(msUnit(lang))" }

    /// Traffic amount: "4,2 МБ", "820 МБ", "3,4 ГБ".
    static func amount(_ mb: Double, _ lang: Lang) -> (value: String, unit: String) {
        let ru = lang == .ru
        if mb >= 1024 {
            let gb = mb / 1024
            return (dec(gb, gb >= 100 ? 0 : 1, lang), ru ? "ГБ" : "GB")
        }
        let unit = ru ? "МБ" : "MB"
        if mb >= 10 || mb <= 0 { return ("\(Int(mb.rounded()))", unit) }
        return (dec(mb, 1, lang), unit)
    }

    static func size(_ mb: Double, _ lang: Lang) -> String {
        let a = amount(mb, lang)
        return "\(a.value) \(a.unit)"
    }

    /// Speed in Mbit/s: one decimal below 10.
    static func speed(_ mbps: Double, _ lang: Lang) -> String {
        dec(mbps, mbps < 10 ? 1 : 0, lang)
    }
    static func gb(_ v: Double, _ lang: Lang) -> String { "\(dec(v, 1, lang)) \(gbUnit(lang))" }

    /// Session timer: 00:42:17.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }

    static func hoursUnit(_ lang: Lang) -> String { lang == .ru ? "ч" : "h" }
    static func minutesUnit(_ lang: Lang) -> String { lang == .ru ? "мин" : "min" }

    /// "2 ч назад" / "2 hr. ago"
    static func relative(_ date: Date, _ lang: Lang, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        let ru = lang == .ru
        switch s {
        case ..<60: return ru ? "только что" : "just now"
        case ..<3600: return ru ? "\(s / 60) мин назад" : "\(s / 60) min ago"
        case ..<86400: return ru ? "\(s / 3600) ч назад" : "\(s / 3600) h ago"
        default: return ru ? "\(s / 86400) дн назад" : "\(s / 86400) d ago"
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
