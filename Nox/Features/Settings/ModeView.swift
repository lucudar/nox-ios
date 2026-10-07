import SwiftUI

struct ModeView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Screen(title: settings.t("Режим", "Mode")) {
            VStack(alignment: .leading, spacing: 12) {
                GroupCard {
                    ForEach(Array(RoutingMode.allCases.enumerated()), id: \.element) { index, mode in
                        if index > 0 { RowDivider(leading: 16) }
                        CheckRow(title: mode.title(settings.lang),
                                 subtitle: mode.details(settings.lang),
                                 selected: settings.prefs.mode == mode) {
                            guard settings.prefs.mode != mode else { return }
                            Haptics.select()
                            settings.prefs.mode = mode
                        }
                    }
                }
                Caption(text: settings.t("Меняется сразу: активное подключение перезапустится с новым режимом.",
                                         "Applies immediately: an active connection restarts with the new mode."))
                    .padding(.horizontal, 4)
            }
        }
    }
}
