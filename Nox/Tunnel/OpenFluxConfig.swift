import Foundation

/// An OpenFlux connection (github.com/lucudar/OpenFlux): IP packets travel inside a Russian
/// service — Yandex documents, Mail.ru, MAX calls, Cups.online rooms — to the user's own exit
/// node. The tunnel extension runs the OpenFlux client (core/noxflux) as a local SOCKS5 proxy
/// and sing-box sends its "proxy" traffic there, so routing, DNS and rules work as usual.
///
/// Stored in `Server.link` as `openflux://yandex?url=…&url=…&codec=batched&key=…#Name`
/// (MAX: `openflux://oneme?token=…&uid=…`). The exit node must use the same documents in the
/// same order, the same codec and the same key.
struct OpenFluxProfile: Equatable {
    enum Transport: String, CaseIterable, Identifiable {
        case yandex, vyandex, mailru, oneme, cupsonline

        var id: String { rawValue }

        var title: String {
            switch self {
            case .yandex: return "Yandex Docs"
            case .vyandex: return "Yandex Volga"
            case .mailru: return "Mail.ru"
            case .oneme: return "MAX"
            case .cupsonline: return "Cups.online"
            }
        }

        /// Shown as the server address when the documents don't name a host.
        var defaultHost: String {
            switch self {
            case .yandex: return "disk.yandex.ru"
            case .vyandex: return "volga.yandex.ru"
            case .mailru: return "cloud.mail.ru"
            case .oneme: return "ws-api.oneme.ru"
            case .cupsonline: return "interview.cups.online"
            }
        }

        /// Everything but MAX works over documents / rooms (`--url` on the exit).
        var usesDocuments: Bool { self != .oneme }

        /// Several documents become parallel channels.
        var allowsSeveral: Bool { self == .yandex || self == .vyandex || self == .mailru }

        var documentPrompt: String {
            switch self {
            case .yandex, .vyandex: return "https://disk.yandex.ru/i/…"
            case .mailru: return "https://cloud.mail.ru/public/…"
            case .cupsonline: return "https://interview.cups.online/?rooms=…"
            case .oneme: return ""
            }
        }

        static func named(_ raw: String) -> Transport? {
            switch raw.lowercased().filter({ $0.isLetter || $0.isNumber }) {
            case "yandex", "yandexdocs", "yadocs", "docs", "ya": return .yandex
            case "vyandex", "volga", "yandexvolga": return .vyandex
            case "mailru", "mail", "mailrudocs", "cloudmailru": return .mailru
            case "oneme", "max", "maxmessenger": return .oneme
            case "cupsonline", "cups": return .cupsonline
            default: return nil
            }
        }

        /// The service a document link belongs to.
        static func guess(_ document: String) -> Transport? {
            let d = document.lowercased()
            if d.contains("mail.ru") { return .mailru }
            if d.contains("cups.online") || d.contains("rooms=") { return .cupsonline }
            if d.contains("volga.yandex") { return .vyandex }
            if d.contains("yandex.") || d.contains("yadi.sk") { return .yandex }
            return nil
        }
    }

    /// Must match the exit's --codec. batched (zstd + coalescing) is OpenFlux's default.
    enum Codec: String, CaseIterable, Identifiable {
        case batched, legacy
        var id: String { rawValue }
    }

    /// SOCKS5 user of the local OpenFlux port (the password is per install, see TunnelEnvironment).
    static let socksUser = "nox"
    /// OpenFlux's --url default, the key context of exits started without --url.
    static let defaultKeyContext = "http://#"

    var transport: Transport = .yandex
    var documents: [String] = []
    var maxToken = ""
    var maxUID = ""
    var codec: Codec = .batched
    /// Shared secret: the contents of the exit's --encryption-key-file. Empty → none.
    var key = ""
    /// KDF context override. Empty → what the exit uses by default (`resolvedKeyContext`).
    var keyContext = ""

    init(transport: Transport = .yandex) { self.transport = transport }

    // MARK: Derived values

