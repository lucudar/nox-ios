import Foundation

// MARK: - Protocols

enum ProxyProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case vless, vmess, trojan, shadowsocks, hysteria2, tuic, wireguard, amneziawg, openvpn, ikev2, ssh, openflux, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vless: return "VLESS"
        case .vmess: return "VMess"
        case .trojan: return "Trojan"
        case .shadowsocks: return "Shadowsocks"
        case .hysteria2: return "Hysteria2"
        case .tuic: return "TUIC v5"
        case .wireguard: return "WireGuard"
        case .amneziawg: return "AmneziaWG"
        case .openvpn: return "OpenVPN"
        case .ikev2: return "IKEv2"
        case .ssh: return "SSH"
        case .openflux: return "OpenFlux"
        case .custom: return L10n.t("Свой протокол", "Custom")
        }
    }

    var defaultPort: Int {
        switch self {
        case .vless, .vmess, .trojan, .hysteria2, .tuic, .openflux, .custom: return 443
        case .shadowsocks: return 8388
        case .wireguard, .amneziawg: return 51820
        case .openvpn: return 1194
        case .ikev2: return 500
        case .ssh: return 22
        }
    }

    /// UDP transports: a TCP connect "ping" can't reach them on their own port.
    var isUDP: Bool {
        switch self {
        case .hysteria2, .tuic, .wireguard, .amneziawg, .ikev2: return true
        default: return false
        }
    }

    var linkScheme: String {
        switch self {
        case .vless: return "vless"
        case .vmess: return "vmess"
        case .trojan: return "trojan"
        case .shadowsocks: return "ss"
        case .hysteria2: return "hy2"
        case .tuic: return "tuic"
        case .wireguard: return "wg"
        case .amneziawg: return "awg"
        case .openvpn: return "openvpn"
        case .ikev2: return "ikev2"
        case .ssh: return "ssh"
        case .openflux: return "openflux"
        case .custom: return "custom"
        }
    }

    /// Meaning of the main secret for the manual editor.
    var secretTitle: (ru: String, en: String) {
        switch self {
        case .vless, .vmess: return ("UUID", "UUID")
        case .tuic: return ("UUID:пароль", "UUID:password")
        case .wireguard, .amneziawg: return ("Приватный ключ", "Private key")
        case .ssh: return ("Пользователь:пароль", "User:password")
        case .openvpn, .ikev2: return ("Логин:пароль", "Login:password")
        case .openflux, .custom: return ("Ключ / токен", "Key / token")
        default: return ("Пароль", "Password")
        }
    }

    /// Protocols that are configured with a whole config blob rather than a link.
    var usesRawConfig: Bool { self == .openvpn || self == .openflux || self == .custom }
}

// MARK: - Server

struct Server: Identifiable, Codable, Hashable, Sendable {
    enum Badge: String, Codable, Sendable { case none, home, globe }

    var id = UUID()
    /// User-visible name. Empty → localized country name is shown.
    var name = ""
    var countryCode = ""
    /// City in English (localized for display via `Countries.city`).
    var city = ""
    var proto: ProxyProtocol = .vless
    /// "Reality", "2022", "WS"… shown after the protocol title.
    var variant = ""
    var host = ""
    var port = 443
    /// Original share link or raw config (WireGuard .conf, .ovpn, JSON…).
    var link = ""
    var badge: Badge = .none
    /// Leftover from the 0.x demo list: such servers are dropped on load.
    var isDemo = false
    var lastPing: Int?
    var pingFailed = false
}

extension Server {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "")
        countryCode = c.value(.countryCode, "")
        city = c.value(.city, "")
        proto = c.value(.proto, .custom)
        variant = c.value(.variant, "")
        host = c.value(.host, "")
        port = c.value(.port, 443)
        link = c.value(.link, "")
        badge = c.value(.badge, .none)
        isDemo = c.value(.isDemo, false)
        lastPing = c.value(.lastPing, nil)
        pingFailed = c.value(.pingFailed, false)
    }

    var protoTitle: String {
        if proto == .custom, !variant.isEmpty { return variant }
        return variant.isEmpty ? proto.title : "\(proto.title) \(variant)"
    }

    func displayName(_ lang: Lang) -> String {
        if !name.isEmpty { return name }
        if badge == .home { return lang == .ru ? "Домашний сервер" : "Home server" }
        if let country = Countries.name(countryCode, lang) { return country }
        return host.isEmpty ? protoTitle : host
    }

    func cityName(_ lang: Lang) -> String { Countries.city(city, lang) }

    /// "Амстердам · VLESS Reality" (or just the protocol when the city is unknown).
    func subtitle(_ lang: Lang) -> String {
        let c = cityName(lang)
        return c.isEmpty ? protoTitle : "\(c) · \(protoTitle)"
    }

    /// Short place name: city, else the display name.
    func place(_ lang: Lang) -> String {
        let c = cityName(lang)
        return c.isEmpty ? displayName(lang) : c
    }
}

// MARK: - Groups

