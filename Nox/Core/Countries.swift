import Foundation

/// Country names (ru / en), flags and best-effort detection of the country / city from
/// server names and host names.
enum Countries {
    typealias Info = (ru: String, en: String)

    static let all: [String: Info] = [
        "NL": ("Нидерланды", "Netherlands"), "DE": ("Германия", "Germany"), "FI": ("Финляндия", "Finland"),
        "TR": ("Турция", "Turkey"), "US": ("США", "United States"), "JP": ("Япония", "Japan"),
        "KZ": ("Казахстан", "Kazakhstan"), "GB": ("Великобритания", "United Kingdom"), "FR": ("Франция", "France"),
        "SE": ("Швеция", "Sweden"), "NO": ("Норвегия", "Norway"), "DK": ("Дания", "Denmark"),
        "IS": ("Исландия", "Iceland"), "PL": ("Польша", "Poland"), "CH": ("Швейцария", "Switzerland"),
        "AT": ("Австрия", "Austria"), "ES": ("Испания", "Spain"), "IT": ("Италия", "Italy"),
        "PT": ("Португалия", "Portugal"), "IE": ("Ирландия", "Ireland"), "BE": ("Бельгия", "Belgium"),
        "LU": ("Люксембург", "Luxembourg"), "CZ": ("Чехия", "Czechia"), "HU": ("Венгрия", "Hungary"),
        "RO": ("Румыния", "Romania"), "BG": ("Болгария", "Bulgaria"), "RS": ("Сербия", "Serbia"),
        "GR": ("Греция", "Greece"), "CY": ("Кипр", "Cyprus"), "LV": ("Латвия", "Latvia"),
        "LT": ("Литва", "Lithuania"), "EE": ("Эстония", "Estonia"), "MD": ("Молдова", "Moldova"),
        "UA": ("Украина", "Ukraine"), "RU": ("Россия", "Russia"), "BY": ("Беларусь", "Belarus"),
        "GE": ("Грузия", "Georgia"), "AM": ("Армения", "Armenia"), "AZ": ("Азербайджан", "Azerbaijan"),
        "UZ": ("Узбекистан", "Uzbekistan"), "KG": ("Киргизия", "Kyrgyzstan"), "IL": ("Израиль", "Israel"),
        "AE": ("ОАЭ", "UAE"), "IN": ("Индия", "India"), "SG": ("Сингапур", "Singapore"),
        "HK": ("Гонконг", "Hong Kong"), "TW": ("Тайвань", "Taiwan"), "KR": ("Южная Корея", "South Korea"),
        "CN": ("Китай", "China"), "VN": ("Вьетнам", "Vietnam"), "TH": ("Таиланд", "Thailand"),
        "MY": ("Малайзия", "Malaysia"), "ID": ("Индонезия", "Indonesia"), "AU": ("Австралия", "Australia"),
        "CA": ("Канада", "Canada"), "MX": ("Мексика", "Mexico"), "BR": ("Бразилия", "Brazil"),
        "AR": ("Аргентина", "Argentina"), "ZA": ("ЮАР", "South Africa"),
    ]

    static let cities: [String: (ru: String, code: String)] = [
        "amsterdam": ("Амстердам", "NL"), "rotterdam": ("Роттердам", "NL"),
        "frankfurt": ("Франкфурт", "DE"), "berlin": ("Берлин", "DE"), "munich": ("Мюнхен", "DE"), "nuremberg": ("Нюрнберг", "DE"),
        "helsinki": ("Хельсинки", "FI"), "istanbul": ("Стамбул", "TR"), "ankara": ("Анкара", "TR"),
        "new york": ("Нью-Йорк", "US"), "los angeles": ("Лос-Анджелес", "US"), "miami": ("Майами", "US"),
        "dallas": ("Даллас", "US"), "chicago": ("Чикаго", "US"), "seattle": ("Сиэтл", "US"), "san jose": ("Сан-Хосе", "US"),
        "tokyo": ("Токио", "JP"), "osaka": ("Осака", "JP"),
        "almaty": ("Алматы", "KZ"), "astana": ("Астана", "KZ"),
        "london": ("Лондон", "GB"), "paris": ("Париж", "FR"), "stockholm": ("Стокгольм", "SE"),
        "oslo": ("Осло", "NO"), "copenhagen": ("Копенгаген", "DK"), "reykjavik": ("Рейкьявик", "IS"),
        "warsaw": ("Варшава", "PL"), "zurich": ("Цюрих", "CH"), "vienna": ("Вена", "AT"),
        "madrid": ("Мадрид", "ES"), "milan": ("Милан", "IT"), "lisbon": ("Лиссабон", "PT"),
        "dublin": ("Дублин", "IE"), "brussels": ("Брюссель", "BE"), "prague": ("Прага", "CZ"),
        "budapest": ("Будапешт", "HU"), "bucharest": ("Бухарест", "RO"), "sofia": ("София", "BG"),
        "belgrade": ("Белград", "RS"), "athens": ("Афины", "GR"), "riga": ("Рига", "LV"),
        "vilnius": ("Вильнюс", "LT"), "tallinn": ("Таллин", "EE"), "chisinau": ("Кишинёв", "MD"),
        "kyiv": ("Киев", "UA"), "moscow": ("Москва", "RU"), "saint petersburg": ("Санкт-Петербург", "RU"),
        "tbilisi": ("Тбилиси", "GE"), "yerevan": ("Ереван", "AM"), "baku": ("Баку", "AZ"),
        "tashkent": ("Ташкент", "UZ"), "bishkek": ("Бишкек", "KG"), "tel aviv": ("Тель-Авив", "IL"),
        "dubai": ("Дубай", "AE"), "mumbai": ("Мумбаи", "IN"), "singapore": ("Сингапур", "SG"),
        "hong kong": ("Гонконг", "HK"), "taipei": ("Тайбэй", "TW"), "seoul": ("Сеул", "KR"),
        "sydney": ("Сидней", "AU"), "toronto": ("Торонто", "CA"), "sao paulo": ("Сан-Паулу", "BR"),
    ]

