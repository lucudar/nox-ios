import Foundation

/// Files shared by the app and the Packet Tunnel extension (App Group container):
/// the app writes `config.json` (+ `openflux.json` for OpenFlux servers) and starts the tunnel;
/// the extension runs sing-box with it, writes the core log to `box.log` (OpenFlux: `openflux.log`)
/// and the last start error to `error.txt`.
enum AppGroup {
    /// `NoxAppGroup` in Info.plist = group.$(NOX_BUNDLE_ID): change NOX_BUNDLE_ID in the project to
    /// re-sign Nox with your own team, the bundle IDs and the group follow it.
    static let identifier: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "NoxAppGroup") as? String ?? ""
        return value.isEmpty || value.contains("$(") ? "group.com.example.nox" : value
    }()
    /// Provider message: re-read config.json and reload sing-box without dropping the tunnel.
    static let reloadMessage = Data("reload".utf8)

    static var container: URL {
        #if os(iOS) || os(macOS)
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) { return url }
        #endif
        // Unsigned builds / tests: no group container, a private directory instead.
        return directory(FileManager.default.temporaryDirectory.appendingPathComponent("NoxGroup", isDirectory: true))
    }

    static var configURL: URL { container.appendingPathComponent("config.json") }
    static var logURL: URL { container.appendingPathComponent("box.log") }
    /// OpenFlux core config: present only while an OpenFlux server is in use.
    static var openFluxURL: URL { container.appendingPathComponent("openflux.json") }
    static var openFluxLogURL: URL { container.appendingPathComponent("openflux.log") }
    static var errorURL: URL { container.appendingPathComponent("error.txt") }
    static var cacheURL: URL { container.appendingPathComponent("cache.db") }
    static var ruleSetsURL: URL { directory(container.appendingPathComponent("RuleSets", isDirectory: true)) }
    static var workingURL: URL { directory(container.appendingPathComponent("Working", isDirectory: true)) }
    static var tempURL: URL { directory(container.appendingPathComponent("Temp", isDirectory: true)) }

    @discardableResult
    static func directory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Start errors

    static func writeError(_ message: String) {
        try? message.write(to: errorURL, atomically: true, encoding: .utf8)
    }

    static func readError() -> String? {
        guard let text = try? String(contentsOf: errorURL, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func clearError() {
        try? FileManager.default.removeItem(at: errorURL)
    }

    // MARK: Core log

    /// Last `maxBytes` of box.log or another log (whole lines only).
    static func logTail(_ file: URL? = nil, maxBytes: Int = 96 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file ?? logURL) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") { text = String(text[text.index(after: newline)...]) }
        return text
    }

    static func truncateLog(_ file: URL? = nil) {
        try? Data().write(to: file ?? logURL)
    }
}