    /// The secret as OpenFlux reads it (the key file is trimmed).
    var secret: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The exit's --url string: the documents joined by commas, "http://#" without --url
    /// (MAX, and Cups.online, whose exit creates the rooms itself).
    var resolvedKeyContext: String {
        let custom = keyContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        if transport.usesDocuments, transport != .cupsonline, !documents.isEmpty { return documents.joined(separator: ",") }
        return Self.defaultKeyContext
    }

    /// Host of the first document (what the traffic actually reaches), else the service's.
    var serviceHost: String {
        if transport.usesDocuments, let first = documents.first, let r = first.range(of: "://") {
            let host = ShareLinkParser.splitHostPort(String(first[r.upperBound...])).0
            if !host.isEmpty, !host.contains("@") { return host.lowercased() }
        }
        return transport.defaultHost
    }

    /// What's missing or wrong, in plain words. nil → ready to connect.
    var problem: String? {
        if transport.usesDocuments {
            if documents.isEmpty {
                return transport == .cupsonline
                    ? L10n.t("нужен список комнат, который напечатал выходной узел", "the room list printed by the exit node is missing")
                    : L10n.t("нужна ссылка на документ", "a document link is missing")
            }
            if transport == .yandex || transport == .vyandex,
               let bad = documents.first(where: { !$0.lowercased().hasPrefix("http://") && !$0.lowercased().hasPrefix("https://") }) {
                return L10n.t("«\(bad)» — не ссылка на документ", "“\(bad)” isn't a document link")
            }
        } else {
            if maxToken.isEmpty { return L10n.t("нужен токен MAX", "the MAX token is missing") }
            if Int64(maxUID) == nil { return L10n.t("ID пользователя MAX — это число", "the MAX user ID must be a number") }
        }
        if !secret.isEmpty, secret.utf8.count < 16 {
            return L10n.t("ключ шифрования — минимум 16 символов", "the encryption key needs at least 16 characters")
        }
        return nil
    }

    /// The exit node command that matches this profile (shown in the editor).
    var exitCommand: String {
        var parts = ["openflux --role=exit --mode=l4 --transport=\(transport.rawValue)"]
        switch transport {
        case .oneme: parts.append("--maxToken=\"…\"")
        case .cupsonline: break
        default: parts.append("--url=\"\(documents.isEmpty ? "…" : documents.joined(separator: ","))\"")
        }
        if codec == .legacy { parts.append("--codec=legacy") }
        if !secret.isEmpty { parts.append("--encryption-key-file=key.txt") }
        return parts.joined(separator: " ")
    }

    // MARK: Link

    func link(name: String = "") -> String {
        var q: [(String, String)] = []
        if transport.usesDocuments {
            q += documents.map { ("url", $0) }
        } else {
            q += [("token", maxToken), ("uid", maxUID)]
        }
        q.append(("codec", codec.rawValue))
        if !key.isEmpty { q.append(("key", key)) }
        if !keyContext.trimmed.isEmpty { q.append(("ctx", keyContext.trimmed)) }
        let query = q.filter { !$0.1.isEmpty }.map { "\($0.0)=\($0.1.urlEncoded)" }.joined(separator: "&")
        let n = name.trimmed
        return "openflux://\(transport.rawValue)?\(query)" + (n.isEmpty ? "" : "#" + n.urlEncoded)
    }

