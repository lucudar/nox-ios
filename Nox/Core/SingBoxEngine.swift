import Foundation
import NetworkExtension

/// The real tunnel: a VPN profile (NETunnelProviderManager) for the NoxTunnel extension, which
/// runs sing-box with the config this engine writes to the App Group container.
@MainActor
final class SingBoxEngine: TunnelEngine {
    let name = "sing-box"
    var onState: ((TunnelState) -> Void)?
    var api: CoreAPI? { CoreAPI(port: Self.clashPort, secret: secret) }

    /// Clash API port of the core (loopback only, secret-protected).
    static let clashPort = 19090

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private let secret: String

    /// The bundled extension's own ID: re-signing tools may rename bundle IDs.
    private let providerID: String = {
        if let plugins = Bundle.main.builtInPlugInsURL,
           let id = Bundle(url: plugins.appendingPathComponent("NoxTunnel.appex"))?.bundleIdentifier {
            return id
        }
        return (Bundle.main.bundleIdentifier ?? "com.example.nox") + ".tunnel"
    }()

    init() {
        let key = "nox.core.secret"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            secret = saved
        } else {
            secret = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            UserDefaults.standard.set(secret, forKey: key)
        }
    }

    // MARK: TunnelEngine

    func restore() async -> TunnelState {
        guard let manager = try? await loadManager() else { return .disconnected }
        observe(manager)
        return Self.state(manager.connection)
    }

    func start(_ server: Server, options: TunnelOptions) async throws {
        await OpenFluxKeys.prepare(server)
        let payload = try writeConfig(server, options)
        let manager = try await prepare(options, onDemand: options.autoConnect)
        AppGroup.clearError()
        AppGroup.truncateLog()
        if server.proto == .openflux {
            AppGroup.truncateLog(AppGroup.openFluxLogURL)
        } else {
            try? FileManager.default.removeItem(at: AppGroup.openFluxLogURL)
        }
        do {
            // The configs go with the request too: without a shared App Group the extension
            // can't read the files.
            try manager.connection.startVPNTunnel(options: payload.options)
        } catch {
            throw Self.describe(error)
        }
        let started = Date()
        var moving = false
        while true {
            try await Task.sleep(nanoseconds: 200_000_000)
            switch manager.connection.status {
            case .connected:
                return
            case .connecting, .reasserting:
                moving = true
            case .disconnected, .invalid:
                // Right after startVPNTunnel the status can still read "disconnected".
                if moving || Date().timeIntervalSince(started) > 4 {
                    throw TunnelError.core(await lastError() ?? TunnelError.stopped.localizedDescription)
                }
            default:
                break
            }
            if Date().timeIntervalSince(started) > 40 {
                manager.connection.stopVPNTunnel()
                throw TunnelError.timeout
            }
        }
    }

    func update(_ server: Server, options: TunnelOptions) async throws {
        await OpenFluxKeys.prepare(server)
        let payload = try writeConfig(server, options)
        guard let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected || session.status == .reasserting || session.status == .connecting else { return }
        let reply = try await Self.send(payload.message, to: session)
        if let reply, !reply.isEmpty {
            throw TunnelError.core(String(decoding: reply, as: UTF8.self))
        }
    }

    func updateProfile(_ options: TunnelOptions) async {
        guard (try? await loadManager()) != nil else { return }
        _ = try? await prepare(options, onDemand: options.autoConnect && isRunning)
    }

    func stop() async {
        guard let manager else { return }
        // Otherwise on-demand rules would bring the tunnel straight back.
        if manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            try? await manager.saveToPreferences()
        }
        manager.connection.stopVPNTunnel()
        for _ in 0..<60 {
            let status = manager.connection.status
            if status == .disconnected || status == .invalid { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func lastError() async -> String? {
        if let text = AppGroup.readError() { return Self.clean(text) }
        guard let manager else { return nil }
        do {
            try await manager.connection.fetchLastDisconnectError()
            return nil
        } catch {
            return Self.clean(Self.describe(error).localizedDescription)
        }
    }

    /// box.log / openflux.log. Without a shared App Group they are in the extension's container:
    /// the running extension sends their tail.
    func coreLog(openFlux: Bool) async -> String {
        let local = AppGroup.logTail(openFlux ? AppGroup.openFluxLogURL : nil)
        guard local.isEmpty, let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected || session.status == .reasserting else { return local }
        let request = openFlux ? ProviderRequest.openFluxLog : ProviderRequest.coreLog
        guard let reply = try? await Self.send(request, to: session, timeout: 5) else { return local }
        return String(decoding: reply, as: UTF8.self)
    }

    // MARK: Profile

    private var isRunning: Bool {
        guard let status = manager?.connection.status else { return false }
        return status == .connected || status == .connecting || status == .reasserting
    }

    private func loadManager() async throws -> NETunnelProviderManager? {
        if let manager { return manager }
        let all = try await NETunnelProviderManager.loadAllFromPreferences()
        let found = all.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID }
        if let found {
            manager = found
            observe(found)
        }
        return found
    }

    /// Creates or updates the VPN profile; saves only when something changed (the first save
    /// shows the system "Add VPN configuration" prompt).
    private func prepare(_ options: TunnelOptions, onDemand: Bool) async throws -> NETunnelProviderManager {
        let manager: NETunnelProviderManager
        do {
            manager = try await loadManager() ?? NETunnelProviderManager()
        } catch {
            throw Self.describe(error)
        }
        let existing = manager.protocolConfiguration as? NETunnelProviderProtocol
        let proto = existing ?? NETunnelProviderProtocol()
        var changed = existing == nil
        if proto.providerBundleIdentifier != providerID { proto.providerBundleIdentifier = providerID; changed = true }
        if proto.serverAddress != "sing-box" { proto.serverAddress = "sing-box"; changed = true }
        // Kill switch: everything goes through the tunnel, nothing leaks while it reconnects.
        if proto.includeAllNetworks != options.killSwitch { proto.includeAllNetworks = options.killSwitch; changed = true }
        if !proto.excludeLocalNetworks { proto.excludeLocalNetworks = true; changed = true }
        if proto.disconnectOnSleep { proto.disconnectOnSleep = false; changed = true }
        if manager.localizedDescription != "Nox" { manager.localizedDescription = "Nox"; changed = true }
        if !manager.isEnabled { manager.isEnabled = true; changed = true }
        if manager.isOnDemandEnabled != onDemand { manager.isOnDemandEnabled = onDemand; changed = true }
        if onDemand, manager.onDemandRules?.isEmpty ?? true {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            manager.onDemandRules = [rule]
            changed = true
        }
        manager.protocolConfiguration = proto
        if changed {
            do {
                try await manager.saveToPreferences()
                // A freshly saved profile must be reloaded before it can start.
                try await manager.loadFromPreferences()
            } catch {
                throw Self.describe(error)
            }
        }
        self.manager = manager
        observe(manager)
        return manager
    }

    private func observe(_ manager: NETunnelProviderManager) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: manager.connection,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let connection = self.manager?.connection else { return }
                self.onState?(Self.state(connection))
            }
        }
    }

    private static func state(_ connection: NEVPNConnection) -> TunnelState {
        switch connection.status {
        case .connected: return .connected(since: connection.connectedDate ?? Date())
        case .connecting: return .connecting
        case .reasserting: return .reasserting
        case .disconnecting: return .disconnecting
        default: return .disconnected
        }
    }

    // MARK: Config

    @discardableResult
    private func writeConfig(_ server: Server, _ options: TunnelOptions) throws -> TunnelPayload {
        var environment = TunnelEnvironment()
        environment.logPath = AppGroup.logURL.path
        environment.cachePath = AppGroup.cacheURL.path
        environment.ruleSetDirectory = AppGroup.ruleSetsURL.path
        environment.bundledRuleSets = Self.installRuleSets()
        environment.clashPort = Self.clashPort
        environment.clashSecret = secret
        environment.openFluxPassword = secret
        environment.openFluxLogPath = AppGroup.openFluxLogURL.path
        let json = try SingBoxConfig.json(server: server, options: options, environment: environment)
        // OpenFlux servers: the extension starts the OpenFlux core from openflux.json first.
        let flux = try SingBoxConfig.openFluxJSON(server: server, options: options, environment: environment)
        let payload = TunnelPayload(config: json, openFlux: flux)
        // Stored for on-demand starts (iOS starts the extension without the app).
        try payload.store()
        return payload
    }

    /// The rule-sets shipped in the app go to the container (fresh copies once per build), so the
    /// first start works before any download.
    private static func installRuleSets() -> Set<String> {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let key = "nox.rulesets.build"
        let fresh = UserDefaults.standard.string(forKey: key) != build
        let tags = BundledRuleSets.install(from: .main, refresh: fresh)
        if fresh { UserDefaults.standard.set(build, forKey: key) }
        return tags
    }

    // MARK: Helpers

    /// Provider message with a timeout (the reply never comes if the extension died).
    private static func send(_ message: Data, to session: NETunnelProviderSession, timeout: Double = 25) async throws -> Data? {
        let gate = OnceGate()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            do {
                try session.sendProviderMessage(message) { reply in
                    if gate.claim() { continuation.resume(returning: reply) }
                }
            } catch {
                if gate.claim() { continuation.resume(throwing: describe(error)) }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if gate.claim() { continuation.resume(throwing: TunnelError.timeout) }
            }
        }
    }

    /// NetworkExtension errors in plain words.
    private static func describe(_ error: Error) -> TunnelError {
        let ns = error as NSError
        // The extension's errors: the text is in userInfo and, in case iOS dropped it, the domain.
        if ns.domain.hasPrefix("Nox: ") {
            return .core(ns.userInfo[NSLocalizedDescriptionKey] as? String ?? String(ns.domain.dropFirst(5)))
        }
        if ns.domain == NEVPNErrorDomain {
            switch ns.code {
            case 5:
                return .core(L10n.t("Нет доступа к настройкам VPN: разрешите добавить конфигурацию VPN. Если запрос не появляется, у сборки нет права Network Extension (нужна подпись с платным Apple Developer).",
                                    "No access to VPN settings: allow adding the VPN configuration. If iOS doesn't ask, the build lacks the Network Extension entitlement (needs a paid Apple Developer signature)."))
            case 2:
                return .core(L10n.t("VPN-профиль Nox выключен в настройках iOS", "The Nox VPN profile is disabled in iOS Settings"))
            case 1, 4, 6:
                return .core(L10n.t("VPN-профиль повреждён — попробуйте ещё раз", "The VPN profile is invalid — try again"))
            default:
                break
            }
        }
        return .core(ns.localizedDescription)
    }

    /// sing-box errors are long chains ("start service: start inbound/tun[tun-in]: …"): keep the tail.
    private static func clean(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).last.map(String.init) ?? text
        return line.count > 300 ? String(line.suffix(300)) : line
    }
}
