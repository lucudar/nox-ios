import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    /// Divider inset: row padding + icon + spacing, so lines start under the titles.
    private let inset: CGFloat = 58

    var body: some View {
        @Bindable var settings = settings
        Screen(title: settings.t("Настройки", "Settings")) {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    GroupCard {
                        NavigationLink(value: Route.routing) {
                            NavRow(glyph: .mode, title: settings.t("Маршрутизация", "Routing"), value: settings.prefs.routing.title(settings.lang))
                        }
                        .buttonStyle(RowPressStyle())
                        RowDivider(leading: inset)
                        ToggleRow(glyph: .killSwitch, title: "Kill Switch", isOn: $settings.prefs.killSwitch)
                        RowDivider(leading: inset)
                        ToggleRow(glyph: .autoConnect, title: settings.t("Автоподключение", "Auto-connect"), isOn: $settings.prefs.autoConnect)
                    }
                    Caption(text: settings.t("Kill Switch: пока VPN включён, трафик идёт только через туннель — при обрыве интернет блокируется, а не утекает. Автоподключение: iOS сама поднимает туннель при смене сети, пока вы не отключите его вручную.",
                                             "Kill switch: while the VPN is on, traffic only goes through the tunnel — on a drop it's blocked instead of leaking. Auto-connect: iOS brings the tunnel back on network changes until you disconnect manually."))
                        .padding(.horizontal, 4)
                }

                GroupCard {
                    NavigationLink(value: Route.routes) {
                        NavRow(glyph: .routes, title: settings.t("Свои правила", "Custom rules"), value: "\(settings.rules.count)")
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
