import Foundation

/// Why a server can't be turned into a sing-box config. Shown to the user as is.
enum TunnelConfigError: LocalizedError, Equatable {
    case unsupported(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let what):
            return L10n.t("\(what) не поддерживается ядром sing-box", "\(what) isn't supported by the sing-box core")
        case .invalid(let what):
            return L10n.t("Ошибка в настройках сервера: \(what)", "Invalid server settings: \(what)")
        }
    }
}

/// Protocol-neutral description of one proxy. Share links, Xray JSON and Clash entries are
/// read into it; `SingBoxOutbound` turns it into a sing-box outbound / endpoint.
struct ProxySpec {
    var proto: ProxyProtocol
    var host = ""
    var port = 0

    // Credentials
    var uuid = ""
    var password = ""
    var user = ""
    /// Shadowsocks cipher or VMess security.
    var method = ""
    var alterID = 0
    var flow = ""

    // TLS / REALITY
    /// "", "tls" or "reality".
    var security = ""
    var sni = ""
    var fingerprint = ""
    var alpn: [String] = []
    var insecure = false
    var publicKey = ""
    var shortID = ""

    // V2Ray transport
    /// tcp, ws, grpc, http, httpupgrade, quic (xhttp / kcp are rejected later).
    var network = "tcp"
    var path = ""
    var hostHeader = ""
    var serviceName = ""
    var headerType = ""

    // Shadowsocks SIP003 plugin
    var plugin = ""
    var pluginOptions = ""

    // Hysteria2 / TUIC
    var obfs = ""
    var obfsPassword = ""
    /// Port hopping: "20000-30000,443".
    var hopPorts = ""
    var upMbps = 0
    var downMbps = 0
    var congestion = ""
    var udpRelayMode = ""

    // WireGuard
    var privateKey = ""
    var peerPublicKey = ""
    var presharedKey = ""
    var addresses: [String] = []
    var allowedIPs: [String] = []
    var reserved: [Int] = []
    var mtu = 0
    var keepalive = 0

    init(proto: ProxyProtocol) { self.proto = proto }
}

/// A server as the config builder sees it.
enum ParsedProxy {
    case spec(ProxySpec)
    /// A sing-box outbound (or endpoint) imported from a sing-box config: used almost as is.
    case singBox([String: Any])
}

extension ProxySpec {
    // MARK: Entry point

