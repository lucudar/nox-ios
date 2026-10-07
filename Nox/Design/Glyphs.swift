import SwiftUI

/// Geometry helpers. Angles are in radians, 0 = 3 o'clock, growing clockwise (y points down).
enum Geo {
    static func point(_ c: CGPoint, _ r: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: c.x + r * CGFloat(cos(angle)), y: c.y + r * CGFloat(sin(angle)))
    }

    /// Polyline arc from `a0` to `a1` (a1 > a0 → clockwise on screen).
    static func arc(_ c: CGPoint, _ r: CGFloat, from a0: Double, to a1: Double, segments: Int = 48) -> Path {
        var path = Path()
        let n = max(2, segments)
        for i in 0...n {
            let a = a0 + (a1 - a0) * Double(i) / Double(n)
            let p = point(c, r, a)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// Star polygon; the first point looks at `rotation` (−π/2 = up).
    static func star(_ c: CGPoint, _ r: CGFloat, points: Int = 5, inner: CGFloat = 0.382, rotation: Double = -Double.pi / 2) -> Path {
        var path = Path()
        let count = points * 2
        for i in 0..<count {
            let radius = i.isMultiple(of: 2) ? r : r * inner
            let p = point(c, radius, rotation + Double(i) * Double.pi / Double(points))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    static func ease(_ t: Double) -> Double {
        let x = t.clamped(0, 1)
        return x * x * (3 - 2 * x)
    }

    static func easeOut(_ t: Double) -> Double {
        let x = t.clamped(0, 1)
        return 1 - (1 - x) * (1 - x) * (1 - x)
    }

    static func easeIn(_ t: Double) -> Double {
        let x = t.clamped(0, 1)
        return x * x
    }

    /// 0…1 progress of `t` inside the window [a, b].
    static func window(_ t: Double, _ a: Double, _ b: Double) -> Double {
        guard b > a else { return t >= b ? 1 : 0 }
        return ((t - a) / (b - a)).clamped(0, 1)
    }
}

/// Settings button glyph: two lines, a knob on the left of the top one and on the right of the bottom one.
struct SlidersGlyph: View {
    var color: Color = Ink.primary
    var lineWidth: CGFloat = 1.6

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let r = h * 0.2
            let y1 = h * 0.27
            let y2 = h * 0.73
            let k1 = CGPoint(x: w * 0.3, y: y1)
            let k2 = CGPoint(x: w * 0.7, y: y2)
            let inset = lineWidth / 2
            var lines = Path()
            lines.move(to: CGPoint(x: k1.x + r + 1.6, y: y1))
            lines.addLine(to: CGPoint(x: w - inset, y: y1))
            lines.move(to: CGPoint(x: inset, y: y2))
            lines.addLine(to: CGPoint(x: k2.x - r - 1.6, y: y2))
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            ctx.stroke(lines, with: .color(color), style: style)
            ctx.stroke(Geo.circle(k1, r), with: .color(color), style: style)
            ctx.stroke(Geo.circle(k2, r), with: .color(color), style: style)
        }
        .frame(width: 20, height: 16)
        .accessibilityHidden(true)
    }
}

/// Gauge with a needle; the needle swings while pinging.
struct GaugeGlyph: View {
    let color: Color
    let swinging: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !swinging)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let needle = swinging ? -Double.pi / 2 + sin(t * 5.4) * 0.95 : -Double.pi / 2 - 0.55
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height * 0.56)
                let r = min(size.width, size.height) * 0.44
                let style = StrokeStyle(lineWidth: 1.6, lineCap: .round)
                ctx.stroke(Geo.arc(c, r, from: Double.pi * 0.8, to: Double.pi * 2.2), with: .color(color), style: style)
                var hand = Path()
                hand.move(to: c)
                hand.addLine(to: Geo.point(c, r * 0.66, needle))
                ctx.stroke(hand, with: .color(color), style: style)
                ctx.fill(Geo.circle(c, 1.5), with: .color(color))
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
