import Foundation
import Observation

/// Connection state machine on top of a `TunnelEngine`, plus live speed / IP / logs.
@MainActor
@Observable
final class ConnectionManager {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected(since: Date)
        case disconnecting

        var key: Int {
            switch self {
            case .disconnected: return 0
            case .connecting: return 1
            case .connected: return 2
            case .disconnecting: return 3
            }
        }
    }

    private(set) var status: Status = .disconnected
    private(set) var server: Server?
    private(set) var down: Double = 0
    private(set) var up: Double = 0
    private(set) var ip = ""
    private(set) var logs: [LogLine] = []
    private(set) var lastError: String?

    /// Traffic hook (MB down, MB up, seconds, server) → statistics.
    @ObservationIgnored var onTraffic: ((Double, Double, Double, Server) -> Void)?

    @ObservationIgnored private let engine: TunnelEngine
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var meter: Task<Void, Never>?

    init(engine: TunnelEngine? = nil) {
        self.engine = engine ?? DemoTunnelEngine()
        log(.info, "Nox · engine: \(self.engine.name)")
    }

    var isActive: Bool { status != .disconnected }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    // MARK: Actions

    func toggle(_ server: Server?, options: TunnelOptions) {
        switch status {
        case .disconnected:
            if let server { connect(server, options: options) }
        case .connecting, .connected:
            disconnect()
        case .disconnecting:
            break
        }
    }

    func connect(_ server: Server, options: TunnelOptions) {
        run(server, options: options, stopFirst: false)
    }

    /// Switching servers while connected / connecting.
    func reconnect(_ server: Server, options: TunnelOptions) {
        guard isActive, server.id != self.server?.id || status == .connecting else { return }
        log(.info, L10n.t("Смена сервера → \(server.displayName(L10n.lang))", "Switching to \(server.displayName(L10n.lang))"))
        run(server, options: options, stopFirst: true)
    }

    /// Mode / DNS / rules / kill switch changed while active → restart the tunnel on the same server.
    func applyOptions(_ options: TunnelOptions) {
        guard isActive, status != .disconnecting, let server else { return }
        log(.info, L10n.t("Настройки изменены — перезапуск туннеля", "Settings changed — restarting the tunnel"))
        run(server, options: options, stopFirst: true)
    }

    func disconnect() {
        job?.cancel()
        meter?.cancel()
        status = .disconnecting
        log(.info, L10n.t("Отключение…", "Disconnecting…"))
        job = Task { [weak self] in
            guard let self else { return }
            await self.engine.stop()
            guard !Task.isCancelled else { return }
            self.status = .disconnected
            self.down = 0
            self.up = 0
            self.log(.info, L10n.t("Отключено", "Disconnected"))
        }
    }

    func clearLogs() { logs.removeAll() }

    var logText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return logs.map { "\(f.string(from: $0.date)) \($0.level.rawValue.uppercased()) \($0.text)" }.joined(separator: "\n")
    }

    // MARK: Internals

    private func run(_ server: Server, options: TunnelOptions, stopFirst: Bool) {
        job?.cancel()
        meter?.cancel()
        self.server = server
        lastError = nil
        status = .connecting
        down = 0
        up = 0
        log(.info, L10n.t("Подключение: ", "Connecting: ") + "\(server.displayName(L10n.lang)) · \(server.protoTitle)")
        job = Task { [weak self] in
            guard let self else { return }
            if stopFirst { await self.engine.stop() }
            do {
                try await self.engine.start(server, options: options) { [weak self] level, text in
                    self?.log(level, text)
                }
                guard !Task.isCancelled else { return }
                self.status = .connected(since: Date())
                self.ip = Self.publicIP(for: server)
                self.log(.info, L10n.t("Защищено · IP ", "Protected · IP ") + Self.masked(self.ip))
                self.startMeter(server)
            } catch is CancellationError {
                // superseded by another action
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = error.localizedDescription
                self.log(.error, error.localizedDescription)
                self.status = .disconnected
            }
        }
    }

    private func startMeter(_ server: Server) {
        meter?.cancel()
        let ping = Double(server.lastPing ?? server.demoPing).clamped(8, 400)
        let baseDown = (950 / (ping + 1)).clamped(6, 46)
        meter = Task { [weak self] in
            var d = baseDown * 0.6
            var u = baseDown * 0.08
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                d = (d + (baseDown - d) * 0.35 + Double.random(in: -2.2...2.2)).clamped(0.3, 95)
                u = (u + (baseDown * 0.13 - u) * 0.35 + Double.random(in: -0.5...0.5)).clamped(0.1, 30)
                self.down = d
                self.up = u
                self.onTraffic?(d / 8, u / 8, 1, server)
            }
        }
    }

    func log(_ level: LogLine.Level, _ text: String) {
        logs.append(LogLine(date: Date(), level: level, text: text))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    /// Exit IP. With a real engine it comes from the tunnel; the demo derives a stable one.
    static func publicIP(for server: Server) -> String {
        let parts = server.host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, !Countries.isPrivateHost(server.host) { return server.host }
        var h: UInt32 = 2166136261
        for b in server.id.uuidString.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return "185.107.\(h % 250 + 2).\((h >> 8) % 250 + 2)"
    }

    /// 185.107.•••.••
    static func masked(_ ip: String) -> String {
        let p = ip.split(separator: ".")
        guard p.count == 4 else { return ip }
        return "\(p[0]).\(p[1]).•••.••"
    }
}
