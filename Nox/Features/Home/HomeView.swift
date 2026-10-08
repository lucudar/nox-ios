import SwiftUI

/// Home: the power button and connection status, the current server, and a bottom bar with
/// Servers and Settings.
struct HomeView: View {
    let openSettings: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(ServerStore.self) private var servers
    @Environment(ConnectionManager.self) private var connection
    @Environment(StatsStore.self) private var stats
    @Environment(BackgroundPhoto.self) private var photo

    @State private var showServers = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            PowerButton(status: connection.status, dimmed: servers.isEmpty) {
                Haptics.press()
                guard let server = servers.current else {
                    showServers = true
                    return
                }
                connection.toggle(server, options: settings.tunnelOptions)
            }

            StatusBlock(hasServers: !servers.isEmpty)
                .padding(.top, 40)

            Spacer(minLength: 12)

            if let server = servers.current {
                ServerChip(server: server, auto: servers.autoSelect) {
                    Haptics.tap()
                    showServers = true
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .transition(.opacity)
            }

            BottomBar(onServers: {
                Haptics.tap()
                showServers = true
            }, onSettings: {
                Haptics.tap()
                openSettings()
            })
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { NoxBackground().ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showServers) {
            ServersSheet()
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(38)
                .presentationBackground(settings.surfaceColor)
                .environment(settings)
                .environment(servers)
                .environment(connection)
                .environment(stats)
                .environment(photo)
                .tint(settings.accentColor)
                .fontDesign(settings.fontDesign)
                .preferredColorScheme(.dark)
        }
        .onChange(of: servers.current?.id) { _, _ in
            guard connection.isActive, let server = servers.current else { return }
            connection.switchServer(server, options: settings.tunnelOptions)
        }
        .onChange(of: connection.status) { _, newValue in
            switch newValue {
            case .connected: Haptics.success()
            case .disconnected: if connection.lastError != nil { Haptics.error() }
            default: break
            }
        }
    }
}

// MARK: - Status under the button

private struct StatusBlock: View {
    let hasServers: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(ConnectionManager.self) private var connection

    var body: some View {
        ZStack(alignment: .top) {
            switch connection.status {
            case .disconnected:
                VStack(spacing: 10) {
                    Text(hasServers ? settings.t("Не подключено", "Not connected") : settings.t("Добавьте сервер", "Add a server"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                    if let error = connection.lastError {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(PingColor.bad.color)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .padding(.horizontal, 36)
                    } else if !hasServers {
                        Text(settings.t("Ссылка, QR-код, файл конфигурации или подписка — в разделе «Серверы»",
                                        "A link, QR code, config file or subscription — in Servers"))
                            .font(.system(size: 15))
                            .foregroundStyle(Ink.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 44)
                    }
                }
                .transition(.opacity)
            case .connecting:
                VStack(spacing: 12) {
                    ConnectingTitle(title: settings.t("Подключение", "Connecting"))
                    Text(connection.server?.protoTitle ?? "")
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.secondary)
                }
                .transition(.opacity)
            case .connected(let since):
                ConnectedBlock(since: since)
                    .transition(.opacity)
            case .disconnecting:
                Text(settings.t("Отключение…", "Disconnecting…"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Ink.secondary)
                    .transition(.opacity)
            }
        }
        .frame(height: 132, alignment: .top)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.3), value: connection.status.key)
    }
}

/// "Подключение" with dots that fill in one by one (fixed width, no jitter).
private struct ConnectingTitle: View {
    let title: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 4
            HStack(spacing: 0) {
                Text(title)
                ForEach(0..<3, id: \.self) { i in
                    Text(".").opacity(i < step ? 1 : 0.2)
                }
            }
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Ink.primary)
        }
    }
}

/// Timer, "● Защищено · 185.107.•••.••", live speed and latency.
private struct ConnectedBlock: View {
    let since: Date

