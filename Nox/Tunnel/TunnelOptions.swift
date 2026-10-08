import Foundation

/// Everything besides the server that shapes the tunnel (see `SingBoxConfig`).
struct TunnelOptions: Equatable, Sendable {
    var routing: RoutingPreset = .russia
    var blockAds = false
    var dnsPreset: DNSPreset = .cloudflare
    var dnsTransport: DNSTransport = .doh
    var customDNS = ""
    var killSwitch = false
    var autoConnect = false
    var verboseLogs = false
    var rules: [RouteRule] = []

    /// The kill switch lives in the VPN profile (includeAllNetworks): changing it needs a
    /// tunnel restart. Everything else is applied by reloading the sing-box config.
    func needsRestart(comparedTo old: TunnelOptions) -> Bool { killSwitch != old.killSwitch }

    /// Only the profile changes (on-demand rules), the running config stays the same.
    func onlyProfileChanged(comparedTo old: TunnelOptions) -> Bool {
        var a = self, b = old
        a.autoConnect = false
        b.autoConnect = false
        return a == b && autoConnect != old.autoConnect
    }

    /// "DoH · Cloudflare" for logs.
    var dnsSummary: String {
        let name = dnsPreset == .custom ? (customDNS.trimmingCharacters(in: .whitespaces).isEmpty ? "1.1.1.1" : customDNS) : dnsPreset.title(.en)
        return "\(dnsTransport.title) · \(name)"
    }
}
