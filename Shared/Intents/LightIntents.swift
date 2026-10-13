import AppIntents
import Foundation

// These actions run inside the Lumen app itself (in the background), which is where permission to
// reach lights on the home Wi-Fi lives. That's why they're marked as live-activity actions.

struct ToggleRoomIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Lights"
    static let description = IntentDescription("Switches a room's lights on if they're off, or off if any are on.")

    @Parameter(title: "Room")
    var room: RoomEntity

    init() {}
    init(room: RoomEntity) { self.room = room }

    static var parameterSummary: some ParameterSummary { Summary("Toggle \(\.$room)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let on = await LightControl.toggleRoom(room.id)
        return .result(dialog: "\(room.name) \(on ? "on" : "off").")
    }
}

struct TurnOnIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn On Lights"
    static let description = IntentDescription("Switches a room's lights on, just as they were.")

    @Parameter(title: "Room")
    var room: RoomEntity

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Turn on \(\.$room)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await LightControl.setRoom(room.id, .power(true))
        return .result(dialog: "\(room.name) on.")
    }
}

struct TurnOffIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn Off Lights"
    static let description = IntentDescription("Switches a room's lights off.")

    @Parameter(title: "Room")
    var room: RoomEntity

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Turn off \(\.$room)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await LightControl.setRoom(room.id, .power(false))
        return .result(dialog: "\(room.name) off.")
    }
}

struct AllOffIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "All Lights Off"
    static let description = IntentDescription("Switches every light off.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await LightControl.setRoom(RoomEntity.everywhereID, .power(false))
        return .result(dialog: "All lights off.")
    }
}

struct SetBrightnessIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Brightness"
    static let description = IntentDescription("Sets how bright a room's lights are, from 10 to 100 per cent.")

    @Parameter(title: "Room")
    var room: RoomEntity

    @Parameter(title: "Brightness", default: 50, inclusiveRange: (10, 100))
    var brightness: Int

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$room) to \(\.$brightness)%") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await LightControl.setRoom(room.id, .brightness(brightness))
        return .result(dialog: "\(room.name) at \(brightness)%.")
    }
}

struct SetColourIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Colour"
    static let description = IntentDescription("Sets a room's lights to a colour or a shade of white.")

    @Parameter(title: "Colour")
    var colour: ColourChoice

    @Parameter(title: "Room")
    var room: RoomEntity

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$room) to \(\.$colour)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await LightControl.setRoom(room.id, .mode(colour.mode))
        return .result(dialog: "Done.")
    }
}

struct SetSceneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play Scene"
    static let description = IntentDescription("Plays one of the lights' built-in scenes, such as Fireplace or Ocean.")

    @Parameter(title: "Scene")
    var scene: SceneChoice

    @Parameter(title: "Room")
    var room: RoomEntity

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Play \(\.$scene) in \(\.$room)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await LightControl.setRoom(room.id, .mode(.scene(id: scene.sceneID, speed: 100)))
        return .result(dialog: "Done.")
    }
}

struct ApplyMoodIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Mood"
    static let description = IntentDescription("Sets your lights to one of your saved moods.")

    @Parameter(title: "Mood")
    var mood: MoodEntity

    init() {}
    init(mood: MoodEntity) { self.mood = mood }

    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$mood)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await LightControl.applyMood(mood.id)
        return .result(dialog: "\(mood.name) set.")
    }
}

// MARK: - Control Centre

/// The on/off switch behind the Control Centre room control.
struct SetRoomPowerIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Switch Room"
    static let description = IntentDescription("Switches a room's lights on or off.")
    static let isDiscoverable = false

    @Parameter(title: "Room")
    var room: RoomEntity?

    @Parameter(title: "On")
    var value: Bool

    init() {}
    init(room: RoomEntity?) { self.room = room }

    func perform() async throws -> some IntentResult {
        await LightControl.setRoom(room?.id ?? RoomEntity.everywhereID, .power(value))
        return .result()
    }
}

struct RoomControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Room"
    static let isDiscoverable = false

    @Parameter(title: "Room")
    var room: RoomEntity?

    init() {}
}

struct MoodControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Mood"
    static let isDiscoverable = false

    @Parameter(title: "Mood")
    var mood: MoodEntity?

    init() {}
}

/// Used by the Control Centre mood button.
struct RunMoodIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Run Mood"
    static let isDiscoverable = false

    @Parameter(title: "Mood")
    var mood: MoodEntity?

    init() {}
    init(mood: MoodEntity?) { self.mood = mood }

    func perform() async throws -> some IntentResult {
        if let mood { await LightControl.applyMood(mood.id) }
        return .result()
    }
}

/// Used by the Lock Screen and Home Screen room widgets.
struct RoomWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Room"
    static let description = IntentDescription("Choose which room this widget switches.")

    @Parameter(title: "Room")
    var room: RoomEntity?

    init() {}
}

/// Used by widget buttons: toggles a room without opening the app.
struct WidgetToggleRoomIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Room"
    static let isDiscoverable = false

    @Parameter(title: "Room ID")
    var roomID: String

    init() {}
    init(roomID: String) { self.roomID = roomID }

    func perform() async throws -> some IntentResult {
        await LightControl.toggleRoom(roomID)
        return .result()
    }
}

/// Used by widget buttons: sets a mood without opening the app.
struct WidgetMoodIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Mood"
    static let isDiscoverable = false

    @Parameter(title: "Mood ID")
    var moodID: String

    init() {}
    init(moodID: String) { self.moodID = moodID }

    func perform() async throws -> some IntentResult {
        await LightControl.applyMood(moodID)
        return .result()
    }
}
