import Foundation

/// The configs the app hands the extension: sing-box's config.json and, for OpenFlux servers,
/// openflux.json. They go with the start request and the reload message, not only through the
/// App Group files: a re-signed build may have no shared container, and then the files the app
/// writes never reach the extension.
struct TunnelPayload: Equatable {
    var config: String
    var openFlux: String?
    /// The container the paths inside the configs point to (log, cache, rule-sets).
    var container: String

    private enum Key {
        static let config = "nox.config"
        static let openFlux = "nox.openflux"
        static let container = "nox.container"
    }

    init(config: String, openFlux: String?, container: String = AppGroup.container.path) {
        self.config = config
        self.openFlux = openFlux.flatMap { $0.isEmpty ? nil : $0 }
        self.container = container
    }

    // MARK: Start request

    /// `startVPNTunnel(options:)`.
    var options: [String: NSObject] {
        var out: [String: NSObject] = [Key.config: config as NSString, Key.container: container as NSString]
        if let openFlux { out[Key.openFlux] = openFlux as NSString }
        return out
    }

    /// nil: started without the configs (on demand, from iOS Settings) — use the stored files.
    init?(options: [String: NSObject]?) {
        guard let config = options?[Key.config] as? String, !config.isEmpty else { return nil }
        self.init(config: config, openFlux: options?[Key.openFlux] as? String,
                  container: options?[Key.container] as? String ?? AppGroup.container.path)
    }

    // MARK: Reload message

    var message: Data {
        var object: [String: String] = [Key.config: config, Key.container: container]
        if let openFlux { object[Key.openFlux] = openFlux }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    init?(message: Data) {
        guard message.first == UInt8(ascii: "{"),
              let object = try? JSONSerialization.jsonObject(with: message) as? [String: String],
              let config = object[Key.config], !config.isEmpty else { return nil }
        self.init(config: config, openFlux: object[Key.openFlux], container: object[Key.container] ?? AppGroup.container.path)
    }

    // MARK: Files

    /// config.json / openflux.json of this process's container.
    static func stored() throws -> TunnelPayload {
        let config = try String(contentsOf: AppGroup.configURL, encoding: .utf8)
        let openFlux = try? String(contentsOf: AppGroup.openFluxURL, encoding: .utf8)
        return TunnelPayload(config: config, openFlux: openFlux)
    }

    func store() throws {
        if let openFlux {
            try Data(openFlux.utf8).write(to: AppGroup.openFluxURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: AppGroup.openFluxURL)
        }
        try Data(config.utf8).write(to: AppGroup.configURL, options: .atomic)
    }

    /// The same configs with the app's container paths moved into this process's container, for
    /// when the two don't share one (the extension can't reach the app's sandbox).
    func relocated(to here: String = AppGroup.container.path) -> TunnelPayload {
        guard !container.isEmpty, container != here else { return self }
        return TunnelPayload(config: config.replacingOccurrences(of: container, with: here),
                             openFlux: openFlux?.replacingOccurrences(of: container, with: here),
                             container: here)
    }
}

/// Rule-sets shipped in the app (`Resources/RuleSets/*.srs`), copied into the container: the
/// config uses them as `initial_path`, so the first start doesn't have to download them.
enum BundledRuleSets {
    /// Copies the missing ones (all of them with `refresh`, after an update) and returns the tags
    /// that are in place.
    @discardableResult
    static func install(from bundle: Bundle, refresh: Bool = false) -> Set<String> {
        let fm = FileManager.default
        let files = (bundle.paths(forResourcesOfType: "srs", inDirectory: "RuleSets")
            + bundle.paths(forResourcesOfType: "srs", inDirectory: nil)).map { URL(fileURLWithPath: $0) }
        let directory = AppGroup.ruleSetsURL
        var tags = Set<String>()
        for url in files {
            let target = directory.appendingPathComponent(url.lastPathComponent)
            if refresh || size(target) != size(url) {
                try? fm.removeItem(at: target)
                guard (try? fm.copyItem(at: url, to: target)) != nil else { continue }
            }
            tags.insert(url.deletingPathExtension().lastPathComponent)
        }
        return tags
    }

    /// The app bundle seen from the extension (Nox.app/PlugIns/NoxTunnel.appex).
    static var containingApp: Bundle {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return .main }
        return Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent()) ?? .main
    }

    private static func size(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }
}

/// Small requests the app sends the running extension besides reloads.
enum ProviderRequest {
    /// Reply: the tail of box.log / openflux.log (they live in the extension's container when
    /// the App Group isn't shared).
    static let coreLog = Data("log".utf8)
    static let openFluxLog = Data("log:openflux".utf8)
}
