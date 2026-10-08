import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The running core's Clash API on 127.0.0.1 (see `SingBoxConfig`): live speed, traffic totals
/// and the latency through the proxy.
struct CoreAPI: Sendable {
    var port: Int
    var secret: String

    struct Totals: Equatable, Sendable {
        var up: Int64
        var down: Int64
    }

    /// Plain loopback HTTP, never through a system proxy, nothing cached.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    private func request(_ path: String, timeout: TimeInterval = 8) -> URLRequest {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!, timeoutInterval: timeout)
        if !secret.isEmpty { request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// Bytes per second (up, down), once a second, until cancelled or the core goes away.
    func traffic() -> AsyncThrowingStream<Totals, Error> {
        let request = request("/traffic", timeout: 3600)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    #if canImport(Darwin)
                    let (bytes, response) = try await Self.session.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    for try await line in bytes.lines {
                        guard let object = Self.object(Data(line.utf8)) else { continue }
                        continuation.yield(Totals(up: Self.int(object["up"]), down: Self.int(object["down"])))
                    }
                    #else
                    _ = request // corelibs Foundation has no URLSession.AsyncBytes (Linux type-check only)
                    #endif
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Bytes through the core since it (re)started.
    func totals() async throws -> Totals {
        let (data, response) = try await Self.session.data(for: request("/connections"))
        guard (response as? HTTPURLResponse)?.statusCode == 200, let object = Self.object(data) else {
            throw URLError(.badServerResponse)
        }
        return Totals(up: Self.int(object["uploadTotal"]), down: Self.int(object["downloadTotal"]))
    }

    /// HTTPS round trip through the proxy (ms), like Clash's latency test.
    func delay(url: String = "https://www.gstatic.com/generate_204", timeout: Int = 6000) async -> Int? {
        var components = URLComponents()
        components.path = "/proxies/\(SingBoxOutbound.tag)/delay"
        components.queryItems = [URLQueryItem(name: "url", value: url), URLQueryItem(name: "timeout", value: "\(timeout)")]
        guard let path = components.string,
              let (data, response) = try? await Self.session.data(for: request(path, timeout: Double(timeout) / 1000 + 3)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = Self.object(data) else { return nil }
        let ms = Int(Self.int(object["delay"]))
        return ms > 0 ? ms : nil
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func int(_ value: Any?) -> Int64 {
        (value as? NSNumber)?.int64Value ?? 0
    }
}

/// Exit address as seen from the internet (Cloudflare trace, always routed through the proxy).
struct ExitInfo: Equatable, Sendable {
    var ip: String
    /// ISO country code, "" when unknown.
    var country: String

    static func fetch() async -> ExitInfo? {
        guard let url = URL(string: SingBoxConfig.ipCheckURL) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await CoreAPI.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// "ip=185.107.56.10\nloc=NL\n…"
    static func parse(_ text: String) -> ExitInfo? {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            values[String(line[..<eq])] = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        }
        guard let ip = values["ip"], !ip.isEmpty else { return nil }
        let loc = values["loc"] ?? ""
        return ExitInfo(ip: ip, country: loc.count == 2 && loc != "XX" && loc != "T1" ? loc.uppercased() : "")
    }
}