struct ServerGroup: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    /// nil → the user's own servers ("Свои").
    var subscriptionURL: URL?
    var updatedAt: Date?
    var servers: [Server] = []
    var isDemo = false

    var isOwn: Bool { subscriptionURL == nil }

    func title(_ lang: Lang) -> String {
        if isOwn { return lang == .ru ? "Свои" : "Own" }
        return name.isEmpty ? (subscriptionURL?.host ?? "Subscription") : name
    }
}

extension ServerGroup {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "")
        subscriptionURL = c.value(.subscriptionURL, nil)
        updatedAt = c.value(.updatedAt, nil)
        servers = c.value(.servers, [])
        isDemo = c.value(.isDemo, false)
    }
}

// MARK: - Routing, DNS

/// What goes through the VPN. Presets are built from curated rule-sets (see `RuleSets`);
/// the user's own rules always apply first.
enum RoutingPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case russia, blocked, global, custom
    var id: String { rawValue }

    func title(_ l: Lang) -> String {
        switch self {
        case .russia: return l == .ru ? "Россия напрямую" : "Russia direct"
        case .blocked: return l == .ru ? "Только заблокированное" : "Blocked sites only"
        case .global: return l == .ru ? "Всё через VPN" : "Everything via VPN"
        case .custom: return l == .ru ? "Только мои правила" : "My rules only"
        }
    }

    func details(_ l: Lang) -> String {
        switch self {
        case .russia:
            return l == .ru ? "Российские сайты и IP — напрямую, остальное через VPN. Заблокированное в РФ — всегда через VPN"
                : "Russian sites and IPs go direct, everything else via VPN. Sites blocked in Russia always use VPN"
        case .blocked:
            return l == .ru ? "Через VPN — только заблокированные в РФ сервисы: YouTube, Instagram, Discord, ChatGPT и другие"
                : "Only services blocked in Russia use VPN: YouTube, Instagram, Discord, ChatGPT and more"
        case .global:
            return l == .ru ? "Весь трафик через сервер, кроме локальной сети" : "All traffic goes through the server, except the local network"
        case .custom:
            return l == .ru ? "Всё напрямую, кроме того, что указано в правилах" : "Everything direct except what your rules send to VPN"
        }
    }

    var symbol: String {
        switch self {
        case .russia: return "house"
        case .blocked: return "lock.open"
        case .global: return "globe"
        case .custom: return "list.bullet"
        }
    }
}

struct RouteRule: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case domain, suffix, keyword, ip, geosite, geoip
        var id: String { rawValue }
        func title(_ l: Lang) -> String {
            switch self {
            case .domain: return l == .ru ? "Домен" : "Domain"
            case .suffix: return l == .ru ? "Суффикс" : "Suffix"
            case .keyword: return l == .ru ? "Слово" : "Keyword"
            case .ip: return "IP / CIDR"
            case .geosite: return "GeoSite"
            case .geoip: return "GeoIP"
            }
        }
    }

    enum Action: String, Codable, CaseIterable, Identifiable, Sendable {
        case proxy, direct, block
        var id: String { rawValue }
        func title(_ l: Lang) -> String {
            switch self {
            case .proxy: return "VPN"
            case .direct: return l == .ru ? "Напрямую" : "Direct"
            case .block: return l == .ru ? "Блок" : "Block"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var value: String
    var action: Action
}

enum DNSPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case cloudflare, google, quad9, adguard, custom
    var id: String { rawValue }

    func title(_ l: Lang) -> String {
        switch self {
        case .cloudflare: return "Cloudflare"
        case .google: return "Google"
        case .quad9: return "Quad9"
        case .adguard: return "AdGuard"
        case .custom: return l == .ru ? "Свой" : "Custom"
        }
    }

    var address: String {
        switch self {
        case .cloudflare: return "1.1.1.1"
        case .google: return "8.8.8.8"
        case .quad9: return "9.9.9.9"
        case .adguard: return "94.140.14.14"
        case .custom: return ""
        }
    }

    /// Resolver address for the chosen transport.
    func endpoint(_ transport: DNSTransport) -> String {
        switch (self, transport) {
        case (.custom, _): return ""
        case (_, .udp): return address
        case (.cloudflare, .doh): return "https://cloudflare-dns.com/dns-query"
        case (.cloudflare, .dot): return "one.one.one.one"
        case (.google, .doh): return "https://dns.google/dns-query"
        case (.google, .dot): return "dns.google"
        case (.quad9, .doh): return "https://dns.quad9.net/dns-query"
        case (.quad9, .dot): return "dns.quad9.net"
        case (.adguard, .doh): return "https://dns.adguard-dns.com/dns-query"
        case (.adguard, .dot): return "dns.adguard-dns.com"
        }
    }
}

enum DNSTransport: String, Codable, CaseIterable, Identifiable, Sendable {
    case doh, dot, udp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .doh: return "DoH"
        case .dot: return "DoT"
        case .udp: return "UDP"
        }
    }
}

// MARK: - Logs

struct LogLine: Identifiable, Hashable, Sendable {
    enum Level: String, Sendable { case info, warn, error }
    let id = UUID()
    let date: Date
    let level: Level
    let text: String
}
