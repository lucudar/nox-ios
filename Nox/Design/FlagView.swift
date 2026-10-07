import SwiftUI

/// Round vector flag with a soft gloss. Unknown codes fall back to the system emoji.
struct FlagView: View {
    let code: String
    var size: CGFloat = 30

    var body: some View {
        let upper = code.uppercased()
        ZStack {
            if FlagPainter.supports(upper) {
                Canvas { ctx, canvasSize in
                    FlagPainter.draw(upper, &ctx, min(canvasSize.width, canvasSize.height))
                }
            } else {
                Color(white: 0.16)
                Text(Countries.flagEmoji(upper))
                    .font(.system(size: size * 1.32))
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(FlagGloss())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        .accessibilityLabel(Countries.name(upper, L10n.lang) ?? upper)
    }
}

struct FlagGloss: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(stops: [
                .init(color: Color.white.opacity(0.22), location: 0),
                .init(color: Color.white.opacity(0.04), location: 0.42),
                .init(color: Color.black.opacity(0), location: 0.6),
                .init(color: Color.black.opacity(0.16), location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }
}

/// Auto · home · unknown-country discs in the same style as the flags.
struct BadgeDisc: View {
    enum Kind { case auto, home, globe }

    let kind: Kind
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(Color.white.opacity(kind == .globe ? 0.8 : 1))
        }
        .frame(width: size, height: size)
        .overlay(FlagGloss().opacity(0.6))
        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
    }

    private var colors: [Color] {
        switch kind {
        case .auto: return [RGB(hex: 0xFBC34F).color, RGB(hex: 0xF29A0E).color]
        case .home: return [RGB(hex: 0x5ED898).color, RGB(hex: 0x2BAA66).color]
        case .globe: return [RGB(hex: 0x4A4B4E).color, RGB(hex: 0x2C2D30).color]
        }
    }

    private var symbol: String {
        switch kind {
        case .auto: return "bolt"
        case .home: return "house"
        case .globe: return "globe"
        }
    }
}

/// Flag, home disc or globe for a server.
struct ServerAvatar: View {
    let server: Server
    var size: CGFloat = 30

    var body: some View {
        if server.badge == .home {
            BadgeDisc(kind: .home, size: size)
        } else if server.badge == .globe || server.countryCode.isEmpty {
            BadgeDisc(kind: .globe, size: size)
        } else {
            FlagView(code: server.countryCode, size: size)
        }
    }
}

// MARK: - Painters (unit square, cropped to a circle by the view)

enum FlagPainter {
    private static let horizontal: [String: ([UInt32], [CGFloat]?)] = [
        "NL": ([0xAE1C28, 0xFFFFFF, 0x21468B], nil),
        "DE": ([0x000000, 0xDD0000, 0xFFCE00], nil),
        "AT": ([0xC8102E, 0xFFFFFF, 0xC8102E], nil),
        "HU": ([0xCD2A3E, 0xFFFFFF, 0x436F4D], nil),
        "BG": ([0xFFFFFF, 0x00966E, 0xD62612], nil),
        "RU": ([0xFFFFFF, 0x0039A6, 0xD52B1E], nil),
        "LV": ([0x9E3039, 0xFFFFFF, 0x9E3039], [2, 1, 2]),
        "LT": ([0xFDB913, 0x006A44, 0xC1272D], nil),
        "EE": ([0x0072CE, 0x000000, 0xFFFFFF], nil),
        "UA": ([0x0057B7, 0xFFD700], nil),
        "AM": ([0xD90012, 0x0033A0, 0xF2A800], nil),
        "LU": ([0xEF3340, 0xFFFFFF, 0x00A3E0], nil),
        "ID": ([0xCE1126, 0xFFFFFF], nil),
        "PL": ([0xFFFFFF, 0xDC143C], nil),
        "ES": ([0xAA151B, 0xF1BF00, 0xAA151B], [1, 2, 1]),
        "RS": ([0xC6363C, 0x0C4076, 0xFFFFFF], nil),
        "TH": ([0xA51931, 0xF4F5F8, 0x2D2A4A, 0xF4F5F8, 0xA51931], [1, 1, 2, 1, 1]),
        "AR": ([0x74ACDF, 0xFFFFFF, 0x74ACDF], nil),
        "IN": ([0xFF9933, 0xFFFFFF, 0x138808], nil),
        "AZ": ([0x00B5E2, 0xEF3340, 0x509E2F], nil),
        "UZ": ([0x0099B5, 0xCE1126, 0xFFFFFF, 0xCE1126, 0x1EB53A], [10, 0.7, 8.6, 0.7, 10]),
        "BY": ([0xC8313E, 0x4AA657], [2, 1]),
    ]

