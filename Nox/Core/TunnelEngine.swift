import Foundation

/// Tunnel backend. `DemoTunnelEngine` simulates a connection so the whole app works without
/// the Network Extension entitlement; a real engine starts the Packet Tunnel extension
/// (NETunnelProviderManager) that runs sing-box with the selected server's config.
@MainActor
protocol TunnelEngine: AnyObject {
    var name: String { get }
    func start(_ server: Server, options: TunnelOptions, log: @escaping (LogLine.Level, String) -> Void) async throws
    func stop() async
}

enum TunnelError: LocalizedError {
    case badConfig

    var errorDescription: String? {
        switch self {
        case .badConfig: return L10n.t("В конфиге нет адреса сервера", "The config has no server address")
        }
    }
}

/// Simulates a handshake so the whole UI (animation, timer, logs, stats) can be used
/// without the Network Extension entitlement.
@MainActor
final class DemoTunnelEngine: TunnelEngine {
    let name = "demo"

    func start(_ server: Server, options: TunnelOptions, log: @escaping (LogLine.Level, String) -> Void) async throws {
        log(.info, "resolve \(server.host.isEmpty ? "—" : server.host):\(server.port)")
        try await Task.sleep(nanoseconds: 450_000_000)
        guard !server.host.isEmpty || server.proto == .openflux || server.proto == .custom else { throw TunnelError.badConfig }
        log(.info, "\(server.protoTitle) handshake…")
        try await Task.sleep(nanoseconds: UInt64.random(in: 650_000_000...1_000_000_000))
        let ruleInfo = options.mode == .rules ? " (\(options.rules.count))" : ""
        log(.info, "tun up · DNS \(options.dns) · \(options.mode.rawValue)\(ruleInfo)")
        if options.killSwitch { log(.info, "kill switch armed") }
    }

    func stop() async {
        try? await Task.sleep(nanoseconds: 380_000_000)
    }
}
