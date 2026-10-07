import Foundation
import Observation

/// Servers grouped by subscription + the user's own list, selection, Auto mode and ping.
@MainActor
@Observable
final class ServerStore {
    private(set) var groups: [ServerGroup] = []
    private(set) var selectedID: UUID?
    private(set) var autoSelect = false

    /// Servers whose ping is in flight (rows shimmer).
    private(set) var pending: Set<UUID> = []
    private(set) var isPinging = false
    /// Set when a full ping pass finishes; the header shows ✓ for a moment.
    private(set) var pingFinishedAt: Date?


    enum ImportResult: Equatable {
        case added(Int)
        case duplicates
        case subscription(URL)
        case nothing
    }

    private struct Snapshot: Codable {
        var groups: [ServerGroup]
        var selectedID: UUID?
        var autoSelect: Bool
    }

    private static var fileURL: URL { Persist.supportDirectory.appendingPathComponent("servers.json") }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            groups = snapshot.groups
            selectedID = snapshot.selectedID
            autoSelect = snapshot.autoSelect
        } else {
            // First launch: the demo list from the design boards.
            groups = DemoData.groups()
            selectedID = groups.first?.servers.first?.id
        }
    }

    // MARK: Lookup

    var allServers: [Server] { groups.flatMap(\.servers) }

    func server(_ id: UUID?) -> Server? {
        guard let id else { return nil }
        return allServers.first { $0.id == id }
    }

    var selected: Server? { server(selectedID) ?? allServers.first }

    /// Fastest server by the last ping. Home / LAN servers are skipped: they only work at home.
    var best: Server? {
        allServers
            .filter { $0.lastPing != nil && !$0.pingFailed && $0.badge != .home && !Countries.isPrivateHost($0.host) }
            .min { ($0.lastPing ?? .max) < ($1.lastPing ?? .max) }
    }

    /// The server that will be used for connecting.
    var current: Server? { autoSelect ? (best ?? selected) : selected }

    var isEmpty: Bool { allServers.isEmpty }

    // MARK: Selection

    func select(_ id: UUID) {
        selectedID = id
        autoSelect = false
        save()
    }

    func setAutoSelect(_ on: Bool) {
        autoSelect = on
        save()
    }

    // MARK: Ping

    func pingAll() async {
        guard !isPinging else { return }
        let targets = allServers
        guard !targets.isEmpty else { return }
        isPinging = true
        pingFinishedAt = nil
        pending = Set(targets.map(\.id))
        let started = Date()

        // Measure everything in parallel, reveal in list order with a small stagger.
        let tasks = targets.map { s in (s.id, Task.detached(priority: .userInitiated) { await PingService.measure(s) }) }
        for (index, item) in tasks.enumerated() {
            let ms = await item.1.value
            let revealAt = started.addingTimeInterval(0.55 + Double(index) * 0.12)
            let wait = revealAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            apply(item.0, ms)
        }
        isPinging = false
        pingFinishedAt = Date()
        save()
    }

    func ping(_ id: UUID) async {
        guard let s = server(id), !pending.contains(id) else { return }
        pending.insert(id)
        let ms = await PingService.measure(s)
        apply(id, ms)
        save()
    }

    private func apply(_ id: UUID, _ ms: Int?) {
        mutate(id) { s in
            s.lastPing = ms
            s.pingFailed = ms == nil
        }
        pending.remove(id)
    }

    // MARK: Editing

    @discardableResult
    func addOwn(_ list: [Server]) -> Int {
        guard !list.isEmpty else { return 0 }
        let i = ensureOwnGroup()
        let known = Set(allServers.map(\.link).filter { !$0.isEmpty })
        let fresh = list.filter { $0.link.isEmpty || !known.contains($0.link) }
        guard !fresh.isEmpty else { return 0 }
        groups[i].servers.append(contentsOf: fresh)
        if server(selectedID) == nil { selectedID = fresh.first?.id }
        save()
        return fresh.count
    }

    func update(_ server: Server) {
        mutate(server.id) { $0 = server }
        save()
    }

    func rename(_ id: UUID, to name: String) {
        mutate(id) { $0.name = name }
        save()
    }

    func delete(_ id: UUID) {
        for i in groups.indices {
            groups[i].servers.removeAll { $0.id == id }
        }
        // An emptied "Own" list disappears; subscriptions stay until deleted.
        groups.removeAll { $0.isOwn && $0.servers.isEmpty }
        if server(selectedID) == nil { selectedID = allServers.first?.id }
        save()
    }

    func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        if server(selectedID) == nil { selectedID = allServers.first?.id }
        save()
    }

    // MARK: Import

    /// Pasted text, scanned QR or file contents.
    func importText(_ text: String, fileName: String? = nil) -> ImportResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("\n"), let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return .subscription(url)
        }
        let parsed = ShareLinkParser.parseMany(trimmed, fileName: fileName)
        guard !parsed.isEmpty else { return .nothing }
        let added = addOwn(parsed)
        return added > 0 ? .added(added) : .duplicates
    }

    // MARK: Subscriptions

    @discardableResult
    func addSubscription(url: URL, name: String?) async throws -> Int {
        let result = try await SubscriptionLoader.fetch(url)
        let group = ServerGroup(name: name?.nilIfEmpty ?? result.title ?? url.host ?? "Subscription",
                                subscriptionURL: url, updatedAt: Date(), servers: result.servers)
        let ownIndex = groups.firstIndex { $0.isOwn } ?? groups.endIndex
        groups.insert(group, at: ownIndex)
        if server(selectedID) == nil { selectedID = group.servers.first?.id }
        save()
        return group.servers.count
    }

    func refresh(_ groupID: UUID) async throws {
        guard let g = groups.first(where: { $0.id == groupID }), let url = g.subscriptionURL else { return }
        if g.isDemo {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if let i = groups.firstIndex(where: { $0.id == groupID }) { groups[i].updatedAt = Date() }
            save()
            return
        }
        let result = try await SubscriptionLoader.fetch(url)
        guard let i = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let selectedLink = selected?.link
        groups[i].servers = result.servers
        groups[i].updatedAt = Date()
        if let link = selectedLink, let same = groups[i].servers.first(where: { $0.link == link }) {
            selectedID = same.id
        } else if server(selectedID) == nil {
            selectedID = allServers.first?.id
        }
        save()
    }

    // MARK: Internals

    private func mutate(_ id: UUID, _ body: (inout Server) -> Void) {
        for g in groups.indices {
            if let s = groups[g].servers.firstIndex(where: { $0.id == id }) {
                body(&groups[g].servers[s])
                return
            }
        }
    }

    /// Index of the "Own" group, created at the end if missing.
    private func ensureOwnGroup() -> Int {
        if let i = groups.firstIndex(where: { $0.isOwn }) { return i }
        groups.append(ServerGroup())
        return groups.count - 1
    }

    private func save() {
        let snapshot = Snapshot(groups: groups, selectedID: selectedID, autoSelect: autoSelect)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
