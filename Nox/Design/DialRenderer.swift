import SwiftUI

/// Everything the dial needs for one frame. DialView animates these values; previews pass constants.
struct DialState {
    var accent: RGB
    var glow: Double = 0.6
    var ticks = 96
    /// 0…1 share of ticks lit clockwise from 12 o'clock (soft front).
    var sweep: Double = 0
    /// Spark head position (0…1 of a turn) and its comet tail.
    var spark: Double?
    var sparkAlpha: Double = 0
    var tail: Double = 0.34
    /// Thin outer ring and the halo around the core.
    var ring: Double = 0
    var halo: Double = 0
    /// Core colour fill, flash and the outgoing wave.
    var core: Double = 0
    var flash: Double = 0
    var wave: Double?
    /// Reverse wave when switching off.
    var implode: Double?
    /// −1…1 breathing.
    var breath: Double = 0
    /// Tick rotation and highlight angle (radians).
    var rotation: Double = 0
    var sheen: Double = -Double.pi * 0.75
    /// Power glyph: grey → accent, then brighter when connected.
    var power: Double = 0
    var powerBright: Double = 0

    /// Fully connected look (previews and preset tiles).
    static func lit(_ accent: RGB, glow: Double = 0.6, ticks: Int = 96) -> DialState {
        var s = DialState(accent: accent)
        s.glow = glow
        s.ticks = ticks
        s.sweep = 1
        s.core = 1
        s.power = 1
        s.powerBright = 1
        return s
    }
}

enum DialRenderer {
    /// Canvas side relative to the dial: room for glow and the wave.
    static let overscan: CGFloat = 1.6

