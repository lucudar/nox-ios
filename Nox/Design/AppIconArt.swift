import SwiftUI

/// Colours of the four app icons (the PNGs in Assets were generated with the same values).
struct AppIconSpec {
    let top: RGB
    let bottom: RGB
    let ring: RGB
    let border: RGB
    let borderAlpha: Double
    let glow: Bool

    static func of(_ choice: AppIconChoice) -> AppIconSpec {
        switch choice {
        case .classic:
            return AppIconSpec(top: RGB(hex: 0x1F5A40), bottom: RGB(hex: 0x0D2A1D), ring: RGB(hex: 0xA6EFC6),
                               border: .white, borderAlpha: 0.08, glow: false)
        case .dark:
            return AppIconSpec(top: RGB(hex: 0x141515), bottom: RGB(hex: 0x050505), ring: RGB(hex: 0x4FD08D),
                               border: .white, borderAlpha: 0.08, glow: false)
        case .light:
            return AppIconSpec(top: RGB(hex: 0xF4F5F4), bottom: RGB(hex: 0xBEC3C1), ring: RGB(hex: 0x1C1D1D),
                               border: .white, borderAlpha: 0.2, glow: false)
        case .neon:
            return AppIconSpec(top: RGB(hex: 0x08150F), bottom: RGB(hex: 0x030806), ring: RGB(hex: 0xB5F5D2),
                               border: RGB(hex: 0x4FD08D), borderAlpha: 0.9, glow: true)
        }
    }
}

/// Small rendering of an app icon for the picker.
struct AppIconArt: View {
    let choice: AppIconChoice
    var size: CGFloat = 56

    var body: some View {
        let spec = AppIconSpec.of(choice)
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [spec.top.color, spec.bottom.color], startPoint: .top, endPoint: .bottom))
            if spec.glow {
                RadialGradient(colors: [RGB(hex: 0x4FD08D).color(0.5), .clear], center: .center, startRadius: 0, endRadius: size * 0.45)
            }
            Circle()
                .strokeBorder(spec.ring.color, lineWidth: size * 0.085)
                .frame(width: size * 0.48, height: size * 0.48)
            Circle()
                .fill(spec.ring.color)
                .frame(width: size * 0.16, height: size * 0.16)
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(spec.border.color(spec.borderAlpha), lineWidth: 1))
    }
}
