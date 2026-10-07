import SwiftUI

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
            HStack {
                Spacer()
                CircleButton(action: {
                    Haptics.tap()
                    openSettings()
                }) {
                    SlidersGlyph(color: Ink.primary)
                }
                .accessibilityLabel(settings.t("Настройки", "Settings"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)

            Spacer(minLength: 12)
                .frame(maxHeight: 110)

            DialView(status: connection.status) {
                Haptics.press()
                guard let server = servers.current else {
                    showServers = true
                    return
                }
                connection.toggle(server, options: settings.tunnelOptions)
            }

            StatusBlock()
                .padding(.top, 34)

            Spacer(minLength: 16)

            ServerPill(server: servers.current, auto: servers.autoSelect) {
                Haptics.tap()
                showServers = true
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
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
            connection.reconnect(server, options: settings.tunnelOptions)
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

// MARK: - Status under the dial

private struct StatusBlock: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConnectionManager.self) private var connection

    var body: some View {
        ZStack(alignment: .top) {
            switch connection.status {
            case .disconnected:
                VStack(spacing: 10) {
                    Text(settings.t("Не подключено", "Not connected"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                    if let error = connection.lastError {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(PingColor.bad.color)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
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
        .frame(height: 136, alignment: .top)
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

/// Timer (blurs in), "● Защищено · 185.107.•••.••", live speeds.
private struct ConnectedBlock: View {
    let since: Date

    @Environment(AppSettings.self) private var settings
    @Environment(ConnectionManager.self) private var connection

    @State private var timerShown = false
    @State private var detailsShown = false

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text(Fmt.clock(max(0, context.date.timeIntervalSince(since))))
                    .font(.system(size: 60, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .blur(radius: timerShown ? 0 : 14)
            .opacity(timerShown ? 1 : 0)
            .scaleEffect(timerShown ? 1 : 0.94)

            HStack(spacing: 6) {
                Circle()
                    .fill(settings.accentColor)
                    .frame(width: 7, height: 7)
                Text(settings.t("Защищено", "Protected"))
                    .foregroundStyle(Ink.primary.opacity(0.88))
                Text("·")
                    .foregroundStyle(Ink.tertiary)
                Text(ConnectionManager.masked(connection.ip))
                    .foregroundStyle(Ink.secondary)
            }
            .font(.system(size: 15))
            .opacity(detailsShown ? 1 : 0)
            .offset(y: detailsShown ? 0 : 6)

            HStack(spacing: 24) {
                SpeedLabel(symbol: "arrow.down", value: connection.down)
                SpeedLabel(symbol: "arrow.up", value: connection.up)
            }
            .padding(.top, 8)
            .opacity(detailsShown ? 1 : 0)
            .offset(y: detailsShown ? 0 : 8)
        }
        .onAppear {
            if Date().timeIntervalSince(since) < 2 {
                withAnimation(.easeOut(duration: 0.9).delay(0.35)) { timerShown = true }
                withAnimation(.easeOut(duration: 0.5).delay(1.45)) { detailsShown = true }
            } else {
                timerShown = true
                detailsShown = true
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(settings.accentColor)
            Text(Fmt.dec(value, 1, settings.lang))
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

// MARK: - Server pill

private struct ServerPill: View {
    let server: Server?
    let auto: Bool
    let action: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: settings.radius, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                if let server {
                    ServerAvatar(server: server, size: 38)
                        .overlay(alignment: .bottomTrailing) {
                            if auto {
                                BadgeDisc(kind: .auto, size: 16)
                                    .offset(x: 3, y: 3)
                            }
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(server.displayName(settings.lang))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Ink.primary)
                        Text(subtitle(server))
                            .font(.system(size: 14))
                            .foregroundStyle(Ink.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    PingText(server: server)
                } else {
                    BadgeDisc(kind: .globe, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.t("Нет серверов", "No servers"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Ink.primary)
                        Text(settings.t("Нажмите, чтобы добавить", "Tap to add one"))
                            .font(.system(size: 14))
                            .foregroundStyle(Ink.secondary)
                    }
                    Spacer(minLength: 8)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.tertiary)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .frame(height: 66)
            .background(shape.fill(settings.surfaceColor.opacity(0.94)))
            .overlay(shape.strokeBorder(Ink.stroke, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .accessibilityLabel(server.map { $0.displayName(settings.lang) } ?? settings.t("Выбрать сервер", "Choose server"))
    }

    private func subtitle(_ server: Server) -> String {
        let base = server.subtitle(settings.lang)
        return auto ? settings.t("Авто", "Auto") + " · " + base : base
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
