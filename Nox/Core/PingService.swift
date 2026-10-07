import Foundation
#if canImport(Network)
import Network
#endif

/// Latency check. Real servers: TCP connect time to host:port (no ICMP on iOS without
/// extra plumbing). Demo servers: simulated values around their design numbers.
enum PingService {
    static func measure(_ server: Server) async -> Int? {
        if server.isDemo {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 250_000_000...1_000_000_000))
            let base = max(server.demoPing, 5)
            let spread = max(2, base / 12)
            return max(3, base + Int.random(in: -spread...spread))
        }
        #if canImport(Network)
        if let ms = await tcpConnect(host: server.host, port: server.port, timeout: 3) { return ms }
        // UDP protocols (Hysteria2, TUIC, WireGuard…) usually still have TCP 443 open.
        if server.proto.isUDP, server.port != 443 {
            return await tcpConnect(host: server.host, port: 443, timeout: 2)
        }
        return nil
        #else
        return nil
        #endif
    }

    #if canImport(Network)
    static func tcpConnect(host: String, port: Int, timeout: TimeInterval) async -> Int? {
        guard !host.isEmpty, (1...65535).contains(port),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let gate = OnceGate()
        let start = DispatchTime.now().uptimeNanoseconds
        return await withCheckedContinuation { (cont: CheckedContinuation<Int?, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    let ms = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                    connection.cancel()
                    cont.resume(returning: max(1, ms))
                case .failed, .waiting:
                    guard gate.claim() else { return }
                    connection.cancel()
                    cont.resume(returning: nil)
                case .cancelled:
                    if gate.claim() { cont.resume(returning: nil) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard gate.claim() else { return }
                connection.cancel()
                cont.resume(returning: nil)
            }
        }
    }
    #endif
}

/// Resumes a continuation exactly once across racing callbacks.
final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
