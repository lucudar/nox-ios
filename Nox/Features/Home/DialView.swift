import SwiftUI

enum DialPhase: Equatable {
    case off, connecting, igniting, on, extinguishing
}

enum DialTiming {
    /// Sweep → core fill → flash & wave.
    static let ignite = 2.0
    /// The same, reversed and faster.
    static let extinguish = 0.75
}

/// The big power dial: 96 ticks, a core and a power glyph, animated by connection state.
///
/// connecting  — a spark runs around the ring with a comet tail
/// igniting    — ticks light up clockwise, a thin outer ring appears, the core fills, flash + wave
/// on          — breathing (pulse / slow rotation / none)
/// extinguishing — the reverse
struct DialView: View {
    let status: ConnectionManager.Status
    var size: CGFloat = 252
    var interactive = true
    var onTap: () -> Void = {}

    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: DialPhase = .off
    @State private var phaseStart = Date()
    @State private var sparkStart = Date()
    @State private var carry: Double = 0
    @State private var fromAccent: RGB?
    @State private var morphStart = Date.distantPast
    @State private var morphing = false

    var body: some View {
        Group {
            if interactive {
                Button(action: onTap) { dial }
                    .buttonStyle(DialPressStyle())
                    .accessibilityLabel(accessibilityTitle)
            } else {
                dial
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            phase = Self.restingPhase(for: status)
            phaseStart = Date()
            sparkStart = Date()
        }
        .onChange(of: status) { _, newValue in
            transition(to: newValue)
        }
        .onChange(of: settings.look.accent) { oldValue, _ in
            fromAccent = oldValue
            morphStart = Date()
            morphing = true
        }
        .task(id: phaseStart) {
            await finishPhase()
        }
        .task(id: morphStart) {
            await finishMorph()
        }
    }

    // MARK: Drawing

    private var dial: some View {
        let animating = isAnimating
        let accent = settings.accent
        let glow = settings.look.glow
        let style = settings.look.animation
        return TimelineView(.animation(minimumInterval: nil, paused: !animating)) { timeline in
            let state = makeState(at: animating ? timeline.date : nil, accent: accent, glow: glow, style: style)
            Canvas { ctx, canvas in
                DialRenderer.draw(&ctx, canvas, dial: size, state)
            }
            .frame(width: size * DialRenderer.overscan, height: size * DialRenderer.overscan)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }

    private var isAnimating: Bool {
        if morphing { return true }
        switch phase {
        case .off: return false
        case .on: return settings.look.animation != .none && !reduceMotion
        case .connecting, .igniting, .extinguishing: return true
        }
    }

    private var accessibilityTitle: String {
        switch status {
        case .disconnected: return settings.t("Подключить", "Connect")
        case .connecting: return settings.t("Подключение, нажмите для отмены", "Connecting, tap to cancel")
        case .connected: return settings.t("Отключить", "Disconnect")
        case .disconnecting: return settings.t("Отключение", "Disconnecting")
        }
    }

    /// `date == nil` → the timeline is paused: draw the settled state of the phase.
    private func makeState(at date: Date?, accent target: RGB, glow: Double, style: DialAnimation) -> DialState {
        var accent = target
        if let from = fromAccent, let date {
            accent = from.mix(target, Geo.ease(date.timeIntervalSince(morphStart) / 0.6))
        }
        var s = DialState(accent: accent)
        s.glow = glow
        let t = date.map { $0.timeIntervalSince(phaseStart) } ?? 1_000
        let sparkT = date.map { $0.timeIntervalSince(sparkStart) } ?? 0
        let spark = (sparkT * 0.85).truncatingRemainder(dividingBy: 1)

        switch phase {
        case .off:
            break

        case .connecting:
            let fade = 1 - Geo.easeOut(t / 0.45)
            s.sweep = carry * fade
            s.core = carry * fade
            s.powerBright = carry * fade
            s.spark = spark
            s.sparkAlpha = Geo.window(t, 0, 0.25)
            s.power = 1

        case .igniting:
            s.spark = spark
            s.sparkAlpha = 1 - Geo.window(t, 0, 0.35)
            s.sweep = Geo.ease(Geo.window(t, 0.05, 1.25))
            s.ring = Geo.window(t, 0.15, 0.7) * (1 - Geo.window(t, 1.5, 1.7))
            s.halo = Geo.window(t, 0.3, 0.9) * (1 - Geo.window(t, 1.5, 1.8))
            s.core = Geo.easeOut(Geo.window(t, 1.15, 1.6))
            s.flash = t < 1.58 ? Geo.window(t, 1.5, 1.58) : 1 - Geo.easeOut(Geo.window(t, 1.58, 2.0))
            s.wave = t >= 1.52 ? Geo.window(t, 1.52, 2.0) : nil
            s.power = 1
            s.powerBright = Geo.window(t, 1.5, 1.7)

        case .on:
            s.sweep = 1
            s.core = 1
            s.power = 1
            s.powerBright = 1
            if date != nil {
                let envelope = Geo.window(t, 0, 0.8)
                switch style {
                case .pulse:
                    s.breath = sin(2 * Double.pi * t / 3.4) * envelope
                case .rotate:
                    s.rotation = t * 2 * Double.pi / 48
                    s.sheen = -Double.pi * 0.75 + t * 0.6
                    s.breath = 0.35 * sin(2 * Double.pi * t / 5) * envelope
                case .none:
                    break
                }
            }

        case .extinguishing:
            s.implode = Geo.window(t, 0, 0.4)
            s.core = carry * (1 - Geo.easeIn(Geo.window(t, 0.05, 0.45)))
            s.sweep = carry * (1 - Geo.ease(Geo.window(t, 0.1, 0.7)))
            s.power = 1 - Geo.window(t, 0.3, 0.75)
            s.powerBright = carry * (1 - Geo.window(t, 0, 0.3))
        }
        return s
    }

    // MARK: Phases

    private static func restingPhase(for status: ConnectionManager.Status) -> DialPhase {
        switch status {
        case .connected: return .on
        case .connecting: return .connecting
        case .disconnected, .disconnecting: return .off
        }
    }

    /// Visual intensity right now, so an interrupted animation continues from where it is.
    private func level(at now: Date) -> Double {
        let t = now.timeIntervalSince(phaseStart)
        switch phase {
        case .off: return 0
        case .connecting: return carry * (1 - Geo.easeOut(t / 0.45))
        case .igniting: return Geo.ease(Geo.window(t, 0.05, 1.25))
        case .on: return 1
        case .extinguishing: return carry * (1 - Geo.ease(Geo.window(t, 0.1, 0.7)))
        }
    }

    private func transition(to status: ConnectionManager.Status) {
        let now = Date()
        let current = level(at: now)
        switch status {
        case .connecting:
            carry = current
            if phase != .connecting { sparkStart = now }
            enter(.connecting, now)
        case .connected:
            guard phase != .on else { return }
            enter(.igniting, now)
        case .disconnecting, .disconnected:
            guard phase != .off, phase != .extinguishing else { return }
            carry = max(current, 0.001)
            enter(.extinguishing, now)
        }
    }

    private func enter(_ next: DialPhase, _ now: Date) {
        phase = next
        phaseStart = now
    }

    private func finishPhase() async {
        let duration: Double
        switch phase {
        case .igniting: duration = DialTiming.ignite
        case .extinguishing: duration = DialTiming.extinguish
        default: return
        }
        let started = phaseStart
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        guard !Task.isCancelled, started == phaseStart else { return }
        enter(phase == .igniting ? .on : .off, Date())
    }

    private func finishMorph() async {
        guard morphing else { return }
        let started = morphStart
        try? await Task.sleep(nanoseconds: 650_000_000)
        guard !Task.isCancelled, started == morphStart else { return }
        morphing = false
        fromAccent = nil
    }
}

/// Spring press: quick squeeze, bouncy release.
private struct DialPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.5),
                       value: configuration.isPressed)
    }
}
