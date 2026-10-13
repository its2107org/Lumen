import AppIntents
import Foundation

/// A room (or every light) for shortcuts, widgets and Control Centre.
struct RoomEntity: AppEntity, Identifiable {
    static let everywhereID = "everywhere"
    static let everywhere = RoomEntity(id: everywhereID, name: "All lights", symbol: "house.fill")

    let id: String
    let name: String
    let symbol: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Room"
    static let defaultQuery = RoomQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(id: String, name: String, symbol: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }

    init(_ room: Room) {
        self.init(id: room.id.uuidString, name: room.name, symbol: room.symbol)
    }

    static func all() -> [RoomEntity] {
        [.everywhere] + HomeStore.load().rooms.map(RoomEntity.init)
    }
}

struct RoomQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RoomEntity] {
        let all = RoomEntity.all()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func entities(matching string: String) async throws -> [RoomEntity] {
        let query = string.lowercased()
        return RoomEntity.all().filter { $0.name.lowercased().contains(query) || query.contains($0.name.lowercased()) }
    }

    func suggestedEntities() async throws -> [RoomEntity] { RoomEntity.all() }

    func defaultResult() async -> RoomEntity? { .everywhere }
}

/// A saved mood for shortcuts, widgets and Control Centre.
struct MoodEntity: AppEntity, Identifiable {
    let id: String
    let name: String
    let symbol: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static let defaultQuery = MoodQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ mood: Mood) {
        id = mood.id.uuidString
        name = mood.name
        symbol = mood.symbol
    }

    static func all() -> [MoodEntity] { HomeStore.load().moods.map(MoodEntity.init) }
}

struct MoodQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [MoodEntity] {
        let all = MoodEntity.all()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func entities(matching string: String) async throws -> [MoodEntity] {
        let query = string.lowercased()
        return MoodEntity.all().filter { $0.name.lowercased().contains(query) || query.contains($0.name.lowercased()) }
    }

    func suggestedEntities() async throws -> [MoodEntity] { MoodEntity.all() }

    func defaultResult() async -> MoodEntity? { MoodEntity.all().first }
}

/// Colours and whites you can ask for by name.
enum ColourChoice: String, AppEnum, CaseIterable {
    case candlelight, warmWhite, daylight, coolWhite
    case red, orange, yellow, green, turquoise, blue, purple, pink

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Colour"
    static let caseDisplayRepresentations: [ColourChoice: DisplayRepresentation] = [
        .candlelight: "Candlelight",
        .warmWhite: "Warm white",
        .daylight: "Daylight",
        .coolWhite: "Cool white",
        .red: "Red",
        .orange: "Orange",
        .yellow: "Yellow",
        .green: "Green",
        .turquoise: "Turquoise",
        .blue: "Blue",
        .purple: "Purple",
        .pink: "Pink"
    ]

    var mode: LightMode {
        switch self {
        case .candlelight: .white(kelvin: 2200)
        case .warmWhite: .white(kelvin: 2700)
        case .daylight: .white(kelvin: 5000)
        case .coolWhite: .white(kelvin: 6500)
        case .red: .colour(red: 255, green: 30, blue: 10)
        case .orange: .colour(red: 255, green: 110, blue: 0)
        case .yellow: .colour(red: 255, green: 200, blue: 20)
        case .green: .colour(red: 40, green: 230, blue: 70)
        case .turquoise: .colour(red: 0, green: 220, blue: 200)
        case .blue: .colour(red: 30, green: 60, blue: 255)
        case .purple: .colour(red: 140, green: 40, blue: 255)
        case .pink: .colour(red: 255, green: 50, blue: 150)
        }
    }
}

/// WiZ's built-in scenes, for shortcuts.
enum SceneChoice: String, AppEnum, CaseIterable {
    case ocean, romance, sunset, party, fireplace, cosy, forest, pastel, wakeUp, bedtime
    case warmWhite, daylight, coolWhite, nightLight, focus, relax, trueColours, tvTime, plantGrowth
    case spring, summer, autumn, deepDive, jungle, mojito, club, christmas, halloween
    case candlelight, goldenWhite, pulse, steampunk, diwali, snowySky

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"
    static let caseDisplayRepresentations: [SceneChoice: DisplayRepresentation] = [
        .ocean: "Ocean",
        .romance: "Romance",
        .sunset: "Sunset",
        .party: "Party",
        .fireplace: "Fireplace",
        .cosy: "Cosy",
        .forest: "Forest",
        .pastel: "Pastel colours",
        .wakeUp: "Wake up",
        .bedtime: "Bedtime",
        .warmWhite: "Warm white",
        .daylight: "Daylight",
        .coolWhite: "Cool white",
        .nightLight: "Night light",
        .focus: "Focus",
        .relax: "Relax",
        .trueColours: "True colours",
        .tvTime: "TV time",
        .plantGrowth: "Plant growth",
        .spring: "Spring",
        .summer: "Summer",
        .autumn: "Autumn",
        .deepDive: "Deep dive",
        .jungle: "Jungle",
        .mojito: "Mojito",
        .club: "Club",
        .christmas: "Christmas",
        .halloween: "Halloween",
        .candlelight: "Candlelight",
        .goldenWhite: "Golden white",
        .pulse: "Pulse",
        .steampunk: "Steampunk",
        .diwali: "Diwali",
        .snowySky: "Snowy sky"
    ]

    var sceneID: Int {
        switch self {
        case .ocean: 1
        case .romance: 2
        case .sunset: 3
        case .party: 4
        case .fireplace: 5
        case .cosy: 6
        case .forest: 7
        case .pastel: 8
        case .wakeUp: 9
        case .bedtime: 10
        case .warmWhite: 11
        case .daylight: 12
        case .coolWhite: 13
        case .nightLight: 14
        case .focus: 15
        case .relax: 16
        case .trueColours: 17
        case .tvTime: 18
        case .plantGrowth: 19
        case .spring: 20
        case .summer: 21
        case .autumn: 22
        case .deepDive: 23
        case .jungle: 24
        case .mojito: 25
        case .club: 26
        case .christmas: 27
        case .halloween: 28
        case .candlelight: 29
        case .goldenWhite: 30
        case .pulse: 31
        case .steampunk: 32
        case .diwali: 33
        case .snowySky: 36
        }
    }
}
