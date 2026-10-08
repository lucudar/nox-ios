import Foundation

/// Where the running config keeps its files. The app fills it with App Group paths; tests use
/// temporary ones (and a local mixed inbound instead of TUN).
struct TunnelEnvironment {
    /// sing-box log file. nil → stderr.
    var logPath: String?
    /// cache.db: rule-sets, DNS and so on survive restarts.
    var cachePath: String?
    /// Directory with bundled `<tag>.srs` files used as `initial_path`.
    var ruleSetDirectory: String?
    /// Tags that actually exist in `ruleSetDirectory`.
    var bundledRuleSets: Set<String> = []
    /// Clash API on 127.0.0.1: the app reads live traffic from it.
    var clashPort = 9090
    var clashSecret = ""
    /// false → a local mixed (SOCKS/HTTP) inbound instead of TUN, for tests.
    var useTun = true
    var mixedPort = 2080
}

/// Builds the complete sing-box (1.14) config for one server + the user's routing options.
///
/// Layout:
/// - inbound `tun-in` (the Packet Tunnel), outbound / endpoint `proxy`, outbound `direct`;
/// - DNS: `dns-remote` (DoH / DoT / UDP through the proxy) and `dns-local` (system resolver)
///   chosen by the same rules as the traffic, so blocked domains never hit the ISP's resolver;
/// - route: sniff → DNS hijack → IP check → user rules → LAN → ads → preset → final.
enum SingBoxConfig {
    static let tunAddress4 = "172.19.0.1/30"
    static let tunAddress6 = "fdfe:dcba:9876::1/126"
    /// Always through the proxy: the app asks it for the exit IP.
    static let ipCheckHost = "speed.cloudflare.com"
    static let ipCheckURL = "https://speed.cloudflare.com/cdn-cgi/trace"

    static func build(server: Server, options: TunnelOptions, environment env: TunnelEnvironment) throws -> [String: Any] {
        let proxy = try SingBoxOutbound.make(server)
        var config: [String: Any] = [:]

        var log: [String: Any] = ["level": options.verboseLogs ? "info" : "warn", "timestamp": true, "disable_color": true]
        if let path = env.logPath { log["output"] = path }
        config["log"] = log

        var rules = Rules()
        rules.addUserRules(options.rules)
        if options.blockAds { rules.addAds() }
        rules.addPreset(options.routing)

        config["dns"] = [
            "servers": [remoteDNS(options, proxyType: proxy.type), ["type": "local", "tag": "dns-local"]],
            "rules": rules.dns,
            "final": rules.dnsFinal,
            "strategy": "ipv4_only",
            "reverse_mapping": true,
        ] as [String: Any]

        if env.useTun {
            config["inbounds"] = [[
                "type": "tun", "tag": "tun-in",
                "address": [tunAddress4, tunAddress6],
                "auto_route": true, "strict_route": true,
                // includeAllNetworks (kill switch) rules out the system / mixed stacks.
                "stack": options.killSwitch ? "gvisor" : "mixed",
            ] as [String: Any]]
        } else {
            config["inbounds"] = [["type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": env.mixedPort] as [String: Any]]
        }

        let direct: [String: Any] = ["type": "direct", "tag": "direct"]
        if proxy.isEndpoint {
            config["endpoints"] = [proxy.object]
            config["outbounds"] = [direct]
        } else {
            config["outbounds"] = [proxy.object, direct]
        }

        var routeRules: [[String: Any]] = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
            ["domain": [ipCheckHost], "outbound": SingBoxOutbound.tag],
        ]
        routeRules += rules.route
        var ruleSets: [[String: Any]] = []
        for source in rules.sources {
            var r: [String: Any] = ["type": "remote", "tag": source.tag, "format": "binary", "url": source.url, "update_interval": "1d"]
            if let dir = env.ruleSetDirectory, env.bundledRuleSets.contains(source.tag) {
                r["initial_path"] = (dir as NSString).appendingPathComponent("\(source.tag).srs")
            }
            ruleSets.append(r)
        }
        var route: [String: Any] = [
            "rules": routeRules,
            "final": rules.final,
            "auto_detect_interface": true,
            "default_domain_resolver": "dns-local",
        ]
        if !ruleSets.isEmpty {
            route["rule_set"] = ruleSets
            route["default_http_client"] = "via-proxy"
            config["http_clients"] = [["tag": "via-proxy", "detour": SingBoxOutbound.tag]]
        }
        config["route"] = route

