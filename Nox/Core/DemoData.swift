import Foundation

/// First-launch content that mirrors the design boards. Demo servers use simulated ping
/// and the demo tunnel engine; real imported servers are pinged over TCP.
enum DemoData {
    static func groups() -> [ServerGroup] {
        let main = ServerGroup(
            name: "Main",
            subscriptionURL: URL(string: "https://example.com/sub/main"),
            updatedAt: Date().addingTimeInterval(-2 * 3600),
            servers: [
                server("NL", "amsterdam", .vless, "Reality", "nl-ams-2.example.net", 443, 38),
                server("DE", "frankfurt", .hysteria2, "", "de-fra-1.example.net", 443, 46),
                server("FI", "helsinki", .trojan, "", "fi-hel-1.example.net", 443, 52),
                server("TR", "istanbul", .shadowsocks, "2022", "tr-ist-1.example.net", 8388, 71),
                server("US", "new york", .wireguard, "", "us-nyc-3.example.net", 51820, 128),
                server("JP", "tokyo", .tuic, "", "jp-tyo-1.example.net", 443, 214),
            ],
            isDemo: true)

        var home = server("", "", .openflux, "", "192.168.1.10", 7443, 12)
        home.badge = .home
        let own = ServerGroup(
            name: "",
            subscriptionURL: nil,
            updatedAt: nil,
            servers: [home, server("KZ", "almaty", .amneziawg, "", "kz-ala-1.example.net", 51820, 64)],
            isDemo: true)
        return [main, own]
    }

    static func server(_ code: String, _ city: String, _ proto: ProxyProtocol, _ variant: String,
                       _ host: String, _ port: Int, _ ping: Int) -> Server {
        var s = Server()
        s.countryCode = code
        s.city = city
        s.proto = proto
        s.variant = variant
        s.host = host
        s.port = port
        s.isDemo = true
        s.demoPing = ping
        s.lastPing = ping
        s.link = "\(proto.linkScheme)://demo@\(host):\(port)#\(city.isEmpty ? "home" : city)"
        return s
    }

    /// Default routing rules (Rules mode): ads blocked, local network and Russian sites direct.
    static let rules: [RouteRule] = [
        RouteRule(kind: .geosite, value: "category-ads-all", action: .block),
        RouteRule(kind: .geoip, value: "private", action: .direct),
        RouteRule(kind: .geosite, value: "category-ru", action: .direct),
        RouteRule(kind: .geoip, value: "ru", action: .direct),
        RouteRule(kind: .suffix, value: ".ru", action: .direct),
    ]
}
