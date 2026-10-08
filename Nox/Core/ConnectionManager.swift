import Foundation
import Observation

/// Connection state on top of a `TunnelEngine` (the system VPN status is the source of truth),
/// plus live speed, exit IP, latency and traffic accounting read from the core.
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
    /// Live speed through the core, Mbit/s.
    private(set) var down: Double = 0
    private(set) var up: Double = 0
    /// Exit address and its country code ("" until known).
    private(set) var ip = ""
    private(set) var exitCountry = ""
    /// HTTPS round trip through the proxy, ms.
    private(set) var latency: Int?
    private(set) var logs: [LogLine] = []
    private(set) var lastError: String?

    /// Traffic (MB down, MB up, seconds online, server) → statistics.
    @ObservationIgnored var onTraffic: ((Double, Double, Double, Server) -> Void)?
    /// Latency samples (ms) → statistics.
    @ObservationIgnored var onLatency: ((Int) -> Void)?

    @ObservationIgnored private let engine: TunnelEngine
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var monitors: [Task<Void, Never>] = []
    @ObservationIgnored private var options: TunnelOptions?
    /// start() is in flight: its result decides, early "disconnected" events are ignored.
    @ObservationIgnored private var starting = false
    /// The user pressed disconnect: not an error.
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var sessionSince: Date?

    private enum Key {
        static let server = "nox.active.server"
    }

    init(engine: TunnelEngine? = nil) {
        #if targetEnvironment(simulator)
        self.engine = engine ?? DemoTunnelEngine()
        #else
        self.engine = engine ?? SingBoxEngine()
        #endif
        self.engine.onState = { [weak self] state in self?.apply(state) }
        log(.info, "Nox \(AppInfo.version) · \(self.engine.name)")
        #if !targetEnvironment(simulator)
        if !AppGroup.isShared {
            log(.warn, L10n.t("Общая папка App Group «\(AppGroup.configuredIdentifier)» недоступна (сборку переподписали без неё?): настройки передаются туннелю напрямую, лог ядра виден только во время подключения.",
                              "The App Group \(AppGroup.configuredIdentifier) isn't available (re-signed without it?): settings go to the tunnel directly, the core log shows only while connected."))
        }
        #endif
    }

    var isActive: Bool { status != .disconnected }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    // MARK: Launch

    /// Picks up a tunnel that kept running while the app was closed (or was started by iOS).
    func restore(servers: ServerStore, options: TunnelOptions) async {
        self.options = options
        if let id = UserDefaults.standard.string(forKey: Key.server).flatMap(UUID.init(uuidString:)) {
            server = servers.server(id)
        }
        if server == nil { server = servers.current }
        let state = await engine.restore()
        guard state != .disconnected else { return }
        log(.info, L10n.t("Туннель уже запущен", "The tunnel is already running"))
        apply(state)
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
        start(server, options: options, restart: false)
    }

    /// The selected server changed while the tunnel is up.
    func switchServer(_ server: Server, options: TunnelOptions) {
        guard isActive, status != .disconnecting, server.id != self.server?.id else { return }
        log(.info, L10n.t("Смена сервера → ", "Switching to ") + server.displayName(L10n.lang))
        if isConnected {
            reload(server, options: options)
        } else {
            start(server, options: options, restart: true)
        }
    }

    /// Routing / DNS / rules / kill switch / auto-connect changed.
    func applyOptions(_ new: TunnelOptions) {
        let old = options
        options = new
        guard let old, old != new else { return }
        guard isActive, status != .disconnecting, let server else {
            // Not running: only switching auto-connect off has to reach the VPN profile now.
            if old.autoConnect, !new.autoConnect { Task { await engine.updateProfile(new) } }
            return
        }
        if new.onlyProfileChanged(comparedTo: old) {
            Task { await engine.updateProfile(new) }
        } else if new.needsRestart(comparedTo: old) {
            log(.info, L10n.t("Kill Switch изменён — переподключение", "Kill switch changed — reconnecting"))
            start(server, options: new, restart: true)
        } else {
            if new.autoConnect != old.autoConnect { Task { await engine.updateProfile(new) } }
            if isConnected {
                log(.info, L10n.t("Настройки применяются без разрыва", "Applying settings without reconnecting"))
                reload(server, options: new)
            } else {
                start(server, options: new, restart: true)
            }
        }
    }

    func disconnect() {
        job?.cancel()
        starting = false
        stopping = true
        status = .disconnecting
        log(.info, L10n.t("Отключение…", "Disconnecting…"))
        stopMonitors()
        job = Task { [weak self] in
            guard let self else { return }
            await self.account()   // the core's counters go away with it
            await self.engine.stop()
            self.stopping = false
            if self.status != .disconnected { self.finish() }
        }
    }

    func clearLogs() { logs.removeAll() }

    /// Tail of the core log (`openFlux`: the OpenFlux client's).
    func coreLog(openFlux: Bool) async -> String {
        await engine.coreLog(openFlux: openFlux)
    }

    var logText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return logs.map { "\(f.string(from: $0.date)) \($0.level.rawValue.uppercased()) \($0.text)" }.joined(separator: "\n")
    }

    func log(_ level: LogLine.Level, _ text: String) {
        logs.append(LogLine(date: Date(), level: level, text: text))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    // MARK: Internals

    private func start(_ server: Server, options: TunnelOptions, restart: Bool) {
        job?.cancel()
        stopMonitors()
        select(server)
        self.options = options
        lastError = nil
        starting = true
        status = .connecting
        log(.info, L10n.t("Подключение: ", "Connecting: ") + "\(server.displayName(L10n.lang)) · \(server.protoTitle)")
        job = Task { [weak self] in
            guard let self else { return }
            if restart {
                await self.account()
                await self.engine.stop()
            }
            do {
                try Task.checkCancellation()
                try await self.engine.start(server, options: options)
                guard !Task.isCancelled else { return }
                self.starting = false
                if !self.isConnected { self.apply(.connected(since: Date())) }
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.starting = false
                self.fail(error.localizedDescription)
            }
        }
    }

    /// New config inside the running tunnel.
    private func reload(_ server: Server, options: TunnelOptions) {
        job?.cancel()
        self.options = options
        job = Task { [weak self] in
            guard let self else { return }
            await self.account()   // traffic so far belongs to the previous server
            self.select(server)
            do {
                try await self.engine.update(server, options: options)
                guard !Task.isCancelled else { return }
                if let since = self.sessionSince { TrafficMark(since: since, up: 0, down: 0, at: Date()).save() }
                self.log(.info, L10n.t("Конфигурация обновлена", "Configuration updated"))
                self.startMonitors()
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    private func select(_ server: Server) {
        self.server = server
        UserDefaults.standard.set(server.id.uuidString, forKey: Key.server)
    }

    /// System VPN status → app status.
    private func apply(_ state: TunnelState) {
        switch state {
        case .connected(let since):
            let fresh = !isConnected || sessionSince != since
            status = .connected(since: since)
            sessionSince = since
            if fresh {
                log(.info, L10n.t("Подключено", "Connected"))
                startMonitors()
            }
        case .connecting:
            if status != .disconnecting { status = .connecting }
        case .reasserting:
            // A reload inside a live tunnel: keep showing it as connected.
            if !isConnected, status != .disconnecting { status = .connecting }
        case .disconnecting:
            if !starting { status = .disconnecting }
        case .disconnected:
            guard !starting, status != .disconnected else { return }
            let unexpected = !stopping
            finish()
            if unexpected {
                // Stopped from outside: iOS Settings, the system, or a core error.
                Task { [weak self] in
                    guard let self, let error = await self.engine.lastError() else { return }
                    self.lastError = error
                    self.log(.error, error)
                }
            }
        }
    }

    private func finish() {
        stopMonitors()
        resetLive()
        status = .disconnected
        log(.info, L10n.t("Отключено", "Disconnected"))
    }

    private func fail(_ message: String) {
        lastError = message
        log(.error, message)
        stopMonitors()
        resetLive()
        status = .disconnected
    }

    private func resetLive() {
        down = 0
        up = 0
        ip = ""
        exitCountry = ""
        latency = nil
    }

    // MARK: Live data

    private func startMonitors() {
        stopMonitors()
        ip = ""
        exitCountry = ""
        latency = nil
        guard let api = engine.api else { return }
        monitors = [
            Task { [weak self] in await self?.watchSpeed(api) },
            Task { [weak self] in await self?.watchTraffic(api) },
            Task { [weak self] in await self?.watchExit(api) },
        ]
    }

    private func stopMonitors() {
        monitors.forEach { $0.cancel() }
        monitors = []
    }

    private func watchSpeed(_ api: CoreAPI) async {
        while !Task.isCancelled {
            do {
                for try await sample in api.traffic() {
                    down = Double(sample.down) * 8 / 1_000_000
                    up = Double(sample.up) * 8 / 1_000_000
                }
            } catch {}
            guard !Task.isCancelled else { return }
            down = 0
            up = 0
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func watchTraffic(_ api: CoreAPI) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await account(api)
        }
    }

    private func watchExit(_ api: CoreAPI) async {
        // The first requests can race the core's start: a few tries.
        for attempt in 0..<5 {
            guard !Task.isCancelled else { return }
            if let info = await ExitInfo.fetch() {
                ip = info.ip
                exitCountry = info.country
                break
            }
            try? await Task.sleep(nanoseconds: UInt64(1 << attempt) * 1_500_000_000)
        }
        while !Task.isCancelled {
            if let ms = await api.delay(), !Task.isCancelled {
                latency = ms
                onLatency?(ms)
            }
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }

    /// Adds what the core moved since the last look to the statistics. The marker survives app
    /// restarts, so traffic while the app was closed is counted once.
    private func account(_ api: CoreAPI? = nil) async {
        guard let api = api ?? engine.api, let since = sessionSince, let server,
              let totals = try? await api.totals() else { return }
        let now = Date()
        var up = totals.up, down = totals.down
        var seconds = now.timeIntervalSince(since)
        if let mark = TrafficMark.load(), abs(mark.since.timeIntervalSince(since)) < 1 {
            seconds = now.timeIntervalSince(mark.at)
            // Smaller totals → the core restarted (reload): its counters began from zero.
            if totals.up >= mark.up, totals.down >= mark.down {
                up -= mark.up
                down -= mark.down
            }
        }
        TrafficMark(since: since, up: totals.up, down: totals.down, at: now).save()
        guard up > 0 || down > 0 || seconds > 0 else { return }
        onTraffic?(Double(down) / 1_048_576, Double(up) / 1_048_576, max(0, seconds), server)
    }

    /// 185.107.•••.•• / 2a01:4f8:•••
    static func masked(_ ip: String) -> String {
        if ip.contains(":") {
            let groups = ip.split(separator: ":", omittingEmptySubsequences: false)
            return groups.prefix(2).joined(separator: ":") + ":•••"
        }
        let p = ip.split(separator: ".")
        guard p.count == 4 else { return ip }
        return "\(p[0]).\(p[1]).•••.••"
    }
}

/// Core counters at the last look, per tunnel session.
private struct TrafficMark: Codable {
    var since: Date
    var up: Int64
    var down: Int64
    var at: Date

    private static let key = "nox.traffic.mark"

    static func load() -> TrafficMark? { Persist.load(key, default: TrafficMark?.none) }
    func save() { Persist.save(self, Self.key) }
}