    static func parse(_ server: Server) throws -> ParsedProxy {
        switch server.proto {
        case .amneziawg: throw TunnelConfigError.unsupported("AmneziaWG")
        case .ikev2: throw TunnelConfigError.unsupported("IKEv2")
        case .openflux: throw TunnelConfigError.unsupported("OpenFlux")
        case .custom:
            throw TunnelConfigError.unsupported(server.variant.isEmpty ? L10n.t("Свой протокол", "A custom protocol") : server.variant)
        default:
            break
        }
        let text = server.link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TunnelConfigError.invalid(L10n.t("нет ссылки или конфига", "no link or config")) }
        if text.hasPrefix("{") { return try json(text) }
        if text.contains("[Interface]") { return .spec(try wireGuardConf(text)) }
        if server.proto == .openvpn { return .singBox(try OpenVPNConfig.endpoint(text)) }
        return .spec(try link(text))
    }

    // MARK: Share links

    static func link(_ text: String) throws -> ProxySpec {
        guard let r = text.range(of: "://") else { throw TunnelConfigError.invalid(L10n.t("ссылка", "link")) }
        let scheme = text[..<r.lowerBound].lowercased()
        if scheme == "vmess", let s = vmessJSON(text) { return s }
        if scheme == "ss" { return try shadowsocks(text) }
        guard let u = RawURL(text), !u.host.isEmpty else { throw TunnelConfigError.invalid(L10n.t("адрес сервера", "server address")) }
        let q = u.query
        let proto = ShareLinkParser.schemes[scheme] ?? .custom
        var s = ProxySpec(proto: proto)
        s.host = u.host
        s.port = u.port ?? proto.defaultPort
        let user = u.user ?? ""
        switch proto {
        case .vless:
            s.uuid = user
            s.flow = q["flow"] ?? ""
            if let enc = q["encryption"]?.lowercased(), !enc.isEmpty, enc != "none" {
                throw TunnelConfigError.unsupported("VLESS Encryption")
            }
            s.applyStream(q, defaultSecurity: "")
        case .vmess:
            s.uuid = user
            s.method = q["encryption"] ?? q["scy"] ?? "auto"
            s.alterID = Int(q["aid"] ?? q["alterid"] ?? "") ?? 0
            s.applyStream(q, defaultSecurity: "")
        case .trojan:
            s.password = user
            s.applyStream(q, defaultSecurity: "tls")
        case .hysteria2:
            s.password = user
            s.security = "tls"
            s.sni = q["sni"] ?? q["peer"] ?? ""
            s.insecure = flag(q["insecure"]) || flag(q["allowinsecure"])
            s.obfs = q["obfs"] ?? ""
            s.obfsPassword = q["obfs-password"] ?? q["obfs_password"] ?? q["obfspassword"] ?? ""
            s.hopPorts = q["mport"] ?? q["ports"] ?? ""
            s.alpn = list(q["alpn"])
            s.upMbps = mbps(q["upmbps"] ?? q["up"])
            s.downMbps = mbps(q["downmbps"] ?? q["down"])
        case .tuic:
            (s.uuid, s.password) = split(user)
            if s.password.isEmpty { s.password = q["password"] ?? "" }
            s.security = "tls"
            s.sni = q["sni"] ?? q["peer"] ?? ""
            s.alpn = list(q["alpn"])
            s.insecure = flag(q["allow_insecure"]) || flag(q["allowinsecure"]) || flag(q["insecure"])
            s.congestion = q["congestion_control"] ?? q["congestion"] ?? q["cc"] ?? ""
            s.udpRelayMode = q["udp_relay_mode"] ?? ""
        case .ssh:
            (s.user, s.password) = split(user)
        case .wireguard:
            s.privateKey = user
            s.peerPublicKey = q["publickey"] ?? q["public_key"] ?? q["peer"] ?? q["pbk"] ?? ""
            s.presharedKey = q["presharedkey"] ?? q["pre_shared_key"] ?? q["psk"] ?? ""
            s.addresses = list(q["address"] ?? q["ip"] ?? q["local_address"])
            s.allowedIPs = list(q["allowedips"] ?? q["allowed_ips"])
            s.reserved = ints(q["reserved"])
            s.mtu = Int(q["mtu"] ?? "") ?? 0
            s.keepalive = Int(q["keepalive"] ?? q["persistentkeepalive"] ?? "") ?? 0
        default:
            throw TunnelConfigError.unsupported(proto == .custom ? scheme : proto.title)
        }
        return s
    }

    /// TLS / REALITY / transport parameters shared by VLESS, VMess and Trojan links.
    mutating func applyStream(_ q: [String: String], defaultSecurity: String) {
        security = (q["security"] ?? defaultSecurity).lowercased()
        if security == "none" || security == "false" { security = "" }
        if security == "xtls" || security == "true" { security = "tls" }
        sni = q["sni"] ?? q["peer"] ?? q["servername"] ?? ""
        fingerprint = q["fp"] ?? q["fingerprint"] ?? ""
        alpn = Self.list(q["alpn"])
        insecure = Self.flag(q["allowinsecure"]) || Self.flag(q["insecure"]) || Self.flag(q["allow_insecure"])
        publicKey = q["pbk"] ?? q["publickey"] ?? q["public-key"] ?? ""
        shortID = q["sid"] ?? q["shortid"] ?? q["short-id"] ?? ""
        network = (q["type"] ?? q["net"] ?? q["network"] ?? "tcp").lowercased()
        path = q["path"] ?? ""
        hostHeader = q["host"] ?? ""
        serviceName = q["servicename"] ?? q["service_name"] ?? ""
        headerType = (q["headertype"] ?? "").lowercased()
        if headerType == "none" { headerType = "" }
        if network == "grpc", serviceName.isEmpty { serviceName = path }
    }

    /// vmess://base64(JSON) — the v2rayN format.
    static func vmessJSON(_ text: String) -> ProxySpec? {
        let body = String(text.dropFirst("vmess://".count))
        let main = ShareLinkParser.splitFragment(body).0
        guard let json = Base64.decodeString(main), let data = json.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let str = ShareLinkParser.str
        var s = ProxySpec(proto: .vmess)
        s.host = str(o["add"])
        s.port = ShareLinkParser.int(o["port"]) ?? 443
        s.uuid = str(o["id"])
        s.alterID = ShareLinkParser.int(o["aid"]) ?? 0
        s.method = str(o["scy"]).isEmpty ? "auto" : str(o["scy"])
        var q: [String: String] = [
            "type": str(o["net"]), "headertype": str(o["type"]), "host": str(o["host"]), "path": str(o["path"]),
            "security": str(o["tls"]), "sni": str(o["sni"]), "alpn": str(o["alpn"]), "fp": str(o["fp"]),
            "allowinsecure": str(o["allowInsecure"] ?? o["skip-cert-verify"]),
        ]
        q = q.filter { !$0.value.isEmpty }
        s.applyStream(q, defaultSecurity: "")
        if s.network == "grpc" { s.serviceName = s.path }
        return s
    }

    /// ss://base64(method:password)@host:port/?plugin=…#name, ss://method:password@host:port
    /// (SIP022 keys) and the legacy ss://base64(method:password@host:port).
    static func shadowsocks(_ text: String) throws -> ProxySpec {
        let body = String(text.dropFirst("ss://".count))
        var main = ShareLinkParser.splitFragment(body).0
        var query: [String: String] = [:]
        if let qi = main.firstIndex(of: "?") {
            for pair in main[main.index(after: qi)...].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard let k = kv.first else { continue }
                let v = kv.count > 1 ? kv[1] : ""
                query[k.lowercased()] = v.removingPercentEncoding ?? v
            }
            main = String(main[..<qi])
        }
        if main.hasSuffix("/") { main.removeLast() }

        var userInfo = "", hostPort = ""
        if let at = main.lastIndex(of: "@") {
            let raw = String(main[..<at])
            let user = raw.removingPercentEncoding ?? raw
            userInfo = user.contains(":") ? user : (Base64.decodeString(user) ?? user)
            hostPort = String(main[main.index(after: at)...])
        } else if let decoded = Base64.decodeString(main), let at = decoded.lastIndex(of: "@") {
            userInfo = String(decoded[..<at])
            hostPort = String(decoded[decoded.index(after: at)...])
        } else {
            throw TunnelConfigError.invalid("Shadowsocks")
        }
        var s = ProxySpec(proto: .shadowsocks)
        (s.method, s.password) = split(userInfo)
        let (host, port) = ShareLinkParser.splitHostPort(hostPort)
        s.host = host
        s.port = port == 0 ? 8388 : port
        if let plugin = query["plugin"], !plugin.isEmpty {
            let parts = plugin.split(separator: ";", maxSplits: 1).map(String.init)
            s.plugin = parts[0]
            s.pluginOptions = parts.count > 1 ? parts[1] : ""
        }
        guard !s.host.isEmpty else { throw TunnelConfigError.invalid(L10n.t("адрес сервера", "server address")) }
        return s
    }

    // MARK: WireGuard .conf

    static func wireGuardConf(_ text: String) throws -> ProxySpec {
        var s = ProxySpec(proto: .wireguard)
        var section = ""
        var peers = 0
        let amnezia: Set<String> = ["jc", "jmin", "jmax", "s1", "s2", "s3", "s4", "h1", "h2", "h3", "h4", "i1", "i2", "i3", "i4", "i5"]
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("[") {
                section = line.lowercased()
                if section == "[peer]" { peers += 1 }
                continue
            }
            let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            let key = kv[0].lowercased(), value = kv[1]
            if section == "[interface]" {
                switch key {
                case "privatekey": s.privateKey = value
                case "address": s.addresses += list(value)
                case "mtu": s.mtu = Int(value) ?? 0
                case _ where amnezia.contains(key): throw TunnelConfigError.unsupported("AmneziaWG")
                default: break
                }
            } else if section == "[peer]", peers == 1 {
                switch key {
                case "publickey": s.peerPublicKey = value
                case "presharedkey": s.presharedKey = value
                case "allowedips": s.allowedIPs += list(value)
                case "endpoint": (s.host, s.port) = ShareLinkParser.splitHostPort(value)
                case "persistentkeepalive": s.keepalive = Int(value) ?? 0
                default: break
                }
            }
        }
        if s.port == 0 { s.port = 51820 }
        return s
    }

    // MARK: sing-box / Xray / Clash JSON (as stored by ConfigFiles)

    static func json(_ text: String) throws -> ParsedProxy {
        guard let data = text.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw TunnelConfigError.invalid("JSON")
        }
        if o["protocol"] is String { return .spec(try xray(o)) }
        // ConfigFiles stores Clash entries as a flat string dictionary with "port".
        if o["port"] != nil, o["server_port"] == nil, o["peers"] == nil {
            var flat: [String: String] = [:]
            for (k, v) in o { flat[k] = ShareLinkParser.str(v) }
            return .spec(try clash(flat))
        }
        if o["type"] is String { return .singBox(o) }
        throw TunnelConfigError.invalid("JSON")
    }

    static func xray(_ o: [String: Any]) throws -> ProxySpec {
        let str = ShareLinkParser.str
        let int = { (v: Any?) in ShareLinkParser.int(v) ?? 0 }
        let name = str(o["protocol"]).lowercased()
        let settings = o["settings"] as? [String: Any] ?? [:]
        var s: ProxySpec
        switch name {
        case "vless", "vmess":
            s = ProxySpec(proto: name == "vless" ? .vless : .vmess)
            let server = (settings["vnext"] as? [[String: Any]])?.first ?? settings
            let user = (server["users"] as? [[String: Any]])?.first ?? server
            s.host = str(server["address"])
            s.port = int(server["port"])
            s.uuid = str(user["id"])
            s.flow = str(user["flow"])
            s.alterID = int(user["alterId"])
            s.method = str(user["security"]).isEmpty ? "auto" : str(user["security"])
            let enc = str(user["encryption"]).lowercased()
            if name == "vless", !enc.isEmpty, enc != "none" { throw TunnelConfigError.unsupported("VLESS Encryption") }
        case "trojan", "shadowsocks":
            s = ProxySpec(proto: name == "trojan" ? .trojan : .shadowsocks)
            let server = (settings["servers"] as? [[String: Any]])?.first ?? settings
            s.host = str(server["address"])
            s.port = int(server["port"])
            s.password = str(server["password"])
            s.method = str(server["method"])
        case "wireguard":
            s = ProxySpec(proto: .wireguard)
            s.privateKey = str(settings["secretKey"])
            s.addresses = strings(settings["address"])
            s.mtu = int(settings["mtu"])
            s.reserved = (settings["reserved"] as? [Any])?.compactMap { ShareLinkParser.int($0) } ?? []
            let peer = (settings["peers"] as? [[String: Any]])?.first ?? [:]
            s.peerPublicKey = str(peer["publicKey"])
            s.presharedKey = str(peer["preSharedKey"])
            (s.host, s.port) = ShareLinkParser.splitHostPort(str(peer["endpoint"]))
            s.allowedIPs = strings(peer["allowedIPs"])
            s.keepalive = int(peer["keepAlive"])
            return s
        default:
            throw TunnelConfigError.unsupported(name.isEmpty ? "Xray" : name)
        }

        let stream = o["streamSettings"] as? [String: Any] ?? [:]
        var network = str(stream["network"]).lowercased()
        if network.isEmpty || network == "raw" { network = "tcp" }
        if network == "h2" { network = "http" }
        s.network = network
        let security = str(stream["security"]).lowercased()
        s.security = security == "none" ? "" : security
        let tls = (stream["realitySettings"] as? [String: Any]) ?? (stream["tlsSettings"] as? [String: Any]) ?? [:]
        s.sni = str(tls["serverName"])
        s.fingerprint = str(tls["fingerprint"])
        s.alpn = strings(tls["alpn"])
        s.insecure = (tls["allowInsecure"] as? Bool) ?? false
        s.publicKey = str(tls["publicKey"]).isEmpty ? str(tls["password"]) : str(tls["publicKey"])
        s.shortID = str(tls["shortId"])
        switch network {
        case "ws":
            let ws = stream["wsSettings"] as? [String: Any] ?? [:]
            s.path = str(ws["path"])
            s.hostHeader = str(ws["host"])
            if s.hostHeader.isEmpty, let headers = ws["headers"] as? [String: Any] {
                s.hostHeader = str(headers["Host"] ?? headers["host"])
            }
        case "grpc":
            let grpc = stream["grpcSettings"] as? [String: Any] ?? [:]
            s.serviceName = str(grpc["serviceName"])
        case "http":
            let http = stream["httpSettings"] as? [String: Any] ?? [:]
            s.hostHeader = strings(http["host"]).joined(separator: ",")
            s.path = str(http["path"])
        case "httpupgrade":
            let hu = stream["httpupgradeSettings"] as? [String: Any] ?? [:]
            s.path = str(hu["path"])
            s.hostHeader = str(hu["host"])
        case "tcp":
            let tcp = (stream["tcpSettings"] as? [String: Any]) ?? (stream["rawSettings"] as? [String: Any]) ?? [:]
            let header = tcp["header"] as? [String: Any] ?? [:]
            s.headerType = str(header["type"]).lowercased() == "http" ? "http" : ""
        default:
            break
        }
        return s
    }

    static func clash(_ p: [String: String]) throws -> ProxySpec {
        let type = (p["type"] ?? "").lowercased()
        let protos: [String: ProxyProtocol] = [
            "vless": .vless, "vmess": .vmess, "trojan": .trojan, "ss": .shadowsocks, "shadowsocks": .shadowsocks,
            "hysteria2": .hysteria2, "hy2": .hysteria2, "tuic": .tuic, "wireguard": .wireguard, "ssh": .ssh,
        ]
        guard let proto = protos[type] else { throw TunnelConfigError.unsupported(type.isEmpty ? "Clash" : type) }
        var s = ProxySpec(proto: proto)
        s.host = p["server"] ?? ""
        s.port = Int(p["port"] ?? "") ?? proto.defaultPort
        s.insecure = flag(p["skip-cert-verify"])
        s.fingerprint = p["client-fingerprint"] ?? ""
        s.alpn = list(p["alpn"])
        s.sni = p["servername"] ?? p["sni"] ?? ""
        let reality = nested(p, "reality-opts")
        s.publicKey = reality["public-key"] ?? ""
        s.shortID = reality["short-id"] ?? ""
        let tls = flag(p["tls"])

        s.network = (p["network"] ?? "tcp").lowercased()
        if s.network == "h2" { s.network = "http" }
        switch s.network {
        case "ws":
            let ws = nested(p, "ws-opts")
            s.path = ws["path"] ?? ""
            let headers = nested(ws, "headers")
            s.hostHeader = headers["Host"] ?? headers["host"] ?? ws["Host"] ?? ""
            if let ed = ws["max-early-data"], let n = Int(ed), n > 0, !s.path.contains("ed=") {
                s.path += (s.path.contains("?") ? "&" : "?") + "ed=\(n)"
            }
        case "grpc":
            s.serviceName = nested(p, "grpc-opts")["grpc-service-name"] ?? ""
        case "http":
            let h2 = nested(p, "h2-opts")
            s.hostHeader = list(h2["host"]).joined(separator: ",")
            s.path = h2["path"] ?? ""
            if p["http-opts"] != nil { s.network = "tcp"; s.headerType = "http" }
        default:
            break
        }

        switch proto {
        case .vless:
            s.uuid = p["uuid"] ?? ""
            s.flow = p["flow"] ?? ""
            s.security = !s.publicKey.isEmpty ? "reality" : (tls ? "tls" : "")
        case .vmess:
            s.uuid = p["uuid"] ?? ""
            s.alterID = Int(p["alterId"] ?? p["alterid"] ?? "") ?? 0
            s.method = p["cipher"] ?? "auto"
            s.security = tls ? "tls" : ""
        case .trojan:
            s.password = p["password"] ?? ""
            s.security = !s.publicKey.isEmpty ? "reality" : "tls"
        case .shadowsocks:
            s.method = p["cipher"] ?? ""
            s.password = p["password"] ?? ""
            let plugin = (p["plugin"] ?? "").lowercased()
            let opts = nested(p, "plugin-opts")
            if plugin == "obfs" || plugin == "simple-obfs" {
                s.plugin = "obfs-local"
                var o = ["obfs=\(opts["mode"] ?? "http")"]
                if let host = opts["host"], !host.isEmpty { o.append("obfs-host=\(host)") }
                s.pluginOptions = o.joined(separator: ";")
            } else if plugin == "v2ray-plugin" {
                s.plugin = "v2ray-plugin"
                var o: [String] = []
                if flag(opts["tls"]) { o.append("tls") }
                if let host = opts["host"], !host.isEmpty { o.append("host=\(host)") }
                if let path = opts["path"], !path.isEmpty { o.append("path=\(path)") }
                s.pluginOptions = o.joined(separator: ";")
            } else if !plugin.isEmpty {
                s.plugin = plugin
            }
        case .hysteria2:
            s.password = p["password"] ?? p["auth"] ?? ""
            s.security = "tls"
            s.obfs = p["obfs"] ?? ""
            s.obfsPassword = p["obfs-password"] ?? ""
            s.hopPorts = p["ports"] ?? ""
            s.upMbps = mbps(p["up"])
            s.downMbps = mbps(p["down"])
        case .tuic:
            s.uuid = p["uuid"] ?? ""
            s.password = p["password"] ?? ""
            s.security = "tls"
            s.congestion = p["congestion-controller"] ?? ""
            s.udpRelayMode = p["udp-relay-mode"] ?? ""
        case .wireguard:
            s.privateKey = p["private-key"] ?? ""
            s.peerPublicKey = p["public-key"] ?? ""
            s.presharedKey = p["pre-shared-key"] ?? p["preshared-key"] ?? ""
            s.addresses = [p["ip"], p["ipv6"]].compactMap { $0 }.filter { !$0.isEmpty }
            s.allowedIPs = list(p["allowed-ips"])
            s.reserved = ints(p["reserved"])
            s.mtu = Int(p["mtu"] ?? "") ?? 0
        case .ssh:
            s.user = p["username"] ?? ""
            s.password = p["password"] ?? ""
        default:
            break
        }
        return s
    }

    // MARK: Helpers

    /// A nested Clash map: flow style ("{path: /x, headers: {Host: a}}") is parsed, block style
    /// was already flattened by ConfigFiles, so the flat dictionary itself is returned.
    static func nested(_ p: [String: String], _ key: String) -> [String: String] {
        if let raw = p[key]?.trimmingCharacters(in: .whitespaces), raw.hasPrefix("{") {
            return ConfigFiles.flowMap(raw)
        }
        return p
    }

    static func flag(_ s: String?) -> Bool {
        guard let s = s?.lowercased() else { return false }
        return s == "1" || s == "true" || s == "yes"
    }

    /// "a,b", "[a, b]", "a b" → ["a", "b"].
    static func list(_ s: String?) -> [String] {
        guard var t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return [] }
        if t.hasPrefix("["), t.hasSuffix("]") { t = String(t.dropFirst().dropLast()) }
        return t.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
            .filter { !$0.isEmpty }
    }

    static func ints(_ s: String?) -> [Int] { list(s).compactMap { Int($0) } }

    static func strings(_ any: Any?) -> [String] {
        if let a = any as? [Any] { return a.map { ShareLinkParser.str($0) }.filter { !$0.isEmpty } }
        if let s = any as? String { return list(s) }
        return []
    }

    /// "100", "100 Mbps", "100mbps" → 100.
    static func mbps(_ s: String?) -> Int {
        guard let s else { return 0 }
        return Int(s.prefix { $0.isNumber }) ?? 0
    }

    /// "a:b" → ("a", "b"); no colon → (whole, "").
    static func split(_ s: String) -> (String, String) {
        guard let c = s.firstIndex(of: ":") else { return (s, "") }
        return (String(s[..<c]), String(s[s.index(after: c)...]))
    }
}