    @Environment(AppSettings.self) private var settings
    @Environment(ConnectionManager.self) private var connection

    @State private var shown = false

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text(Fmt.clock(max(0, context.date.timeIntervalSince(since))))
                    .font(.system(size: 52, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(settings.accentColor)
                    .frame(width: 6, height: 6)
                Text(settings.t("Защищено", "Protected"))
                    .foregroundStyle(Ink.primary.opacity(0.88))
                if !connection.ip.isEmpty {
                    Text("·")
                        .foregroundStyle(Ink.tertiary)
                    if !connection.exitCountry.isEmpty {
                        FlagView(code: connection.exitCountry, size: 14)
                    }
                    Text(ConnectionManager.masked(connection.ip))
                        .foregroundStyle(Ink.secondary)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 15))
            .animation(Motion.quick, value: connection.ip)

            HStack(spacing: 20) {
                SpeedLabel(symbol: "arrow.down", value: connection.down)
                SpeedLabel(symbol: "arrow.up", value: connection.up)
                if let ms = connection.latency {
                    Text(Fmt.ms(ms, settings.lang))
                        .font(.system(size: 15))
                        .foregroundStyle(PingColor.color(ms))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(ms)))
                }
            }
            .padding(.top, 2)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 6)
        .onAppear {
            if Date().timeIntervalSince(since) < 2 {
                withAnimation(.easeOut(duration: 0.6).delay(0.25)) { shown = true }
            } else {
                shown = true
            }
        }
    }
}

private struct SpeedLabel: View {
    let symbol: String
    let value: Double

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settings.accentColor)
            Text(Fmt.speed(value, settings.lang))
                .foregroundStyle(Ink.primary)
                .contentTransition(.numericText(value: value))
            Text(Fmt.speedUnit(settings.lang))
                .foregroundStyle(Ink.secondary)
        }
        .font(.system(size: 15))
        .monospacedDigit()
        .animation(.snappy, value: value)
    }
}

// MARK: - Current server

/// One line: flag, name, ping. Opens the server list.
private struct ServerChip: View {
    let server: Server
    let auto: Bool
    let action: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ServerAvatar(server: server, size: 24)
                    .overlay(alignment: .bottomTrailing) {
                        if auto {
                            BadgeDisc(kind: .auto, size: 12)
                                .offset(x: 3, y: 3)
                        }
                    }
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                PingText(server: server)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Capsule().fill(settings.surfaceColor.opacity(0.6)))
            .overlay(Capsule().strokeBorder(Ink.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .accessibilityLabel(server.displayName(settings.lang))
    }

    private var title: String {
        let name = server.displayName(settings.lang)
        return auto ? settings.t("Авто", "Auto") + " · " + name : name
    }
}

// MARK: - Bottom bar

private struct BottomBar: View {
    let onServers: () -> Void
    let onSettings: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 10) {
            BarButton(title: settings.t("Серверы", "Servers"), action: onServers) {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .regular))
            }
            BarButton(title: settings.t("Настройки", "Settings"), action: onSettings) {
                SlidersGlyph(color: Ink.primary)
            }
        }
    }
}

private struct BarButton<Icon: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: settings.radius, style: .continuous)
        Button(action: action) {
            HStack(spacing: 9) {
                icon()
                    .foregroundStyle(Ink.primary)
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Ink.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(shape.fill(settings.surfaceColor.opacity(0.92)))
            .overlay(shape.strokeBorder(Ink.stroke, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle(scale: 0.97))
    }
}

/// "38 мс" coloured by latency.
struct PingText: View {
    let server: Server

    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let ms = server.shownPing {
            Text(Fmt.ms(ms, settings.lang))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PingColor.color(ms))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(ms)))
        } else if server.pingFailed {
            Text(settings.t("нет ответа", "timeout"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PingColor.bad.color.opacity(0.85))
        } else {
            Text("—")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ink.tertiary)
        }
    }
}
