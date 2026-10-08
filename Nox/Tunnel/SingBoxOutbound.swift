import Foundation

/// sing-box outbound (or endpoint) for one server, always tagged "proxy".
enum SingBoxOutbound {
    struct Built {
        var object: [String: Any]
        /// WireGuard / OpenVPN live in `endpoints`, everything else in `outbounds`.
        var isEndpoint: Bool
        var type: String { object["type"] as? String ?? "" }
    }

    static let tag = "proxy"
    static let endpointTypes: Set<String> = ["wireguard", "openvpn-client", "tailscale", "openconnect"]

    static func make(_ server: Server) throws -> Built {
        switch try ProxySpec.parse(server) {
        case .spec(let spec): return try make(spec)
        case .singBox(let object): return try imported(object)
        }
    }

    // MARK: From a spec

    static func make(_ s: ProxySpec) throws -> Built {
        guard !s.host.isEmpty else { throw TunnelConfigError.invalid(L10n.t("нет адреса сервера", "no server address")) }
        guard (1...65535).contains(s.port) else { throw TunnelConfigError.invalid(L10n.t("порт \(s.port)", "port \(s.port)")) }
        var o: [String: Any] = ["tag": tag, "server": s.host, "server_port": s.port]
        switch s.proto {
        case .vless:
            guard !s.uuid.isEmpty else { throw TunnelConfigError.invalid("UUID") }
            o["type"] = "vless"
            o["uuid"] = s.uuid
            let flow = s.flow.lowercased()
            if flow.hasPrefix("xtls-rprx-vision") {
                o["flow"] = "xtls-rprx-vision"
            } else if !flow.isEmpty, flow != "none" {
                throw TunnelConfigError.unsupported("VLESS flow \(s.flow)")
            }
            o["tls"] = try tls(s)
            o["transport"] = try transport(s)
        case .vmess:
            guard !s.uuid.isEmpty else { throw TunnelConfigError.invalid("UUID") }
            o["type"] = "vmess"
            o["uuid"] = s.uuid
            o["security"] = vmessSecurity(s.method)
            if s.alterID > 0 { o["alter_id"] = s.alterID }
            o["tls"] = try tls(s)
            o["transport"] = try transport(s)
        case .trojan:
            guard !s.password.isEmpty else { throw TunnelConfigError.invalid(L10n.t("пароль", "password")) }
            o["type"] = "trojan"
            o["password"] = s.password
            var spec = s
            if spec.security.isEmpty { spec.security = "tls" }
            o["tls"] = try tls(spec)
            o["transport"] = try transport(s)
        case .shadowsocks:
            guard !s.method.isEmpty else { throw TunnelConfigError.invalid(L10n.t("метод шифрования", "cipher")) }
            o["type"] = "shadowsocks"
            o["method"] = shadowsocksMethod(s.method)
            o["password"] = s.password
            var plugin = s.plugin.lowercased()
            if plugin == "simple-obfs" || plugin == "obfs" { plugin = "obfs-local" }
            if plugin == "obfs-local" || plugin == "v2ray-plugin" {
                o["plugin"] = plugin
                if !s.pluginOptions.isEmpty { o["plugin_opts"] = s.pluginOptions }
            } else if !plugin.isEmpty {
                throw TunnelConfigError.unsupported(L10n.t("Плагин Shadowsocks \(s.plugin)", "Shadowsocks plugin \(s.plugin)"))
            }
        case .hysteria2:
            o["type"] = "hysteria2"
            o["password"] = s.password
            if !s.obfsPassword.isEmpty || s.obfs.lowercased() == "salamander" {
                o["obfs"] = ["type": "salamander", "password": s.obfsPassword]
            }
            let ports = portRanges(s.hopPorts)
            if !ports.isEmpty {
                o["server_ports"] = ports
                o.removeValue(forKey: "server_port")
            }
            if s.upMbps > 0 { o["up_mbps"] = s.upMbps }
            if s.downMbps > 0 { o["down_mbps"] = s.downMbps }
            o["tls"] = quicTLS(s, alpn: ["h3"])
        case .tuic:
            guard !s.uuid.isEmpty else { throw TunnelConfigError.invalid("UUID") }
            o["type"] = "tuic"
            o["uuid"] = s.uuid
            o["password"] = s.password
            o["congestion_control"] = ["bbr", "cubic", "new_reno"].contains(s.congestion.lowercased()) ? s.congestion.lowercased() : "bbr"
            if ["native", "quic"].contains(s.udpRelayMode.lowercased()) { o["udp_relay_mode"] = s.udpRelayMode.lowercased() }
            o["tls"] = quicTLS(s, alpn: ["h3"])
        case .ssh:
            o["type"] = "ssh"
            o["user"] = s.user.isEmpty ? "root" : s.user
            if !s.password.isEmpty { o["password"] = s.password }
        case .wireguard:
            return Built(object: try wireGuard(s), isEndpoint: true)
        default:
            throw TunnelConfigError.unsupported(s.proto.title)
        }
        return Built(object: o.compactMapValues { $0 is NSNull ? nil : $0 }, isEndpoint: false)
    }

