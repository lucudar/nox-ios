import Foundation
import Libbox
import NetworkExtension

/// The Packet Tunnel: runs sing-box (libbox) with the config the app sends with the start request
/// (also stored as `AppGroup.configURL` for on-demand starts), plus the OpenFlux client for
/// OpenFlux servers (`OpenFluxCore`). The app hot-reloads it with a `TunnelPayload` message when
/// the server or routing changes, so the tunnel never drops.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: LibboxCommandServer?
    private lazy var platform = PlatformInterface(self)

    override func startTunnel(options: [String: NSObject]?) async throws {
        AppGroup.clearError()
        do {
            let sent = TunnelPayload(options: options)
            let payload = try Self.payload(sent)
            if let sent, payload.container != sent.container {
                // The app clears the logs in its own container; these are only here.
                AppGroup.truncateLog()
                AppGroup.truncateLog(AppGroup.openFluxLogURL)
            }
            let server = try makeCommandServer()
            try OpenFluxCore.apply(payload.openFlux, waitMillis: 25_000)
            try server.startOrReloadService(payload.config, options: LibboxOverrideOptions())
        } catch {
            let message = Self.describe(error)
            AppGroup.writeError(message)
            shutdown()
            throw Self.failure(message)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        defer { OpenFluxCore.stop() }
        guard let server = commandServer else { return }
        try? server.closeService()
        platform.reset()
        try? await Task.sleep(nanoseconds: 100_000_000)
        server.close()
        commandServer = nil
    }

    /// A `TunnelPayload` (or the older "reload": re-read the files) restarts sing-box inside the
    /// running tunnel; `ProviderRequest`s read the core logs.
    override func handleAppMessage(_ messageData: Data) async -> Data? {
        if messageData == ProviderRequest.coreLog { return Data(AppGroup.logTail().utf8) }
        if messageData == ProviderRequest.openFluxLog { return Data(AppGroup.logTail(AppGroup.openFluxLogURL).utf8) }
        let sent = TunnelPayload(message: messageData)
        guard sent != nil || messageData == AppGroup.reloadMessage else { return nil }
        do {
            try reload(sent)
            return nil
        } catch {
            let message = Self.describe(error)
            AppGroup.writeError(message)
            // The old instance is already gone: drop the tunnel instead of black-holing traffic.
            cancelTunnelWithError(Self.failure(message))
            return Data(message.utf8)
        }
    }

    override func sleep() async {
        commandServer?.pause()
    }

    override func wake() {
        commandServer?.wake()
    }

    // MARK: Core

    /// New configs from the app, or the stored ones (a reload the core asked for itself).
    func reload(_ sent: TunnelPayload? = nil) throws {
        guard let server = commandServer else { throw TunnelFailure("sing-box is not running") }
        reasserting = true
        defer { reasserting = false }
        AppGroup.clearError()
        let payload = try Self.payload(sent)
        try OpenFluxCore.apply(payload.openFlux, waitMillis: 15_000)
        try server.startOrReloadService(payload.config, options: LibboxOverrideOptions())
    }

    /// The configs to run. Sent by the app: their paths are moved into this process's container if
    /// the app's isn't shared with it, and a copy is kept there for on-demand starts. Not sent: the
    /// stored files.
    private static func payload(_ sent: TunnelPayload?) throws -> TunnelPayload {
        let payload: TunnelPayload
        if let sent {
            payload = sent.relocated()
            if payload.container != sent.container { try? payload.store() }
        } else {
            do {
                payload = try TunnelPayload.stored()
            } catch {
                guard !AppGroup.isShared else { throw TunnelFailure("config.json: \(error.localizedDescription)") }
                let group = AppGroup.configuredIdentifier
                throw TunnelFailure(Locale.preferredLanguages.first?.hasPrefix("ru") == true
                    ? "Нет конфигурации: туннелю недоступна App Group \(group) (сборку переподписали без неё?). Подключитесь из приложения Nox."
                    : "No configuration: the App Group \(group) isn't available to the tunnel (re-signed without it?). Connect from the Nox app.")
            }
        }
        // Normally the app has put them into the shared container already.
        BundledRuleSets.install(from: BundledRuleSets.containingApp)
        return payload
    }

    private func makeCommandServer() throws -> LibboxCommandServer {
        if let commandServer { return commandServer }
        let options = LibboxSetupOptions()
        options.basePath = AppGroup.container.path
        options.workingPath = AppGroup.workingURL.path
        options.tempPath = AppGroup.tempURL.path
        options.logMaxLines = 3000
        options.crashReportSource = "NetworkExtension"
        // Network Extensions are killed above ~50 MB: let sing-box shed connections first.
        options.oomKillerEnabled = true
        options.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        options.appMarketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var error: NSError?
        _ = LibboxSetup(options, &error)
        if let error { throw TunnelFailure("libbox setup: \(error.localizedDescription)") }
        let server = LibboxNewCommandServer(platform, platform, &error)
        if let error { throw TunnelFailure("libbox: \(error.localizedDescription)") }
        guard let server else { throw TunnelFailure("libbox: no command server") }
        commandServer = server
        return server
    }

    private func shutdown() {
        OpenFluxCore.stop()
        guard let server = commandServer else { return }
        try? server.closeService()
        platform.reset()
        server.close()
        commandServer = nil
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? TunnelFailure { return failure.message }
        return (error as NSError).localizedDescription
    }

    /// What iOS hands back to the app (`fetchLastDisconnectError`). A Swift error arrives as
    /// "NoxTunnel.TunnelFailure error 1": its text is computed on the fly and doesn't survive the
    /// trip. A plain NSError carries the text in userInfo, and the domain repeats it in case iOS
    /// drops userInfo (the app reads it back, see `SingBoxEngine.describe`).
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Nox: " + message.prefix(400), code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

struct TunnelFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
