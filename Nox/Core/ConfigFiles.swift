import Foundation

/// Config files: sing-box / Xray JSON, Clash YAML, WireGuard / AmneziaWG .conf and OpenVPN
/// .ovpn. Every recognised outbound becomes a `Server`; its `link` keeps the original config
/// so the tunnel engine receives it unchanged.
enum ConfigFiles {
    // MARK: sing-box / Xray JSON

    /// Outbounds of a sing-box or Xray config: a full config, a bare outbound or an array of
    /// either. nil → the text isn't JSON.
    static func json(_ text: String) -> [Server]? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var outbounds: [[String: Any]] = []
        var stack: [Any] = [root]
        while let object = stack.popLast() {
            if let dict = object as? [String: Any] {
                if let list = dict["outbounds"] as? [[String: Any]] {
                    outbounds += list
                } else {
                    outbounds.append(dict)
                }
            } else if let list = object as? [Any] {
                stack += list.reversed()
            }
        }
        return outbounds.compactMap(outbound)
    }

    private static let types: [String: ProxyProtocol] = [
        "vless": .vless, "vmess": .vmess, "trojan": .trojan, "shadowsocks": .shadowsocks, "ss": .shadowsocks,
        "hysteria2": .hysteria2, "hy2": .hysteria2, "tuic": .tuic, "wireguard": .wireguard, "ssh": .ssh,
    ]

    private static func outbound(_ o: [String: Any]) -> Server? {
        let str = ShareLinkParser.str
        let int = ShareLinkParser.int
        // OpenFlux profile ({"transport": "yandex", "urls": […]}); sing-box's transport is an object.
        if o["transport"] is String, let profile = OpenFluxProfile(json: o) {
            return profile.server(name: str(o["name"] ?? o["tag"]))
        }
        var s = Server()
        if let type = o["type"] as? String {
            // sing-box: type / server / server_port / tls / transport
            guard let proto = types[type.lowercased()] else { return nil }
            s.proto = proto
            s.host = str(o["server"])
            s.port = int(o["server_port"]) ?? 0
            if proto == .wireguard, s.host.isEmpty, let peer = (o["peers"] as? [[String: Any]])?.first {
                s.host = str(peer["server"])
                s.port = int(peer["server_port"]) ?? 0
            }
            let tls = o["tls"] as? [String: Any]
            let reality = (tls?["reality"] as? [String: Any])?["enabled"] as? Bool ?? false
            s.variant = variant(proto, reality: reality, tls: tls?["enabled"] as? Bool ?? false,
                                network: str((o["transport"] as? [String: Any])?["type"]), method: str(o["method"]))
        } else if let name = o["protocol"] as? String {
            // Xray: protocol / settings.vnext|servers|peers / streamSettings
            guard let proto = types[name.lowercased()] else { return nil }
            s.proto = proto
            let settings = o["settings"] as? [String: Any] ?? [:]
            let entry = (settings["vnext"] as? [[String: Any]])?.first
                ?? (settings["servers"] as? [[String: Any]])?.first
                ?? (settings["peers"] as? [[String: Any]])?.first
                ?? settings
            if let endpoint = entry["endpoint"] as? String {
                (s.host, s.port) = ShareLinkParser.splitHostPort(endpoint)
            } else {
                s.host = str(entry["address"])
                s.port = int(entry["port"]) ?? 0
            }
            let stream = o["streamSettings"] as? [String: Any] ?? [:]
            let security = str(stream["security"]).lowercased()
            s.variant = variant(proto, reality: security == "reality", tls: security == "tls",
                                network: str(stream["network"]), method: str(entry["method"]))
        } else {
            return nil
        }
        guard !s.host.isEmpty else { return nil }
        if s.port == 0 { s.port = s.proto.defaultPort }
        var tag = str(o["tag"])
        if ["proxy", "out", "outbound"].contains(tag.lowercased()) { tag = "" }
        s.link = serialize(o)
        s.name = ShareLinkParser.cleanName(tag)
        ShareLinkParser.finish(&s, hint: tag)
        return s
    }

    /// Short label after the protocol title — the same values share links produce.
    static func variant(_ proto: ProxyProtocol, reality: Bool, tls: Bool, network: String, method: String) -> String {
        switch proto {
        case .shadowsocks:
            return method.lowercased().hasPrefix("2022-") ? "2022" : ""
        case .vless, .vmess, .trojan:
            if reality { return "Reality" }
            switch network.lowercased() {
            case "ws": return "WS"
            case "grpc": return "gRPC"
            case "xhttp", "splithttp": return "XHTTP"
            case "httpupgrade": return "HTTPUpgrade"
            case "h2", "http": return "H2"
            default: return tls ? "TLS" : ""
            }
        default:
            return ""
        }
    }

    private static func serialize(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: WireGuard / AmneziaWG

    static func wireguard(_ text: String, name: String?) -> Server? {
        var section = ""
        var endpoint = ""
        var isAmnezia = false
        let amneziaKeys: Set<String> = ["jc", "jmin", "jmax", "s1", "s2", "h1", "h2", "h3", "h4"]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { section = line.lowercased(); continue }
            let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            let key = kv[0].lowercased()
            if section == "[interface]", amneziaKeys.contains(key) { isAmnezia = true }
            if section == "[peer]", key == "endpoint", endpoint.isEmpty { endpoint = kv[1] }
        }
        guard !endpoint.isEmpty else { return nil }
        let (host, port) = ShareLinkParser.splitHostPort(endpoint)
        var s = Server()
        s.proto = isAmnezia ? .amneziawg : .wireguard
        s.host = host
        s.port = port == 0 ? 51820 : port
        s.link = text
        let base = fileBase(name)
        s.name = ShareLinkParser.cleanName(base)
        ShareLinkParser.finish(&s, hint: base)
        return s
    }

    // MARK: OpenVPN

    static func looksLikeOpenVPN(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("\nremote ") || lower.hasPrefix("remote ") || (lower.contains("client") && lower.contains("<ca>"))
    }

    static func openvpn(_ text: String, name: String?) -> Server? {
        var host = "", port = 1194
        for raw in text.components(separatedBy: .newlines) {
            let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: " ")
            if parts.first?.lowercased() == "remote", parts.count >= 2 {
                host = String(parts[1])
                if parts.count >= 3, let p = Int(parts[2]) { port = p }
                break
            }
        }
        guard !host.isEmpty else { return nil }
        var s = Server()
        s.proto = .openvpn
        s.host = host
        s.port = port
        s.link = text
        let base = fileBase(name)
        s.name = ShareLinkParser.cleanName(base)
        ShareLinkParser.finish(&s, hint: base)
        return s
    }

    // MARK: Clash YAML (minimal: block and flow style proxies)

    static func clash(_ text: String) -> [Server] {
        var out: [Server] = []
        var inProxies = false
        var current: [String: String] = [:]
        /// Indent of the "- name: …" items; deeper "- x" lines are nested lists ("alpn:\n  - h2").
        var itemIndent: Int?
        var lastKey: String?

        func flush() {
            defer { current = [:] }
            guard !current.isEmpty, let s = clashProxy(current) else { return }
            out.append(s)
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.replacingOccurrences(of: "\t", with: "  ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix { $0 == " " }.count
            if indent == 0, !trimmed.hasPrefix("-") {
                // Top-level key: "proxies:" opens the list, anything else closes it.
                flush()
                inProxies = trimmed.hasPrefix("proxies:")
                itemIndent = nil
                lastKey = nil
                continue
            }
            guard inProxies else { continue }
            if trimmed == "-" || trimmed.hasPrefix("- ") {
                let item = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if let base = itemIndent, indent > base {
                    // Nested block list → comma-joined value of the key above it.
                    if let key = lastKey {
                        let value = unquote(item)
                        let old = current[key] ?? ""
                        current[key] = old.isEmpty ? value : old + "," + value
                    }
                    continue
                }
                itemIndent = indent
                flush()
                lastKey = nil
                if item.hasPrefix("{") {
                    current = flowMap(item)
                    flush()
                } else if let kv = keyValue(item) {
                    current[kv.0] = kv.1
                    lastKey = kv.0
                }
            } else if let kv = keyValue(trimmed) {
                if current[kv.0] == nil {
                    current[kv.0] = kv.1
                    lastKey = kv.0
                } else {
                    lastKey = nil
                }
            }
        }
        flush()
        return out
    }

    private static let clashTypes: [String: ProxyProtocol] = [
        "vless": .vless, "vmess": .vmess, "trojan": .trojan, "ss": .shadowsocks, "shadowsocks": .shadowsocks,
        "hysteria2": .hysteria2, "hy2": .hysteria2, "tuic": .tuic, "wireguard": .wireguard, "ssh": .ssh,
    ]

    private static func clashProxy(_ p: [String: String]) -> Server? {
        guard let type = p["type"]?.lowercased(), let proto = clashTypes[type],
              let host = p["server"], !host.isEmpty else { return nil }
        var s = Server()
        s.proto = proto
        s.host = host
        s.port = Int(p["port"] ?? "") ?? proto.defaultPort
        let name = p["name"] ?? ""
        let reality = p["reality-opts"] != nil || p["public-key"] != nil
        let tls = (p["tls"] ?? "").lowercased() == "true"
        s.variant = variant(proto, reality: reality, tls: tls, network: p["network"] ?? "", method: p["cipher"] ?? "")
        s.link = serialize(p)
        s.name = ShareLinkParser.cleanName(name)
        ShareLinkParser.finish(&s, hint: name)
        return s
    }

    /// "key: value" → (key, value) with quotes stripped.
    private static func keyValue(_ s: String) -> (String, String)? {
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let key = s[..<colon].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.contains(" ") || key.hasPrefix("\"") else { return nil }
        return (unquote(key), unquote(String(s[s.index(after: colon)...])))
    }

    /// `{name: US-1, type: ss, server: us.example.com, port: 8388}` → top-level pairs.
    static func flowMap(_ s: String) -> [String: String] {
        var body = Substring(s.trimmingCharacters(in: .whitespaces))
        if body.hasPrefix("{") { body = body.dropFirst() }
        if body.hasSuffix("}") { body = body.dropLast() }
        var out: [String: String] = [:]
        var token = ""
        var depth = 0
        var quote: Character?
        for ch in body {
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == "{" || ch == "[" {
                depth += 1
            } else if ch == "}" || ch == "]" {
                depth -= 1
            } else if ch == ",", depth == 0 {
                if let kv = keyValue(token) { out[kv.0] = kv.1 }
                token = ""
                continue
            }
            token.append(ch)
        }
        if let kv = keyValue(token) { out[kv.0] = kv.1 }
        return out
    }

    private static func unquote(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, let f = t.first, f == "\"" || f == "'", t.last == f {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }

    private static func fileBase(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "" }
        return (name as NSString).deletingPathExtension
    }
}
