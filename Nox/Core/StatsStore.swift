import Foundation
import Observation

/// Traffic statistics. History is mock data from the design; the live session (demo
/// engine meter) is added on top so the numbers move while connected.
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
        let gb: Double
    }

    struct Snapshot {
        let caption: String
        let totalGB: Double
        let downGB: Double
        let upGB: Double
        let bars: [Double]
        let labels: [String]
        let onlineMinutes: Int
        let avgPing: Int
        let top: [TopItem]
    }

    private(set) var liveDownMB = 0.0
    private(set) var liveUpMB = 0.0
    private(set) var liveSeconds = 0.0
    private var liveByPlace: [String: (code: String, badge: Server.Badge, mb: Double)] = [:]

    func record(downMB: Double, upMB: Double, seconds: Double, server: Server) {
        liveDownMB += downMB
        liveUpMB += upMB
        liveSeconds += seconds
        let key = server.city.isEmpty ? (server.badge == .home ? "home" : server.displayName(.en)) : server.city
        var entry = liveByPlace[key] ?? (code: server.countryCode, badge: server.badge, mb: 0)
        entry.mb += downMB + upMB
        liveByPlace[key] = entry
    }

    // MARK: Mock history

    private static let weekBars: [Double] = [2.1, 3.4, 1.8, 4.3, 2.9, 2.6, 1.3]
    private static let dayBars: [Double] = [0.02, 0.01, 0.0, 0.0, 0.05, 0.12, 0.18, 0.22, 0.15, 0.2, 0.25, 0.1]
    private static let monthBars: [Double] = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        var out: [Double] = []
        for _ in 0..<23 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            out.append(0.9 + Double(seed >> 40) / Double(1 << 24) * 3.6)
        }
        return out + weekBars
    }()

    func snapshot(_ period: Period, _ lang: Lang) -> Snapshot {
        let liveGB = (liveDownMB + liveUpMB) / 1024
        let liveDownGB = liveDownMB / 1024
        let liveMinutes = Int(liveSeconds / 60)
        var bars: [Double]
        let caption: String
        let online: Int
        let ping: Int
        let topBase: [(String, String, Server.Badge, Double)]

        switch period {
        case .day:
            bars = Self.dayBars
            caption = lang == .ru ? "Трафик за сегодня" : "Traffic today"
            online = 221
            ping = 39
            topBase = [("amsterdam", "NL", .none, 0.8), ("frankfurt", "DE", .none, 0.3), ("home", "", .home, 0.2)]
        case .week:
            bars = Self.weekBars
            caption = lang == .ru ? "Трафик за 7 дней" : "Traffic, 7 days"
            online = 31 * 60 + 12
            ping = 41
            topBase = [("amsterdam", "NL", .none, 9.8), ("frankfurt", "DE", .none, 5.1), ("home", "", .home, 2.2)]
        case .month:
            bars = Self.monthBars
            caption = lang == .ru ? "Трафик за 30 дней" : "Traffic, 30 days"
            online = 124 * 60 + 22
            ping = 44
            topBase = [("amsterdam", "NL", .none, 34.2), ("frankfurt", "DE", .none, 18.0), ("home", "", .home, 7.6)]
        }
        if !bars.isEmpty { bars[bars.count - 1] += liveGB }

        let total = bars.reduce(0, +)
        let down = total * 0.918 + liveDownGB * 0.082

        var top: [String: (code: String, badge: Server.Badge, gb: Double)] = [:]
        for t in topBase { top[t.0] = (code: t.1, badge: t.2, gb: t.3) }
        for (key, v) in liveByPlace {
            var e = top[key] ?? (code: v.code, badge: v.badge, gb: 0)
            e.gb += v.mb / 1024
            top[key] = e
        }
        let items = top.map { key, v -> TopItem in
            let name: String
            if key == "home" { name = lang == .ru ? "Домашний сервер" : "Home server" }
            else if Countries.cities[key] != nil { name = Countries.city(key, lang) }
            else { name = key }
            return TopItem(id: key, name: name, code: v.code, badge: v.badge, gb: v.gb)
        }
        .sorted { $0.gb > $1.gb }

        return Snapshot(caption: caption, totalGB: total, downGB: min(down, total), upGB: max(0, total - min(down, total)),
                        bars: bars, labels: labels(period, count: bars.count, lang),
                        onlineMinutes: online + liveMinutes, avgPing: ping, top: Array(items.prefix(4)))
    }

    private func labels(_ period: Period, count: Int, _ lang: Lang) -> [String] {
        let cal = Calendar.current
        let today = Date()
        switch period {
        case .day:
            return (0..<count).map { $0 % 3 == 0 ? "\($0 * 2)" : "" }
        case .week:
            let f = DateFormatter()
            f.locale = lang.locale
            let symbols = f.shortStandaloneWeekdaySymbols ?? []
            return (0..<count).map { i in
                guard let d = cal.date(byAdding: .day, value: i - (count - 1), to: today), !symbols.isEmpty else { return "" }
                let s = symbols[(cal.component(.weekday, from: d) - 1) % symbols.count]
                return s.prefix(1).uppercased() + s.dropFirst()
            }
        case .month:
            return (0..<count).map { i in
                let back = count - 1 - i
                guard back % 7 == 0, let d = cal.date(byAdding: .day, value: -back, to: today) else { return "" }
                return "\(cal.component(.day, from: d))"
            }
        }
    }
}
