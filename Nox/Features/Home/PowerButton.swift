import SwiftUI

/// The power button: a hairline ring around a power glyph.
///
/// off           — dim ring, grey glyph
/// connecting    — an accent comet runs around the ring, the glyph breathes
/// on            — the ring closes in the accent colour with a soft glow, plus the idle animation
///                 from Appearance: pulse (ripples), rotate (a light orbiting the ring) or none
/// disconnecting — the comet runs back and the ring fades
struct PowerButton: View {
    let status: ConnectionManager.Status
    var size: CGFloat = 212
    var interactive = true
    /// No servers yet: everything a notch dimmer.
    var dimmed = false
    var onTap: () -> Void = {}

    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var closure: CGFloat = 0

    private enum Phase { case off, connecting, on, disconnecting }

    var body: some View {
        Group {
            if interactive {
                Button(action: onTap) { face }
                    .buttonStyle(PowerPressStyle())
                    .accessibilityLabel(isOn ? settings.t("Отключить", "Disconnect") : settings.t("Подключить", "Connect"))
            } else {
                face
                    .accessibilityHidden(true)
            }
        }
        .onAppear { closure = isOn ? 1 : 0 }
        .onChange(of: isOn) { _, on in
            withAnimation(on ? .easeOut(duration: 0.9) : .easeIn(duration: 0.35)) { closure = on ? 1 : 0 }
        }
    }

    private var isOn: Bool {
        if case .connected = status { return true }
        return false
    }

    private var phase: Phase {
        switch status {
        case .disconnected: return .off
        case .connecting: return .connecting
        case .connected: return .on
        case .disconnecting: return .disconnecting
        }
    }

    private var face: some View {
        let accent = settings.accent
        let glow = settings.look.glow
        let style: DialAnimation = reduceMotion ? .none : settings.look.animation
        let phase = self.phase
        let running = phase == .connecting || phase == .disconnecting
        let moving = running || (phase == .on && style != .none)
        let lineWidth = max(1.5, size / 106)
        return TimelineView(.animation(minimumInterval: nil, paused: !moving)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                // Soft halo when connected.
                Circle()
                    .fill(RadialGradient(colors: [accent.color(0.20 * glow), accent.color(0)],
                                         center: .center, startRadius: size * 0.3, endRadius: size * 0.78))
                    .frame(width: size * 1.6, height: size * 1.6)
                    .opacity(Double(closure))

                if phase == .on, style == .pulse {
                    ForEach(0..<2, id: \.self) { k in
                        let p = (t / 3.2 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(accent.color((1 - p) * (0.25 + 0.4 * glow)), lineWidth: 1)
                            .scaleEffect(1 + 0.3 * p)
                    }
                }

                // Track.
                Circle()
                    .stroke(Color.white.opacity(dimmed ? 0.07 : 0.11), lineWidth: lineWidth)

                // The lit ring closes clockwise from the top.
                Circle()
                    .trim(from: 0, to: closure)
                    .stroke(accent.color, style: StrokeStyle(lineWidth: lineWidth + 0.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accent.color(0.75 * glow), radius: 10 * glow)

                if running {
                    let turn = phase == .connecting ? t * 300 : -t * 420
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(AngularGradient(colors: [accent.color(0), accent.color],
                                                center: .center, startAngle: .degrees(0), endAngle: .degrees(0.28 * 360)),
                                style: StrokeStyle(lineWidth: lineWidth + 0.5, lineCap: .round))
                        .rotationEffect(.degrees(turn.truncatingRemainder(dividingBy: 360)))
                        .shadow(color: accent.color(0.6 * glow), radius: 6 * glow)
                }

                if phase == .on, style == .rotate {
                    Circle()
                        .fill(Color.white)
                        .frame(width: lineWidth * 3, height: lineWidth * 3)
                        .shadow(color: accent.color, radius: 6)
                        .offset(y: -size / 2)
                        .rotationEffect(.degrees((t * 36).truncatingRemainder(dividingBy: 360)))
                }

                // Inner disc.
                Circle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.015)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().fill(accent.color(0.10 * Double(closure))))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                    .padding(size * 0.12)

                Image(systemName: "power")
                    .font(.system(size: size * 0.2, weight: .light))
                    .foregroundStyle(glyphColor(phase, accent: accent, t: t))
                    .shadow(color: phase == .on ? accent.color(0.6 * glow) : .clear, radius: 8)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }

    private func glyphColor(_ phase: Phase, accent: RGB, t: TimeInterval) -> Color {
        switch phase {
        case .on: return accent.color
        case .connecting: return accent.color(0.5 + 0.5 * (0.5 + 0.5 * sin(t * 4.2)))
        case .disconnecting: return Ink.secondary
        case .off: return dimmed ? Ink.tertiary : Ink.primary.opacity(0.72)
        }
    }
}

private struct PowerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The lit button in miniature (Appearance preset tiles).
struct MiniPower: View {
    let accent: RGB
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.color, lineWidth: max(1.2, size / 32))
                .shadow(color: accent.color(0.6), radius: size / 10)
            Image(systemName: "power")
                .font(.system(size: size * 0.34, weight: .regular))
                .foregroundStyle(accent.color)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}
