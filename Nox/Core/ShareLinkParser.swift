import Foundation

/// Parses share links (vless://, vmess://, trojan://, ss://, hy2://, tuic://, wg://, awg://,
/// ssh://, openflux://, any custom scheme), subscription bodies (plain or base64) and config
/// files (sing-box / Xray JSON, Clash YAML, WireGuard .conf, OpenVPN .ovpn).
enum ShareLinkParser {
    static let schemes: [String: ProxyProtocol] = [
        "vless": .vless, "vmess": .vmess, "trojan": .trojan, "ss": .shadowsocks,
        "hysteria2": .hysteria2, "hy2": .hysteria2, "tuic": .tuic,
        "wireguard": .wireguard, "wg": .wireguard, "awg": .amneziawg, "amneziawg": .amneziawg,
        "ssh": .ssh, "openflux": .openflux, "flux": .openflux, "ofx": .openflux,
        "openvpn": .openvpn, "ikev2": .ikev2,
    ]

    // MARK: Entry points

    /// Anything the user pasted, scanned, imported or a subscription returned.
    static func parseMany(_ input: String, fileName: String? = nil) -> [Server] {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        // Base64 subscription body.
        if !text.contains("://"), !text.contains("[Interface]"),
           let decoded = Base64.decodeString(text),
           decoded.contains("://") || decoded.contains("[Interface]") {
            text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if text.hasPrefix("{") || text.hasPrefix("["), let list = ConfigFiles.json(text), !list.isEmpty {
            return list
        }
        if text.contains("[Interface]"), text.contains("[Peer]") {
            return ConfigFiles.wireguard(text, name: fileName).map { [$0] } ?? []
        }
        if ConfigFiles.looksLikeOpenVPN(text) {
            return ConfigFiles.openvpn(text, name: fileName).map { [$0] } ?? []
        }
        if text.range(of: "(^|\\n)proxies:", options: .regularExpression) != nil {
            let list = ConfigFiles.clash(text)
            if !list.isEmpty { return list }
        }

        var out: [Server] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.contains("://") else { continue }
            // Fragments may contain spaces ("#🇳🇱 Amsterdam 2"), so only split lines
            // that hold several links.
            let tokens = line.components(separatedBy: "://").count > 2
                ? line.split(separator: " ").map(String.init).filter { $0.contains("://") }
                : [line]
            for token in tokens {
                if let s = parse(token) { out.append(s) }
            }
        }
        return out
    }

    /// A single share link.
    static func parse(_ link: String) -> Server? {
        guard let r = link.range(of: "://") else { return nil }
        let scheme = link[..<r.lowerBound].lowercased()
        guard !scheme.isEmpty, scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) else { return nil }
        if scheme == "http" || scheme == "https" { return nil }
        if scheme == "vmess" { return vmess(link) }
        if scheme == "ss" { return shadowsocks(link) }

