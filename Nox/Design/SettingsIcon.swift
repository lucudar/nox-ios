import SwiftUI

/// Settings rows that have an icon. The look depends on Appearance → Icon style.
enum SettingsGlyph: CaseIterable {
    case mode, killSwitch, autoConnect, routes, dns, appearance, language, stats, logs

    /// SF Symbol; nil → the ">_" text glyph.
    var symbol: String? {
        switch self {
        case .mode: return "point.topleft.down.to.point.bottomright.curvepath"
        case .killSwitch: return "shield"
        case .autoConnect: return "bolt"
        case .routes: return "line.3.horizontal.decrease"
        case .dns: return "network"
        case .appearance: return "paintpalette"
        case .language: return "translate"
        case .stats: return "chart.bar.xaxis"
        case .logs: return nil
        }
    }

    /// Tile colour (like iOS Settings).
    var tile: RGB {
        switch self {
        case .mode: return RGB(hex: 0x3D8BFF)
        case .killSwitch: return RGB(hex: 0xFF4D45)
        case .autoConnect: return RGB(hex: 0x34C66A)
        case .routes: return RGB(hex: 0xFF9F1A)
        case .dns: return RGB(hex: 0x2FC2C9)
        case .appearance: return RGB(hex: 0xB264F0)
        case .language: return RGB(hex: 0x4DB5FF)
        case .stats: return RGB(hex: 0x6366F1)
        case .logs: return RGB(hex: 0x6B6E73)
        }
    }

    var emoji: String {
        switch self {
        case .mode: return "🧭"
        case .killSwitch: return "🛡️"
        case .autoConnect: return "⚡️"
        case .routes: return "📋"
        case .dns: return "📡"
        case .appearance: return "🎨"
        case .language: return "🌍"
        case .stats: return "📊"
        case .logs: return "🧾"
        }
    }
}

struct SettingsIcon: View {
    let glyph: SettingsGlyph
    /// Overrides the setting (style picker previews).
    var style: IconStyle? = nil

    @Environment(AppSettings.self) private var settings

    var body: some View {
        switch style ?? settings.look.iconStyle {
        case .line:
            symbol(size: 19, weight: .light)
                .foregroundStyle(settings.accentColor)
                .frame(width: 28, height: 28)
        case .tiles:
            symbol(size: 15, weight: .semibold)
                .foregroundStyle(Color.white)
                .frame(width: 29, height: 29)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [glyph.tile.lighter(0.14).color, glyph.tile.darker(0.06).color],
                                             startPoint: .top, endPoint: .bottom))
                )
        case .emoji:
            Text(glyph.emoji)
                .font(.system(size: 17))
                .frame(width: 29, height: 29)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
        }
    }

    @ViewBuilder
    private func symbol(size: CGFloat, weight: Font.Weight) -> some View {
        if let name = glyph.symbol {
            Image(systemName: name)
                .font(.system(size: size, weight: weight))
        } else {
            Text(">_")
                .font(.system(size: size * 0.86, weight: weight == .light ? .regular : .bold, design: .monospaced))
        }
    }
}
