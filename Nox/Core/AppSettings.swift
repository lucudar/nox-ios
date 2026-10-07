import Foundation
import Observation

/// Appearance + preferences. Saved by RootView via `.onChange` (see `persist…`).
@MainActor
@Observable
final class AppSettings {
    var look: Appearance
    var prefs: Prefs
    var userPresets: [UserPreset]
    var rules: [RouteRule]

    private enum Key {
        static let look = "nox.look.v1"
        static let prefs = "nox.prefs.v1"
        static let presets = "nox.presets.v1"
        static let rules = "nox.rules.v1"
    }

    init() {
        look = Persist.load(Key.look, default: Appearance())
        prefs = Persist.load(Key.prefs, default: Prefs())
        userPresets = Persist.load(Key.presets, default: [UserPreset]())
        rules = Persist.load(Key.rules, default: DemoData.rules)
        L10n.lang = prefs.language
    }

    // MARK: Language

    var lang: Lang { prefs.language }

    /// Inline translation. Reading `prefs` makes views re-render on language change.
    func t(_ ru: String, _ en: String) -> String { prefs.language == .ru ? ru : en }

    // MARK: Look helpers

    var palette: Palette { look.theme.palette }
    var accent: RGB { look.accent }

    func apply(_ preset: LookPreset) { look.preset = preset }

    /// Built-in preset matching the current look, if any.
    var currentPreset: Preset? { Preset.all.first { matches($0.look) } }
    var currentUserPreset: UserPreset? { userPresets.first { matches($0.look) } }

    func presetTitle() -> String {
        if let p = currentPreset { return p.title(lang) }
        if let u = currentUserPreset { return u.name }
        return t("Свой", "Custom")
    }

    func matches(_ p: LookPreset) -> Bool {
        p.theme == look.theme && p.background == look.background && p.animation == look.animation
            && p.font == look.font && p.accent.distance(to: look.accent) < 0.012
    }

    @discardableResult
    func saveCurrentAsPreset() -> UserPreset {
        let n = userPresets.count + 1
        let preset = UserPreset(name: t("Мой \(n)", "Mine \(n)"), look: look.preset)
        userPresets.append(preset)
        return preset
    }

    func deletePreset(_ id: UUID) { userPresets.removeAll { $0.id == id } }

    func resetLook() {
        let icon = look.appIcon
        look = Appearance()
        look.appIcon = icon
    }

    // MARK: Persistence

    func persistLook() { Persist.save(look, Key.look) }
    func persistPrefs() {
        Persist.save(prefs, Key.prefs)
        L10n.lang = prefs.language
    }
    func persistPresets() { Persist.save(userPresets, Key.presets) }
    func persistRules() { Persist.save(rules, Key.rules) }

    var tunnelOptions: TunnelOptions {
        let dns = prefs.dnsPreset == .custom ? (prefs.customDNS.nilIfEmpty ?? "1.1.1.1") : prefs.dnsPreset.endpoint(prefs.dnsTransport)
        return TunnelOptions(mode: prefs.mode, dns: "\(prefs.dnsTransport.title) \(dns)", killSwitch: prefs.killSwitch, rules: rules)
    }
}

struct TunnelOptions: Equatable, Sendable {
    var mode: RoutingMode
    var dns: String
    var killSwitch: Bool
    var rules: [RouteRule]
}