        guard let u = RawURL(link) else { return nil }
        let proto = schemes[scheme] ?? .custom
        var s = Server()
        s.proto = proto
        s.host = u.host
        s.port = u.port ?? proto.defaultPort
        s.link = link
        s.name = cleanName(u.fragment ?? "")
        switch proto {
        case .vless, .trojan:
            s.variant = transportVariant(u.query)
        case .custom:
            s.variant = scheme.prefix(1).uppercased() + scheme.dropFirst()
        default:
            break
        }
        finish(&s, hint: u.fragment ?? "")
        if s.host.isEmpty && proto != .openflux && proto != .custom { return nil }
        return s
    }

    // MARK: Protocol specifics

    static func transportVariant(_ q: [String: String]) -> String {
        let security = q["security"]?.lowercased() ?? ""
        if security == "reality" { return "Reality" }
        switch (q["type"] ?? q["net"] ?? "").lowercased() {
        case "ws": return "WS"
        case "grpc": return "gRPC"
        case "xhttp", "splithttp": return "XHTTP"
        case "httpupgrade": return "HTTPUpgrade"
        case "h2", "http": return "H2"
        default: return security == "tls" ? "TLS" : ""
        }
    }

    static func vmess(_ link: String) -> Server? {
        let body = String(link.dropFirst("vmess://".count))
        let (main, fragment) = splitFragment(body)
        if let json = Base64.decodeString(main), let data = json.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            var s = Server()
            s.proto = .vmess
            s.host = str(obj["add"])
            s.port = int(obj["port"]) ?? 443
            let ps = str(obj["ps"])
            s.name = cleanName(ps.isEmpty ? (fragment ?? "") : ps)
            let net = str(obj["net"]).lowercased(), tls = str(obj["tls"]).lowercased()
            s.variant = net == "ws" ? "WS" : net == "grpc" ? "gRPC" : (tls == "tls" ? "TLS" : "")
            s.link = link
            finish(&s, hint: ps.isEmpty ? (fragment ?? "") : ps)
            return s.host.isEmpty ? nil : s
        }
        // Non-standard vmess://uuid@host:port?…#name
        guard let u = RawURL(link), !u.host.isEmpty else { return nil }
        var s = Server()
        s.proto = .vmess
        s.host = u.host
        s.port = u.port ?? 443
        s.link = link
        s.name = cleanName(u.fragment ?? "")
        s.variant = transportVariant(u.query)
        finish(&s, hint: u.fragment ?? "")
        return s
    }

    static func shadowsocks(_ link: String) -> Server? {
        let body = String(link.dropFirst("ss://".count))
        let (main0, fragment) = splitFragment(body)
        var main = main0
        if let q = main.firstIndex(of: "?") { main = String(main[..<q]) }
        if main.hasSuffix("/") { main.removeLast() }

        var method = "", host = "", port = 0
        if let at = main.lastIndex(of: "@") {
            // SIP002: base64(method:password)@host:port or method:password@host:port
            let rawUser = String(main[..<at])
            let user = rawUser.removingPercentEncoding ?? rawUser
            let decoded = user.contains(":") ? user : (Base64.decodeString(user) ?? user)
            method = decoded.components(separatedBy: ":").first ?? ""
            (host, port) = splitHostPort(String(main[main.index(after: at)...]))
        } else if let decoded = Base64.decodeString(main), let at = decoded.lastIndex(of: "@") {
            // Legacy: base64(method:password@host:port)
            method = String(decoded[..<at]).components(separatedBy: ":").first ?? ""
            (host, port) = splitHostPort(String(decoded[decoded.index(after: at)...]))
        } else {
            return nil
        }
        guard !host.isEmpty else { return nil }
        var s = Server()
        s.proto = .shadowsocks
        s.host = host
        s.port = port == 0 ? 8388 : port
        s.link = link
        s.variant = method.lowercased().hasPrefix("2022-") ? "2022" : ""
        s.name = cleanName(fragment ?? "")
        finish(&s, hint: fragment ?? "")
        return s
    }

    // MARK: Shared helpers

    /// Country/city detection + "name equals the country/city" cleanup + home badge.
    static func finish(_ s: inout Server, hint: String) {
        let d = Countries.detect(in: hint, host: s.host)
        if s.countryCode.isEmpty { s.countryCode = d.code }
        if s.city.isEmpty { s.city = d.city }
        let lower = s.name.lowercased()
        if !lower.isEmpty {
            if let info = Countries.all[s.countryCode], lower == info.en.lowercased() || lower == info.ru.lowercased() {
                s.name = ""
            } else if !s.city.isEmpty, let c = Countries.cities[s.city], lower == s.city || lower == c.ru.lowercased() {
                s.name = ""
            }
        }
        if Countries.isPrivateHost(s.host) {
            s.badge = .home
        } else if s.countryCode.isEmpty {
            s.badge = .globe
        }
    }

    static func cleanName(_ raw: String) -> String {
        let decoded = raw.removingPercentEncoding ?? raw
        return Countries.stripFlags(decoded.replacingOccurrences(of: "+", with: " "))
    }

    static func splitFragment(_ s: String) -> (String, String?) {
        guard let h = s.firstIndex(of: "#") else { return (s, nil) }
        let frag = String(s[s.index(after: h)...])
        return (String(s[..<h]), frag.removingPercentEncoding ?? frag)
    }

    static func splitHostPort(_ s: String) -> (String, Int) {
        var rest = s
        if let slash = rest.firstIndex(of: "/") { rest = String(rest[..<slash]) }
        if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            let host = String(rest[rest.index(after: rest.startIndex)..<close])
            let after = rest[rest.index(after: close)...]
            return (host, after.hasPrefix(":") ? Int(after.dropFirst()) ?? 0 : 0)
        }
        if let colon = rest.lastIndex(of: ":") {
            return (String(rest[..<colon]), Int(rest[rest.index(after: colon)...]) ?? 0)
        }
        return (rest, 0)
    }

    static func str(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return ""
    }

    static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}

// MARK: - Raw URL

/// Lenient URL splitter: share-link fragments often contain spaces and emoji that make
/// `URLComponents` fail, so everything is split by hand.
struct RawURL {
    var scheme = ""
    var user: String?
    var host = ""
    var port: Int?
    var path = ""
    var query: [String: String] = [:]
    var fragment: String?

    init?(_ string: String) {
        guard let schemeEnd = string.range(of: "://") else { return nil }
        scheme = string[..<schemeEnd.lowerBound].lowercased()
        var rest = String(string[schemeEnd.upperBound...])

        let (main, frag) = ShareLinkParser.splitFragment(rest)
        rest = main
        fragment = frag

        if let q = rest.firstIndex(of: "?") {
            let qs = rest[rest.index(after: q)...]
            for pair in qs.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard let k = kv.first, !k.isEmpty else { continue }
                let v = kv.count > 1 ? kv[1] : ""
                query[(k.removingPercentEncoding ?? k).lowercased()] = v.removingPercentEncoding ?? v
            }
            rest = String(rest[..<q])
        }
        if let slash = rest.firstIndex(of: "/") {
            path = String(rest[slash...])
            rest = String(rest[..<slash])
        }
        if let at = rest.lastIndex(of: "@") {
            let u = String(rest[..<at])
            user = u.removingPercentEncoding ?? u
            rest = String(rest[rest.index(after: at)...])
        }
        let (h, p) = ShareLinkParser.splitHostPort(rest)
        host = h
        port = p == 0 ? nil : p
    }
}

// MARK: - Base64

enum Base64 {
    static func decode(_ s: String) -> Data? {
        var t = s.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !t.isEmpty,
              t.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=") })
        else { return nil }
        let rem = t.count % 4
        if rem == 1 { return nil }
        if rem > 0 { t += String(repeating: "=", count: 4 - rem) }
        return Data(base64Encoded: t)
    }

    static func decodeString(_ s: String) -> String? {
        guard let d = decode(s), let str = String(data: d, encoding: .utf8), !str.isEmpty else { return nil }
        return str
    }
}
