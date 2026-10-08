import Foundation

/// Rule-sets (sing-box binary `.srs`) used by the routing presets and by GeoSite / GeoIP rules.
/// The preset ones ship inside the app (downloaded by CI into Resources/RuleSets) and are
/// refreshed by sing-box itself once a day through the proxy.
enum RuleSets {
    struct Source: Hashable {
        let tag: String
        let url: String
        /// Contains `ip_cidr` items: such sets are kept out of DNS rules.
        let hasIP: Bool
    }

    // MARK: Preset sets

    static let ads = Source(tag: "geosite-category-ads-all", url: sagerSite("category-ads-all"), hasIP: false)

    /// Domains blocked in Russia (itdoginfo/allow-domains): proxied by "Russia direct" and "Blocked only".
    static let blocked: [Source] = [
        itdog("russia_inside", hasIP: false),
        itdog("telegram", hasIP: true),
        itdog("meta", hasIP: true),
        itdog("discord", hasIP: true),
        itdog("google_ai", hasIP: false),
    ]

    /// Russian sites and services: direct in the "Russia direct" preset.
    static let russianDomains: [Source] = [
        Source(tag: "geosite-category-ru", url: sagerSite("category-ru"), hasIP: false),
        Source(tag: "geosite-ru-available-only-inside",
               url: "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-ru-available-only-inside.srs",
               hasIP: false),
    ]
    static let russianIP = Source(tag: "geoip-ru", url: sagerIP("ru"), hasIP: true)

    /// National top-level domains that always go direct in "Russia direct": .ru .su .рф .рус .москва .дети.
    static let ruZones = ["ru", "su", "xn--p1ai", "xn--p1acf", "xn--80adxhks", "xn--d1acj3b", "moscow", "tatar"]

    /// Everything the presets can use — CI bundles these files.
    static var bundled: [Source] { [ads] + blocked + russianDomains + [russianIP] }

    // MARK: GeoSite / GeoIP rules

    /// "geosite:youtube" → SagerNet's geosite-youtube.srs (nil for an invalid name).
    static func geosite(_ name: String) -> Source? {
        guard let n = cleanName(name) else { return nil }
        if let known = bundled.first(where: { $0.tag == "geosite-\(n)" }) { return known }
        return Source(tag: "geosite-\(n)", url: sagerSite(n), hasIP: false)
    }

    /// "geoip:ru" → SagerNet's geoip-ru.srs. "private" is handled by `ip_is_private` instead.
    static func geoip(_ name: String) -> Source? {
        guard let n = cleanName(name), n != "private" else { return nil }
        if let known = bundled.first(where: { $0.tag == "geoip-\(n)" }) { return known }
        return Source(tag: "geoip-\(n)", url: sagerIP(n), hasIP: true)
    }

    /// Lowercased, "geosite:" / "geoip:" prefixes dropped; only [a-z0-9-_!@.] allowed.
    static func cleanName(_ raw: String) -> String? {
        var n = raw.trimmingCharacters(in: .whitespaces).lowercased()
        for prefix in ["geosite:", "geoip:", "geosite-", "geoip-"] where n.hasPrefix(prefix) {
            n = String(n.dropFirst(prefix.count))
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_!@.")
        guard !n.isEmpty, n.count <= 64, n.allSatisfy({ allowed.contains($0) }) else { return nil }
        return n
    }

    // MARK: URLs

    static func sagerSite(_ name: String) -> String {
        "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-\(name).srs"
    }

    static func sagerIP(_ name: String) -> String {
        "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-\(name).srs"
    }

    static func itdog(_ name: String, hasIP: Bool) -> Source {
        Source(tag: "itdog-\(name.replacingOccurrences(of: "_", with: "-"))",
               url: "https://github.com/itdoginfo/allow-domains/releases/latest/download/\(name).srs",
               hasIP: hasIP)
    }
}
