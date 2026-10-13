import AppIntents
import SwiftUI
import WidgetKit

@main
struct LumenWidgets: WidgetBundle {
    var body: some Widget {
        RoomsWidget()
        MoodsWidget()
        RoomWidget()
        RoomToggleControl()
        MoodControl()
        AllOffControl()
    }
}

// MARK: - Shared bits

struct RoomInfo: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let isOn: Bool
    let colors: [Color]
    let darkColour: Bool

    static func make(roomID: String, name: String, symbol: String, home: HomeSetup) -> RoomInfo {
        let ids = Set(LightControl.ids(forRoom: roomID, in: home))
        let lit = home.bulbs.filter { ids.contains($0.id) && $0.state.on }
        var colors: [Color] = []
        for bulb in lit { for color in bulb.state.displayColors where !colors.contains(color) { colors.append(color) } }
        return RoomInfo(id: roomID, name: name, symbol: symbol, isOn: !lit.isEmpty, colors: Array(colors.prefix(3)),
                        darkColour: lit.first?.state.isDarkColour ?? false)
    }

    static func all(in home: HomeSetup) -> [RoomInfo] {
        let rooms = home.rooms.filter { room in home.bulbs.contains { $0.roomID == room.id } }
        if rooms.isEmpty {
            return [make(roomID: RoomEntity.everywhereID, name: "All lights", symbol: "house.fill", home: home)]
        }
        return rooms.map { make(roomID: $0.id.uuidString, name: $0.name, symbol: $0.symbol, home: home) }
    }
}

struct HomeEntry: TimelineEntry {
    let date: Date
    let home: HomeSetup
}

struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry { HomeEntry(date: .now, home: WidgetSample.home) }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        let home = HomeStore.load()
        completion(HomeEntry(date: .now, home: home.bulbs.isEmpty && context.isPreview ? WidgetSample.home : home))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let entry = HomeEntry(date: .now, home: HomeStore.load())
        // Check back now and then in case lights were changed elsewhere (the app updates this whenever it's used).
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

enum WidgetSample {
    static let home: HomeSetup = {
        let living = Room(id: UUID(), name: "Living room", symbol: "sofa.fill")
        let bedroom = Room(id: UUID(), name: "Bedroom", symbol: "bed.double.fill")
        let kitchen = Room(id: UUID(), name: "Kitchen", symbol: "cooktop.fill")
        let hall = Room(id: UUID(), name: "Hall", symbol: "door.left.hand.open")
        func bulb(_ n: Int, _ room: Room, _ on: Bool, _ mode: LightMode) -> Bulb {
            Bulb(id: "\(n)", name: "Light", address: "", kind: .colour, model: "", minKelvin: 2200, maxKelvin: 6500,
                 roomID: room.id, state: LightState(on: on, brightness: 70, mode: mode), reachable: true, signal: nil)
        }
        let mood = { (name: String, symbol: String, mode: LightMode) in
            Mood(id: UUID(), name: name, symbol: symbol, settings: ["1": LightState(on: true, brightness: 60, mode: mode)])
        }
        return HomeSetup(
            bulbs: [bulb(1, living, true, .white(kelvin: 2700)), bulb(2, bedroom, true, .colour(red: 150, green: 60, blue: 255)),
                    bulb(3, kitchen, false, .white(kelvin: 4000)), bulb(4, hall, true, .white(kelvin: 2200))],
            rooms: [living, bedroom, kitchen, hall],
            moods: [mood("Evening", "moon.stars.fill", .white(kelvin: 2400)), mood("Film night", "film.fill", .colour(red: 40, green: 80, blue: 255)),
                    mood("Fireside", "flame.fill", .scene(id: 5, speed: 100)), mood("Bright", "sun.max.fill", .white(kelvin: 4500))]
        )
    }()
}

struct RoomBubble: View {
    let room: RoomInfo
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle()
                .fill(room.isOn ? AnyShapeStyle(LinearGradient(colors: room.colors.count > 1 ? room.colors : [room.colors.first ?? .orange, (room.colors.first ?? .orange).opacity(0.75)],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color.secondary.opacity(0.18)))
            Image(systemName: room.symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(room.isOn ? (room.darkColour ? Color.white : Color.black.opacity(0.75)) : Color.secondary)
        }
        .frame(width: size, height: size)
    }
}

private struct EmptyHomeView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lightbulb.2")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open Lumen to find your lights")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Rooms widget

