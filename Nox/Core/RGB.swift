import Foundation

/// Plain sRGB color (0…1). Codable, so it can be saved; converted to SwiftUI `Color` in ColorBridge.
struct RGB: Codable, Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255,
                  Double((hex >> 8) & 0xFF) / 255,
                  Double(hex & 0xFF) / 255)
    }

    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    var hexString: String {
        func c(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }

    /// Linear interpolation towards `other` (t = 0 … 1).
    func mix(_ other: RGB, _ t: Double) -> RGB {
        let k = min(max(t, 0), 1)
        return RGB(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }

    func lighter(_ t: Double) -> RGB { mix(.white, t) }
    func darker(_ t: Double) -> RGB { mix(.black, t) }

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    func distance(to o: RGB) -> Double { abs(r - o.r) + abs(g - o.g) + abs(b - o.b) }

    static let white = RGB(1, 1, 1)
    static let black = RGB(0, 0, 0)
}
