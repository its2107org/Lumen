import SwiftUI

/// WiZ's built-in light scenes. The lights run these themselves, including the moving ones.
struct WizScene: Identifiable, Hashable {
    let id: Int
    let name: String
    let symbol: String
    let isDynamic: Bool
    let group: Category
    let colors: [Color]

    enum Category: String, CaseIterable {
        case everyday = "Everyday"
        case moving = "Colourful"
        case seasonal = "Seasons and occasions"
    }

    /// Which lights can play this scene.
    func works(on kind: LightKind) -> Bool {
        switch kind {
        case .colour: true
        case .tunableWhite: Self.tunableWhiteIDs.contains(id)
        case .dimmable: Self.dimmableIDs.contains(id)
        case .plug: false
        }
    }

    static func find(_ id: Int) -> WizScene? { all.first { $0.id == id } }

    static func available(for kinds: Set<LightKind>) -> [WizScene] {
        all.filter { scene in kinds.allSatisfy { scene.works(on: $0) } }
    }

    private static let tunableWhiteIDs: Set<Int> = [6, 9, 10, 11, 12, 13, 14, 15, 16, 18, 29, 30, 31, 32, 33, 35, 40]
    private static let dimmableIDs: Set<Int> = [9, 10, 14, 29, 31, 32, 34, 35]

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    static let all: [WizScene] = [
        // Everyday whites and routines
        WizScene(id: 11, name: "Warm white", symbol: "sun.haze.fill", isDynamic: false, group: .everyday, colors: [.kelvin(2700)]),
        WizScene(id: 12, name: "Daylight", symbol: "sun.max.fill", isDynamic: false, group: .everyday, colors: [.kelvin(4200)]),
        WizScene(id: 13, name: "Cool white", symbol: "snowflake", isDynamic: false, group: .everyday, colors: [.kelvin(6500)]),
        WizScene(id: 30, name: "Golden white", symbol: "sparkle", isDynamic: false, group: .everyday, colors: [hex(0xFFD08A)]),
        WizScene(id: 15, name: "Focus", symbol: "scope", isDynamic: false, group: .everyday, colors: [.kelvin(5000)]),
        WizScene(id: 16, name: "Relax", symbol: "cup.and.saucer.fill", isDynamic: false, group: .everyday, colors: [hex(0xFFB15E)]),
        WizScene(id: 6, name: "Cosy", symbol: "sofa.fill", isDynamic: true, group: .everyday, colors: [hex(0xFF9A3C), hex(0xFFC27A)]),
        WizScene(id: 18, name: "TV time", symbol: "tv.fill", isDynamic: false, group: .everyday, colors: [hex(0x9DA8FF)]),
        WizScene(id: 17, name: "True colours", symbol: "paintpalette.fill", isDynamic: false, group: .everyday, colors: [.kelvin(4500)]),
        WizScene(id: 40, name: "Dim to warm", symbol: "sun.dust.fill", isDynamic: false, group: .everyday, colors: [hex(0xFFA552)]),
        WizScene(id: 29, name: "Candlelight", symbol: "flame.fill", isDynamic: true, group: .everyday, colors: [hex(0xFF8A1F), hex(0xFFB347)]),
        WizScene(id: 14, name: "Night light", symbol: "moon.fill", isDynamic: false, group: .everyday, colors: [hex(0xFF7A2A)]),
        WizScene(id: 9, name: "Wake up", symbol: "alarm.fill", isDynamic: true, group: .everyday, colors: [hex(0xFFB25E), hex(0xFFE3B0)]),
        WizScene(id: 10, name: "Bedtime", symbol: "bed.double.fill", isDynamic: true, group: .everyday, colors: [hex(0xFF9840), hex(0xD9561A)]),
        WizScene(id: 19, name: "Plant growth", symbol: "leaf.fill", isDynamic: false, group: .everyday, colors: [hex(0xD24DFF)]),

        // Colourful, moving scenes
        WizScene(id: 1, name: "Ocean", symbol: "water.waves", isDynamic: true, group: .moving, colors: [hex(0x0077FF), hex(0x00D0E0)]),
        WizScene(id: 2, name: "Romance", symbol: "heart.fill", isDynamic: true, group: .moving, colors: [hex(0xFF2D6F), hex(0xB0207A)]),
        WizScene(id: 3, name: "Sunset", symbol: "sun.horizon.fill", isDynamic: true, group: .moving, colors: [hex(0xFF5E3A), hex(0xFFB03A)]),
        WizScene(id: 4, name: "Party", symbol: "party.popper.fill", isDynamic: true, group: .moving, colors: [hex(0xFF2D95), hex(0x4C4CFF), hex(0x00E0A0)]),
        WizScene(id: 5, name: "Fireplace", symbol: "fireplace.fill", isDynamic: true, group: .moving, colors: [hex(0xFF4D00), hex(0xFFA000)]),
        WizScene(id: 7, name: "Forest", symbol: "tree.fill", isDynamic: true, group: .moving, colors: [hex(0x1FA34A), hex(0x9BDB4D)]),
        WizScene(id: 8, name: "Pastel colours", symbol: "cloud.fill", isDynamic: true, group: .moving, colors: [hex(0xFFB3D9), hex(0xB3D9FF), hex(0xC9FFB3)]),
        WizScene(id: 23, name: "Deep dive", symbol: "drop.fill", isDynamic: true, group: .moving, colors: [hex(0x003CFF), hex(0x00A0B0)]),
        WizScene(id: 24, name: "Jungle", symbol: "leaf.circle.fill", isDynamic: true, group: .moving, colors: [hex(0x00B050), hex(0xD0E000)]),
        WizScene(id: 25, name: "Mojito", symbol: "wineglass.fill", isDynamic: true, group: .moving, colors: [hex(0x40FF80), hex(0x00C0FF)]),
        WizScene(id: 26, name: "Club", symbol: "music.note", isDynamic: true, group: .moving, colors: [hex(0xFF00C8), hex(0x3D00FF)]),
        WizScene(id: 31, name: "Pulse", symbol: "waveform.path", isDynamic: true, group: .moving, colors: [.kelvin(3500), hex(0xFFE7C0)]),
        WizScene(id: 32, name: "Steampunk", symbol: "gearshape.2.fill", isDynamic: true, group: .moving, colors: [hex(0xFF8C1A), hex(0xC06010)]),
        WizScene(id: 36, name: "Snowy sky", symbol: "cloud.snow.fill", isDynamic: true, group: .moving, colors: [hex(0xBFE6FF), hex(0x7AB8FF)]),
        WizScene(id: 1000, name: "Rhythm", symbol: "metronome.fill", isDynamic: true, group: .moving, colors: [hex(0xFF3D3D), hex(0x3DA0FF)]),

        // Seasons and occasions
        WizScene(id: 20, name: "Spring", symbol: "camera.macro", isDynamic: true, group: .seasonal, colors: [hex(0xFFC0E0), hex(0xA0FF90)]),
        WizScene(id: 21, name: "Summer", symbol: "sun.max.circle.fill", isDynamic: true, group: .seasonal, colors: [hex(0xFFD000), hex(0x00C8FF)]),
        WizScene(id: 22, name: "Autumn", symbol: "leaf.arrow.triangle.circlepath", isDynamic: true, group: .seasonal, colors: [hex(0xFF7A00), hex(0xC03000)]),
        WizScene(id: 27, name: "Christmas", symbol: "gift.fill", isDynamic: true, group: .seasonal, colors: [hex(0xFF2020), hex(0x20C040)]),
        WizScene(id: 28, name: "Halloween", symbol: "moon.stars.fill", isDynamic: true, group: .seasonal, colors: [hex(0xFF7000), hex(0x8A2BE2)]),
        WizScene(id: 33, name: "Diwali", symbol: "sparkles", isDynamic: true, group: .seasonal, colors: [hex(0xFFB000), hex(0xFF4080)])
    ]
}