struct RoomsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LumenRooms", provider: HomeProvider()) { entry in
            RoomsWidgetView(home: entry.home)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Rooms")
        .description("Switch rooms on and off with a tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RoomsWidgetView: View {
    let home: HomeSetup
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let rooms = RoomInfo.all(in: home)
        if home.bulbs.isEmpty {
            EmptyHomeView()
        } else {
            switch family {
            case .systemSmall:
                grid(Array(rooms.prefix(4)), columns: 2, bubble: 46, showState: false)
            case .systemMedium:
                grid(Array(rooms.prefix(4)), columns: 4, bubble: 54, showState: true)
            default:
                VStack(alignment: .leading, spacing: 14) {
                    grid(Array(rooms.prefix(6)), columns: 3, bubble: 54, showState: true)
                    if !home.moods.isEmpty {
                        Divider()
                        MoodButtons(moods: Array(home.moods.prefix(4)), columns: 2)
                    }
                }
            }
        }
    }

    private func grid(_ rooms: [RoomInfo], columns: Int, bubble: CGFloat, showState: Bool) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 12) {
            ForEach(rooms) { room in
                Button(intent: WidgetToggleRoomIntent(roomID: room.id)) {
                    VStack(spacing: 5) {
                        RoomBubble(room: room, size: bubble)
                        Text(room.name)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if showState {
                            Text(room.isOn ? "On" : "Off")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Moods widget

struct MoodsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LumenMoods", provider: HomeProvider()) { entry in
            Group {
                if entry.home.moods.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.title2).foregroundStyle(.secondary)
                        Text("Save a mood in Lumen to see it here").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                } else {
                    MoodButtons(moods: Array(entry.home.moods.prefix(4)), columns: 2)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Moods")
        .description("Set a saved mood with a tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MoodButtons: View {
    let moods: [Mood]
    let columns: Int
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(moods) { mood in
                Button(intent: WidgetMoodIntent(moodID: mood.id.uuidString)) {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(AngularGradient(colors: mood.previewColors + [mood.previewColors.first ?? .orange], center: .center))
                            Image(systemName: mood.symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                        .frame(width: family == .systemSmall ? 22 : 28, height: family == .systemSmall ? 22 : 28)
                        if family != .systemSmall {
                            Text(mood.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, family == .systemSmall ? 0 : 8)
                    .frame(maxWidth: .infinity, minHeight: family == .systemSmall ? 52 : 40)
                    .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .bottom) {
                        if family == .systemSmall {
                            Text(mood.name)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .padding(.bottom, 3)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - One room (Home Screen and Lock Screen)

struct RoomEntry: TimelineEntry {
    let date: Date
    let room: RoomInfo?
}

struct RoomProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RoomEntry {
        RoomEntry(date: .now, room: RoomInfo.all(in: WidgetSample.home).first)
    }

    func snapshot(for configuration: RoomWidgetConfiguration, in context: Context) async -> RoomEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: RoomWidgetConfiguration, in context: Context) async -> Timeline<RoomEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(30 * 60)))
    }

    private func entry(for configuration: RoomWidgetConfiguration) -> RoomEntry {
        let home = HomeStore.load()
        let room = configuration.room ?? .everywhere
        return RoomEntry(date: .now, room: RoomInfo.make(roomID: room.id, name: room.name, symbol: room.symbol, home: home))
    }
}

struct RoomWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LumenRoom", intent: RoomWidgetConfiguration.self, provider: RoomProvider()) { entry in
            RoomWidgetView(room: entry.room)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Room switch")
        .description("One room's lights, on the Home Screen or Lock Screen.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RoomWidgetView: View {
    let room: RoomInfo?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let room {
            switch family {
            case .accessoryCircular:
                Button(intent: WidgetToggleRoomIntent(roomID: room.id)) {
                    ZStack {
                        AccessoryWidgetBackground()
                        Image(systemName: room.isOn ? "lightbulb.fill" : "lightbulb")
                            .font(.title2.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(room.name), \(room.isOn ? "on" : "off")")
            case .accessoryRectangular:
                Button(intent: WidgetToggleRoomIntent(roomID: room.id)) {
                    HStack(spacing: 8) {
                        Image(systemName: room.isOn ? "lightbulb.fill" : "lightbulb")
                            .font(.title3.weight(.semibold))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(room.name).font(.headline).lineLimit(1)
                            Text(room.isOn ? "On · tap to switch off" : "Off · tap to switch on").font(.caption).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            case .accessoryInline:
                Label("\(room.name) \(room.isOn ? "on" : "off")", systemImage: room.isOn ? "lightbulb.fill" : "lightbulb")
            default:
                Button(intent: WidgetToggleRoomIntent(roomID: room.id)) {
                    VStack(alignment: .leading) {
                        RoomBubble(room: room, size: 56)
                        Spacer()
                        Text(room.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(room.isOn ? "On" : "Off")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        } else {
            EmptyHomeView()
        }
    }
}

// MARK: - Control Centre

struct RoomControlValue {
    var isOn: Bool
    var room: RoomEntity
}

struct RoomControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: RoomControlConfiguration) -> RoomControlValue {
        RoomControlValue(isOn: true, room: configuration.room ?? .everywhere)
    }

    func currentValue(configuration: RoomControlConfiguration) async throws -> RoomControlValue {
        let room = configuration.room ?? .everywhere
        return RoomControlValue(isOn: LightControl.isOn(roomID: room.id, in: HomeStore.load()), room: room)
    }
}

struct RoomToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "LumenRoomControl", provider: RoomControlProvider()) { value in
            ControlWidgetToggle(value.room.name, isOn: value.isOn, action: SetRoomPowerIntent(room: value.room)) { isOn in
                Label(isOn ? "On" : "Off", systemImage: isOn ? "lightbulb.fill" : "lightbulb")
            }
            .tint(.orange)
        }
        .displayName("Room lights")
        .description("Switch a room's lights on or off.")
        .promptsForUserConfiguration()
    }
}

struct MoodControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: MoodControlConfiguration) -> MoodEntity? { configuration.mood }
    func currentValue(configuration: MoodControlConfiguration) async throws -> MoodEntity? { configuration.mood }
}

struct MoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "LumenMoodControl", provider: MoodControlProvider()) { mood in
            ControlWidgetButton(action: RunMoodIntent(mood: mood)) {
                Label(mood?.name ?? "Mood", systemImage: mood?.symbol ?? "sparkles")
            }
        }
        .displayName("Mood")
        .description("Set one of your saved moods.")
        .promptsForUserConfiguration()
    }
}

struct AllOffControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LumenAllOff") {
            ControlWidgetButton(action: AllOffIntent()) {
                Label("All lights off", systemImage: "lightbulb.slash")
            }
        }
        .displayName("All lights off")
        .description("Switch every light off.")
    }
}
