import Foundation

/// What the system reports about the tunnel.
enum TunnelState: Equatable {
    case disconnected
    case connecting
    case connected(since: Date)
    /// The core is reloading inside a live tunnel (server / routing change).
    case reasserting
    case disconnecting
}

/// Tunnel backend. On a device: `SingBoxEngine` (the NoxTunnel Packet Tunnel extension running
/// sing-box). The simulator has no Network Extensions, so it gets `DemoTunnelEngine`.
@MainActor
protocol TunnelEngine: AnyObject {
    var name: String { get }
    /// State changes, including ones the app didn't start (iOS Settings, on-demand, a crash).
    var onState: ((TunnelState) -> Void)? { get set }
    /// Clash API of the running core (live speed, traffic, latency); nil → no live data.
    var api: CoreAPI? { get }
    /// Looks for a tunnel that is already running (app relaunch).
    func restore() async -> TunnelState
    func start(_ server: Server, options: TunnelOptions) async throws
    /// New config for the running core (server, routing, DNS…) without dropping the tunnel.
    func update(_ server: Server, options: TunnelOptions) async throws
    /// VPN profile only (auto-connect on demand).
    func updateProfile(_ options: TunnelOptions) async
    func stop() async
    /// Why the tunnel stopped or failed to start, if known.
    func lastError() async -> String?
}

enum TunnelError: LocalizedError {
    case timeout
    case stopped
    case core(String)

    var errorDescription: String? {
        switch self {
        case .timeout: return L10n.t("Сервер не ответил за 40 секунд", "The server didn't respond within 40 seconds")
        case .stopped: return L10n.t("Туннель остановился", "The tunnel stopped")
        case .core(let text): return text
        }
    }
}

#if targetEnvironment(simulator)
/// The simulator can't run Packet Tunnel extensions: this engine builds the real sing-box
/// config (so bad servers still fail) and pretends to connect, to exercise the UI.
@MainActor
final class DemoTunnelEngine: TunnelEngine {
    let name = "simulator (no tunnel)"
    var onState: ((TunnelState) -> Void)?
    var api: CoreAPI? { nil }

    func restore() async -> TunnelState { .disconnected }

    func start(_ server: Server, options: TunnelOptions) async throws {
        _ = try SingBoxConfig.build(server: server, options: options, environment: TunnelEnvironment())
        onState?(.connecting)
        try await Task.sleep(nanoseconds: 900_000_000)
        onState?(.connected(since: Date()))
    }

    func update(_ server: Server, options: TunnelOptions) async throws {
        _ = try SingBoxConfig.build(server: server, options: options, environment: TunnelEnvironment())
    }

    func updateProfile(_ options: TunnelOptions) async {}

    func stop() async {
        onState?(.disconnecting)
        try? await Task.sleep(nanoseconds: 300_000_000)
        onState?(.disconnected)
    }

    func lastError() async -> String? { nil }
}
#endif