    // MARK: TLS

    /// TLS / REALITY for TCP-based protocols (uTLS fingerprint included). nil → plain.
    static func tls(_ s: ProxySpec) throws -> Any {
        let security = s.security.lowercased()
        guard security == "tls" || security == "reality" else { return NSNull() }
        var t: [String: Any] = ["enabled": true]
        let name = serverName(s)
        if !name.isEmpty { t["server_name"] = name }
        if s.insecure { t["insecure"] = true }
        if !s.alpn.isEmpty { t["alpn"] = s.alpn }
        var fingerprint = utlsFingerprint(s.fingerprint)
        if security == "reality" {
            guard !s.publicKey.isEmpty else { throw TunnelConfigError.invalid(L10n.t("нет публичного ключа REALITY (pbk)", "no REALITY public key (pbk)")) }
            guard !name.isEmpty else { throw TunnelConfigError.invalid(L10n.t("нет SNI для REALITY", "no SNI for REALITY")) }
            var reality: [String: Any] = ["enabled": true, "public_key": s.publicKey]
            if !s.shortID.isEmpty { reality["short_id"] = s.shortID }
            t["reality"] = reality
            t.removeValue(forKey: "insecure")
            if fingerprint == nil { fingerprint = "chrome" }
        }
        if let fingerprint { t["utls"] = ["enabled": true, "fingerprint": fingerprint] }
        return t
    }

    /// TLS for QUIC protocols (Hysteria2, TUIC): no uTLS / REALITY.
    static func quicTLS(_ s: ProxySpec, alpn: [String]) -> [String: Any] {
        var t: [String: Any] = ["enabled": true, "alpn": s.alpn.isEmpty ? alpn : s.alpn]
        let name = serverName(s)
        if !name.isEmpty { t["server_name"] = name }
        if s.insecure { t["insecure"] = true }
        return t
    }

    /// SNI → else the transport Host header → else the server address (when it's a domain).
    static func serverName(_ s: ProxySpec) -> String {
        if !s.sni.isEmpty { return s.sni }
        let header = ProxySpec.list(s.hostHeader).first ?? ""
        if !header.isEmpty, !isIP(header) { return header }
        return isIP(s.host) ? "" : s.host
    }

    static func utlsFingerprint(_ value: String) -> String? {
        let f = value.lowercased()
        switch f {
        case "", "none", "unsafe": return nil
        case "chrome", "firefox", "edge", "safari", "360", "qq", "ios", "android", "random", "randomized": return f
        case "randomizednoalpn": return "randomized"
        default: return "chrome"
        }
    }

    // MARK: Transport

