import Foundation

/// OpenVPN `.ovpn` → sing-box `openvpn-client` endpoint (sing-box 1.14+, userspace OpenVPN).
/// Only inline configs work: certificates and keys must be inside `<ca>`, `<cert>`… blocks.
enum OpenVPNConfig {
    static func endpoint(_ text: String) throws -> [String: Any] {
        let (directives, blocks) = parse(text)
        func first(_ key: String) -> [String]? { directives.first { $0.0 == key }?.1 }
        func has(_ key: String) -> Bool { directives.contains { $0.0 == key } }

        if let dev = first("dev")?.first?.lowercased(), dev.hasPrefix("tap") {
            throw TunnelConfigError.unsupported("OpenVPN TAP")
        }
        if blocks["secret"] != nil || has("secret") {
            throw TunnelConfigError.unsupported(L10n.t("OpenVPN со статическим ключом", "OpenVPN static key mode"))
        }

        // Servers
        let defaultNetwork = network(first("proto")?.first) ?? "udp"
        let defaultPort = Int(first("port")?.first ?? "") ?? 1194
        var servers: [[String: Any]] = []
        for (key, args) in directives where key == "remote" {
            guard let host = args.first, !host.isEmpty else { continue }
            var s: [String: Any] = ["server": host, "server_port": args.count > 1 ? (Int(args[1]) ?? defaultPort) : defaultPort]
            if args.count > 2, let n = network(args[2]) { s["network"] = n }
            servers.append(s)
        }
        guard !servers.isEmpty else { throw TunnelConfigError.invalid(L10n.t("нет строки remote", "no remote line")) }

        var e: [String: Any] = ["type": "openvpn-client", "tag": SingBoxOutbound.tag, "network": defaultNetwork]
        if servers.count == 1 {
            e["server"] = servers[0]["server"]
            e["server_port"] = servers[0]["server_port"]
            if let n = servers[0]["network"] { e["network"] = n }
        } else {
            e["servers"] = servers
            if has("remote-random") { e["remote_random"] = true }
        }

        // TLS control channel
        var tls: [String: Any] = [:]
        guard let ca = blocks["ca"], !ca.isEmpty else {
            if has("ca") {
                throw TunnelConfigError.invalid(L10n.t("сертификат CA должен быть внутри файла (<ca>…</ca>)", "the CA certificate must be inline (<ca>…</ca>)"))
            }
            throw TunnelConfigError.invalid(L10n.t("нет сертификата CA", "no CA certificate"))
        }
        tls["certificate"] = lines(ca)
        if let cert = blocks["cert"], let key = blocks["key"] {
            tls["client_certificate"] = lines(cert)
            tls["client_key"] = lines(key)
        } else if has("cert") || has("key") {
            throw TunnelConfigError.invalid(L10n.t("сертификат и ключ клиента должны быть внутри файла", "the client certificate and key must be inline"))
        }
        if let wrap = blocks["tls-crypt-v2"] {
            tls["control_wrap"] = ["type": "tls_crypt_v2", "key": lines(wrap)]
        } else if let wrap = blocks["tls-crypt"] {
            tls["control_wrap"] = ["type": "tls_crypt", "key": lines(wrap)]
        } else if let wrap = blocks["tls-auth"] {
            var w: [String: Any] = ["type": "tls_auth", "key": lines(wrap)]
            let direction = first("key-direction")?.first ?? first("tls-auth")?.dropFirst().first
            if direction == "1" { w["direction"] = "client" } else if direction == "0" { w["direction"] = "server" }
            tls["control_wrap"] = w
        }
        for key in ["tls-auth", "tls-crypt", "tls-crypt-v2"] where has(key) && blocks[key] == nil {
            throw TunnelConfigError.invalid(L10n.t("ключ \(key) должен быть внутри файла", "the \(key) key must be inline"))
        }
        if let args = first("verify-x509-name"), let name = args.first, !name.isEmpty {
            tls["server_name"] = name
            let type = args.count > 1 ? args[1].lowercased() : "subject"
            tls["server_name_type"] = ["subject", "name", "name-prefix"].contains(type) ? type : "subject"
        }
        if let value = first("remote-cert-tls")?.first?.lowercased(), ["server", "client", "none"].contains(value) {
            tls["remote_certificate_tls"] = value
        }
        if let value = first("tls-version-min")?.first, ["1.0", "1.1", "1.2", "1.3"].contains(value) {
            tls["version_min"] = value
        }
        if let value = first("tls-version-max")?.first, ["1.0", "1.1", "1.2", "1.3"].contains(value) {
            tls["version_max"] = value
        }
        if let value = first("tls-cipher")?.first, !value.isEmpty { tls["cipher"] = value }
        e["tls"] = tls

        // Data channel
        if let value = (first("data-ciphers") ?? first("ncp-ciphers"))?.first, !value.isEmpty {
            e["data_ciphers"] = value.split(separator: ":").map(String.init)
        }
        if let value = (first("data-ciphers-fallback") ?? first("cipher"))?.first, !value.isEmpty {
            e["data_ciphers_fallback"] = value.uppercased()
        }
        if let value = first("auth")?.first, !value.isEmpty, value.lowercased() != "none" { e["auth"] = value.uppercased() }
        if let args = first("comp-lzo") {
            let mode = args.first?.lowercased() ?? "adaptive"
            e["compression_lzo"] = ["yes", "no", "adaptive"].contains(mode) ? mode : "adaptive"
            if mode != "no" { e["allow_compression"] = "asym" }
        }
        if let args = first("compress") {
            let mode = args.first?.lowercased() ?? "stub"
            e["compression"] = ["lz4", "lz4-v2", "stub", "stub-v2"].contains(mode) ? mode : "stub"
            if mode.hasPrefix("lz4") { e["allow_compression"] = "asym" }
        }

        // Credentials: inline <auth-user-pass> (the manual editor writes one).
        if let auth = blocks["auth-user-pass"] {
            let parts = auth.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let user = parts.first { e["username"] = user }
            if parts.count > 1 { e["password"] = parts[1] }
        } else if has("auth-user-pass"), first("auth-user-pass")?.isEmpty ?? true {
            throw TunnelConfigError.invalid(L10n.t("сервер требует логин и пароль — укажите их в настройках сервера",
                                                   "the server needs a login and password — add them in the server settings"))
        }
        return e
    }

