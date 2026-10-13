import Foundation
import SwiftUI

/// What a light can do, worked out from the model name the bulb reports.
enum LightKind: String, Codable, Hashable {
    /// Full colour plus tunable white.
    case colour
    /// Warm to cool white, no colour.
    case tunableWhite
    /// Brightness only (most filament bulbs).
    case dimmable
    /// A smart plug: on and off only.
    case plug

    /// WiZ module names look like `ESP01_SHRGB1C_31`. The middle part says what the light can do.
    init(moduleName: String) {
        let parts = moduleName.uppercased().split(separator: "_")
        let identifier = parts.count > 1 ? String(parts[1]) : moduleName.uppercased()
        if identifier.contains("RGB") {
            self = .colour
        } else if identifier.contains("TW") {
            self = .tunableWhite
        } else if identifier.contains("SOCKET") {
            self = .plug
        } else {
            self = .dimmable
        }
    }

    var hasColour: Bool { self == .colour }
    var hasWhiteTuning: Bool { self == .colour || self == .tunableWhite }
    var hasBrightness: Bool { self != .plug }
    var hasScenes: Bool { self != .plug }

    var label: String {
        switch self {
        case .colour: "Colour and white"
        case .tunableWhite: "Warm to cool white"
        case .dimmable: "Dimmable white"
        case .plug: "Smart plug"
        }
    }
}

/// How a light is lit: a shade of white, a colour, or one of WiZ's built-in scenes.
enum LightMode: Codable, Hashable {
    case white(kelvin: Int)
    case colour(red: Int, green: Int, blue: Int)
    case scene(id: Int, speed: Int)
}

/// Everything about how one light looks right now.
struct LightState: Codable, Hashable {
    var on: Bool
    /// 10 to 100 per cent (WiZ lights don't go lower than 10).
    var brightness: Int
    var mode: LightMode

    static let `default` = LightState(on: true, brightness: 100, mode: .white(kelvin: 2700))

    /// The message a WiZ light understands, for this state.
    func pilotParams(for kind: LightKind) -> [String: Any] {
        guard on else { return ["state": false] }
        var params: [String: Any] = ["state": true]
        if kind == .plug { return params }
        params["dimming"] = min(100, max(10, brightness))
        switch mode {
        case .white(let kelvin):
            if kind.hasWhiteTuning { params["temp"] = kelvin }
        case .colour(let red, let green, let blue):
            if kind.hasColour {
                params["r"] = red
                params["g"] = green
                params["b"] = blue
            } else if kind.hasWhiteTuning {
                params["temp"] = Self.nearestKelvin(red: red, green: green, blue: blue)
            }
        case .scene(let id, let speed):
            params["sceneId"] = id
            if WizScene.find(id)?.isDynamic == true { params["speed"] = min(200, max(10, speed)) }
        }
        return params
    }

    /// Rough warm/cool match for a colour, for lights that can only do white.
    static func nearestKelvin(red: Int, green: Int, blue: Int) -> Int {
        let warmth = Double(red - blue) / 255
        return Int(4000 - warmth * 1800)
    }

    /// The colour to show on screen for this state.
    var displayColor: Color {
        switch mode {
        case .white(let kelvin): Color.kelvin(kelvin)
        case .colour(let red, let green, let blue): Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
        case .scene(let id, _): WizScene.find(id)?.colors.first ?? .orange
        }
    }

