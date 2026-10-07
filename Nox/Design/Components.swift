import SwiftUI

// MARK: - Buttons

/// Springy press feedback used across the app.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.66), value: configuration.isPressed)
    }
}

/// 44 pt round button (settings, back, close).
struct CircleButton<Label: View>: View {
    var size: CGFloat = 44
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            CircleChrome(size: size, label: label)
        }
        .buttonStyle(PressStyle(scale: 0.9))
    }
}

/// The round chrome of `CircleButton`, for ShareLink / PhotosPicker labels.
struct CircleChrome<Label: View>: View {
    var size: CGFloat = 44
    @ViewBuilder let label: () -> Label

    @Environment(AppSettings.self) private var settings

    var body: some View {
        label()
            .frame(width: size, height: size)
            .background(Circle().fill(settings.elevatedColor.opacity(0.78)))
            .overlay(Circle().strokeBorder(Ink.stroke, lineWidth: 1))
            .contentShape(Circle())
    }
}

struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    var body: some View {
        CircleButton(action: {
            Haptics.tap()
            dismiss()
        }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.primary)
        }
        .accessibilityLabel(settings.t("Назад", "Back"))
    }
}

// MARK: - Screen scaffold

/// Back button + large title + scrolling content on the themed background.
/// `trailing` goes to the right of the back button (Logs: copy / share / clear).
struct Screen<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    BackButton()
                    Spacer(minLength: 0)
                    trailing()
                }
                .padding(.top, 6)
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Ink.primary)
                    .padding(.top, 16)
                    .padding(.bottom, 22)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background { NoxBackground().ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension Screen where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// Row highlight for NavigationLinks / buttons inside a GroupCard.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
            .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.25), value: configuration.isPressed)
    }
}

/// Full-width hairline between appearance sections.
struct SectionDivider: View {
    var body: some View {
        RowDivider()
            .padding(.vertical, 22)
    }
}

/// "Пресет ······ Базовый"
struct SectionHeader: View {
    let title: String
    var value: String? = nil
    var mono: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Ink.primary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
            if let mono {
                Text(mono)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.secondary)
            }
        }
    }
}

/// Small grey caption above / below groups.
struct Caption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Ink.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Groups & rows

struct GroupCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: settings.radius, style: .continuous)
        VStack(spacing: 0) {
            content()
        }
        .background(shape.fill(settings.surfaceColor))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Ink.stroke, lineWidth: 1))
    }
}

/// Hairline separator, optionally inset from the leading edge.
struct RowDivider: View {
    var leading: CGFloat = 0

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Ink.separator)
            .frame(height: 1 / max(displayScale, 1))
            .padding(.leading, leading)
    }
}

/// Icon (in the chosen style) + title.
struct RowLabel: View {
    let glyph: SettingsGlyph?
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            if let glyph {
                SettingsIcon(glyph: glyph)
            }
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
        }
    }
}

/// Label for a NavigationLink row: icon · title ······ value ›
struct NavRow: View {
    let glyph: SettingsGlyph?
    let title: String
    var value: String? = nil
    var dot: Color? = nil

    var body: some View {
        HStack(spacing: 10) {
            RowLabel(glyph: glyph, title: title)
            Spacer(minLength: 8)
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            if let value {
                Text(value)
                    .font(.system(size: 17))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

struct ToggleRow: View {
    let glyph: SettingsGlyph?
    let title: String
    @Binding var isOn: Bool

    @Environment(AppSettings.self) private var settings

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { value in
            Haptics.select()
            isOn = value
        })) {
            RowLabel(glyph: glyph, title: title)
        }
        .tint(settings.accentColor)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

/// A selectable row with a trailing checkmark (Mode, Language, DNS presets…).
struct CheckRow: View {
    let title: String
    var subtitle: String? = nil
    let selected: Bool
    let action: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17))
                        .foregroundStyle(Ink.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(Ink.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(settings.accentColor)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.bouncy, value: selected)
    }
}

// MARK: - Sliding segmented control

struct SlidingSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    @Namespace private var namespace
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button {
                    guard !isOn else { return }
                    Haptics.select()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isOn ? Ink.primary : Ink.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(settings.elevatedColor)
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ink.stroke, lineWidth: 1))
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(settings.surfaceColor))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Ink.stroke, lineWidth: 1))
    }
}

// MARK: - Shimmer placeholder (ping in flight)

struct ShimmerBar: View {
    var width: CGFloat = 40
    var height: CGFloat = 10
    let tint: Color

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t.truncatingRemainder(dividingBy: 1.25) / 1.25)
            Capsule()
                .fill(tint.opacity(0.2))
                .overlay {
                    LinearGradient(colors: [.clear, tint.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: width * 0.7)
                        .offset(x: (phase * 1.8 - 0.9) * width)
                }
                .clipShape(Capsule())
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Toast

struct Toast: Equatable {
    let id = UUID()
    let text: String
    var isError = false
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastLabel(toast: toast)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 26)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: toast.id) {
                            try? await Task.sleep(nanoseconds: 2_300_000_000)
                            guard !Task.isCancelled else { return }
                            withAnimation(Motion.spring) { self.toast = nil }
                        }
                        .onTapGesture { withAnimation(Motion.spring) { self.toast = nil } }
                }
            }
            .animation(Motion.spring, value: toast?.id)
    }
}

private struct ToastLabel: View {
    let toast: Toast

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? PingColor.bad.color : settings.accentColor)
            Text(toast.text)
                .foregroundStyle(Ink.primary)
                .lineLimit(2)
        }
        .font(.system(size: 15, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(settings.elevatedColor))
        .overlay(Capsule().strokeBorder(Ink.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
