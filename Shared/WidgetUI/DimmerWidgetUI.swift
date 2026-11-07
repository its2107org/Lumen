import AppIntents
import SwiftUI

// The look of the widgets that dim and colour a room. Shared with the app so the build checks can
// take pictures of them.

/// How one room looks right now, for widgets.
struct RoomInfo: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let isOn: Bool
    let colors: [Color]
    let darkColour: Bool
    /// Average brightness of the lit lights (10 to 100).
    var brightness: Int = 0
    /// e.g. "Warm white" or "Blue".
    var summary: String = "Off"
    /// How the first lit light looks, to mark the matching swatch.
    var mode: LightMode?
    var hasColour = true
    var hasWhiteTuning = true

    static func make(roomID: String, name: String, symbol: String, home: HomeSetup) -> RoomInfo {
        let ids = Set(LightControl.ids(forRoom: roomID, in: home))
        let inRoom = home.bulbs.filter { ids.contains($0.id) }
        let lit = inRoom.filter(\.state.on)
        var colors: [Color] = []
        for bulb in lit { for color in bulb.state.displayColors where !colors.contains(color) { colors.append(color) } }
        return RoomInfo(id: roomID, name: name, symbol: symbol, isOn: !lit.isEmpty, colors: Array(colors.prefix(3)),
                        darkColour: lit.first?.state.isDarkColour ?? false,
                        brightness: LightControl.brightness(roomID: roomID, in: home),
                        summary: lit.first?.state.summary ?? "Off",
                        mode: lit.first?.state.mode,
                        hasColour: inRoom.isEmpty || inRoom.contains { $0.kind.hasColour },
                        hasWhiteTuning: inRoom.isEmpty || inRoom.contains { $0.kind.hasWhiteTuning })
    }

    static func all(in home: HomeSetup) -> [RoomInfo] {
        let rooms = home.rooms.filter { room in home.bulbs.contains { $0.roomID == room.id } }
        if rooms.isEmpty {
            return [make(roomID: RoomEntity.everywhereID, name: "All lights", symbol: "house.fill", home: home)]
        }
        return rooms.map { make(roomID: $0.id.uuidString, name: $0.name, symbol: $0.symbol, home: home) }
    }
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

/// One tappable colour on the dimmer widget.
struct Swatch: Identifiable, Hashable {
    let id: String
    let mode: LightMode
    let color: Color

    static func white(_ preset: WhitePreset) -> Swatch {
        Swatch(id: "w\(preset.kelvin)", mode: .white(kelvin: preset.kelvin), color: .kelvin(preset.kelvin))
    }

    static func colour(_ rgb: RGB) -> Swatch {
        Swatch(id: "c\(rgb.red)-\(rgb.green)-\(rgb.blue)", mode: .colour(red: rgb.red, green: rgb.green, blue: rgb.blue), color: rgb.color)
    }

    var intentValues: (kelvin: Int, red: Int, green: Int, blue: Int) {
        switch mode {
        case .white(let kelvin): (kelvin, 0, 0, 0)
        case .colour(let red, let green, let blue): (0, red, green, blue)
        case .scene: (2700, 0, 0, 0)
        }
    }
}

enum DimmerLayout {
    case small, medium, large, lockScreen
}

/// The brightness levels the bar's segments jump to.
let dimmerLevels = [20, 40, 60, 80, 100]

struct DimmerWidgetView: View {
    let room: RoomInfo?
    let home: HomeSetup
    let layout: DimmerLayout

