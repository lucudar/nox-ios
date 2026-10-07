import SwiftUI
import PhotosUI

struct AppearanceView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BackgroundPhoto.self) private var photo

    @State private var photoItem: PhotosPickerItem?
    @State private var toast: Toast?
    @State private var confirmReset = false
    @State private var renaming: UserPreset?
    @State private var newName = ""

    var body: some View {
        Screen(title: settings.t("Оформление", "Appearance")) {
            VStack(alignment: .leading, spacing: 0) {
                DialView(status: .connected(since: .distantPast), size: 150, interactive: false)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
                    .padding(.bottom, 52)

                presetSection
                SectionDivider()
                accentSection
                SectionDivider()
                themeSection
                SectionDivider()
                backgroundSection
                SectionDivider()
                glowSection
                SectionDivider()
                radiusSection
                SectionDivider()
                animationSection
                SectionDivider()
                fontSection
                SectionDivider()
                iconStyleSection
                SectionDivider()
                appIconSection

                Button {
                    confirmReset = true
                } label: {
                    Text(settings.t("Сбросить", "Reset"))
                        .font(.system(size: 17))
                        .foregroundStyle(Ink.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .padding(.top, 34)
            }
        }
        .toast($toast)
        .onChange(of: photoItem) { _, item in
            load(item)
        }
        .confirmationDialog(settings.t("Сбросить оформление?", "Reset appearance?"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(settings.t("Сбросить", "Reset"), role: .destructive) {
                Haptics.rigid()
                withAnimation(Motion.spring) { settings.resetLook() }
            }
        } message: {
            Text(settings.t("Цвета, тема, фон и шрифт вернутся к базовым. Свои пресеты и иконка останутся.",
                            "Colors, theme, background and font go back to Base. Your presets and the icon stay."))
        }
        .alert(settings.t("Название пресета", "Preset name"), isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField(settings.t("Название", "Name"), text: $newName)
            Button(settings.t("Готово", "Done")) { rename() }
            Button(settings.t("Отмена", "Cancel"), role: .cancel) {}
        }
    }

    // MARK: Preset · accent · theme

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: settings.t("Пресет", "Preset"), value: settings.presetTitle())
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Preset.all) { preset in
                        PresetTile(look: preset.look, title: preset.title(settings.lang),
                                   selected: settings.currentPreset?.id == preset.id) {
                            apply(preset.look)
                        }
                    }
                    ForEach(settings.userPresets) { preset in
                        PresetTile(look: preset.look, title: preset.name,
                                   selected: settings.currentPreset == nil && settings.currentUserPreset?.id == preset.id) {
                            apply(preset.look)
                        }
                        .contextMenu {
                            Button {
                                newName = preset.name
                                renaming = preset
                            } label: {
                                Label(settings.t("Переименовать", "Rename"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                Haptics.rigid()
                                withAnimation(Motion.spring) { settings.deletePreset(preset.id) }
                            } label: {
                                Label(settings.t("Удалить", "Delete"), systemImage: "trash")
                            }
                        }
                    }
                    AddPresetTile(title: settings.t("Сохранить", "Save"), action: savePreset)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -18)
        }
    }

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: settings.t("Акцент", "Accent"),
                          value: Accents.name(for: settings.accent, settings.lang),
                          mono: settings.accent.hexString)
            HStack(spacing: 0) {
                ForEach(Accents.all) { option in
                    AccentDot(rgb: option.rgb, selected: option.rgb.distance(to: settings.accent) < 0.012) {
                        setAccent(option.rgb)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(option.title(settings.lang))
                }
                ColorPicker(settings.t("Свой цвет", "Custom color"), selection: Binding(
                    get: { settings.accent.color },
                    set: { settings.look.accent = RGB($0) }
                ), supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(1.25)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: settings.t("Тема", "Theme"), value: settings.look.theme.title(settings.lang))
            HStack(spacing: 10) {
                ForEach(ThemeID.allCases) { theme in
                    ThemeTile(theme: theme, accent: settings.accent, selected: settings.look.theme == theme) {
                        guard settings.look.theme != theme else { return }
                        Haptics.select()
                        withAnimation(Motion.spring) { settings.look.theme = theme }
                    }
                    .accessibilityLabel(theme.title(settings.lang))
                }
            }
        }
    }

    // MARK: Background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: settings.t("Фон", "Background"), value: settings.look.background.title(settings.lang))
            HStack(spacing: 10) {
                ForEach(BackgroundKind.allCases) { kind in
                    if kind == .photo, photo.image == nil {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            BackgroundTile(kind: kind, selected: false)
                        }
                        .buttonStyle(PressStyle(scale: 0.94))
                        .accessibilityLabel(kind.title(settings.lang))
                    } else {
                        Button {
                            setBackground(kind)
                        } label: {
                            BackgroundTile(kind: kind, selected: settings.look.background == kind)
                        }
                        .buttonStyle(PressStyle(scale: 0.94))
                        .accessibilityLabel(kind.title(settings.lang))
                    }
                }
            }

            if settings.look.background == .photo, photo.image != nil {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledSlider(title: settings.t("Размытие", "Blur"), value: "\(Int(settings.look.photoBlur))",
                                  binding: Bindable(settings).look.photoBlur, range: 0...30, step: 1)
                    LabeledSlider(title: settings.t("Затемнение", "Dim"), value: "\(Int((settings.look.photoDim * 100).rounded()))%",
                                  binding: Bindable(settings).look.photoDim, range: 0...0.85, step: nil)
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(settings.t("Другое фото", "Change photo"), systemImage: "photo")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Ink.primary)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(Capsule().fill(settings.elevatedColor))
                                .overlay(Capsule().strokeBorder(Ink.stroke, lineWidth: 1))
                        }
                        .buttonStyle(PressStyle())
                        Button {
                            Haptics.rigid()
                            withAnimation(Motion.spring) {
                                settings.look.background = .solid
                                photo.clear()
                            }
                        } label: {
                            Text(settings.t("Убрать фото", "Remove photo"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(PingColor.bad.color)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Glow · radius · animation · font

    private var glowSection: some View {
        LabeledSlider(title: settings.t("Свечение", "Glow"), value: "\(Int((settings.look.glow * 100).rounded()))%",
                      binding: Bindable(settings).look.glow, range: 0...1, step: nil, large: true)
    }

    private var radiusSection: some View {
        LabeledSlider(title: settings.t("Скругление", "Corner radius"), value: "\(Int(settings.look.radius)) pt",
                      binding: Bindable(settings).look.radius, range: 8...30, step: 1, large: true)
    }

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: settings.t("Анимация", "Animation"))
            SlidingSegmented(options: DialAnimation.allCases, selection: Binding(
                get: { settings.look.animation },
                set: { settings.look.animation = $0 }
            )) {
                $0.title(settings.lang)
            }
        }
    }

    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: settings.t("Шрифт", "Font"), value: settings.look.font.title)
            HStack(spacing: 10) {
                ForEach(FontChoice.allCases) { font in
                    OptionTile(selected: settings.look.font == font) {
                        guard settings.look.font != font else { return }
                        Haptics.select()
                        withAnimation(Motion.spring) { settings.look.font = font }
                    } content: {
                        Text("Aa")
                            .font(.system(size: 30, design: font.design))
                            .foregroundStyle(Ink.primary)
                        Text(font.short)
                            .font(.system(size: 13, design: font.design))
                            .foregroundStyle(Ink.secondary)
                    }
                }
            }
        }
    }

    private var iconStyleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: settings.t("Значки", "Icons"), value: settings.look.iconStyle.title(settings.lang))
            HStack(spacing: 10) {
                ForEach(IconStyle.allCases) { style in
                    OptionTile(selected: settings.look.iconStyle == style) {
                        guard settings.look.iconStyle != style else { return }
                        Haptics.select()
                        withAnimation(Motion.spring) { settings.look.iconStyle = style }
                    } content: {
                        HStack(spacing: 5) {
                            SettingsIcon(glyph: .mode, style: style)
                            SettingsIcon(glyph: .killSwitch, style: style)
                            SettingsIcon(glyph: .appearance, style: style)
                        }
                        .scaleEffect(0.86)
                        Text(style.title(settings.lang))
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.secondary)
                    }
                }
            }
        }
    }

    private var appIconSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: settings.t("Иконка", "App icon"), value: settings.look.appIcon.title(settings.lang))
            HStack(spacing: 0) {
                ForEach(AppIconChoice.allCases) { choice in
                    let selected = settings.look.appIcon == choice
                    Button {
                        setIcon(choice)
                    } label: {
                        AppIconArt(choice: choice, size: 62)
                            .padding(5)
                            .overlay {
                                RoundedRectangle(cornerRadius: 62 * 0.225 + 5, style: .continuous)
                                    .strokeBorder(settings.accentColor, lineWidth: 2)
                                    .opacity(selected ? 1 : 0)
                            }
                            .scaleEffect(selected ? 1 : 0.94)
                            .animation(Motion.bouncy, value: selected)
                    }
                    .buttonStyle(PressStyle(scale: 0.92))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(choice.title(settings.lang))
                }
            }
        }
    }

    // MARK: Actions

    private func apply(_ look: LookPreset) {
        guard !settings.matches(look) else { return }
        Haptics.select()
        withAnimation(Motion.spring) { settings.apply(look) }
    }

    private func setAccent(_ rgb: RGB) {
        guard rgb.distance(to: settings.accent) >= 0.012 else { return }
        Haptics.select()
        withAnimation(Motion.spring) { settings.look.accent = rgb }
    }

    private func setBackground(_ kind: BackgroundKind) {
        guard settings.look.background != kind else { return }
        Haptics.select()
        withAnimation(Motion.spring) { settings.look.background = kind }
    }

    private func savePreset() {
        if settings.currentPreset != nil || settings.currentUserPreset != nil {
            Haptics.warning()
            toast = Toast(text: settings.t("Такой пресет уже есть", "This preset already exists"), isError: true)
            return
        }
        Haptics.success()
        withAnimation(Motion.spring) { settings.saveCurrentAsPreset() }
        toast = Toast(text: settings.t("Пресет сохранён", "Preset saved"))
    }

    private func rename() {
        guard let target = renaming else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty, let i = settings.userPresets.firstIndex(where: { $0.id == target.id }) else { return }
        settings.userPresets[i].name = name
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            photoItem = nil
            guard let data, photo.set(data) else {
                Haptics.error()
                toast = Toast(text: settings.t("Не удалось открыть фото", "Couldn't open the photo"), isError: true)
                return
            }
            Haptics.success()
            withAnimation(Motion.spring) { settings.look.background = .photo }
        }
    }

    private func setIcon(_ choice: AppIconChoice) {
        guard settings.look.appIcon != choice else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            toast = Toast(text: settings.t("Смена иконки недоступна", "Icon change isn't available"), isError: true)
            return
        }
        Haptics.select()
        let previous = settings.look.appIcon
        settings.look.appIcon = choice
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(choice.iconName)
            } catch {
                settings.look.appIcon = previous
                toast = Toast(text: error.localizedDescription, isError: true)
            }
        }
    }
}

