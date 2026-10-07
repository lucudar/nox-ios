import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Downloads a subscription and parses it with `ShareLinkParser`. The title comes from the
/// `profile-title` header (plain or "base64:…"), as served by Marzban / 3x-ui / Remnawave.
enum SubscriptionLoader {
    struct Result: Sendable {
        let title: String?
        let servers: [Server]
    }

    enum LoadError: LocalizedError {
        case http(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .http(let code):
                return L10n.t("Сервер подписки ответил с ошибкой \(code)", "The subscription server returned error \(code)")
            case .empty:
                return L10n.t("В подписке не нашлось серверов", "No servers found in the subscription")
            }
        }
    }

    static func fetch(_ url: URL) async throws -> Result {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Nox/\(version) (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        if let code = http?.statusCode, !(200..<300).contains(code) { throw LoadError.http(code) }

        let body = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let servers = ShareLinkParser.parseMany(body)
        guard !servers.isEmpty else { throw LoadError.empty }
        return Result(title: title(http?.value(forHTTPHeaderField: "profile-title")), servers: servers)
    }

    private static func title(_ header: String?) -> String? {
        guard var t = header?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.lowercased().hasPrefix("base64:"), let decoded = Base64.decodeString(String(t.dropFirst(7))) {
            t = decoded
        }
        return t.nilIfEmpty
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5"
    }
}