    var body: some View {
        if let room, !home.bulbs.isEmpty {
            switch layout {
            case .lockScreen: lockScreen(room)
            case .small: small(room)
            case .medium: medium(room)
            case .large: large(room)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "lightbulb.2").font(.title2).foregroundStyle(.secondary)
                Text("Open Lumen to find your lights").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Layouts

    private func small(_ room: RoomInfo) -> some View {
        VStack(spacing: 10) {
            header(room, bubble: 30, compact: true)
            HStack(spacing: 8) {
                stepButton(room, step: -10, height: 40)
                stepButton(room, step: 10, height: 40)
            }
            HStack(spacing: 0) {
                ForEach(swatches(for: room, whites: 2, colours: 2)) { swatch in
                    swatchButton(swatch, room: room, size: 26)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func medium(_ room: RoomInfo) -> some View {
        VStack(spacing: 12) {
            header(room, bubble: 34, compact: false)
            levelRow(room, height: 30)
            HStack(spacing: 0) {
                ForEach(swatches(for: room, whites: 3, colours: 5)) { swatch in
                    swatchButton(swatch, room: room, size: 28)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func large(_ room: RoomInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(room, bubble: 40, compact: false)
            levelRow(room, height: 40)
            sectionLabel("Whites")
            HStack(spacing: 0) {
                ForEach(whiteSwatches(for: room, count: 6)) { swatch in
                    swatchButton(swatch, room: room, size: 32)
                        .frame(maxWidth: .infinity)
                }
            }
            if room.hasColour {
                sectionLabel("Colours")
                HStack(spacing: 0) {
                    ForEach(colourSwatches(for: room, count: 6)) { swatch in
                        swatchButton(swatch, room: room, size: 32)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func lockScreen(_ room: RoomInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: room.isOn ? "lightbulb.fill" : "lightbulb")
                Text(room.name).lineLimit(1)
                Spacer(minLength: 2)
                Text(room.isOn ? "\(room.brightness)%" : "Off")
                    .monospacedDigit()
                    .invalidatableContent()
            }
            .font(.headline)
            HStack(spacing: 6) {
                lockStep(room, step: -10)
                HStack(spacing: 2) {
                    ForEach(dimmerLevels, id: \.self) { level in
                        Button(intent: WidgetBrightnessIntent(roomID: room.id, level: level)) {
                            Capsule()
                                .fill(Color.primary.opacity(room.isOn && room.brightness >= level - 9 ? 1 : 0.25))
                                .frame(height: 10)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(level) per cent")
                    }
                }
                lockStep(room, step: 10)
            }
        }
    }

    // MARK: Pieces

    private func header(_ room: RoomInfo, bubble: CGFloat, compact: Bool) -> some View {
        HStack(spacing: 8) {
            if !compact { RoomBubble(room: room, size: bubble) }
            VStack(alignment: .leading, spacing: 0) {
                Text(room.name)
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .lineLimit(1)
                Text(room.isOn ? (compact ? "\(room.brightness)%" : "\(room.brightness)% · \(room.summary)") : "Off")
                    .font(compact ? .title3.weight(.semibold) : .caption)
                    .monospacedDigit()
                    .foregroundStyle(compact ? .primary : .secondary)
                    .lineLimit(1)
                    .invalidatableContent()
            }
            Spacer(minLength: 4)
            Button(intent: WidgetToggleRoomIntent(roomID: room.id)) {
                Image(systemName: "power")
                    .font(.system(size: compact ? 13 : 15, weight: .bold))
                    .foregroundStyle(room.isOn ? (room.darkColour ? Color.white : Color.black.opacity(0.8)) : Color.secondary)
                    .frame(width: bubble, height: bubble)
                    .background(Circle().fill(room.isOn ? AnyShapeStyle(room.colors.first ?? .orange) : AnyShapeStyle(Color.secondary.opacity(0.18))))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(room.isOn ? "Switch off" : "Switch on")
        }
    }

    private func levelRow(_ room: RoomInfo, height: CGFloat) -> some View {
        HStack(spacing: 8) {
            stepButton(room, step: -10, height: height, width: height + 6)
            HStack(spacing: 4) {
                ForEach(dimmerLevels, id: \.self) { level in
                    Button(intent: WidgetBrightnessIntent(roomID: room.id, level: level)) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(room.isOn && room.brightness >= level - 9 ? AnyShapeStyle(fill(for: room)) : AnyShapeStyle(Color.secondary.opacity(0.18)))
                            .frame(height: height)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(level) per cent")
                }
            }
            stepButton(room, step: 10, height: height, width: height + 6)
        }
    }

    private func fill(for room: RoomInfo) -> LinearGradient {
        let first = room.colors.first ?? .orange
        return LinearGradient(colors: [first.opacity(0.75), first], startPoint: .leading, endPoint: .trailing)
    }

    private func stepButton(_ room: RoomInfo, step: Int, height: CGFloat, width: CGFloat? = nil) -> some View {
        Button(intent: WidgetStepBrightnessIntent(roomID: room.id, step: step)) {
            Image(systemName: step < 0 ? "minus" : "plus")
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: width ?? .infinity)
                .frame(width: width, height: height)
                .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step < 0 ? "Dimmer" : "Brighter")
    }

    private func lockStep(_ room: RoomInfo, step: Int) -> some View {
        Button(intent: WidgetStepBrightnessIntent(roomID: room.id, step: step)) {
            Image(systemName: step < 0 ? "minus.circle.fill" : "plus.circle.fill")
                .font(.title3)
                .frame(minWidth: 28, minHeight: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step < 0 ? "Dimmer" : "Brighter")
    }

    private func swatchButton(_ swatch: Swatch, room: RoomInfo, size: CGFloat) -> some View {
        let values = swatch.intentValues
        let selected = room.isOn && room.mode == swatch.mode
        return Button(intent: WidgetColourIntent(roomID: room.id, kelvin: values.kelvin, red: values.red, green: values.green, blue: values.blue)) {
            Circle()
                .fill(swatch.color)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .padding(selected ? 3 : 0)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.85 : 0), lineWidth: 2))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, -6)
    }

    // MARK: Which swatches to show

    private func whiteSwatches(for room: RoomInfo, count: Int) -> [Swatch] {
        guard room.hasWhiteTuning else { return [] }
        let presets: [WhitePreset] = switch count {
        case ...2: [.warm, .daylight]
        case 3: [.candle, .warm, .daylight]
        case 4: [.candle, .warm, .neutral, .cool]
        default: WhitePreset.allCases
        }
        return presets.map(Swatch.white)
    }

    private func colourSwatches(for room: RoomInfo, count: Int) -> [Swatch] {
        guard room.hasColour else { return [] }
        var colours = home.favouriteColours.isEmpty ? RGB.defaultFavourites : home.favouriteColours
        // With few slots, spread the picks round the colour wheel.
        if colours.count > count, count <= 3 {
            let gap = colours.count / count
            colours = (0..<count).map { colours[$0 * gap] }
        }
        return Array(colours.prefix(count)).map(Swatch.colour)
    }

    /// A mix of whites and colours, giving any spare colour slots to whites when the room can't do colour.
    private func swatches(for room: RoomInfo, whites: Int, colours: Int) -> [Swatch] {
        let colourPicks = colourSwatches(for: room, count: colours)
        let whitePicks = whiteSwatches(for: room, count: whites + (colours - colourPicks.count))
        return whitePicks + colourPicks
    }
}

extension ColourChoice {
    var name: String { String(localized: Self.caseDisplayRepresentations[self]?.title ?? "Colour") }

    var isWhite: Bool {
        if case .white = mode { return true }
        return false
    }

    var tint: Color { LightState(on: true, brightness: 100, mode: mode).displayColor }
}
