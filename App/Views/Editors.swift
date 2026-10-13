import SwiftUI

enum Symbols {
    static let rooms = [
        "sofa.fill", "bed.double.fill", "fork.knife", "cooktop.fill", "shower.fill", "bathtub.fill",
        "desktopcomputer", "books.vertical.fill", "tv.fill", "door.left.hand.open", "stairs", "tree.fill",
        "car.fill", "figure.and.child.holdinghands", "lamp.desk.fill", "lamp.floor.fill", "washer.fill", "house.fill"
    ]

    static let moods = [
        "sparkles", "sun.max.fill", "moon.stars.fill", "flame.fill", "book.fill", "film.fill",
        "fork.knife", "wineglass.fill", "bed.double.fill", "music.note", "heart.fill", "leaf.fill",
        "cup.and.saucer.fill", "figure.yoga", "party.popper.fill", "gamecontroller.fill", "briefcase.fill", "sunrise.fill"
    ]

    static let roomSuggestions: [(String, String)] = [
        ("Living room", "sofa.fill"), ("Bedroom", "bed.double.fill"), ("Kitchen", "cooktop.fill"),
        ("Dining room", "fork.knife"), ("Office", "desktopcomputer"), ("Hall", "door.left.hand.open"),
        ("Bathroom", "shower.fill"), ("Guest room", "bed.double.fill")
    ]

    static let moodSuggestions: [(String, String)] = [
        ("Evening", "moon.stars.fill"), ("Reading", "book.fill"), ("Film night", "film.fill"),
        ("Dinner", "wineglass.fill"), ("Bright", "sun.max.fill"), ("Wind down", "bed.double.fill")
    ]
}

struct SymbolGrid: View {
    let symbols: [String]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                Button { selection = symbol } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(selection == symbol ? Color.white : Color.primary)
                        .background(selection == symbol ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.12)), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Rooms

struct RoomEditor: View {
    let existing: Room?

