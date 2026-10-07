import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    /// Divider inset: row padding + icon + spacing, so lines start under the titles.
    private let inset: CGFloat = 58

    var body: some View {
        @Bindable var settings = settings
        Screen(title: settings.t("Настройки", "Settings")) {
            VStack(spacing: 18) {
                GroupCard {
                    NavigationLink(value: Route.mode) {
                        NavRow(glyph: .mode, title: settings.t("Режим", "Mode"), value: settings.prefs.mode.title(settings.lang))
                    }
                    .buttonStyle(RowPressStyle())
                    RowDivider(leading: inset)
                    ToggleRow(glyph: .killSwitch, title: "Kill Switch", isOn: $settings.prefs.killSwitch)
                    RowDivider(leading: inset)
                    ToggleRow(glyph: .autoConnect, title: settings.t("Автоподключение", "Auto-connect"), isOn: $settings.prefs.autoConnect)
                }

                GroupCard {
                    NavigationLink(value: Route.routes) {
                        NavRow(glyph: .routes, title: settings.t("Маршруты", "Routes"), value: "\(settings.rules.count)")
                    }
                    .buttonStyle(RowPressStyle())
                    RowDivider(leading: inset)
                    NavigationLink(value: Route.dns) {
                        NavRow(glyph: .dns, title: "DNS", value: settings.prefs.dnsTransport.title)
                    }
                    .buttonStyle(RowPressStyle())
                }

                GroupCard {
                    NavigationLink(value: Route.appearance) {
                        NavRow(glyph: .appearance, title: settings.t("Оформление", "Appearance"), dot: settings.accentColor)
                    }
                    .buttonStyle(RowPressStyle())
                    RowDivider(leading: inset)
                    NavigationLink(value: Route.language) {
                        NavRow(glyph: .language, title: settings.t("Язык", "Language"), value: settings.lang.nativeName)
                    }
                    .buttonStyle(RowPressStyle())
                }

                GroupCard {
                    NavigationLink(value: Route.stats) {
                        NavRow(glyph: .stats, title: settings.t("Статистика", "Statistics"))
                    }
                    .buttonStyle(RowPressStyle())
                    RowDivider(leading: inset)
                    NavigationLink(value: Route.logs) {
                        NavRow(glyph: .logs, title: settings.t("Логи", "Logs"))
                    }
                    .buttonStyle(RowPressStyle())
                }

                Text("Nox \(AppInfo.version)")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5"
    }
}