    // MARK: Parsing

    /// Directives in file order + inline blocks (`<ca>…</ca>`) by lowercased name.
    static func parse(_ text: String) -> ([(String, [String])], [String: String]) {
        var directives: [(String, [String])] = []
        var blocks: [String: String] = [:]
        var blockName: String?
        var blockLines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name = blockName {
                if line.lowercased() == "</\(name)>" {
                    blocks[name] = blockLines.joined(separator: "\n")
                    blockName = nil
                    blockLines = []
                } else {
                    blockLines.append(line)
                }
                continue
            }
            if line.hasPrefix("<"), line.hasSuffix(">"), !line.hasPrefix("</") {
                blockName = String(line.dropFirst().dropLast()).lowercased()
                continue
            }
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            let parts = tokens(line)
            guard let key = parts.first?.lowercased() else { continue }
            directives.append((key.hasPrefix("--") ? String(key.dropFirst(2)) : key, Array(parts.dropFirst())))
        }
        return (directives, blocks)
    }

    /// Whitespace-separated arguments, "double" / 'single' quotes respected.
    static func tokens(_ line: String) -> [String] {
        var out: [String] = []
        var token = ""
        var quote: Character?
        var hasToken = false
        for ch in line {
            if let q = quote {
                if ch == q { quote = nil } else { token.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                hasToken = true
            } else if ch == " " || ch == "\t" {
                if hasToken { out.append(token) }
                token = ""
                hasToken = false
            } else if ch == "#" || ch == ";", !hasToken {
                break
            } else {
                token.append(ch)
                hasToken = true
            }
        }
        if hasToken { out.append(token) }
        return out
    }

    /// udp, udp4, udp6 → udp; tcp, tcp-client, tcp4… → tcp.
    static func network(_ value: String?) -> String? {
        guard let v = value?.lowercased() else { return nil }
        if v.hasPrefix("udp") { return "udp" }
        if v.hasPrefix("tcp") { return "tcp" }
        return nil
    }

    static func lines(_ block: String) -> [String] {
        block.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