    private static let vertical: [String: ([UInt32], [CGFloat]?)] = [
        "FR": ([0x0055A4, 0xFFFFFF, 0xEF4135], nil),
        "IT": ([0x009246, 0xFFFFFF, 0xCE2B37], nil),
        "IE": ([0x169B62, 0xFFFFFF, 0xFF883E], nil),
        "BE": ([0x000000, 0xFDDA24, 0xEF3340], nil),
        "RO": ([0x002B7F, 0xFCD116, 0xCE1126], nil),
        "MD": ([0x0046AE, 0xFFD200, 0xCC092F], nil),
        "MX": ([0x006847, 0xFFFFFF, 0xCE1126], nil),
        "CA": ([0xD52B1E, 0xFFFFFF, 0xD52B1E], [1, 2, 1]),
        "PT": ([0x006600, 0xFF0000], [2, 3]),
    ]

    /// background, cross, inner cross
    private static let nordic: [String: (UInt32, UInt32, UInt32?)] = [
        "FI": (0xFFFFFF, 0x002F6C, nil),
        "SE": (0x006AA7, 0xFECC00, nil),
        "DK": (0xC8102E, 0xFFFFFF, nil),
        "NO": (0xBA0C2F, 0xFFFFFF, 0x00205B),
        "IS": (0x02529C, 0xFFFFFF, 0xDC1E35),
    ]

    private static let custom: Set<String> = [
        "JP", "TR", "US", "KZ", "GB", "CH", "CZ", "GR", "CY", "GE", "KG", "IL", "AE", "SG", "HK", "TW",
        "KR", "CN", "VN", "MY", "AU", "BR", "ZA",
    ]

    static func supports(_ code: String) -> Bool {
        horizontal[code] != nil || vertical[code] != nil || nordic[code] != nil || custom.contains(code)
    }

    static func draw(_ code: String, _ ctx: inout GraphicsContext, _ s: CGFloat) {
        if let entry = horizontal[code] {
            stripes(&ctx, s, entry.0, entry.1, vertical: false)
            decorate(code, &ctx, s)
            return
        }
        if let entry = vertical[code] {
            stripes(&ctx, s, entry.0, entry.1, vertical: true)
            decorate(code, &ctx, s)
            return
        }
        if let entry = nordic[code] {
            nordicCross(&ctx, s, entry.0, entry.1, entry.2)
            return
        }
        drawCustom(code, &ctx, s)
    }

    // MARK: Primitives