    /// `openflux://…` (also flux:// and ofx://). Old 0.6 links kept the raw config in `config=`.
    init?(link raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = text.range(of: "://"), ShareLinkParser.schemes[text[..<r.lowerBound].lowercased()] == .openflux else { return nil }
        var rest = String(text[r.upperBound...])
        if let hash = rest.firstIndex(of: "#") { rest = String(rest[..<hash]) }
        var authority = rest, query = ""
        if let mark = rest.firstIndex(of: "?") {
            authority = String(rest[..<mark])
            query = String(rest[rest.index(after: mark)...])
        }
        let pairs = Self.pairs(query)
        func value(_ keys: String...) -> String? { pairs.last { keys.contains($0.0) }?.1 }

        if let config = value("config"), let data = Base64.decode(config) {
            let inner = String(decoding: data, as: UTF8.self)
            if let p = Self(text: inner) { self = p; return }
        }
        authority = authority.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let slash = authority.firstIndex(of: "/") { authority = String(authority[..<slash]) }
        let named = value("transport", "type", "t").flatMap(Transport.named) ?? Transport.named(authority)
        let documents = pairs.filter { ["url", "urls", "doc", "docs", "document", "u"].contains($0.0) }.flatMap { Self.split($0.1) }
        guard let transport = named ?? (authority.isEmpty ? documents.first.flatMap(Transport.guess) ?? .yandex : nil) else { return nil }
        self.init(transport: transport)
        self.documents = documents
        maxToken = (value("token", "maxtoken", "max_token") ?? "").trimmed
        maxUID = (value("uid", "maxuid", "max_uid", "user") ?? "").trimmed
        codec = Codec(rawValue: (value("codec", "c") ?? "").lowercased()) ?? (value("legacy") == "1" ? .legacy : .batched)
        key = value("key", "secret", "encryption_key") ?? ""
        keyContext = value("ctx", "context", "key_context", "keycontext") ?? ""
    }

    /// Upstream OpenFlux iOS profiles and Nox's own core config: {"transport": "yandex",
    /// "urls": […], "maxToken": …, "maxUid": …, "codec": …, "key": …}.
    init?(json o: [String: Any]) {
        let str = ShareLinkParser.str
        let documents = (ProxySpec.strings(o["urls"]) + ProxySpec.strings(o["url"]) + ProxySpec.strings(o["documents"])).flatMap(Self.split)
        let name = str(o["transport"])
        guard let transport = Transport.named(name) ?? (name.isEmpty ? documents.first.flatMap(Transport.guess) : nil) else { return nil }
        self.init(transport: transport)
        self.documents = documents
        maxToken = str(o["maxToken"] ?? o["max_token"] ?? o["token"]).trimmed
        maxUID = str(o["maxUid"] ?? o["max_uid"] ?? o["uid"]).trimmed
        codec = Codec(rawValue: str(o["codec"]).lowercased()) ?? ((o["legacy"] as? Bool) == true ? .legacy : .batched)
        key = str(o["key"] ?? o["encryption_key"] ?? o["secret"])
        keyContext = str(o["key_context"] ?? o["keyContext"])
    }

    /// Anything pasted into the editor: a link, a JSON profile, an `openflux …` command line
    /// or bare document links.
    init?(text raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = Self(link: text) { self = p; return }
        if text.hasPrefix("{"), let data = text.data(using: .utf8),
           let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let p = Self(json: o) {
            self = p
            return
        }
        if text.contains("--") {
            var flags: [String: String] = [:]
            let words = Self.shellWords(text)
            var i = 0
            while i < words.count {
                let word = words[i]
                i += 1
                guard word.hasPrefix("-") else { continue }
                let body = word.drop { $0 == "-" }
                if let eq = body.firstIndex(of: "=") {
                    flags[body[..<eq].lowercased()] = String(body[body.index(after: eq)...])
                } else if i < words.count, !words[i].hasPrefix("-") {
                    flags[body.lowercased()] = words[i]
                    i += 1
                }
            }
            let documents = Self.split(flags["url"] ?? flags["u"] ?? "")
            if let name = flags["transport"] ?? flags["t"], let transport = Transport.named(name) {
                self.init(transport: transport)
            } else if let guessed = documents.first.flatMap(Transport.guess) {
                self.init(transport: guessed)
            } else {
                return nil
            }
            self.documents = documents
            maxToken = flags["maxtoken"] ?? ""
            maxUID = flags["maxuid"] ?? ""
            codec = Codec(rawValue: (flags["codec"] ?? flags["c"] ?? "").lowercased()) ?? .batched
            return
        }
        let documents = Self.split(text)
        guard let first = documents.first, first.contains("://"), let transport = Transport.guess(first) else { return nil }
        self.init(transport: transport)
        self.documents = documents
    }