    /// Airport-style city codes often used in hostnames: nl-ams-2 → Amsterdam.
    static let cityCodes: [String: String] = [
        "ams": "amsterdam", "fra": "frankfurt", "ber": "berlin", "muc": "munich", "hel": "helsinki",
        "ist": "istanbul", "nyc": "new york", "jfk": "new york", "lax": "los angeles", "mia": "miami",
        "dfw": "dallas", "sea": "seattle", "tyo": "tokyo", "nrt": "tokyo", "osa": "osaka", "ala": "almaty",
        "lon": "london", "lhr": "london", "par": "paris", "cdg": "paris", "sto": "stockholm", "arn": "stockholm",
        "osl": "oslo", "cph": "copenhagen", "waw": "warsaw", "zrh": "zurich", "vie": "vienna", "mad": "madrid",
        "mil": "milan", "lis": "lisbon", "dub": "dublin", "bru": "brussels", "prg": "prague", "bud": "budapest",
        "buh": "bucharest", "sof": "sofia", "beg": "belgrade", "ath": "athens", "rix": "riga", "vno": "vilnius",
        "tll": "tallinn", "tbs": "tbilisi", "evn": "yerevan", "dxb": "dubai", "sin": "singapore",
        "hkg": "hong kong", "sel": "seoul", "icn": "seoul", "syd": "sydney", "yyz": "toronto",
    ]

    static func name(_ code: String, _ lang: Lang) -> String? {
        guard let info = all[code.uppercased()] else { return nil }
        return lang == .ru ? info.ru : info.en
    }

    static func city(_ city: String, _ lang: Lang) -> String {
        guard !city.isEmpty else { return "" }
        if lang == .ru, let c = cities[city.lowercased()] { return c.ru }
        return city.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func flagEmoji(_ code: String) -> String {
        let base: UInt32 = 0x1F1E6
        var out = ""
        for ch in code.uppercased().unicodeScalars where ch.value >= 65 && ch.value <= 90 {
            if let s = Unicode.Scalar(base + ch.value - 65) { out.unicodeScalars.append(s) }
        }
        return out
    }

    /// Code from the first flag emoji in a string ("🇳🇱 NL-1" → "NL").
    static func codeFromFlag(in text: String) -> String? {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count >= 2 else { return nil }
        for i in 0..<(scalars.count - 1) {
            let a = scalars[i].value, b = scalars[i + 1].value
            if (0x1F1E6...0x1F1FF).contains(a), (0x1F1E6...0x1F1FF).contains(b) {
                let code = String(UnicodeScalar(UInt8(a - 0x1F1E6 + 65))) + String(UnicodeScalar(UInt8(b - 0x1F1E6 + 65)))
                return code == "UK" ? "GB" : code
            }
        }
        return nil
    }

    /// Removes flag emoji and decorative separators from a name.
    static func stripFlags(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for s in text.unicodeScalars where !(0x1F1E6...0x1F1FF).contains(s.value) { scalars.append(s) }
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|·-–—_:,"))
        return String(scalars)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: trimSet)
    }

    /// Best-effort detection: (country code, English city) — either may be empty.
    static func detect(in text: String, host: String) -> (code: String, city: String) {
        let lower = text.lowercased()
        var code = codeFromFlag(in: text) ?? ""
        var city = ""

        for (en, info) in cities where lower.contains(en) || lower.contains(info.ru.lowercased()) {
            city = en
            if code.isEmpty { code = info.code }
            break
        }
        if code.isEmpty {
            for (c, info) in all where lower.contains(info.en.lowercased()) || lower.contains(info.ru.lowercased()) {
                code = c
                break
            }
        }
        if code.isEmpty {
            // Uppercase 2-letter tokens in the name: "NL-1", "DE Hetzner".
            let tokens = text.components(separatedBy: CharacterSet.letters.inverted)
            for t in tokens where t.count == 2 && t == t.uppercased() {
                let c = t == "UK" ? "GB" : t
                if all[c] != nil { code = c; break }
            }
        }
        // Host labels: nl-ams-2.example.com
        let labels = host.lowercased().split(separator: ".").first.map { $0.split(separator: "-").map(String.init) } ?? []
        if code.isEmpty, let first = labels.first, first.count == 2, all[first.uppercased()] != nil, labels.count > 1 || host.split(separator: ".").count > 2 {
            code = first.uppercased()
        }
        if city.isEmpty {
            for l in labels {
                if let c = cityCodes[l] { city = c; break }
            }
        }
        if code.isEmpty, !city.isEmpty, let info = cities[city] { code = info.code }
        return (code, city)
    }

    /// Codes sorted by localized name, for pickers.
    static func sortedCodes(_ lang: Lang) -> [String] {
        all.keys.sorted { (name($0, lang) ?? $0) < (name($1, lang) ?? $1) }
    }

    static func isPrivateHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h.hasSuffix(".local") || h.hasSuffix(".lan") || h.hasSuffix(".home") || h == "localhost" { return true }
        let parts = h.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1])) || parts[0] == 127
    }
}
