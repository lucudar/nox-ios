import Foundation

// MARK: - Themes

struct Palette: Equatable, Sendable {
    let bg: RGB
    let surface: RGB
    let elevated: RGB
    /// Secondary tint used by the aurora background.
    let tint: RGB
}

enum ThemeID: String, Codable, CaseIterable, Identifiable, Sendable {
    case obsidian, graphite, forest, midnight, amethyst
    var id: String { rawValue }

    func title(_ l: Lang) -> String {
        switch self {
        case .obsidian: return l == .ru ? "Обсидиан" : "Obsidian"
        case .graphite: return l == .ru ? "Графит" : "Graphite"
        case .forest: return l == .ru ? "Лес" : "Forest"
        case .midnight: return l == .ru ? "Полночь" : "Midnight"
        case .amethyst: return l == .ru ? "Аметист" : "Amethyst"
        }
    }

    var palette: Palette {
        switch self {
        case .obsidian: return Palette(bg: RGB(hex: 0x000000), surface: RGB(hex: 0x111212), elevated: RGB(hex: 0x1C1D1D), tint: RGB(hex: 0x0F2A1D))
        case .graphite: return Palette(bg: RGB(hex: 0x111214), surface: RGB(hex: 0x1B1C1F), elevated: RGB(hex: 0x26272B), tint: RGB(hex: 0x2A2C30))
        case .forest: return Palette(bg: RGB(hex: 0x040A06), surface: RGB(hex: 0x0C1610), elevated: RGB(hex: 0x15221A), tint: RGB(hex: 0x1D3A12))
        case .midnight: return Palette(bg: RGB(hex: 0x04070D), surface: RGB(hex: 0x0B111C), elevated: RGB(hex: 0x141C2B), tint: RGB(hex: 0x0E2340))
        case .amethyst: return Palette(bg: RGB(hex: 0x07050D), surface: RGB(hex: 0x120E1D), elevated: RGB(hex: 0x1C162B), tint: RGB(hex: 0x2A1650))
        }
    }
}

// MARK: - Accents

struct AccentOption: Identifiable, Sendable {
    let id: String
    let ru: String
    let en: String
    let rgb: RGB
    func title(_ l: Lang) -> String { l == .ru ? ru : en }
}

enum Accents {
    static let emerald = RGB(hex: 0x4FD08D)
    static let mint = RGB(hex: 0x5EE3C8)
    static let lime = RGB(hex: 0xB7E94F)
    static let sky = RGB(hex: 0x6EC3FF)
    static let violet = RGB(hex: 0xA07CFF)
    static let amber = RGB(hex: 0xF6B845)
    static let silver = RGB(hex: 0xDCDFDB)

    static let all: [AccentOption] = [
        .init(id: "emerald", ru: "Изумруд", en: "Emerald", rgb: emerald),
        .init(id: "mint", ru: "Мята", en: "Mint", rgb: mint),
        .init(id: "lime", ru: "Лайм", en: "Lime", rgb: lime),
        .init(id: "sky", ru: "Небо", en: "Sky", rgb: sky),
        .init(id: "violet", ru: "Фиолетовый", en: "Violet", rgb: violet),
        .init(id: "amber", ru: "Янтарь", en: "Amber", rgb: amber),
        .init(id: "silver", ru: "Серебро", en: "Silver", rgb: silver),
    ]

    static func option(for rgb: RGB) -> AccentOption? { all.first { $0.rgb.distance(to: rgb) < 0.012 } }

    static func name(for rgb: RGB, _ l: Lang) -> String {
        option(for: rgb)?.title(l) ?? (l == .ru ? "Свой" : "Custom")
    }
}

// MARK: - Options

enum BackgroundKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case solid, aurora, grid, grain, photo
    var id: String { rawValue }
    func title(_ l: Lang) -> String {
        switch self {
        case .solid: return l == .ru ? "Сплошной" : "Solid"
        case .aurora: return l == .ru ? "Аврора" : "Aurora"
        case .grid: return l == .ru ? "Сетка" : "Grid"
        case .grain: return l == .ru ? "Зерно" : "Grain"
        case .photo: return l == .ru ? "Своё фото" : "Photo"
        }
    }
}

enum DialAnimation: String, Codable, CaseIterable, Identifiable, Sendable {
    case pulse, rotate, none
    var id: String { rawValue }
    func title(_ l: Lang) -> String {
        switch self {
        case .pulse: return l == .ru ? "Пульс" : "Pulse"
        case .rotate: return l == .ru ? "Вращение" : "Rotate"
        case .none: return l == .ru ? "Нет" : "None"
        }
    }
}

enum FontChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case pro, rounded, mono
    var id: String { rawValue }
    var short: String {
        switch self {
        case .pro: return "Pro"
        case .rounded: return "Rounded"
        case .mono: return "Mono"
        }
    }
    var title: String { "SF " + short }
}

enum IconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case line, tiles, emoji
    var id: String { rawValue }
    func title(_ l: Lang) -> String {
        switch self {
        case .line: return l == .ru ? "Линия" : "Line"
        case .tiles: return l == .ru ? "Плитки" : "Tiles"
        case .emoji: return l == .ru ? "Эмодзи" : "Emoji"
        }
    }
}

