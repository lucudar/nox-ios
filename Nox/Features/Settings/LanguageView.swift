import SwiftUI

struct LanguageView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Screen(title: settings.t("Язык", "Language")) {
            GroupCard {
                ForEach(Array(Lang.allCases.enumerated()), id: \.element) { index, lang in
                    if index > 0 { RowDivider(leading: 16) }
                    CheckRow(title: lang.nativeName,
                             subtitle: lang == .ru ? settings.t("Русский", "Russian") : settings.t("Английский", "English"),
                             selected: settings.lang == lang) {
                        guard settings.lang != lang else { return }
                        Haptics.select()
                        withAnimation(Motion.quick) { settings.prefs.language = lang }
                    }
                }
            }
        }
    }
}