    // MARK: Server and core config

    func server(name: String) -> Server {
        var s = Server()
        s.proto = .openflux
        s.variant = transport.title
        s.name = ShareLinkParser.cleanName(name)
        s.link = link(name: name)
        // The location is the exit node's, unknown here: only the name can tell it.
        ShareLinkParser.finish(&s, hint: name)
        s.host = serviceHost
        s.port = 443
        return s
    }

    /// openflux.json for the tunnel extension (see core/noxflux/noxflux.go).
    func coreConfig(port: Int, password: String, dns: String, logPath: String?, verbose: Bool) -> [String: Any] {
        var o: [String: Any] = [
            "transport": transport.rawValue,
            "codec": codec.rawValue,
            "listen": "127.0.0.1:\(port)",
            "username": Self.socksUser,
            "password": password,
            "dns": dns,
            "verbose": verbose,
            // For the extension's own error messages.
            "lang": L10n.lang.rawValue,
            "service": transport.title,
        ]
        if transport.usesDocuments {
            o["urls"] = documents
        } else {
            o["max_token"] = maxToken
            o["max_uid"] = maxUID
        }
        if !secret.isEmpty {
            if let master = OpenFluxKeys.shared.master(secret: secret, context: resolvedKeyContext) {
                o["master_key"] = master
            } else {
                o["key"] = secret
                o["key_context"] = resolvedKeyContext
            }
        }
        if let logPath { o["log_path"] = logPath }
        return o
    }

    // MARK: Parsing helpers

    /// Documents separated by commas, spaces or new lines (OpenFlux's splitDocURLs).
    static func split(_ text: String) -> [String] {
        text.split { $0 == "," || $0 == ";" || $0.isWhitespace }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>")) }
            .filter { !$0.isEmpty }
    }

    /// Query pairs in order, repeated keys kept (several url=…).
    static func pairs(_ query: String) -> [(String, String)] {
        query.split(separator: "&").compactMap { pair in
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let k = kv.first, !k.isEmpty else { return nil }
            let v = kv.count > 1 ? kv[1] : ""
            return ((k.removingPercentEncoding ?? k).lowercased(), v.removingPercentEncoding ?? v)
        }
    }

    /// Splits a command line, honouring "double" and 'single' quotes.
    static func shellWords(_ text: String) -> [String] {
        var words: [String] = [], current = "", quote: Character?
        for ch in text {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch.isWhitespace || ch == "\\" {
                if !current.isEmpty { words.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}

/// OpenFlux master keys: scrypt with 32 MB of memory runs in the app, never in the 50 MB
/// tunnel extension, which only receives the result (`master_key`). Cached per secret + context.
final class OpenFluxKeys: @unchecked Sendable {
    static let shared = OpenFluxKeys()

    private let lock = NSLock()
    private var cache: [String: String] = [:]

    /// Hex master key, derived on the calling thread when it isn't cached yet.
    func master(secret: String, context: String) -> String? {
        let id = secret + "\u{0}" + context
        lock.lock()
        let hit = cache[id]
        lock.unlock()
        if let hit { return hit }
        let salt = Hash256.hash(Array("OpenFlux encrypted transport v1\u{0}".utf8) + Array(context.utf8))
        guard let key = Scrypt.derive(password: Array(secret.utf8), salt: salt, n: 32768, r: 8, p: 1, length: 32) else { return nil }
        let hex = key.map { String(format: "%02x", $0) }.joined()
        lock.lock()
        cache[id] = hex
        lock.unlock()
        return hex
    }

    /// Derives the key of an OpenFlux server in the background, before the config is written.
    static func prepare(_ server: Server) async {
        guard server.proto == .openflux, let profile = OpenFluxProfile(link: server.link), !profile.secret.isEmpty else { return }
        let secret = profile.secret, context = profile.resolvedKeyContext
        await Task.detached(priority: .userInitiated) { _ = shared.master(secret: secret, context: context) }.value
    }
}
