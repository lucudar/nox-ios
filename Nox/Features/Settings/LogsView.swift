import SwiftUI

struct LogsView: View {
    private enum Source: Hashable, CaseIterable {
        case app, core, openflux

        var file: URL? { self == .openflux ? AppGroup.openFluxLogURL : nil }
    }

    @Environment(AppSettings.self) private var settings
    @Environment(ConnectionManager.self) private var connection

    @State private var source: Source = .app
    @State private var coreLines: [String] = []
    @State private var toast: Toast?
    @State private var confirmClear = false

    var body: some View {
        @Bindable var settings = settings
        Screen(title: settings.t("Логи", "Logs"), trailing: { actions }) {
            VStack(alignment: .leading, spacing: 12) {
                SlidingSegmented(options: sources, selection: $source) { option in
                    switch option {
                    case .app: return settings.t("Приложение", "App")
                    case .core: return settings.t("Ядро", "Core")
                    case .openflux: return "OpenFlux"
                    }
                }
                .padding(.bottom, 8)

                switch source {
                case .app:
                    appLog
                case .core, .openflux:
                    GroupCard {
                        ToggleRow(glyph: nil, title: settings.t("Подробный лог", "Verbose log"), isOn: $settings.prefs.verboseLogs)
                    }
                    Caption(text: source == .core
                            ? settings.t("sing-box пишет предупреждения и ошибки; подробный режим добавляет каждое соединение.",
                                         "sing-box logs warnings and errors; verbose mode adds every connection.")
                            : settings.t("Клиент OpenFlux: подключение к сервису, ответ выходного узла, переподключения; подробный режим добавляет каждое соединение.",
                                         "The OpenFlux client: the service channel, the exit node's answer, reconnects; verbose mode adds every connection."))
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                    coreLog
                }
            }
        }
        .toast($toast)
        .task(id: source) {
            guard source != .app else { return }
            coreLines = []
            while !Task.isCancelled {
                coreLines = Self.lines(AppGroup.logTail(source.file))
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .confirmationDialog(settings.t("Очистить логи?", "Clear logs?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(settings.t("Очистить", "Clear"), role: .destructive) {
                Haptics.rigid()
                withAnimation(Motion.spring) {
                    if source == .app {
                        connection.clearLogs()
                    } else {
                        AppGroup.truncateLog(source.file)
                        coreLines = []
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var appLog: some View {
        if connection.logs.isEmpty {
            Caption(text: settings.t("Пока пусто. Здесь появятся события подключения.",
                                     "Nothing yet. Connection events will show up here."))
                .padding(.horizontal, 4)
        } else {
            GroupCard {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(connection.logs.reversed()) { line in
                        LogRow(line: line)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Caption(text: settings.t("Новые сверху · \(connection.logs.count)", "Newest first · \(connection.logs.count)"))
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var coreLog: some View {
        if coreLines.isEmpty {
            Caption(text: settings.t("Лог ядра появится после подключения.", "The core log shows up after connecting."))
                .padding(.horizontal, 4)
        } else {
            GroupCard {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(coreLines.enumerated().reversed()), id: \.offset) { _, line in
                        CoreLogRow(line: line)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Caption(text: settings.t("Новые сверху · \(coreLines.count)", "Newest first · \(coreLines.count)"))
                .padding(.horizontal, 4)
        }
    }

    /// The OpenFlux tab appears once its client has written a log.
    private var sources: [Source] {
        let flux = FileManager.default.fileExists(atPath: AppGroup.openFluxLogURL.path)
        return flux || source == .openflux ? Source.allCases : [.app, .core]
    }

    private var currentText: String {
        source == .app ? connection.logText : coreLines.joined(separator: "\n")
    }

    private var isEmpty: Bool {
        source == .app ? connection.logs.isEmpty : coreLines.isEmpty
    }

    private var actions: some View {
        HStack(spacing: 10) {
            CircleButton(action: copy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.primary)
            }
            .accessibilityLabel(settings.t("Скопировать", "Copy"))

            ShareLink(item: currentText) {
                CircleChrome {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Ink.primary)
                        .offset(y: -1)
                }
            }
            .buttonStyle(PressStyle(scale: 0.9))
            .accessibilityLabel(settings.t("Поделиться", "Share"))

            CircleButton(action: { confirmClear = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.primary)
            }
            .accessibilityLabel(settings.t("Очистить", "Clear"))
        }
        .disabled(isEmpty)
        .opacity(isEmpty ? 0.45 : 1)
    }

    private func copy() {
        UIPasteboard.general.string = currentText
        Haptics.success()
        toast = Toast(text: settings.t("Логи скопированы", "Logs copied"))
    }

    /// Last 400 non-empty lines.
    private static func lines(_ text: String) -> [String] {
        let all = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        return Array(all.suffix(400))
    }
}

/// A sing-box line: "+0300 2025-10-07 21:00:00 ERROR [id 12ms] outbound/vless[proxy]: …".
private struct CoreLogRow: View {
    let line: String

    var body: some View {
        Text(line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(color)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var color: Color {
        if line.contains(" ERROR ") || line.contains(" FATAL ") || line.contains(" PANIC ") { return PingColor.bad.color }
        if line.contains(" WARN ") { return PingColor.fair.color }
        return Ink.primary.opacity(0.8)
    }
}

private struct LogRow: View {
    let line: LogLine

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        (Text(Self.time.string(from: line.date)).foregroundStyle(Ink.tertiary)
            + Text("  ")
            + Text(line.text).foregroundStyle(color))
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var color: Color {
        switch line.level {
        case .info: return Ink.primary.opacity(0.86)
        case .warn: return PingColor.fair.color
        case .error: return PingColor.bad.color
        }
    }
}