    /// Whether text on top of this colour should be white.
    var isDarkColour: Bool {
        switch mode {
        case .colour(let red, let green, let blue): 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue) < 150
        case .scene(let id, _): [1, 2, 23, 26, 28].contains(id)
        case .white: false
        }
    }

    /// The colours to show on screen (scenes have several).
    var displayColors: [Color] {
        if case .scene(let id, _) = mode, let scene = WizScene.find(id) { return scene.colors }
        return [displayColor]
    }

    /// A short description, e.g. "Warm white" or "Ocean".
    var summary: String {
        guard on else { return "Off" }
        switch mode {
        case .white(let kelvin): return WhitePreset.name(for: kelvin)
        case .colour(let red, let green, let blue): return ColourNamer.name(red: red, green: green, blue: blue)
        case .scene(let id, _): return WizScene.find(id)?.name ?? "Scene"
        }
    }

    /// Reads the state a light reports back.
    init(pilot: [String: Any], fallback: LightState = .default) {
        func int(_ key: String) -> Int? {
            if let value = pilot[key] as? Int { return value }
            if let value = pilot[key] as? Double { return Int(value) }
            return nil
        }
        on = (pilot["state"] as? Bool) ?? fallback.on
        brightness = int("dimming") ?? fallback.brightness
        let sceneID = int("sceneId") ?? 0
        let red = int("r") ?? 0, green = int("g") ?? 0, blue = int("b") ?? 0
        if sceneID > 0 {
            mode = .scene(id: sceneID, speed: int("speed") ?? 100)
        } else if let kelvin = int("temp"), kelvin > 0 {
            mode = .white(kelvin: kelvin)
        } else if red + green + blue > 0 {
            mode = .colour(red: red, green: green, blue: blue)
        } else {
            mode = fallback.mode
        }
    }

    init(on: Bool, brightness: Int, mode: LightMode) {
        self.on = on
        self.brightness = brightness
        self.mode = mode
    }
}

/// One WiZ light (or plug) in the home.
struct Bulb: Codable, Identifiable, Hashable {
    /// The light's hardware address, which never changes.
    var id: String
    var name: String
    /// Where it lives on the home Wi-Fi. This can change; Lumen finds it again by its hardware address.
    var address: String
    var kind: LightKind
    var model: String
    var minKelvin: Int
    var maxKelvin: Int
    var roomID: UUID?
    var state: LightState
    var reachable: Bool
    var signal: Int?

    var kelvinRange: ClosedRange<Int> { minKelvin...max(minKelvin + 100, maxKelvin) }

    var symbol: String {
        switch kind {
        case .plug: "powerplug.fill"
        case .dimmable: "lightbulb.led.fill"
        default: "lightbulb.fill"
        }
    }
}

struct Room: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
}

/// A saved look for some or all lights, e.g. "Dinner" or "Film night".
struct Mood: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
    /// Light id to how it should look. Lights not listed are left alone.
    var settings: [String: LightState]

    var previewColors: [Color] {
        let lit = settings.values.filter(\.on)
        if lit.isEmpty { return [Color(white: 0.25)] }
        var seen: [Color] = []
        for state in lit.sorted(by: { $0.summary < $1.summary }) {
            for color in state.displayColors where !seen.contains(color) { seen.append(color) }
        }
        return Array(seen.prefix(4))
    }
}

/// Everything Lumen knows about the home. Saved in the shared space so widgets and shortcuts can use it.
struct HomeSetup: Codable, Hashable {
    var bulbs: [Bulb] = []
    var rooms: [Room] = []
    var moods: [Mood] = []
    var favouriteColours: [RGB] = RGB.defaultFavourites

    func bulbs(in room: Room?) -> [Bulb] {
        bulbs.filter { $0.roomID == room?.id }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func bulbs(inRoomID id: UUID?) -> [Bulb] {
        bulbs.filter { $0.roomID == id }
    }

    var unassigned: [Bulb] { bulbs(in: nil) }

    func room(_ id: UUID?) -> Room? { rooms.first { $0.id == id } }
}

struct RGB: Codable, Hashable {
    var red: Int
    var green: Int
    var blue: Int

    var color: Color { Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }

    static let defaultFavourites: [RGB] = [
        RGB(red: 255, green: 40, blue: 20),
        RGB(red: 255, green: 120, blue: 0),
        RGB(red: 255, green: 200, blue: 40),
        RGB(red: 60, green: 220, blue: 90),
        RGB(red: 0, green: 200, blue: 255),
        RGB(red: 40, green: 80, blue: 255),
        RGB(red: 150, green: 50, blue: 255),
        RGB(red: 255, green: 60, blue: 160)
    ]
}

// MARK: - Colour helpers

extension Color {
    /// Roughly how a white light at this temperature looks.
    static func kelvin(_ kelvin: Int) -> Color {
        let (r, g, b) = kelvinToRGB(kelvin)
        return Color(red: r, green: g, blue: b)
    }

