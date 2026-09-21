import AppKit

struct RGBA: Codable, Equatable {
    var r: Double; var g: Double; var b: Double; var a: Double = 1
    var color: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func interpolated(to other: RGBA, fraction: Double) -> NSColor {
        let t = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return NSColor(srgbRed: r + (other.r - r) * t,
                       green: g + (other.g - g) * t,
                       blue: b + (other.b - b) * t,
                       alpha: a + (other.a - a) * t)
    }
    init(_ gray: Double, alpha: Double = 1) { r = gray; g = gray; b = gray; a = alpha }
    init(color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .white
        r = c.redComponent; g = c.greenComponent; b = c.blueComponent; a = c.alphaComponent
    }
}
struct Appearance: Codable, Equatable {
    var background = RGBA(0.15, alpha: 0.98)
    var inactive = RGBA(0.24)
    var selection = RGBA(0.96)
    var text = RGBA(0.94)
    var selectedText = RGBA(0.18)
    var radius: Double = 13
    var speed: Double = 1
    var animation = true
    var topOffset: Double = 8
    var height: Double = 26
    var fontSize: Double = 11
    var minimumHeight: Double { ceil(fontSize * 1.4) + 10 }
    var effectiveHeight: Double { max(height, minimumHeight) }
    init() {}
    enum CodingKeys: String, CodingKey {
        case background, inactive, selection, text, selectedText, radius, speed, animation, topOffset, height, fontSize
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decodeIfPresent(RGBA.self, forKey: .background) ?? background
        inactive = try c.decodeIfPresent(RGBA.self, forKey: .inactive) ?? inactive
        selection = try c.decodeIfPresent(RGBA.self, forKey: .selection) ?? selection
        text = try c.decodeIfPresent(RGBA.self, forKey: .text) ?? text
        selectedText = try c.decodeIfPresent(RGBA.self, forKey: .selectedText) ?? selectedText
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? radius
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? speed
        animation = try c.decodeIfPresent(Bool.self, forKey: .animation) ?? animation
        topOffset = try c.decodeIfPresent(Double.self, forKey: .topOffset) ?? topOffset
        height = min(64, max(22, try c.decodeIfPresent(Double.self, forKey: .height) ?? height))
        fontSize = min(24, max(9, try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize))
    }
}
final class AppearanceStore {
    private let defaults: UserDefaults
    var onChange: (() -> Void)?
    var value: Appearance { didSet { persist(); onChange?() } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "appearance"), let saved = try? JSONDecoder().decode(Appearance.self, from: data) {
            value = saved
        } else {
            value = Appearance()
            value.topOffset = defaults.object(forKey: "topOffset") as? Double ?? (CommandLine.arguments.contains("--trial") ? 44 : 8)
        }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "appearance") }
        defaults.set(value.topOffset, forKey: "topOffset")
    }
    func reset() { value = Appearance() }
}

// Exact critically damped spring: a new destination preserves both position and velocity.
struct SpringAxis {
    var position: Double
    var velocity: Double = 0
    mutating func step(target: Double, omega: Double, dt: Double) {
        let displacement = position - target
        let coefficient = velocity + omega * displacement
        let decay = exp(-omega * dt)
        position = target + (displacement + coefficient * dt) * decay
        velocity = (velocity - omega * coefficient * dt) * decay
    }
}
struct SelectionMotion {
    var center: SpringAxis
    var width: SpringAxis
    var target: CGRect
    init(rect: CGRect) {
        center = SpringAxis(position: rect.midX)
        width = SpringAxis(position: rect.width)
        target = rect
    }
    var rect: CGRect { CGRect(x: center.position - width.position / 2, y: target.minY, width: max(4, width.position), height: target.height) }
    mutating func advance(dt: Double, speed: Double) -> Bool {
        let rate = max(0.4, min(2.5, speed))
        center.step(target: target.midX, omega: 19 * rate, dt: dt)
        // Stretch slightly in motion, then recover the exact destination pill width.
        let stretch = min(24, abs(center.velocity) * 0.018 / rate)
        width.step(target: target.width + stretch, omega: 24 * rate, dt: dt)
        let settled = abs(center.position - target.midX) < 0.03 && abs(center.velocity) < 0.1 && abs(width.position - target.width) < 0.03 && abs(width.velocity) < 0.1
        if settled { self = SelectionMotion(rect: target) }
        return settled
    }
}