    static func transport(_ s: ProxySpec) throws -> Any {
        switch s.network.lowercased() {
        case "", "tcp", "raw", "none":
            if s.headerType == "http" { throw TunnelConfigError.unsupported(L10n.t("TCP с HTTP-маскировкой", "TCP with HTTP header obfuscation")) }
            return NSNull()
        case "ws", "websocket":
            var t: [String: Any] = ["type": "ws"]
            var path = s.path.isEmpty ? "/" : s.path
            // Xray early data: /path?ed=2048
            if let q = path.firstIndex(of: "?") {
                var rest: [String] = []
                for pair in path[path.index(after: q)...].split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1)
                    if kv.first == "ed", kv.count == 2, let n = Int(kv[1]), n > 0 {
                        t["max_early_data"] = n
                        t["early_data_header_name"] = "Sec-WebSocket-Protocol"
                    } else {
                        rest.append(String(pair))
                    }
                }
                path = String(path[..<q]) + (rest.isEmpty ? "" : "?" + rest.joined(separator: "&"))
            }
            t["path"] = path
            if let host = ProxySpec.list(s.hostHeader).first { t["headers"] = ["Host": host] }
            return t
        case "grpc", "gun":
            return ["type": "grpc", "service_name": s.serviceName]
        case "http", "h2":
            var t: [String: Any] = ["type": "http"]
            let hosts = ProxySpec.list(s.hostHeader)
            if !hosts.isEmpty { t["host"] = hosts }
            if !s.path.isEmpty { t["path"] = s.path }
            return t
        case "httpupgrade":
            var t: [String: Any] = ["type": "httpupgrade"]
            if let host = ProxySpec.list(s.hostHeader).first { t["host"] = host }
            if !s.path.isEmpty { t["path"] = s.path }
            return t
        case "quic":
            return ["type": "quic"]
        case "xhttp", "splithttp":
            throw TunnelConfigError.unsupported(L10n.t("Транспорт XHTTP", "The XHTTP transport"))
        case "kcp", "mkcp":
            throw TunnelConfigError.unsupported(L10n.t("Транспорт mKCP", "The mKCP transport"))
        default:
            throw TunnelConfigError.unsupported(L10n.t("Транспорт \(s.network)", "The \(s.network) transport"))
        }
    }

    // MARK: WireGuard

    static func wireGuard(_ s: ProxySpec) throws -> [String: Any] {
        guard !s.privateKey.isEmpty else { throw TunnelConfigError.invalid(L10n.t("нет PrivateKey", "no PrivateKey")) }
        guard !s.peerPublicKey.isEmpty else { throw TunnelConfigError.invalid(L10n.t("нет PublicKey пира", "no peer PublicKey")) }
        let addresses = s.addresses.map(cidr)
        guard !addresses.isEmpty else { throw TunnelConfigError.invalid(L10n.t("нет Address", "no Address")) }
        var peer: [String: Any] = [
            "address": s.host, "port": s.port, "public_key": s.peerPublicKey,
            "allowed_ips": s.allowedIPs.isEmpty ? ["0.0.0.0/0", "::/0"] : s.allowedIPs.map(cidr),
        ]
        if !s.presharedKey.isEmpty { peer["pre_shared_key"] = s.presharedKey }
        if s.keepalive > 0 { peer["persistent_keepalive_interval"] = s.keepalive }
        if s.reserved.count == 3 { peer["reserved"] = s.reserved }
        var e: [String: Any] = ["type": "wireguard", "tag": tag, "address": addresses, "private_key": s.privateKey, "peers": [peer]]
        if s.mtu > 0 { e["mtu"] = s.mtu }
        return e
    }

    // MARK: Imported sing-box outbounds

    static func imported(_ source: [String: Any]) throws -> Built {
        var o = source
        let type = (o["type"] as? String ?? "").lowercased()
        if ["selector", "urltest", "direct", "block", "dns"].contains(type) {
            throw TunnelConfigError.unsupported(L10n.t("Исходящее «\(type)»", "Outbound \"\(type)\""))
        }
        // Tags / resolvers of the original config don't exist in ours.
        for key in ["detour", "domain_resolver", "domain_strategy", "bind_interface", "inet4_bind_address",
                    "inet6_bind_address", "routing_mark", "netns", "fallback_delay"] {
            o.removeValue(forKey: key)
        }
        o["tag"] = tag
        if type == "wireguard", o["peers"] == nil || o["local_address"] != nil || o["server"] != nil {
            return Built(object: legacyWireGuard(o), isEndpoint: true)
        }
        return Built(object: o, isEndpoint: endpointTypes.contains(type))
    }

    /// sing-box ≤ 1.10 WireGuard outbound → 1.11+ endpoint.
    static func legacyWireGuard(_ o: [String: Any]) -> [String: Any] {
        let str = ShareLinkParser.str
        var e: [String: Any] = ["type": "wireguard", "tag": tag]
        e["address"] = ProxySpec.strings(o["local_address"]).map(cidr)
        e["private_key"] = str(o["private_key"])
        if let mtu = ShareLinkParser.int(o["mtu"]), mtu > 0 { e["mtu"] = mtu }
        var peers: [[String: Any]] = []
        let list = (o["peers"] as? [[String: Any]]) ?? [o]
        for p in list {
            var peer: [String: Any] = [
                "address": str(p["server"]), "port": ShareLinkParser.int(p["server_port"]) ?? 51820,
                "public_key": str(p["public_key"] ?? p["peer_public_key"]),
                "allowed_ips": ProxySpec.strings(p["allowed_ips"]).isEmpty ? ["0.0.0.0/0", "::/0"] : ProxySpec.strings(p["allowed_ips"]),
            ]
            let psk = str(p["pre_shared_key"])
            if !psk.isEmpty { peer["pre_shared_key"] = psk }
            if let reserved = (p["reserved"] ?? o["reserved"]) as? [Any], reserved.count == 3 { peer["reserved"] = reserved }
            peers.append(peer)
        }
        e["peers"] = peers
        return e
    }

    // MARK: Small helpers

    static func vmessSecurity(_ value: String) -> String {
        let v = value.lowercased()
        let known = ["auto", "none", "zero", "aes-128-gcm", "chacha20-poly1305", "aes-128-ctr"]
        return known.contains(v) ? v : "auto"
    }

    static func shadowsocksMethod(_ value: String) -> String {
        let v = value.lowercased()
        switch v {
        case "chacha20-poly1305": return "chacha20-ietf-poly1305"
        case "xchacha20-poly1305": return "xchacha20-ietf-poly1305"
        default: return v
        }
    }

    /// "20000-30000,443" → ["20000:30000", "443:443"].
    static func portRanges(_ value: String) -> [String] {
        ProxySpec.list(value).compactMap { item in
            let parts = item.split(whereSeparator: { $0 == "-" || $0 == ":" }).compactMap { Int($0) }
            if parts.count == 2, parts[0] > 0, parts[0] <= parts[1], parts[1] <= 65535 { return "\(parts[0]):\(parts[1])" }
            if parts.count == 1, (1...65535).contains(parts[0]) { return "\(parts[0]):\(parts[0])" }
            return nil
        }
    }

    static func isIP(_ host: String) -> Bool {
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h.contains(":") { return true }
        let parts = h.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    /// "10.0.0.2" → "10.0.0.2/32", "fd00::2" → "fd00::2/128".
    static func cidr(_ value: String) -> String {
        let v = value.trimmingCharacters(in: .whitespaces)
        if v.contains("/") { return v }
        return v.contains(":") ? "\(v)/128" : "\(v)/32"
    }
}