    static func kelvinToRGB(_ kelvin: Int) -> (Double, Double, Double) {
        // Tanner Helland's approximation, softened a little so warm whites don't look orange.
        let temp = Double(min(10000, max(1000, kelvin))) / 100
        var red: Double, green: Double, blue: Double
        if temp <= 66 {
            red = 255
            green = 99.4708025861 * log(temp) - 161.1195681661
            blue = temp <= 19 ? 0 : 138.5177312231 * log(temp - 10) - 305.0447927307
        } else {
            red = 329.698727446 * pow(temp - 60, -0.1332047592)
            green = 288.1221695283 * pow(temp - 60, -0.0755148492)
            blue = 255
        }
        func clamp(_ value: Double) -> Double { min(255, max(0, value)) / 255 }
        let soften = 0.18
        return (clamp(red) * (1 - soften) + soften, clamp(green) * (1 - soften) + soften, clamp(blue) * (1 - soften) + soften)
    }

    /// Hue and saturation of a colour (0...1 each).
    static func hueSaturation(red: Int, green: Int, blue: Int) -> (hue: Double, saturation: Double) {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let maxV = max(r, g, b), minV = min(r, g, b)
        let delta = maxV - minV
        guard maxV > 0, delta > 0 else { return (0, 0) }
        var hue: Double
        if maxV == r {
            hue = (g - b) / delta
        } else if maxV == g {
            hue = 2 + (b - r) / delta
        } else {
            hue = 4 + (r - g) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / maxV)
    }

    /// Full-brightness colour from a hue and saturation (0...1 each).
    static func rgb(hue: Double, saturation: Double) -> RGB {
        let h = (hue - floor(hue)) * 6
        let s = min(1, max(0, saturation))
        let i = Int(h) % 6
        let f = h - floor(h)
        let p = 1 - s, q = 1 - s * f, t = 1 - s * (1 - f)
        let (r, g, b): (Double, Double, Double) = switch i {
        case 0: (1, t, p)
        case 1: (q, 1, p)
        case 2: (p, 1, t)
        case 3: (p, q, 1)
        case 4: (t, p, 1)
        default: (1, p, q)
        }
        return RGB(red: Int(r * 255), green: Int(g * 255), blue: Int(b * 255))
    }
}

enum WhitePreset: CaseIterable, Identifiable {
    case candle, warm, soft, neutral, daylight, cool

    var id: Self { self }

    var kelvin: Int {
        switch self {
        case .candle: 2200
        case .warm: 2700
        case .soft: 3200
        case .neutral: 4000
        case .daylight: 5000
        case .cool: 6500
        }
    }

    var name: String {
        switch self {
        case .candle: "Candlelight"
        case .warm: "Warm white"
        case .soft: "Soft white"
        case .neutral: "Neutral"
        case .daylight: "Daylight"
        case .cool: "Cool white"
        }
    }

    static func name(for kelvin: Int) -> String {
        let nearest = allCases.min { abs($0.kelvin - kelvin) < abs($1.kelvin - kelvin) } ?? .warm
        return nearest.name
    }
}

enum ColourNamer {
    static func name(red: Int, green: Int, blue: Int) -> String {
        let (hue, saturation) = Color.hueSaturation(red: red, green: green, blue: blue)
        if saturation < 0.15 { return "White" }
        let degrees = hue * 360
        let base: String = switch degrees {
        case ..<12: "Red"
        case ..<40: "Orange"
        case ..<65: "Yellow"
        case ..<160: "Green"
        case ..<200: "Turquoise"
        case ..<255: "Blue"
        case ..<290: "Purple"
        case ..<335: "Pink"
        default: "Red"
        }
        return saturation < 0.5 ? "Soft \(base.lowercased())" : base
    }
}