    private static func c(_ hex: UInt32) -> GraphicsContext.Shading { .color(RGB(hex: hex).color) }

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ s: CGFloat) -> Path {
        Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s))
    }

    private static func pt(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

    private static func poly(_ points: [(CGFloat, CGFloat)], _ s: CGFloat) -> Path {
        var path = Path()
        for (i, p) in points.enumerated() {
            if i == 0 { path.move(to: pt(p.0, p.1, s)) } else { path.addLine(to: pt(p.0, p.1, s)) }
        }
        path.closeSubpath()
        return path
    }

    private static func fill(_ ctx: inout GraphicsContext, _ s: CGFloat, _ hex: UInt32) {
        ctx.fill(rect(0, 0, 1, 1, s), with: c(hex))
    }

    private static func stripes(_ ctx: inout GraphicsContext, _ s: CGFloat, _ colors: [UInt32], _ weights: [CGFloat]?, vertical: Bool) {
        let w = weights ?? Array(repeating: 1, count: colors.count)
        let total = w.reduce(0, +)
        var offset: CGFloat = 0
        for (i, hex) in colors.enumerated() {
            let part = w[i] / total
            let extra: CGFloat = i == colors.count - 1 ? 0 : 0.6 / s
            let r = vertical ? rect(offset, 0, part + extra, 1, s) : rect(0, offset, 1, part + extra, s)
            ctx.fill(r, with: c(hex))
            offset += part
        }
    }

    private static func nordicCross(_ ctx: inout GraphicsContext, _ s: CGFloat, _ bg: UInt32, _ cross: UInt32, _ inner: UInt32?) {
        fill(&ctx, s, bg)
        let cx: CGFloat = 0.38
        let wide: CGFloat = inner == nil ? 0.2 : 0.26
        ctx.fill(rect(cx - wide / 2, 0, wide, 1, s), with: c(cross))
        ctx.fill(rect(0, 0.5 - wide / 2, 1, wide, s), with: c(cross))
        if let inner {
            let thin: CGFloat = 0.12
            ctx.fill(rect(cx - thin / 2, 0, thin, 1, s), with: c(inner))
            ctx.fill(rect(0, 0.5 - thin / 2, 1, thin, s), with: c(inner))
        }
    }

    private static func crescent(_ ctx: inout GraphicsContext, _ s: CGFloat, center: CGPoint, r: CGFloat, cut: CGPoint, cutR: CGFloat, color: UInt32, bg: UInt32) {
        ctx.fill(Geo.circle(pt(center.x, center.y, s), r * s), with: c(color))
        ctx.fill(Geo.circle(pt(cut.x, cut.y, s), cutR * s), with: c(bg))
    }

    private static func star(_ ctx: inout GraphicsContext, _ s: CGFloat, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ hex: UInt32,
                             points: Int = 5, inner: CGFloat = 0.382, rotation: Double = -Double.pi / 2) {
        ctx.fill(Geo.star(pt(x, y, s), r * s, points: points, inner: inner, rotation: rotation), with: c(hex))
    }

    private static func sun(_ ctx: inout GraphicsContext, _ s: CGFloat, _ x: CGFloat, _ y: CGFloat, disc: CGFloat, rays: CGFloat, count: Int, _ hex: UInt32) {
        star(&ctx, s, x, y, rays, hex, points: count, inner: disc / rays * 1.05)
        ctx.fill(Geo.circle(pt(x, y, s), disc * s), with: c(hex))
    }

    // MARK: Emblems on striped flags

    private static func decorate(_ code: String, _ ctx: inout GraphicsContext, _ s: CGFloat) {
        switch code {
        case "IN":
            let center = pt(0.5, 0.5, s)
            let r = 0.105 * s
            let navy = c(0x000080)
            ctx.stroke(Geo.circle(center, r), with: navy, lineWidth: max(0.6, 0.016 * s))
            var spokes = Path()
            for i in 0..<24 {
                spokes.move(to: center)
                spokes.addLine(to: Geo.point(center, r, Double(i) * Double.pi / 12))
            }
            ctx.stroke(spokes, with: navy, lineWidth: max(0.3, 0.006 * s))
            ctx.fill(Geo.circle(center, 0.022 * s), with: navy)
        case "AR":
            sun(&ctx, s, 0.5, 0.5, disc: 0.06, rays: 0.11, count: 16, 0xF6B40E)
        case "AZ":
            crescent(&ctx, s, center: CGPoint(x: 0.47, y: 0.5), r: 0.115, cut: CGPoint(x: 0.5, y: 0.5), cutR: 0.095, color: 0xFFFFFF, bg: 0xEF3340)
            star(&ctx, s, 0.6, 0.5, 0.05, 0xFFFFFF, points: 8, inner: 0.5)
        case "UZ":
            crescent(&ctx, s, center: CGPoint(x: 0.26, y: 0.17), r: 0.085, cut: CGPoint(x: 0.29, y: 0.17), cutR: 0.072, color: 0xFFFFFF, bg: 0x0099B5)
            for (x, y) in [(0.4, 0.1), (0.48, 0.1), (0.56, 0.1), (0.4, 0.2), (0.48, 0.2), (0.56, 0.2)] {
                star(&ctx, s, x, y, 0.022, 0xFFFFFF)
            }
        case "BY":
            ctx.fill(rect(0, 0, 0.16, 1, s), with: c(0xFFFFFF))
            var pattern = Path()
            var y: CGFloat = 0.04
            while y < 1 {
                pattern.addLines([pt(0.08, y, s), pt(0.13, y + 0.05, s), pt(0.08, y + 0.1, s), pt(0.03, y + 0.05, s), pt(0.08, y, s)])
                y += 0.12
            }
            ctx.stroke(pattern, with: c(0xC8313E), lineWidth: max(0.5, 0.02 * s))
        case "PT":
            let center = pt(0.4, 0.5, s)
            ctx.stroke(Geo.circle(center, 0.15 * s), with: c(0xFFE900), lineWidth: max(0.8, 0.04 * s))
            ctx.fill(Path(roundedRect: CGRect(x: 0.33 * s, y: 0.41 * s, width: 0.14 * s, height: 0.17 * s), cornerRadius: 0.05 * s), with: c(0xFFFFFF))
            ctx.fill(Path(roundedRect: CGRect(x: 0.355 * s, y: 0.435 * s, width: 0.09 * s, height: 0.115 * s), cornerRadius: 0.03 * s), with: c(0x003399))
        case "MX":
            ctx.fill(Geo.circle(pt(0.5, 0.48, s), 0.075 * s), with: c(0x8C5A2B))
            ctx.stroke(Geo.arc(pt(0.5, 0.47, s), 0.11 * s, from: Double.pi * 0.15, to: Double.pi * 0.85), with: c(0x2E7D32), lineWidth: max(0.6, 0.025 * s))
        case "MD":
            ctx.fill(Path(roundedRect: CGRect(x: 0.44 * s, y: 0.4 * s, width: 0.12 * s, height: 0.2 * s), cornerRadius: 0.04 * s), with: c(0x8C5A2B))
        case "CA":
            let leaf: [(CGFloat, CGFloat)] = [
                (0, -1), (0.12, -0.72), (0.3, -0.82), (0.25, -0.35), (0.55, -0.6), (0.5, -0.42), (0.85, -0.5),
                (0.75, -0.2), (0.95, -0.05), (0.5, 0.25), (0.6, 0.45), (0.08, 0.38), (0.08, 0.8), (-0.08, 0.8),
                (-0.08, 0.38), (-0.6, 0.45), (-0.5, 0.25), (-0.95, -0.05), (-0.75, -0.2), (-0.85, -0.5),
                (-0.5, -0.42), (-0.55, -0.6), (-0.25, -0.35), (-0.3, -0.82), (-0.12, -0.72),
            ]
            ctx.fill(poly(leaf.map { (0.5 + $0.0 * 0.2, 0.47 + $0.1 * 0.2) }, s), with: c(0xD52B1E))
        default:
            break
        }
    }

    // MARK: Everything else

    private static func drawCustom(_ code: String, _ ctx: inout GraphicsContext, _ s: CGFloat) {
        switch code {
        case "JP":
            fill(&ctx, s, 0xF7F7F5)
            ctx.fill(Geo.circle(pt(0.5, 0.5, s), 0.3 * s), with: c(0xBC002D))
        case "TR":
            fill(&ctx, s, 0xE30A17)
            crescent(&ctx, s, center: CGPoint(x: 0.4, y: 0.5), r: 0.25, cut: CGPoint(x: 0.46, y: 0.5), cutR: 0.2, color: 0xFFFFFF, bg: 0xE30A17)
            star(&ctx, s, 0.66, 0.5, 0.1, 0xFFFFFF, rotation: Double.pi)
        case "US":
            for i in 0..<13 {
                ctx.fill(rect(0, CGFloat(i) / 13, 1, 1 / 13 + 0.5 / s, s), with: c(i.isMultiple(of: 2) ? 0xB22234 : 0xFFFFFF))
            }
            ctx.fill(rect(0, 0, 0.5, 7 / 13, s), with: c(0x3C3B6E))
            for row in 0..<5 {
                let cols = row.isMultiple(of: 2) ? 4 : 3
                for col in 0..<cols {
                    let x = 0.08 + CGFloat(col) * 0.12 + (row.isMultiple(of: 2) ? 0 : 0.06)
                    let y = 0.07 + CGFloat(row) * 0.1
                    ctx.fill(Geo.circle(pt(x, y, s), 0.022 * s), with: c(0xFFFFFF))
                }
            }
        case "KZ":
            fill(&ctx, s, 0x00AFCA)
            sun(&ctx, s, 0.5, 0.43, disc: 0.13, rays: 0.21, count: 24, 0xFEC50C)
            var wings = Path()
            wings.move(to: pt(0.25, 0.62, s))
            wings.addQuadCurve(to: pt(0.5, 0.7, s), control: pt(0.36, 0.73, s))
            wings.addQuadCurve(to: pt(0.75, 0.62, s), control: pt(0.64, 0.73, s))
            ctx.stroke(wings, with: c(0xFEC50C), style: StrokeStyle(lineWidth: max(1, 0.05 * s), lineCap: .round))
        case "GB":
            unionJack(&ctx, s)
        case "AU":
            fill(&ctx, s, 0x012169)
            var canton = ctx
            canton.clip(to: rect(0, 0, 0.5, 0.5, s))
            canton.scaleBy(x: 0.5, y: 0.5)
            unionJack(&canton, s)
            star(&ctx, s, 0.25, 0.76, 0.1, 0xFFFFFF, points: 7, inner: 0.45)
            for (x, y, r) in [(0.75, 0.18, 0.05), (0.6, 0.44, 0.05), (0.9, 0.38, 0.05), (0.76, 0.8, 0.055), (0.82, 0.56, 0.03)] {
                star(&ctx, s, x, y, r, 0xFFFFFF, points: 7, inner: 0.45)
            }
        case "CH":
            fill(&ctx, s, 0xDA291C)
            ctx.fill(rect(0.4, 0.2, 0.2, 0.6, s), with: c(0xFFFFFF))
            ctx.fill(rect(0.2, 0.4, 0.6, 0.2, s), with: c(0xFFFFFF))
        case "CZ":
            ctx.fill(rect(0, 0, 1, 0.5, s), with: c(0xFFFFFF))
            ctx.fill(rect(0, 0.5, 1, 0.5, s), with: c(0xD7141A))
            ctx.fill(poly([(0, 0), (0.55, 0.5), (0, 1)], s), with: c(0x11457E))
        case "GR":
            for i in 0..<9 {
                ctx.fill(rect(0, CGFloat(i) / 9, 1, 1 / 9 + 0.5 / s, s), with: c(i.isMultiple(of: 2) ? 0x0D5EAF : 0xFFFFFF))
            }
            ctx.fill(rect(0, 0, 0.5, 5 / 9, s), with: c(0x0D5EAF))
            ctx.fill(rect(0.2, 0, 0.11, 5 / 9, s), with: c(0xFFFFFF))
            ctx.fill(rect(0, 2 / 9, 0.5, 1 / 9, s), with: c(0xFFFFFF))
        case "CY":
            fill(&ctx, s, 0xF7F7F5)
            var island = Path()
            island.move(to: pt(0.24, 0.48, s))
            island.addQuadCurve(to: pt(0.62, 0.36, s), control: pt(0.42, 0.34, s))
            island.addQuadCurve(to: pt(0.8, 0.3, s), control: pt(0.72, 0.36, s))
            island.addQuadCurve(to: pt(0.6, 0.52, s), control: pt(0.7, 0.48, s))
            island.addQuadCurve(to: pt(0.24, 0.48, s), control: pt(0.4, 0.6, s))
            ctx.fill(island, with: c(0xD57800))
            ctx.stroke(Geo.arc(pt(0.5, 0.5, s), 0.2 * s, from: Double.pi * 0.25, to: Double.pi * 0.75), with: c(0x4E5B31), lineWidth: max(0.8, 0.035 * s))
        case "GE":
            fill(&ctx, s, 0xFFFFFF)
            ctx.fill(rect(0.42, 0, 0.16, 1, s), with: c(0xFF0000))
            ctx.fill(rect(0, 0.42, 1, 0.16, s), with: c(0xFF0000))
            for (x, y) in [(0.22, 0.22), (0.78, 0.22), (0.22, 0.78), (0.78, 0.78)] {
                ctx.fill(rect(x - 0.025, y - 0.08, 0.05, 0.16, s), with: c(0xFF0000))
                ctx.fill(rect(x - 0.08, y - 0.025, 0.16, 0.05, s), with: c(0xFF0000))
            }
        case "KG":
            fill(&ctx, s, 0xE8112D)
            sun(&ctx, s, 0.5, 0.5, disc: 0.2, rays: 0.32, count: 40, 0xFFEF00)
            ctx.fill(Geo.circle(pt(0.5, 0.5, s), 0.125 * s), with: c(0xE8112D))
            ctx.fill(Geo.circle(pt(0.5, 0.5, s), 0.1 * s), with: c(0xFFEF00))
            var lines = Path()
            for dx in [-0.035, 0.035] as [CGFloat] {
                lines.move(to: pt(0.5 + dx, 0.4, s))
                lines.addLine(to: pt(0.5 + dx, 0.6, s))
                lines.move(to: pt(0.4, 0.5 + dx, s))
                lines.addLine(to: pt(0.6, 0.5 + dx, s))
            }
            ctx.stroke(lines, with: c(0xE8112D), lineWidth: max(0.5, 0.018 * s))
        case "IL":
            fill(&ctx, s, 0xFFFFFF)
            ctx.fill(rect(0, 0.13, 1, 0.12, s), with: c(0x0038B8))
            ctx.fill(rect(0, 0.75, 1, 0.12, s), with: c(0x0038B8))
            let center = pt(0.5, 0.5, s)
            let up = Geo.star(center, 0.17 * s, points: 3, inner: 0.5, rotation: -Double.pi / 2)
            let down = Geo.star(center, 0.17 * s, points: 3, inner: 0.5, rotation: Double.pi / 2)
            ctx.stroke(up, with: c(0x0038B8), lineWidth: max(0.7, 0.03 * s))
            ctx.stroke(down, with: c(0x0038B8), lineWidth: max(0.7, 0.03 * s))
        case "AE":
            ctx.fill(rect(0, 0, 1, 1 / 3 + 0.5 / s, s), with: c(0x00732F))
            ctx.fill(rect(0, 1 / 3, 1, 1 / 3 + 0.5 / s, s), with: c(0xFFFFFF))
            ctx.fill(rect(0, 2 / 3, 1, 1 / 3, s), with: c(0x000000))
            ctx.fill(rect(0, 0, 0.28, 1, s), with: c(0xFF0000))
        case "SG":
            ctx.fill(rect(0, 0, 1, 0.5, s), with: c(0xEF3340))
            ctx.fill(rect(0, 0.5, 1, 0.5, s), with: c(0xFFFFFF))
            crescent(&ctx, s, center: CGPoint(x: 0.28, y: 0.26), r: 0.15, cut: CGPoint(x: 0.33, y: 0.26), cutR: 0.13, color: 0xFFFFFF, bg: 0xEF3340)
            for i in 0..<5 {
                let p = Geo.point(CGPoint(x: 0.42, y: 0.26), 0.075, -Double.pi / 2 + Double(i) * 2 * Double.pi / 5)
                star(&ctx, s, p.x, p.y, 0.028, 0xFFFFFF)
            }
        case "HK":
            fill(&ctx, s, 0xDE2910)
            let center = pt(0.5, 0.5, s)
            for i in 0..<5 {
                var petal = ctx
                petal.translateBy(x: center.x, y: center.y)
                petal.rotate(by: .radians(Double(i) * 2 * Double.pi / 5))
                petal.fill(Path(ellipseIn: CGRect(x: -0.055 * s, y: -0.29 * s, width: 0.13 * s, height: 0.24 * s)), with: c(0xFFFFFF))
            }
        case "TW":
            fill(&ctx, s, 0xFE0000)
            ctx.fill(rect(0, 0, 0.5, 0.5, s), with: c(0x000095))
            star(&ctx, s, 0.25, 0.25, 0.17, 0xFFFFFF, points: 12, inner: 0.6)
            ctx.fill(Geo.circle(pt(0.25, 0.25, s), 0.095 * s), with: c(0x000095))
            ctx.fill(Geo.circle(pt(0.25, 0.25, s), 0.08 * s), with: c(0xFFFFFF))
        case "KR":
            fill(&ctx, s, 0xFFFFFF)
            var g = ctx
            g.translateBy(x: 0.5 * s, y: 0.5 * s)
            g.rotate(by: .radians(atan2(2.0, 3.0)))
            let r = 0.22 * s
            g.fill(Path(CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)).intersection(Geo.circle(.zero, r)), with: c(0x0047A0))
            g.fill(Path(CGRect(x: -r, y: -r, width: 2 * r, height: r)).intersection(Geo.circle(.zero, r)), with: c(0xCD2E3A))
            g.fill(Geo.circle(CGPoint(x: -r / 2, y: 0), r / 2), with: c(0xCD2E3A))
            g.fill(Geo.circle(CGPoint(x: r / 2, y: 0), r / 2), with: c(0x0047A0))
            let a = atan2(2.0, 3.0)
            for direction in [-Double.pi + a, -a, a, Double.pi - a] {
                var t = ctx
                t.translateBy(x: 0.5 * s, y: 0.5 * s)
                t.rotate(by: .radians(direction + Double.pi / 2))
                for k in 0..<3 {
                    t.fill(Path(CGRect(x: -0.07 * s, y: -(0.33 + CGFloat(k) * 0.045) * s, width: 0.14 * s, height: 0.025 * s)), with: c(0x000000))
                }
            }
        case "CN":
            fill(&ctx, s, 0xDE2910)
            star(&ctx, s, 0.27, 0.32, 0.15, 0xFFDE00)
            for (x, y) in [(0.45, 0.15), (0.53, 0.25), (0.53, 0.39), (0.45, 0.49)] as [(CGFloat, CGFloat)] {
                star(&ctx, s, x, y, 0.05, 0xFFDE00, rotation: atan2(Double(0.32 - y), Double(0.27 - x)))
            }
        case "VN":
            fill(&ctx, s, 0xDA251D)
            star(&ctx, s, 0.5, 0.52, 0.3, 0xFFFF00)
        case "MY":
            for i in 0..<14 {
                ctx.fill(rect(0, CGFloat(i) / 14, 1, 1 / 14 + 0.5 / s, s), with: c(i.isMultiple(of: 2) ? 0xCC0001 : 0xFFFFFF))
            }
            ctx.fill(rect(0, 0, 0.55, 8 / 14, s), with: c(0x010066))
            crescent(&ctx, s, center: CGPoint(x: 0.22, y: 0.29), r: 0.15, cut: CGPoint(x: 0.27, y: 0.29), cutR: 0.125, color: 0xFFCC00, bg: 0x010066)
            star(&ctx, s, 0.39, 0.29, 0.09, 0xFFCC00, points: 14, inner: 0.45)
        case "BR":
            fill(&ctx, s, 0x009C3B)
            ctx.fill(poly([(0.5, 0.13), (0.93, 0.5), (0.5, 0.87), (0.07, 0.5)], s), with: c(0xFEDF00))
            let disc = Geo.circle(pt(0.5, 0.5, s), 0.21 * s)
            ctx.fill(disc, with: c(0x002776))
            var band = ctx
            band.clip(to: disc)
            var arc = Path()
            arc.move(to: pt(0.27, 0.44, s))
            arc.addQuadCurve(to: pt(0.74, 0.56, s), control: pt(0.5, 0.38, s))
            band.stroke(arc, with: c(0xFFFFFF), lineWidth: max(0.8, 0.04 * s))
        case "ZA":
            ctx.fill(rect(0, 0, 1, 0.5, s), with: c(0xE03C31))
            ctx.fill(rect(0, 0.5, 1, 0.5, s), with: c(0x001489))
            var y = Path()
            y.move(to: pt(-0.05, -0.05, s))
            y.addLine(to: pt(0.42, 0.5, s))
            y.addLine(to: pt(1.05, 0.5, s))
            y.move(to: pt(-0.05, 1.05, s))
            y.addLine(to: pt(0.42, 0.5, s))
            ctx.stroke(y, with: c(0xFFFFFF), style: StrokeStyle(lineWidth: 0.32 * s, lineJoin: .miter))
            ctx.stroke(y, with: c(0x007749), style: StrokeStyle(lineWidth: 0.2 * s, lineJoin: .miter))
            ctx.fill(poly([(0, 0.14), (0.36, 0.5), (0, 0.86)], s), with: c(0xFFB81C))
            ctx.fill(poly([(0, 0.22), (0.28, 0.5), (0, 0.78)], s), with: c(0x000000))
        default:
            fill(&ctx, s, 0x2C2D30)
        }
    }

    private static func unionJack(_ ctx: inout GraphicsContext, _ s: CGFloat) {
        fill(&ctx, s, 0x012169)
        var diagonals = Path()
        diagonals.move(to: pt(0, 0, s))
        diagonals.addLine(to: pt(1, 1, s))
        diagonals.move(to: pt(1, 0, s))
        diagonals.addLine(to: pt(0, 1, s))
        ctx.stroke(diagonals, with: c(0xFFFFFF), lineWidth: 0.2 * s)
        ctx.stroke(diagonals, with: c(0xC8102E), lineWidth: 0.07 * s)
        ctx.fill(rect(0.4, 0, 0.2, 1, s), with: c(0xFFFFFF))
        ctx.fill(rect(0, 0.4, 1, 0.2, s), with: c(0xFFFFFF))
        ctx.fill(rect(0.44, 0, 0.12, 1, s), with: c(0xC8102E))
        ctx.fill(rect(0, 0.44, 1, 0.12, s), with: c(0xC8102E))
    }
}
