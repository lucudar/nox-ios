import SwiftUI
import UIKit

/// Themed full-screen background: solid · aurora · dot grid · grain · own photo.
/// `kind` overrides the setting (Appearance tiles); `compact` scales details for small previews.
struct NoxBackground: View {
    var kind: BackgroundKind? = nil
    var theme: ThemeID? = nil
    var accent: RGB? = nil
    var compact = false

    @Environment(AppSettings.self) private var settings
    @Environment(BackgroundPhoto.self) private var photo

    var body: some View {
        let palette = (theme ?? settings.look.theme).palette
        let tint = accent ?? settings.accent
        ZStack {
            palette.bg.color
            switch kind ?? settings.look.background {
            case .solid:
                Color.clear
            case .aurora:
                AuroraLayer(accent: tint, tint: palette.tint)
            case .grid:
                DotGridLayer(accent: tint, spacing: compact ? 8 : 18, dot: compact ? 0.7 : 0.9)
            case .grain:
                GrainLayer(accent: tint)
            case .photo:
                if let image = photo.image {
                    PhotoLayer(image: image, blur: compact ? 2 : settings.look.photoBlur, dim: settings.look.photoDim)
                } else {
                    AuroraLayer(accent: tint, tint: palette.tint)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Soft accent light from the top + a faint counter-glow at the bottom.
struct AuroraLayer: View {
    let accent: RGB
    let tint: RGB

    var body: some View {
        GeometryReader { geo in
            let s = max(geo.size.width, geo.size.height)
            ZStack {
                RadialGradient(colors: [accent.color(0.22), accent.color(0.07), .clear],
                               center: UnitPoint(x: 0.22, y: -0.04), startRadius: 0, endRadius: s * 0.72)
                RadialGradient(colors: [tint.lighter(0.06).color(0.55), .clear],
                               center: UnitPoint(x: 0.95, y: 0.08), startRadius: 0, endRadius: s * 0.5)
                RadialGradient(colors: [accent.color(0.10), .clear],
                               center: UnitPoint(x: 0.82, y: 1.04), startRadius: 0, endRadius: s * 0.55)
            }
        }
    }
}

/// Dot grid drawn once per size, fading towards the bottom.
struct DotGridLayer: View {
    let accent: RGB
    var spacing: CGFloat = 18
    var dot: CGFloat = 0.9

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2))
                    x += spacing
                }
                y += spacing
            }
            ctx.fill(path, with: .color(Color.white.opacity(0.11)))
        }
        .mask(LinearGradient(colors: [.white, .white.opacity(0.35)], startPoint: .top, endPoint: .bottom))
        .overlay(
            RadialGradient(colors: [accent.color(0.12), .clear], center: .top, startRadius: 0, endRadius: 420)
        )
    }
}

/// Film grain: a tiny noise tile repeated over the screen.
struct GrainLayer: View {
    let accent: RGB

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color.white.opacity(0.05), .clear], center: .top, startRadius: 0, endRadius: 460)
            if let image = GrainTexture.image {
                Image(decorative: image, scale: 2)
                    .resizable(resizingMode: .tile)
                    .opacity(0.09)
                    .blendMode(.screen)
            }
        }
    }
}

@MainActor
enum GrainTexture {
    static let image: CGImage? = make(size: 128)

    private static func make(size: Int) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for i in 0..<(size * size) {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let v = UInt8(truncatingIfNeeded: state >> 56)
            pixels[i * 4] = v
            pixels[i * 4 + 1] = v
            pixels[i * 4 + 2] = v
            pixels[i * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// The user's photo: blurred and dimmed so text stays readable.
struct PhotoLayer: View {
    let image: UIImage
    let blur: Double
    let dim: Double

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .blur(radius: blur, opaque: true)
                .overlay(Color.black.opacity(dim))
        }
    }
}