    @State private var model = LightsModel.shared
    @State private var name = ""
    @State private var symbol = "sofa.fill"
    @State private var members: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Room name", text: $name)
                        .font(.title3)
                    if existing == nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Symbols.roomSuggestions, id: \.0) { suggestion in
                                    Button(suggestion.0) {
                                        name = suggestion.0
                                        symbol = suggestion.1
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                Section("Icon") {
                    SymbolGrid(symbols: Symbols.rooms, selection: $symbol)
                }
                if !model.bulbs.isEmpty {
                    Section("Lights in this room") {
                        ForEach(model.bulbs) { bulb in
                            Button {
                                if members.contains(bulb.id) { members.remove(bulb.id) } else { members.insert(bulb.id) }
                            } label: {
                                HStack {
                                    Image(systemName: bulb.symbol).foregroundStyle(.secondary).frame(width: 26)
                                    VStack(alignment: .leading) {
                                        Text(bulb.name).foregroundStyle(.primary)
                                        if let room = model.home.room(bulb.roomID), room.id != existing?.id {
                                            Text("Now in \(room.name)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: members.contains(bulb.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(members.contains(bulb.id) ? Color.accentColor : Color.secondary)
                                        .font(.title3)
                                }
                            }
                        }
                    }
                }
                if let existing {
                    Section {
                        Button("Delete room", role: .destructive) {
                            model.deleteRoom(existing)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New room" : "Edit room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    symbol = existing.symbol
                    members = Set(model.bulbs.filter { $0.roomID == existing.id }.map(\.id))
                }
            }
        }
    }

    private func save() {
        var room: Room
        if var existing {
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.symbol = symbol
            model.updateRoom(existing)
            room = existing
        } else {
            room = model.addRoom(name: name, symbol: symbol)
        }
        for bulb in model.bulbs {
            if members.contains(bulb.id) {
                if bulb.roomID != room.id { model.move(bulb.id, to: room.id) }
            } else if bulb.roomID == room.id {
                model.move(bulb.id, to: nil)
            }
        }
        dismiss()
    }
}

// MARK: - Moods

struct MoodEditor: View {
    let existing: Mood?

    @State private var model = LightsModel.shared
    @State private var name = ""
    @State private var symbol = "sparkles"
    @State private var included: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mood name", text: $name)
                        .font(.title3)
                    if existing == nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Symbols.moodSuggestions, id: \.0) { suggestion in
                                    Button(suggestion.0) {
                                        name = suggestion.0
                                        symbol = suggestion.1
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                } footer: {
                    Text(existing == nil
                         ? "Saves how the ticked lights look right now, including lights that are off."
                         : "Tap Update to save how the ticked lights look right now.")
                }
                Section("Icon") {
                    SymbolGrid(symbols: Symbols.moods, selection: $symbol)
                }
                Section("Lights") {
                    ForEach(groupedLights, id: \.0) { title, lights in
                        ForEach(lights) { bulb in
                            Button {
                                if included.contains(bulb.id) { included.remove(bulb.id) } else { included.insert(bulb.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(bulb.state.on ? AnyShapeStyle(bulb.state.displayColor.gradient) : AnyShapeStyle(Color.secondary.opacity(0.2)))
                                        .frame(width: 26, height: 26)
                                    VStack(alignment: .leading) {
                                        Text(bulb.name).foregroundStyle(.primary)
                                        Text("\(title) · \(bulb.state.on ? "\(bulb.state.brightness)% \(bulb.state.summary.lowercased())" : "off")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: included.contains(bulb.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(included.contains(bulb.id) ? Color.accentColor : Color.secondary)
                                        .font(.title3)
                                }
                            }
                        }
                    }
                }
                if let existing {
                    Section {
                        Button("Rename only") {
                            model.renameMood(existing, name: name, symbol: symbol)
                            dismiss()
                        }
                        Button("Delete mood", role: .destructive) {
                            model.deleteMood(existing)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Save a mood" : "Edit mood")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Save" : "Update") {
                        model.saveMood(name: name, symbol: symbol, lightIDs: Array(included), replacing: existing)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || included.isEmpty)
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    symbol = existing.symbol
                    included = Set(existing.settings.keys)
                } else {
                    included = Set(model.bulbs.map(\.id))
                }
            }
        }
    }

    private var groupedLights: [(String, [Bulb])] {
        var groups: [(String, [Bulb])] = model.rooms.map { ($0.name, model.bulbs(in: $0)) }
        groups.append(("No room", model.home.unassigned))
        return groups.filter { !$0.1.isEmpty }
    }
}

// MARK: - Naming and arranging lights

struct SetUpLightsView: View {
    @State private var model = LightsModel.shared
    @State private var router = Router.shared
    @State private var addingRoom = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.bulbs) { bulb in
                        SetUpRow(bulb: bulb, addRoom: { addingRoom = true })
                    }
                } footer: {
                    Text("Tap Flash and watch which light blinks, then give it a name and a room.")
                }
            }
            .navigationTitle("Your lights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $addingRoom) { RoomEditor(existing: nil) }
        }
    }
}

private struct SetUpRow: View {
    let bulb: Bulb
    let addRoom: () -> Void
    @State private var model = LightsModel.shared
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: bulb.symbol)
                    .foregroundStyle(bulb.state.on ? Color.accentColor : .secondary)
                    .frame(width: 24)
                TextField("Name", text: $name)
                    .font(.body.weight(.medium))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { model.rename(bulb, to: name) }
                    .onChange(of: focused) { _, isFocused in if !isFocused { model.rename(bulb, to: name) } }
                Button {
                    model.identify(bulb)
                } label: {
                    Label("Flash", systemImage: "light.max")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
            Menu {
                ForEach(model.rooms) { room in
                    Button { model.move(bulb.id, to: room.id) } label: { Label(room.name, systemImage: room.symbol) }
                }
                Button { model.move(bulb.id, to: nil) } label: { Text("No room") }
                Divider()
                Button { addRoom() } label: { Label("New room…", systemImage: "plus") }
            } label: {
                HStack(spacing: 6) {
                    Text(model.home.room(bulb.roomID)?.name ?? "Choose a room")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.subheadline)
            }
            .padding(.leading, 34)
        }
        .padding(.vertical, 4)
        .onAppear { name = bulb.name }
    }
}
