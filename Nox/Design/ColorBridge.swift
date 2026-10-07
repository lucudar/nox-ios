import SwiftUI
import UIKit

// MARK: - RGB ⇄ SwiftUI

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    func color(_ opacity: Double) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: opacity) }

    /// From a SwiftUI colour (ColorPicker), converted and clamped to sRGB.
    init(_ color: Color) {
        let cg = UIColor(color).cgColor
        var source = cg
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let converted = cg.converted(to: space, intent: .defaultIntent, options: nil) {
            source = converted
        }
        let c = source.components ?? []
        if c.count >= 3 {
            self.init(Double(c[0]).clamped(0, 1), Double(c[1]).clamped(0, 1), Double(c[2]).clamped(0, 1))
        } else {
            let w = Double(c.first ?? 0).clamped(0, 1)
            self.init(w, w, w)
        }
    }
}

// MARK: - Ink (text & hairlines on dark backgrounds)

enum Ink {
    static let primary = Color.white.opacity(0.96)
    static let secondary = Color.white.opacity(0.56)
    static let tertiary = Color.white.opacity(0.34)
    static let stroke = Color.white.opacity(0.07)
    static let separator = Color.white.opacity(0.08)
}

// MARK: - Ping colours: green < 100 ms, amber 100–149, red 150+

enum PingColor {
    static let good = RGB(hex: 0x4FD08D)
    static let fair = RGB(hex: 0xF2B84B)
    static let bad = RGB(hex: 0xF0645A)

    static func rgb(_ ms: Int) -> RGB { ms < 100 ? good : (ms < 150 ? fair : bad) }
    static func color(_ ms: Int) -> Color { rgb(ms).color }
}

// MARK: - Motion

enum Motion {
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let bouncy = Animation.spring(response: 0.34, dampingFraction: 0.68)
    static let quick = Animation.easeOut(duration: 0.22)
}

// MARK: - Settings → SwiftUI values

extension AppSettings {
    var radius: CGFloat { CGFloat(look.radius) }
    var accentColor: Color { look.accent.color }
    var bgColor: Color { palette.bg.color }
    var surfaceColor: Color { palette.surface.color }
    var elevatedColor: Color { palette.elevated.color }

    var fontDesign: Font.Design {
        switch look.font {
        case .pro: return .default
        case .rounded: return .rounded
        case .mono: return .monospaced
        }
    }
}

extension FontChoice {
    var design: Font.Design {
        switch self {
        case .pro: return .default
        case .rounded: return .rounded
        case .mono: return .monospaced
        }
    }
}

extension Server {
    /// Ping to show in lists: the last measurement (demo servers start with their design value).
    var shownPing: Int? { pingFailed ? nil : lastPing }
}
