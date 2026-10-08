import Foundation
import Libbox
import Network
import NetworkExtension

/// libbox ⇄ iOS. sing-box calls this from its own threads: open the utun (through
/// NEPacketTunnelProvider network settings), follow the default network interface, and
/// handle the command server's reload / stop requests. Desktop-only features are refused.
final class PlatformInterface: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    private unowned let tunnel: PacketTunnelProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var monitor: NWPathMonitor?
    private var lastPath: String?

    init(_ tunnel: PacketTunnelProvider) {
        self.tunnel = tunnel
    }

    func reset() {
        networkSettings = nil
        monitor?.cancel()
        monitor = nil
        lastPath = nil
    }

    // MARK: TUN

    func openTun(_ options: (any LibboxTunOptionsProtocol)?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options else { throw Self.failure("no TUN options") }
        guard let ret0_ else { throw Self.failure("no return pointer") }
        let settings = try Self.makeSettings(options)
        networkSettings = settings
        let tunnel = self.tunnel
        try runBlocking {
            try await tunnel.setTunnelNetworkSettings(settings)
        }
        if let fd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = fd
            return
        }
        let fd = LibboxGetTunnelFileDescriptor()
        guard fd != -1 else { throw Self.failure("missing utun file descriptor") }
        ret0_.pointee = fd
    }

    private static func makeSettings(_ options: any LibboxTunOptionsProtocol) throws -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        guard options.getAutoRoute() else { return settings }
        settings.mtu = NSNumber(value: options.getMTU())

        var dnsSettings: NEDNSSettings?
        if (options.getDNSMode()?.value ?? LibboxDNSModeHijack) != LibboxDNSModeDisabled {
            let servers = strings(try options.getDNSServerAddress())
            if !servers.isEmpty { dnsSettings = NEDNSSettings(servers: servers) }
        }

        let v4 = prefixes(options.getInet4Address())
        let ipv4 = NEIPv4Settings(addresses: v4.map { $0.address() }, subnetMasks: v4.map { $0.mask() })
        var routes4 = prefixes(options.getInet4RouteAddress()).map {
            NEIPv4Route(destinationAddress: $0.address(), subnetMask: $0.mask())
        }
        if routes4.isEmpty { routes4 = [NEIPv4Route.default()] }
        ipv4.includedRoutes = routes4
        ipv4.excludedRoutes = prefixes(options.getInet4RouteExcludeAddress()).map {
            NEIPv4Route(destinationAddress: $0.address(), subnetMask: $0.mask())
        }
        settings.ipv4Settings = ipv4

        let v6 = prefixes(options.getInet6Address())
        if !v6.isEmpty {
            let ipv6 = NEIPv6Settings(addresses: v6.map { $0.address() },
                                      networkPrefixLengths: v6.map { NSNumber(value: $0.prefix()) })
            var routes6 = prefixes(options.getInet6RouteAddress()).map {
                NEIPv6Route(destinationAddress: $0.address(), networkPrefixLength: NSNumber(value: $0.prefix()))
            }
            if routes6.isEmpty { routes6 = [NEIPv6Route.default()] }
            ipv6.includedRoutes = routes6
            ipv6.excludedRoutes = prefixes(options.getInet6RouteExcludeAddress()).map {
                NEIPv6Route(destinationAddress: $0.address(), networkPrefixLength: NSNumber(value: $0.prefix()))
            }
            settings.ipv6Settings = ipv6
        }

        // Without a default route the system only sends matching queries to our resolver.
        let hasDefaultRoute = routes4.contains { $0.destinationAddress == "0.0.0.0" && $0.destinationSubnetMask == "0.0.0.0" }
        if !hasDefaultRoute {
            dnsSettings?.matchDomains = [""]
            dnsSettings?.matchDomainsNoSearch = true
        }
        settings.dnsSettings = dnsSettings

        if options.isHTTPProxyEnabled() {
            let proxy = NEProxySettings()
            let server = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
            proxy.httpServer = server
            proxy.httpsServer = server
            proxy.httpEnabled = true
            proxy.httpsEnabled = true
            let bypass = strings(options.getHTTPProxyBypassDomain())
            if !bypass.isEmpty { proxy.exceptionList = bypass }
            let match = strings(options.getHTTPProxyMatchDomain())
            if !match.isEmpty { proxy.matchDomains = match }
            settings.proxySettings = proxy
        }
        return settings
    }

    func clearDNSCache() {
        guard let settings = networkSettings else { return }
        let tunnel = self.tunnel
        runBlocking {
            tunnel.reasserting = true
            defer { tunnel.reasserting = false }
            try? await tunnel.setTunnelNetworkSettings(nil)
            try? await tunnel.setTunnelNetworkSettings(settings)
        }
    }

    func includeAllNetworks() -> Bool {
        tunnel.protocolConfiguration.includeAllNetworks
    }

    func underNetworkExtension() -> Bool { true }

    // MARK: Default interface

    func startDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        let first = DispatchSemaphore(value: 0)
        let gate = Once()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(listener, path)
            if gate.claim() { first.signal() }
        }
        monitor.start(queue: DispatchQueue.global())
        // libbox expects the current interface to be known when this returns.
        _ = first.wait(timeout: .now() + 5)
    }

    func closeDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        monitor?.cancel()
        monitor = nil
        lastPath = nil
    }

    private func update(_ listener: any LibboxInterfaceUpdateListenerProtocol, _ path: NWPath) {
        let description = Self.describe(path)
        listener.updateNetworkPath(description)
        guard description != lastPath else { return }
        lastPath = description
        guard path.status != .unsatisfied, let interface = path.availableInterfaces.first else {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        listener.updateDefaultInterface(interface.name, interfaceIndex: Int32(interface.index),
                                        isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }

    private static func describe(_ path: NWPath) -> String {
        var parts: [String] = []
        switch path.status {
        case .satisfied: parts.append("satisfied")
        case .unsatisfied: parts.append("unsatisfied(\(path.unsatisfiedReason))")
        case .requiresConnection: parts.append("requiresConnection")
        @unknown default: parts.append("unknown")
        }
        if !path.availableInterfaces.isEmpty {
            parts.append("interfaces=" + path.availableInterfaces.map { "\($0.name)#\($0.index)/\($0.type)" }.joined(separator: ","))
        }
        if !path.gateways.isEmpty {
            parts.append("gateways=" + path.gateways.map { "\($0)" }.sorted().joined(separator: ","))
        }
        if path.supportsIPv4 { parts.append("ipv4") }
        if path.supportsIPv6 { parts.append("ipv6") }
        if path.supportsDNS { parts.append("dns") }
        if path.isExpensive { parts.append("expensive") }
        if path.isConstrained { parts.append("constrained") }
        return parts.joined(separator: " ")
    }

    func getInterfaces() throws -> any LibboxNetworkInterfaceIteratorProtocol {
        guard let monitor else { throw Self.failure("interface monitor is not running") }
        let path = monitor.currentPath
        guard path.status != .unsatisfied else { return InterfaceList([]) }
        let list: [LibboxNetworkInterface] = path.availableInterfaces.map { item in
            let interface = LibboxNetworkInterface()
            interface.name = item.name
            interface.index = Int32(item.index)
            switch item.type {
            case .wifi: interface.type = LibboxInterfaceTypeWIFI
            case .cellular: interface.type = LibboxInterfaceTypeCellular
            case .wiredEthernet: interface.type = LibboxInterfaceTypeEthernet
            default: interface.type = LibboxInterfaceTypeOther
            }
            return interface
        }
        return InterfaceList(list)
    }

    // MARK: Command server

    func serviceReload() throws {
        try tunnel.reload()
    }

    func serviceStop() throws {
        tunnel.cancelTunnelWithError(nil)
    }

    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        LibboxSystemProxyStatus()
    }

    func setSystemProxyEnabled(_ enabled: Bool) throws {}

    func connectSSHAgent(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw Self.failure("SSH agent is not available on iOS")
    }

    func triggerNativeCrash() throws {}

    func writeDebugMessage(_ message: String?) {}

    // MARK: Not available on iOS

    func usePlatformAutoDetectInterfaceControl() -> Bool { false }
    func autoDetectInterfaceControl(_ fd: Int32) throws {}
    func useProcFS() -> Bool { false }
    func usePlatformBridge() -> Bool { false }
    func usePlatformShell() -> Bool { false }
    func localDNSTransport() -> (any LibboxLocalDNSTransportProtocol)? { nil }
    func readWIFIState() -> LibboxWIFIState? { nil }
    func registerMyInterface(_ name: String?) {}
    func tailscaleHostname() -> String { "" }
    func send(_ notification: LibboxNotification?) throws {}
    func cancelNotification(_ identifier: String?, typeID: Int32) throws {}
    func startNeighborMonitor(_ listener: (any LibboxNeighborUpdateListenerProtocol)?) throws {}
    func closeNeighborMonitor(_ listener: (any LibboxNeighborUpdateListenerProtocol)?) throws {}

    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32,
                             destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner {
        throw Self.failure("process lookup is not available on iOS")
    }

    func createBridge(_ options: LibboxBridgeOptions?) throws -> any LibboxBridgeSessionProtocol {
        throw Self.failure("bridges are not available on iOS")
    }

    func checkPlatformShell() throws {
        throw Self.failure("shell is not available on iOS")
    }

    func lookupUser(_ username: String?) throws -> LibboxPlatformUser {
        throw Self.failure("users are not available on iOS")
    }

    func openShellSession(_ user: LibboxPlatformUser?, command: String?, environ: (any LibboxStringIteratorProtocol)?,
                          term: String?, rows: Int32, cols: Int32) throws -> any LibboxShellSessionProtocol {
        throw Self.failure("shell is not available on iOS")
    }

    func readSystemSSHHostKey(_ error: NSErrorPointer) -> String {
        error?.pointee = Self.failure("SSH is not available on iOS")
        return ""
    }

    func lookupSFTPServer(_ error: NSErrorPointer) -> String {
        error?.pointee = Self.failure("SFTP is not available on iOS")
        return ""
    }

    // MARK: Helpers

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Nox.PlatformInterface", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func strings(_ iterator: (any LibboxStringIteratorProtocol)?) -> [String] {
        guard let iterator else { return [] }
        var out: [String] = []
        while iterator.hasNext() { out.append(iterator.next()) }
        return out
    }

    private static func prefixes(_ iterator: (any LibboxRoutePrefixIteratorProtocol)?) -> [LibboxRoutePrefix] {
        guard let iterator else { return [] }
        var out: [LibboxRoutePrefix] = []
        while iterator.hasNext() {
            if let prefix = iterator.next() { out.append(prefix) }
        }
        return out
    }
}

private final class InterfaceList: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    private var iterator: IndexingIterator<[LibboxNetworkInterface]>
    private var current: LibboxNetworkInterface?

    init(_ list: [LibboxNetworkInterface]) {
        iterator = list.makeIterator()
    }

    func hasNext() -> Bool {
        current = iterator.next()
        return current != nil
    }

    func next() -> LibboxNetworkInterface? { current }
}

/// True exactly once (first path update) across concurrent callbacks.
private final class Once: @unchecked Sendable {
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
