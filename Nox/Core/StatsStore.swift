import Foundation
import Observation

/// Traffic statistics from the core's counters (see `ConnectionManager.account`), kept as hourly
/// buckets for 31 days in Application Support.
@MainActor
@Observable
final class StatsStore {
    enum Period: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        func title(_ l: Lang) -> String {
            switch self {
            case .day: return l == .ru ? "День" : "Day"
            case .week: return l == .ru ? "Неделя" : "Week"
            case .month: return l == .ru ? "Месяц" : "Month"
            }
        }
    }

    struct TopItem: Identifiable {
        let id: String
        let name: String
        let code: String
        let badge: Server.Badge
        let mb: Double
    }

    struct Snapshot {
        let caption: String
        let totalMB: Double
        let downMB: Double
        let upMB: Double
        /// MB per bar.
        let bars: [Double]
        let labels: [String]
        /// The bar for "now".
        let current: Int
        let onlineMinutes: Int
        /// 0 → no measurements.
        let avgPing: Int
        let top: [TopItem]

        var isEmpty: Bool { totalMB < 0.01 && onlineMinutes == 0 }
    }

    /// One hour of tunnel use.
    struct Bucket: Codable {
        /// Hours since 1970.
        var hour: Int
        var down = 0.0
        var up = 0.0
        var seconds = 0.0
        var pingSum = 0.0
        var pingCount = 0
        /// Place key → MB.
        var places: [String: Double] = [:]
    }

    struct Place: Codable {
        var code: String
        var badge: Server.Badge
        var nameRU: String
        var nameEN: String
    }

    private struct Stored: Codable {
        var buckets: [Bucket]
        var places: [String: Place]
    }

    private(set) var buckets: [Bucket] = []
    private var places: [String: Place] = [:]
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var dirty = false

    private static let keepHours = 31 * 24
    private static var fileURL: URL { Persist.supportDirectory.appendingPathComponent("stats.json") }

    init() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        buckets = stored.buckets.sorted { $0.hour < $1.hour }
        places = stored.places
        prune()
    }

    static func hour(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 3600).rounded(.down)) }

    // MARK: Recording

    func record(downMB: Double, upMB: Double, seconds: Double, server: Server, at date: Date = Date()) {
        let down = max(0, downMB), up = max(0, upMB), secs = max(0, seconds)
        guard down + up > 0 || secs > 0 else { return }
        let key = Self.placeKey(server)
        places[key] = Place(code: server.countryCode, badge: server.badge,
                            nameRU: server.displayName(.ru), nameEN: server.displayName(.en))
        mutate(at: date) { b in
            b.down += down
            b.up += up
            b.seconds += secs
            if down + up > 0 { b.places[key, default: 0] += down + up }
        }
    }

    func recordPing(_ ms: Int, at date: Date = Date()) {
        guard ms > 0 else { return }
        mutate(at: date) { b in
            b.pingSum += Double(ms)
            b.pingCount += 1
        }
    }

    /// Writes pending changes (app going to background).
    func flush() {
        if dirty { save() }
    }

    func reset() {
        buckets = []
        places = [:]
        save()
    }

    private func mutate(at date: Date, _ body: (inout Bucket) -> Void) {
        let hour = Self.hour(date)
        if let i = buckets.lastIndex(where: { $0.hour == hour }) {
            body(&buckets[i])
        } else {
            var bucket = Bucket(hour: hour)
            body(&bucket)
            let at = buckets.firstIndex { $0.hour > hour } ?? buckets.endIndex
            buckets.insert(bucket, at: at)
            prune()
        }
        dirty = true
        if Date().timeIntervalSince(lastSave) > 30 { save() }
    }

    private func prune() {
        let oldest = Self.hour(Date()) - Self.keepHours
        buckets.removeAll { $0.hour < oldest }
        let used = Set(buckets.flatMap { $0.places.keys })
        places = places.filter { used.contains($0.key) }
    }

    private func save() {
        dirty = false
        lastSave = Date()
        guard let data = try? JSONEncoder().encode(Stored(buckets: buckets, places: places)) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    /// City, else "home" / the server's name.
    static func placeKey(_ server: Server) -> String {
        if !server.city.isEmpty { return server.city }
        return server.badge == .home ? "home" : server.displayName(.en)
    }

    // MARK: Reading

    func snapshot(_ period: Period, _ lang: Lang, now: Date = Date()) -> Snapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let slots: [(start: Date, end: Date)]
        let caption: String
        switch period {
        case .day:
            slots = (0..<12).map { i in
                (cal.date(byAdding: .hour, value: i * 2, to: today) ?? today,
                 cal.date(byAdding: .hour, value: i * 2 + 2, to: today) ?? today)
            }
            caption = lang == .ru ? "Трафик за сегодня" : "Traffic today"
        case .week, .month:
            let count = period == .week ? 7 : 30
            slots = (0..<count).map { i in
                let start = cal.date(byAdding: .day, value: i - (count - 1), to: today) ?? today
                return (start, cal.date(byAdding: .day, value: 1, to: start) ?? start)
            }
            caption = period == .week ? (lang == .ru ? "Трафик за 7 дней" : "Traffic, 7 days")
                                      : (lang == .ru ? "Трафик за 30 дней" : "Traffic, 30 days")
        }
        let edges = slots.map { (Self.hour($0.start), Self.hour($0.end)) }
        let lo = edges.first?.0 ?? 0, hi = edges.last?.1 ?? 0

        var bars = Array(repeating: 0.0, count: slots.count)
        var down = 0.0, up = 0.0, seconds = 0.0, pingSum = 0.0, pingCount = 0
        var byPlace: [String: Double] = [:]
        for b in buckets where b.hour >= lo && b.hour < hi {
            if let i = edges.firstIndex(where: { b.hour >= $0.0 && b.hour < $0.1 }) { bars[i] += b.down + b.up }
            down += b.down
            up += b.up
            seconds += b.seconds
            pingSum += b.pingSum
            pingCount += b.pingCount
            for (key, mb) in b.places { byPlace[key, default: 0] += mb }
        }

        let top = byPlace.map { key, mb -> TopItem in
            let place = places[key]
            let name: String
            if key == "home" { name = lang == .ru ? "Домашний сервер" : "Home server" }
            else if Countries.cities[key] != nil { name = Countries.city(key, lang) }
            else { name = (lang == .ru ? place?.nameRU : place?.nameEN) ?? key }
            return TopItem(id: key, name: name, code: place?.code ?? "", badge: place?.badge ?? .none, mb: mb)
        }
        .sorted { $0.mb > $1.mb }

        let nowHour = Self.hour(now)
        let current = edges.firstIndex { nowHour >= $0.0 && nowHour < $0.1 } ?? (slots.count - 1)
        return Snapshot(caption: caption, totalMB: down + up, downMB: down, upMB: up,
                        bars: bars, labels: labels(period, slots: slots.map(\.start), lang), current: current,
                        onlineMinutes: Int(seconds / 60), avgPing: pingCount > 0 ? Int((pingSum / Double(pingCount)).rounded()) : 0,
                        top: Array(top.prefix(4)))
    }

    private func labels(_ period: Period, slots: [Date], _ lang: Lang) -> [String] {
        let cal = Calendar.current
        switch period {
        case .day:
            return slots.indices.map { $0 % 3 == 0 ? "\($0 * 2)" : "" }
        case .week:
            let f = DateFormatter()
            f.locale = lang.locale
            let symbols = f.shortStandaloneWeekdaySymbols ?? []
            return slots.map { d in
                guard !symbols.isEmpty else { return "" }
                let s = symbols[(cal.component(.weekday, from: d) - 1) % symbols.count]
                return s.prefix(1).uppercased() + s.dropFirst()
            }
        case .month:
            return slots.indices.map { i in
                let back = slots.count - 1 - i
                return back % 7 == 0 ? "\(cal.component(.day, from: slots[i]))" : ""
            }
        }
    }
}