// MARK: - Tiles

private struct PresetTile: View {
    let look: LookPreset
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    NoxBackground(kind: look.background, theme: look.theme, accent: look.accent, compact: true)
                    MiniDial(accent: look.accent, size: 46)
                }
                .frame(width: 86, height: 86)
                .clipShape(shape)
                .overlay(shape.strokeBorder(selected ? look.accent.color : Ink.stroke, lineWidth: selected ? 2 : 1))
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Ink.primary : Ink.secondary)
                    .lineLimit(1)
                    .frame(width: 86)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .animation(Motion.spring, value: selected)
    }
}

private struct AddPresetTile: View {
    let title: String
    let action: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Ink.secondary)
                    .frame(width: 86, height: 86)
                    .background(shape.fill(settings.surfaceColor))
                    .overlay(shape.strokeBorder(Ink.stroke, lineWidth: 1))
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityLabel(title)
    }
}

private struct AccentDot: View {
    let rgb: RGB
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(rgb.color)
                .frame(width: 32, height: 32)
                .padding(4)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2).opacity(selected ? 1 : 0))
                .scaleEffect(selected ? 1 : 0.92)
                .animation(Motion.bouncy, value: selected)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.88))
    }
}

private struct ThemeTile: View {
    let theme: ThemeID
    let accent: RGB
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let palette = theme.palette
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            VStack(spacing: 9) {
                Circle()
                    .fill(palette.elevated.color)
                    .overlay(Circle().strokeBorder(accent.color, lineWidth: 1.5))
                    .frame(width: 22, height: 22)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(palette.elevated.color)
                    .frame(height: 12)
                    .padding(.horizontal, 11)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(shape.fill(palette.surface.color))
            .overlay(shape.strokeBorder(selected ? accent.color : Ink.stroke, lineWidth: selected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .animation(Motion.spring, value: selected)
    }
}

private struct BackgroundTile: View {
    let kind: BackgroundKind
    let selected: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(BackgroundPhoto.self) private var photo

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack {
            if kind == .photo {
                if let image = photo.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .overlay(Color.black.opacity(0.25))
                } else {
                    settings.surfaceColor
                    Image(systemName: "photo")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Ink.secondary)
                }
            } else {
                NoxBackground(kind: kind, compact: true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .clipShape(shape)
        .overlay(shape.strokeBorder(selected ? settings.accentColor : Ink.stroke, lineWidth: selected ? 2 : 1))
        .contentShape(shape)
        .animation(Motion.spring, value: selected)
    }
}

/// Font / icon-style choice: content centered in a tile, accent border when selected.
private struct OptionTile<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: action) {
            VStack(spacing: 4) {
                content()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(shape.fill(settings.surfaceColor))
            .overlay(shape.strokeBorder(selected ? settings.accentColor : Ink.stroke, lineWidth: selected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .animation(Motion.spring, value: selected)
    }
}

/// "Свечение ······ 60%" + slider.
private struct LabeledSlider: View {
    let title: String
    let value: String
    let binding: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double?
    var large = false

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 14 : 8) {
            if large {
                SectionHeader(title: title, value: value)
            } else {
                HStack {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.secondary)
                    Spacer()
                    Text(value)
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.secondary)
                        .monospacedDigit()
                }
            }
            Group {
                if let step {
                    Slider(value: binding, in: range, step: step)
                } else {
                    Slider(value: binding, in: range)
                }
            }
            .tint(settings.accentColor)
        }
    }
}
