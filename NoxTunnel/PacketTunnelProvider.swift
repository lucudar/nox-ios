import Foundation
import Libbox
import NetworkExtension

/// The Packet Tunnel: runs sing-box (libbox) with the config the app wrote to the App Group
/// container (`AppGroup.configURL`), plus the OpenFlux client for OpenFlux servers
/// (`OpenFluxCore`). The app hot-reloads it with `AppGroup.reloadMessage` when the server or
/// routing changes, so the tunnel never drops.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: LibboxCommandServer?
    private lazy var platform = PlatformInterface(self)

    override func startTunnel(options: [String: NSObject]?) async throws {
        AppGroup.clearError()
        do {
            let config = try Self.readConfig()
            let server = try makeCommandServer()
            try OpenFluxCore.apply(waitMillis: 25_000)
            try server.startOrReloadService(config, options: LibboxOverrideOptions())
        } catch {
            let message = Self.describe(error)
            AppGroup.writeError(message)
            shutdown()
            throw TunnelFailure(message)
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

    /// "reload": re-read config.json and restart sing-box inside the running tunnel.
    override func handleAppMessage(_ messageData: Data) async -> Data? {
        guard messageData == AppGroup.reloadMessage else { return nil }
        do {
            try reload()
            return nil
        } catch {
            let message = Self.describe(error)
            AppGroup.writeError(message)
            // The old instance is already gone: drop the tunnel instead of black-holing traffic.
            cancelTunnelWithError(TunnelFailure(message))
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

    func reload() throws {
        guard let server = commandServer else { throw TunnelFailure("sing-box is not running") }
        reasserting = true
        defer { reasserting = false }
        AppGroup.clearError()
        let config = try Self.readConfig()
        try OpenFluxCore.apply(waitMillis: 15_000)
        try server.startOrReloadService(config, options: LibboxOverrideOptions())
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

    private static func readConfig() throws -> String {
        do {
            return try String(contentsOf: AppGroup.configURL, encoding: .utf8)
        } catch {
            throw TunnelFailure("config.json: \(error.localizedDescription)")
        }
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? TunnelFailure { return failure.message }
        return (error as NSError).localizedDescription
    }
}

struct TunnelFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