        var experimental: [String: Any] = [
            "clash_api": ["external_controller": "127.0.0.1:\(env.clashPort)", "secret": env.clashSecret],
        ]
        if let cache = env.cachePath { experimental["cache_file"] = ["enabled": true, "path": cache] }
        config["experimental"] = experimental
        return config
    }

    static func json(server: Server, options: TunnelOptions, environment: TunnelEnvironment) throws -> String {
        let object = try build(server: server, options: options, environment: environment)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: DNS servers

    /// The resolver from Settings → DNS, always through the proxy. Presets use IP addresses with
    /// the TLS name set, so no bootstrap lookup through the (possibly filtered) ISP resolver.
    static func remoteDNS(_ o: TunnelOptions, proxyType: String) -> [String: Any] {
        var server: [String: Any]
        if o.dnsPreset == .custom {
            server = customDNS(o.customDNS, transport: o.dnsTransport)
        } else {
            let ip = o.dnsPreset.address
            switch o.dnsTransport {
            case .doh:
                let name = URL(string: o.dnsPreset.endpoint(.doh))?.host ?? ""
                server = ["type": "https", "server": ip, "tls": ["server_name": name]]
            case .dot:
                server = ["type": "tls", "server": ip, "tls": ["server_name": o.dnsPreset.endpoint(.dot)]]
            case .udp:
                server = ["type": "udp", "server": ip]
            }
        }
        // SSH can't carry UDP: plain DNS goes over TCP instead.
        if proxyType == "ssh", server["type"] as? String == "udp" { server["type"] = "tcp" }
        server["tag"] = "dns-remote"
        server["detour"] = SingBoxOutbound.tag
        return server
    }

    /// "1.1.1.1", "dns.example.com", "8.8.8.8:53", "https://dns.example.com/q", "tls://dns.example.com".
    static func customDNS(_ raw: String, transport: DNSTransport) -> [String: Any] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = "1.1.1.1" }
        var type: String
        switch transport {
        case .doh: type = "https"
        case .dot: type = "tls"
        case .udp: type = "udp"
        }
        if let r = text.range(of: "://") {
            switch text[..<r.lowerBound].lowercased() {
            case "https", "doh": type = "https"
            case "tls", "dot": type = "tls"
            case "quic", "doq": type = "quic"
            case "h3": type = "h3"
            case "tcp": type = "tcp"
            default: type = "udp"
            }
            text = String(text[r.upperBound...])
        }
        var path = ""
        if let slash = text.firstIndex(of: "/") {
            path = String(text[slash...])
            text = String(text[..<slash])
        }
        var host = text, port = 0
        let colons = text.filter { $0 == ":" }.count
        if text.hasPrefix("[") || colons == 1 { (host, port) = ShareLinkParser.splitHostPort(text) }
        var s: [String: Any] = ["type": type, "server": host]
        if port > 0 { s["server_port"] = port }
        if (type == "https" || type == "h3"), !path.isEmpty, path != "/dns-query" { s["path"] = path }
        if !SingBoxOutbound.isIP(host) { s["domain_resolver"] = "dns-local" }
        return s
    }

    // MARK: Rules

    /// Route + DNS rules collected together so both always agree.
    struct Rules {
        var route: [[String: Any]] = []
        var dns: [[String: Any]] = []
        var final = SingBoxOutbound.tag
        var dnsFinal = "dns-remote"
        private(set) var sources: [RuleSets.Source] = []

        mutating func use(_ list: [RuleSets.Source]) -> [String] {
            for s in list where !sources.contains(s) { sources.append(s) }
            return list.map(\.tag)
        }

        static func outbound(_ action: RouteRule.Action) -> [String: Any] {
            switch action {
            case .proxy: return ["outbound": SingBoxOutbound.tag]
            case .direct: return ["outbound": "direct"]
            case .block: return ["action": "reject"]
            }
        }

        static func dnsAction(_ action: RouteRule.Action) -> [String: Any] {
            switch action {
            case .proxy: return ["server": "dns-remote"]
            case .direct: return ["server": "dns-local"]
            case .block: return ["action": "predefined", "rcode": "NXDOMAIN"]
            }
        }

        /// The user's rules, in order. Several values in one rule: "a.com, b.com".
        mutating func addUserRules(_ list: [RouteRule]) {
            for rule in list {
                let values = ProxySpec.list(rule.value)
                guard !values.isEmpty else { continue }
                var match: [String: Any] = [:]
                var isDomain = true
                switch rule.kind {
                case .domain:
                    match["domain"] = values.map { $0.lowercased() }
                case .suffix:
                    match["domain_suffix"] = values.map { v -> String in
                        var s = v.lowercased()
                        if s.hasPrefix("*.") { s.removeFirst(2) }
                        while s.hasPrefix(".") { s.removeFirst() }
                        return s
                    }.filter { !$0.isEmpty }
                case .keyword:
                    match["domain_keyword"] = values.map { $0.lowercased() }
                case .ip:
                    match["ip_cidr"] = values.map(SingBoxOutbound.cidr)
                    isDomain = false
                case .geosite:
                    let sets = values.compactMap(RuleSets.geosite)
                    guard !sets.isEmpty else { continue }
                    match["rule_set"] = use(sets)
                case .geoip:
                    isDomain = false
                    if values.contains(where: { $0.lowercased() == "private" }) {
                        route.append(["ip_is_private": true].merging(Self.outbound(rule.action)) { a, _ in a })
                    }
                    let sets = values.compactMap(RuleSets.geoip)
                    guard !sets.isEmpty else { continue }
                    match["rule_set"] = use(sets)
                }
                if let list = match.values.first as? [String], list.isEmpty { continue }
                route.append(match.merging(Self.outbound(rule.action)) { a, _ in a })
                if isDomain { dns.append(match.merging(Self.dnsAction(rule.action)) { a, _ in a }) }
            }
            // LAN and link-local addresses never leave the device's network.
            route.append(["ip_is_private": true, "outbound": "direct"])
        }

        mutating func addAds() {
            let tags = use([RuleSets.ads])
            route.append(["rule_set": tags, "action": "reject"])
            dns.append(["rule_set": tags, "action": "predefined", "rcode": "NXDOMAIN"])
        }

        mutating func addPreset(_ preset: RoutingPreset) {
            switch preset {
            case .global:
                final = SingBoxOutbound.tag
                dnsFinal = "dns-remote"
            case .russia:
                addBlocked()
                route.append(["domain_suffix": RuleSets.ruZones, "outbound": "direct"])
                dns.append(["domain_suffix": RuleSets.ruZones, "server": "dns-local"])
                let domains = use(RuleSets.russianDomains)
                route.append(["rule_set": domains, "outbound": "direct"])
                dns.append(["rule_set": domains, "server": "dns-local"])
                route.append(["rule_set": use([RuleSets.russianIP]), "outbound": "direct"])
                final = SingBoxOutbound.tag
                dnsFinal = "dns-remote"
            case .blocked:
                addBlocked()
                final = "direct"
                dnsFinal = "dns-local"
            case .custom:
                final = "direct"
                dnsFinal = "dns-local"
            }
        }

        /// Services blocked in Russia → proxy; their domains are resolved through the proxy too.
        private mutating func addBlocked() {
            route.append(["rule_set": use(RuleSets.blocked), "outbound": SingBoxOutbound.tag])
            // DNS rules can't use sets with IP ranges (they'd turn into response filters).
            let domainOnly = RuleSets.blocked.filter { !$0.hasIP }.map(\.tag)
            dns.append(["rule_set": domainOnly, "server": "dns-remote"])
        }
    }
}
