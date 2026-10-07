import Foundation

/// Tiny persistence layer: settings as JSON in UserDefaults, bigger data as files in
/// Application Support (see `supportDirectory`).
enum Persist {
    static func load<T: Codable>(_ key: String, default def: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key) else { return def }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Unreadable (e.g. an incompatible older format) → start from defaults.
            UserDefaults.standard.removeObject(forKey: key)
            return def
        }
    }

    static func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Nox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

extension KeyedDecodingContainer {
    /// Lenient decoding: a missing or mismatched key falls back to the default, so saved
    /// data keeps loading after new fields are added.
    func value<T: Decodable>(_ key: Key, _ def: T) -> T {
        guard let v = try? decodeIfPresent(T.self, forKey: key) else { return def }
        return v
    }
}