    static func draw(_ ctx: inout GraphicsContext, _ canvas: CGSize, dial: CGFloat, _ s: DialState) {
        let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let k = dial / 252
        let accent = s.accent
        let tickOuter = 117 * k
        let coreR = 78 * k
        let ringR = 123.5 * k
        let userGlow = 0.25 + 0.75 * s.glow.clamped(0, 1)

        // Ambient glow
        let intensity = (s.core * (0.84 + 0.16 * s.breath) + s.flash * 0.9 + s.sweep * 0.16 + s.sparkAlpha * 0.1) * userGlow
        if intensity > 0.002 {
            let outer = 196 * k
            let g = Gradient(stops: [
                .init(color: accent.color(0.5 * intensity), location: 0),
                .init(color: accent.color(0.2 * intensity), location: 0.42),
                .init(color: accent.color(0.06 * intensity), location: 0.72),
                .init(color: accent.color(0), location: 1),
            ])
            ctx.fill(Geo.circle(c, outer), with: .radialGradient(g, center: c, startRadius: coreR * 0.5, endRadius: outer))
        }

        // Outgoing wave
        if let w = s.wave, w < 1 {
            let r = ringR + CGFloat(w) * 66 * k
            let alpha = pow(1 - w, 1.4)
            ctx.stroke(Geo.circle(c, r), with: .color(accent.color(0.12 * alpha)), lineWidth: 12 * k)
            ctx.stroke(Geo.circle(c, r), with: .color(accent.lighter(0.25).color(0.6 * alpha)), lineWidth: max(0.6, (1.8 - 1.2 * CGFloat(w)) * k))
        }

        // Reverse wave
        if let w = s.implode, w > 0, w < 1 {
            let r = ringR + CGFloat(1 - w) * 42 * k
            ctx.stroke(Geo.circle(c, r), with: .color(accent.color(0.35 * sin(w * Double.pi))), lineWidth: max(0.6, 1.2 * k))
        }

        // Outer ring + halo
        if s.ring > 0.002 {
            ctx.stroke(Geo.circle(c, ringR), with: .color(accent.color(0.55 * s.ring)), lineWidth: max(0.6, 1.2 * k))
        }
        if s.halo > 0.002 {
            ctx.stroke(Geo.circle(c, coreR + 13 * k), with: .color(accent.lighter(0.1).color(0.3 * s.halo)), lineWidth: max(0.6, 1 * k))
        }

        // Ticks
        let n = max(12, s.ticks)
        let majorEvery = max(1, n / 12)
        let litRGB = accent.lighter(0.08)
        for i in 0..<n {
            let f = Double(i) / Double(n)
            let angle = f * 2 * Double.pi - Double.pi / 2 + s.rotation
            let major = i % majorEvery == 0
            let length = (major ? 11.5 : 6.5) * k
            let width = max(0.7, (major ? 1.8 : 1.15) * k)
            var lit = ((s.sweep * 1.06 - f) / 0.06).clamped(0, 1)
            if let head = s.spark, s.sparkAlpha > 0 {
                var d = head - f
                d -= d.rounded(.down)
                if d < s.tail { lit = max(lit, pow(1 - d / s.tail, 1.7) * s.sparkAlpha) }
            }
            let sheen = 0.5 + 0.5 * cos(angle - s.sheen)
            let offAlpha = major ? 0.32 : 0.16
            let litAlpha = (major ? 1.0 : 0.8) * (0.72 + 0.28 * sheen) * (0.92 + 0.08 * s.breath)
            let alpha = offAlpha + (litAlpha - offAlpha) * lit
            let rgb = RGB.white.mix(major ? litRGB.lighter(0.1) : litRGB, lit)
            var p = Path()
            p.move(to: Geo.point(c, tickOuter - length, angle))
            p.addLine(to: Geo.point(c, tickOuter, angle))
            ctx.stroke(p, with: .color(rgb.color(alpha)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }

        // Spark head
        if let head = s.spark, s.sparkAlpha > 0.01 {
            let angle = head * 2 * Double.pi - Double.pi / 2 + s.rotation
            let p = Geo.point(c, tickOuter - 4 * k, angle)
            let glowR = 18 * k
            ctx.fill(Geo.circle(p, glowR), with: .radialGradient(
                Gradient(colors: [accent.lighter(0.4).color(0.75 * s.sparkAlpha), accent.color(0)]),
                center: p, startRadius: 0, endRadius: glowR))
            ctx.fill(Geo.circle(p, max(1, 2.2 * k)), with: .color(accent.lighter(0.7).color(s.sparkAlpha)))
        }

        // Core: depth shadow, dark base, colour fill from the centre, rim, highlight, flash
        let corePath = Geo.circle(c, coreR)
        ctx.fill(Geo.circle(c, coreR + 8 * k), with: .radialGradient(
            Gradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0)]),
            center: CGPoint(x: c.x, y: c.y + 4 * k), startRadius: coreR * 0.9, endRadius: coreR + 9 * k))
        ctx.fill(corePath, with: .linearGradient(
            Gradient(colors: [Color(white: 0.155), Color(white: 0.06)]),
            startPoint: CGPoint(x: c.x - coreR * 0.5, y: c.y - coreR), endPoint: CGPoint(x: c.x + coreR * 0.4, y: c.y + coreR)))
        if s.core > 0.001 {
            let r = coreR * CGFloat(Geo.easeOut(s.core))
            let disc = Geo.circle(c, r)
            ctx.fill(disc, with: .linearGradient(
                Gradient(colors: [accent.darker(0.5).color, accent.darker(0.78).color]),
                startPoint: CGPoint(x: c.x, y: c.y - coreR), endPoint: CGPoint(x: c.x, y: c.y + coreR)))
            ctx.fill(disc, with: .radialGradient(
                Gradient(colors: [accent.color(0.24 * s.core), accent.color(0)]),
                center: CGPoint(x: c.x, y: c.y - coreR * 0.35), startRadius: 0, endRadius: coreR))
        }
        ctx.stroke(corePath, with: .color(RGB.white.mix(accent, s.core).color(0.07 + 0.28 * s.core)), lineWidth: max(0.5, 1 * k))
        ctx.fill(corePath, with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0)]),
            center: CGPoint(x: c.x - coreR * 0.25, y: c.y - coreR * 0.6), startRadius: 0, endRadius: coreR * 1.05))
        if s.flash > 0.002 {
            ctx.fill(corePath, with: .color(accent.lighter(0.55).color(0.5 * s.flash)))
        }

        // Power glyph
        let pr = 15.5 * k
        let glyphRGB = RGB(0.62, 0.62, 0.62).mix(accent.lighter(0.15 + 0.22 * s.powerBright), s.power)
        let gap = 0.62
        var glyph = Geo.arc(c, pr, from: -Double.pi / 2 + gap, to: Double.pi * 1.5 - gap, segments: 40)
        glyph.move(to: CGPoint(x: c.x, y: c.y - pr - 2.5 * k))
        glyph.addLine(to: CGPoint(x: c.x, y: c.y - pr * 0.18))
        ctx.stroke(glyph, with: .color(glyphRGB.color(0.78 + 0.22 * s.power)), style: StrokeStyle(lineWidth: max(1, 2.3 * k), lineCap: .round))
    }
}

/// Static lit dial for preset tiles.
struct MiniDial: View {
    let accent: RGB
    var size: CGFloat = 44

    var body: some View {
        Canvas { ctx, canvas in
            DialRenderer.draw(&ctx, canvas, dial: size, DialState.lit(accent, glow: 0.55, ticks: 48))
        }
        .frame(width: size * DialRenderer.overscan, height: size * DialRenderer.overscan)
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}
