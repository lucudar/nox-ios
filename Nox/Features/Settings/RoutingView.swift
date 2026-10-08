import SwiftUI

/// What goes through the VPN: a preset built from curated, auto-updating rule-sets, ad blocking,
/// and the user's own rules on top.
struct RoutingView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Screen(title: settings.t("Маршрутизация", "Routing")) {
            VStack(alignment: .leading, spacing: 12) {
                GroupCard {
                    ForEach(Array(RoutingPreset.allCases.enumerated()), id: \.element) { index, preset in
                        if index > 0 { RowDivider(leading: 54) }
                        PresetRow(preset: preset, selected: settings.prefs.routing == preset) {
                            guard settings.prefs.routing != preset else { return }
                            Haptics.select()
                            settings.prefs.routing = preset
                        }
                    }
                }
                Caption(text: settings.t("Списки сайтов (itdoginfo, runetfreedom, SagerNet) встроены в приложение и обновляются раз в сутки через VPN. Меняется сразу, без переподключения.",
                                         "Site lists (itdoginfo, runetfreedom, SagerNet) ship with the app and refresh daily through the VPN. Applies instantly, without reconnecting."))
                    .padding(.horizontal, 4)

                GroupCard {
                    ToggleRow(glyph: nil, title: settings.t("Блокировать рекламу", "Block ads"), isOn: $settings.prefs.blockAds)
                    RowDivider(leading: 16)
                    NavigationLink(value: Route.routes) {
                        NavRow(glyph: nil, title: settings.t("Свои правила", "Custom rules"),
                               value: settings.rules.isEmpty ? settings.t("нет", "none") : "\(settings.rules.count)")
                    }
                    .buttonStyle(RowPressStyle())
                }
                .padding(.top, 14)
                Caption(text: settings.t("Реклама и трекеры режутся по списку category-ads-all. Свои правила всегда проверяются раньше пресета.",
                                         "Ads and trackers are cut by the category-ads-all list. Your own rules always come before the preset."))
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct PresetRow: View {
    let preset: RoutingPreset
    let selected: Bool
    let action: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(selected ? settings.accentColor : Ink.secondary)
                    .frame(width: 24, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title(settings.lang))
                        .font(.system(size: 17))
                        .foregroundStyle(Ink.primary)
                    Text(preset.details(settings.lang))
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(settings.accentColor)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.6)
                    .frame(height: 22)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.bouncy, value: selected)
    }
}