enum AppIconChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, dark, light, neon
    var id: String { rawValue }
    func title(_ l: Lang) -> String {
        switch self {
        case .classic: return l == .ru ? "Классика" : "Classic"
        case .dark: return l == .ru ? "Тёмная" : "Dark"
        case .light: return l == .ru ? "Светлая" : "Light"
        case .neon: return l == .ru ? "Неон" : "Neon"
        }
    }
    /// Name of the alternate icon set in Assets (nil = primary icon).
    var iconName: String? {
        switch self {
        case .classic: return nil
        case .dark: return "AppIconDark"
        case .light: return "AppIconLight"
        case .neon: return "AppIconNeon"
        }
    }
}

// MARK: - Presets

/// The part of the look that a preset controls (everything except glow, radius and icons).
struct LookPreset: Codable, Equatable, Sendable {
    var accent: RGB
    var theme: ThemeID
    var background: BackgroundKind
    var animation: DialAnimation
    var font: FontChoice
}

struct Preset: Identifiable, Sendable {
    let id: String
    let ru: String
    let en: String
    let look: LookPreset
    func title(_ l: Lang) -> String { l == .ru ? ru : en }

    static let all: [Preset] = [
        .init(id: "base", ru: "Базовый", en: "Base", look: .init(accent: Accents.emerald, theme: .obsidian, background: .solid, animation: .pulse, font: .pro)),
        .init(id: "amethyst", ru: "Аметист", en: "Amethyst", look: .init(accent: Accents.violet, theme: .amethyst, background: .aurora, animation: .pulse, font: .pro)),
        .init(id: "stealth", ru: "Стелс", en: "Stealth", look: .init(accent: Accents.silver, theme: .graphite, background: .grain, animation: .none, font: .pro)),
        .init(id: "forest", ru: "Лес", en: "Forest", look: .init(accent: Accents.lime, theme: .forest, background: .aurora, animation: .pulse, font: .rounded)),
        .init(id: "neon", ru: "Неон", en: "Neon", look: .init(accent: Accents.mint, theme: .midnight, background: .grid, animation: .rotate, font: .mono)),
    ]
}

struct UserPreset: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var look: LookPreset
}

// MARK: - Appearance & preferences

struct Appearance: Codable, Equatable, Sendable {
    var accent: RGB = Accents.emerald
    var theme: ThemeID = .obsidian
    var background: BackgroundKind = .solid
    var glow: Double = 0.6
    var radius: Double = 22
    var animation: DialAnimation = .pulse
    var font: FontChoice = .pro
    var iconStyle: IconStyle = .line
    var appIcon: AppIconChoice = .classic
    var photoBlur: Double = 12
    var photoDim: Double = 0.45

    var preset: LookPreset {
        get { LookPreset(accent: accent, theme: theme, background: background, animation: animation, font: font) }
        set {
            accent = newValue.accent
            theme = newValue.theme
            background = newValue.background
            animation = newValue.animation
            font = newValue.font
        }
    }
}

struct Prefs: Codable, Equatable, Sendable {
    var language: Lang = .system
    var routing: RoutingPreset = .russia
    var blockAds = false
    /// The VPN profile's includeAllNetworks: nothing leaves the device outside the tunnel.
    var killSwitch = false
    var autoConnect = false
    var dnsPreset: DNSPreset = .cloudflare
    var dnsTransport: DNSTransport = .doh
    var customDNS = ""
    /// sing-box log level info instead of warn.
    var verboseLogs = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case language, routing, blockAds, killSwitch, autoConnect, dnsPreset, dnsTransport, customDNS, verboseLogs
        /// 0.5: rules / global / direct.
        case mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = c.value(.language, .system)
        let current = (try? c.decodeIfPresent(RoutingPreset.self, forKey: .routing)) ?? nil
        if let current {
            routing = current
        } else if let old = try? c.decodeIfPresent(String.self, forKey: .mode) {
            routing = old == "global" ? .global : (old == "direct" ? .custom : .russia)
        }
        blockAds = c.value(.blockAds, false)
        // 0.x had a cosmetic kill switch that defaulted to on: start from off with the real one.
        killSwitch = current == nil ? false : c.value(.killSwitch, false)
        autoConnect = c.value(.autoConnect, false)
        dnsPreset = c.value(.dnsPreset, .cloudflare)
        dnsTransport = c.value(.dnsTransport, .doh)
        customDNS = c.value(.customDNS, "")
        verboseLogs = c.value(.verboseLogs, false)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(language, forKey: .language)
        try c.encode(routing, forKey: .routing)
        try c.encode(blockAds, forKey: .blockAds)
        try c.encode(killSwitch, forKey: .killSwitch)
        try c.encode(autoConnect, forKey: .autoConnect)
        try c.encode(dnsPreset, forKey: .dnsPreset)
        try c.encode(dnsTransport, forKey: .dnsTransport)
        try c.encode(customDNS, forKey: .customDNS)
        try c.encode(verboseLogs, forKey: .verboseLogs)
    }
}
