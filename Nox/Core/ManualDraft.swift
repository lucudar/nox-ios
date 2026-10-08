import Foundation

/// Form state of "Создать вручную". `build()` turns it into a regular share link (or a
/// .conf / .ovpn text) and runs it through `ShareLinkParser`, so a manually created server
/// is stored exactly like an imported one.
struct ManualDraft: Equatable {
    enum Security: String, CaseIterable, Identifiable {
        case reality, tls, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .reality: return "Reality"
            case .tls: return "TLS"
            case .none: return L10n.t("Нет", "None")
            }
        }
    }

    enum Transport: String, CaseIterable, Identifiable {
        case tcp, ws, grpc
        var id: String { rawValue }
        var title: String {
            switch self {
            case .tcp: return "TCP"
            case .ws: return "WS"
            case .grpc: return "gRPC"
            }
        }
    }

    static let ssMethods = [
        "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305",
        "aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305",
    ]
    static let fingerprints = ["chrome", "firefox", "safari", "ios", "edge", "random"]
    static let awgKeys = ["Jc", "Jmin", "Jmax", "S1", "S2", "H1", "H2", "H3", "H4"]
    static let awgDefaults: [String: String] = [
        "Jc": "4", "Jmin": "40", "Jmax": "70", "S1": "0", "S2": "0", "H1": "1", "H2": "2", "H3": "3", "H4": "4",
    ]

    var proto: ProxyProtocol = .vless
    var name = ""
    var host = ""
    var port = "443"
    /// "" = detect automatically from the name / host.
    var country = ""

    var uuid = ""
    var password = ""
    var user = ""

    var security: Security = .reality
    var transport: Transport = .tcp
    var sni = ""
    var publicKey = ""
    var shortID = ""
    var fingerprint = "chrome"
    var vision = true
    /// WS path or gRPC service name.
    var path = ""
    var vmessTLS = true
    var insecure = false
    var obfsPassword = ""

    var method = ssMethods[0]

    var privateKey = ""
    var peerPublicKey = ""
    var presharedKey = ""
    var address = "10.0.0.2/32"
    var dns = "1.1.1.1"
    var awg = awgDefaults

    var config = ""
    var scheme = ""
    var token = ""

    // OpenFlux
    var fluxTransport: OpenFluxProfile.Transport = .yandex
    /// Document links as typed: one per line (or comma-separated).
    var fluxDocuments = ""
    var fluxToken = ""
    var fluxUID = ""
    var fluxCodec: OpenFluxProfile.Codec = .batched
    var fluxKey = ""
    var fluxContext = ""

    var fluxProfile: OpenFluxProfile {
        var p = OpenFluxProfile(transport: fluxTransport)
        p.documents = OpenFluxProfile.split(fluxDocuments)
        p.maxToken = fluxToken.trimmed
        p.maxUID = fluxUID.trimmed
        p.codec = fluxCodec
        p.key = fluxKey.trimmed
        p.keyContext = fluxContext.trimmed
        return p
    }

    var fluxHasInput: Bool {
        !fluxDocuments.trimmed.isEmpty || !fluxToken.trimmed.isEmpty || !fluxUID.trimmed.isEmpty || !fluxKey.isEmpty
    }

    /// Fills the OpenFlux fields from pasted text (link, JSON, command line, document links).
    /// false → nothing recognised.
    mutating func pasteOpenFlux(_ raw: String) -> Bool {
        let text = raw.trimmed
        guard let p = OpenFluxProfile(text: text) else { return false }
        fluxTransport = p.transport
        fluxDocuments = p.documents.joined(separator: "\n")
        fluxToken = p.maxToken
        fluxUID = p.maxUID
        fluxCodec = p.codec
        if !p.key.isEmpty { fluxKey = p.key }
        if !p.keyContext.isEmpty { fluxContext = p.keyContext }
        if name.trimmed.isEmpty, let r = text.range(of: "://"),
           ShareLinkParser.schemes[text[..<r.lowerBound].lowercased()] == .openflux,
           let fragment = RawURL(text)?.fragment {
            name = ShareLinkParser.cleanName(fragment)
        }
        return true
    }

    // MARK: Validation

    var portNumber: Int? {
        guard let p = Int(port.trimmed), (1...65535).contains(p) else { return nil }
        return p
    }

    /// OpenVPN configs usually carry their own `remote host port` line.
    var configHasRemote: Bool { Self.hasRemoteLine(config) }

    var needsHost: Bool { !(proto == .openvpn && configHasRemote) && proto != .openflux }

    var schemeIsValid: Bool {
        let s = scheme.trimmed.lowercased()
        guard let first = s.first, first.isASCII, first.isLetter else { return false }
        guard s != "http", s != "https" else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
    }

    /// All required fields are filled in (the Save button is enabled).
    var isComplete: Bool {
        if needsHost {
            guard !host.trimmed.isEmpty, portNumber != nil else { return false }
        }
        switch proto {
        case .vless:
            guard !uuid.trimmed.isEmpty else { return false }
            if security == .reality { return !publicKey.trimmed.isEmpty && !sni.trimmed.isEmpty }
            return true
        case .vmess:
            return !uuid.trimmed.isEmpty
        case .trojan, .shadowsocks, .hysteria2:
            return !password.isEmpty
        case .tuic:
            return !uuid.trimmed.isEmpty && !password.isEmpty
        case .wireguard, .amneziawg:
            return !privateKey.trimmed.isEmpty && !peerPublicKey.trimmed.isEmpty && !address.trimmed.isEmpty
        case .openvpn:
            return !config.trimmed.isEmpty
        case .ikev2, .ssh:
            return !user.trimmed.isEmpty
        case .openflux:
            return fluxProfile.problem == nil
        case .custom:
            return schemeIsValid
        }
    }

    mutating func switchProtocol(from old: ProxyProtocol) {
        if port.trimmed.isEmpty || port.trimmed == String(old.defaultPort) {
            port = String(proto.defaultPort)
        }
    }

    // MARK: Building

    /// The share link / config text the server is created from.
    func linkText() -> String {
        let name = self.name.trimmed
        let host = self.host.trimmed
        let port = portNumber ?? proto.defaultPort
        let hostPort = Self.hostPort(host, port)
        let fragment = name.isEmpty ? "" : "#" + name.urlEncoded

        switch proto {
        case .vless:
            var q: [(String, String)] = [("encryption", "none")]
            switch security {
            case .reality:
                q += [("security", "reality"), ("sni", sni.trimmed), ("fp", fingerprint), ("pbk", publicKey.trimmed), ("sid", shortID.trimmed)]
            case .tls:
                q += [("security", "tls"), ("sni", sni.trimmed), ("fp", fingerprint)]
            case .none:
                q += [("security", "none")]
            }
            if transport == .tcp, security != .none, vision { q.append(("flow", "xtls-rprx-vision")) }
            q += transportQuery()
            return "vless://\(uuid.trimmed.urlEncoded)@\(hostPort)?\(Self.query(q))\(fragment)"

        case .vmess:
            let object: [String: String] = [
                "v": "2", "ps": name, "add": host, "port": String(port), "id": uuid.trimmed, "aid": "0",
                "scy": "auto", "net": transport.rawValue, "type": "none", "host": "",
                "path": path.trimmed, "tls": vmessTLS ? "tls" : "", "sni": vmessTLS ? sni.trimmed : "",
            ]
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
            return "vmess://" + data.base64EncodedString()

        case .trojan:
            let q: [(String, String)] = [("security", "tls"), ("sni", sni.trimmed), ("allowInsecure", insecure ? "1" : "")] + transportQuery()
            return "trojan://\(password.urlEncoded)@\(hostPort)?\(Self.query(q))\(fragment)"

        case .shadowsocks:
            let userInfo = Self.base64URL(Data("\(method):\(password)".utf8))
            return "ss://\(userInfo)@\(hostPort)\(fragment)"

        case .hysteria2:
            var q: [(String, String)] = [("sni", sni.trimmed)]
            if !obfsPassword.isEmpty { q += [("obfs", "salamander"), ("obfs-password", obfsPassword)] }
            if insecure { q.append(("insecure", "1")) }
            let query = Self.query(q)
            return "hy2://\(password.urlEncoded)@\(hostPort)/\(query.isEmpty ? "" : "?" + query)\(fragment)"

        case .tuic:
            var q: [(String, String)] = [("congestion_control", "bbr"), ("alpn", "h3"), ("sni", sni.trimmed)]
            if insecure { q.append(("allow_insecure", "1")) }
            return "tuic://\(uuid.trimmed.urlEncoded):\(password.urlEncoded)@\(hostPort)?\(Self.query(q))\(fragment)"

        case .wireguard, .amneziawg:
            var lines = ["[Interface]", "PrivateKey = \(privateKey.trimmed)", "Address = \(address.trimmed)"]
            if !dns.trimmed.isEmpty { lines.append("DNS = \(dns.trimmed)") }
            if proto == .amneziawg {
                for key in Self.awgKeys {
                    let value = (awg[key] ?? "").trimmed
                    lines.append("\(key) = \(value.isEmpty ? (Self.awgDefaults[key] ?? "0") : value)")
                }
            }
            lines += ["", "[Peer]", "PublicKey = \(peerPublicKey.trimmed)"]
            if !presharedKey.trimmed.isEmpty { lines.append("PresharedKey = \(presharedKey.trimmed)") }
            lines += ["AllowedIPs = 0.0.0.0/0, ::/0", "Endpoint = \(hostPort)", "PersistentKeepalive = 25"]
            return lines.joined(separator: "\n") + "\n"

        case .openvpn:
            var text = config.trimmingCharacters(in: .whitespacesAndNewlines)
            if !Self.hasRemoteLine(text), !host.isEmpty { text = "remote \(host) \(port)\n" + text }
            if !user.trimmed.isEmpty, !text.contains("<auth-user-pass>") {
                text += "\n<auth-user-pass>\n\(user.trimmed)\n\(password)\n</auth-user-pass>"
            }
            return text + "\n"

        case .ikev2, .ssh:
            let secret = password.isEmpty ? "" : ":" + password.urlEncoded
            return "\(proto.linkScheme)://\(user.trimmed.urlEncoded)\(secret)@\(hostPort)\(fragment)"

        case .openflux:
            return fluxProfile.link(name: name)

        case .custom:
            let scheme = self.scheme.trimmed.lowercased()
            let token = self.token.trimmed
            var link = "\(scheme)://" + (token.isEmpty ? "" : token.urlEncoded + "@") + hostPort
            let raw = config.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty { link += "?config=" + Self.base64URL(Data(raw.utf8)) }
            return link + fragment
        }
    }

    /// Builds the server. nil → the link couldn't be parsed (shouldn't happen for a complete draft).
    func build() -> Server? {
        let text = linkText()
        var server: Server?
        switch proto {
        case .wireguard, .amneziawg:
            server = ConfigFiles.wireguard(text, name: fileName("conf"))
        case .openvpn:
            server = ConfigFiles.openvpn(text, name: fileName("ovpn"))
        default:
            server = ShareLinkParser.parse(text)
        }
        guard var s = server else { return nil }
        if proto == .amneziawg { s.proto = .amneziawg }
        // The parser already cleaned the name (flags, "name == country"); only drop the
        // placeholder file name used for configs.
        if name.trimmed.isEmpty { s.name = "" }
        if !country.isEmpty {
            s.countryCode = country
            if let city = Countries.cities[s.city], city.code != country { s.city = "" }
            if s.badge == .globe { s.badge = .none }
        }
        return s
    }

    // MARK: Helpers

    private func transportQuery() -> [(String, String)] {
        switch transport {
        case .tcp: return [("type", "tcp")]
        case .ws: return [("type", "ws"), ("path", path.trimmed.isEmpty ? "/" : path.trimmed), ("host", sni.trimmed)]
        case .grpc: return [("type", "grpc"), ("serviceName", path.trimmed), ("mode", "gun")]
        }
    }

    private func fileName(_ ext: String) -> String {
        let base = name.trimmed.replacingOccurrences(of: "/", with: " ")
        return "\(base.isEmpty ? "manual" : base).\(ext)"
    }

    static func hostPort(_ host: String, _ port: Int) -> String {
        let h = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(h):\(port)"
    }

    static func query(_ items: [(String, String)]) -> String {
        items.filter { !$0.1.isEmpty }.map { "\($0.0)=\($0.1.urlEncoded)" }.joined(separator: "&")
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func hasRemoteLine(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains {
            let parts = $0.trimmingCharacters(in: .whitespaces).split(separator: " ")
            return parts.first?.lowercased() == "remote" && parts.count >= 2
        }
    }

    static func == (a: ManualDraft, b: ManualDraft) -> Bool { a.linkText() == b.linkText() && a.country == b.country }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// RFC 3986 unreserved characters only, so the parser's lenient splitter can't trip on
    /// '@', '#', '?', '&' or '/' inside passwords and names.
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlUnreserved) ?? self
    }
}

extension CharacterSet {
    static let urlUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
