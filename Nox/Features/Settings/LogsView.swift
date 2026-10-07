import SwiftUI

struct LogsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConnectionManager.self) private var connection

    @State private var toast: Toast?
    @State private var confirmClear = false

    var body: some View {
        Screen(title: settings.t("Логи", "Logs"), trailing: { actions }) {
            if connection.logs.isEmpty {
                Caption(text: settings.t("Пока пусто. Здесь появятся события подключения.",
                                         "Nothing yet. Connection events will show up here."))
                    .padding(.horizontal, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
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
        }
        .toast($toast)
        .confirmationDialog(settings.t("Очистить логи?", "Clear logs?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(settings.t("Очистить", "Clear"), role: .destructive) {
                Haptics.rigid()
                withAnimation(Motion.spring) { connection.clearLogs() }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            CircleButton(action: copy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.primary)
            }
            .accessibilityLabel(settings.t("Скопировать", "Copy"))

            ShareLink(item: connection.logText) {
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
        .disabled(connection.logs.isEmpty)
        .opacity(connection.logs.isEmpty ? 0.45 : 1)
    }

    private func copy() {
        UIPasteboard.general.string = connection.logText
        Haptics.success()
        toast = Toast(text: settings.t("Логи скопированы", "Logs copied"))
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
