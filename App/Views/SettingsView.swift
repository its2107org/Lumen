import SwiftUI

struct SettingsView: View {
    @State private var model = LightsModel.shared
    @State private var router = Router.shared
    @State private var editingRoom: Room?
    @State private var editingMood: Mood?
    @State private var addingRoom = false
    @State private var addingAddress = false
    @State private var address = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Lights") {
                    ForEach(model.bulbs) { bulb in
                        NavigationLink {
                            BulbDetailView(bulbID: bulb.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: bulb.symbol)
                                    .foregroundStyle(bulb.reachable ? (bulb.state.on ? Color.accentColor : .secondary) : .orange)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(bulb.name)
                                    Text(model.home.room(bulb.roomID)?.name ?? "No room")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !bulb.reachable {
                                    Text("Not responding").font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    Button {
                        Task { await model.findLights() }
                    } label: {
                        HStack {
                            Label(model.isSearching ? "Searching…" : "Find new lights", systemImage: "magnifyingglass")
                            Spacer()
                            if model.isSearching { ProgressView() }
                        }
                    }
                    .disabled(model.isSearching)
                    if let message = model.lastSearchMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button { addingAddress = true } label: {
                        Label("Add a light by its address", systemImage: "number")
                    }
                }

                Section("Rooms") {
                    ForEach(model.rooms) { room in
                        Button { editingRoom = room } label: {
                            HStack(spacing: 12) {
                                Image(systemName: room.symbol).foregroundStyle(.secondary).frame(width: 24)
                                Text(room.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(model.bulbs(in: room).count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { model.moveRooms(from: $0, to: $1) }
                    .onDelete { offsets in offsets.map { model.rooms[$0] }.forEach(model.deleteRoom) }
                    Button { addingRoom = true } label: { Label("Add a room", systemImage: "plus") }
                }

                Section("Moods") {
                    ForEach(model.moods) { mood in
                        Button { editingMood = mood } label: {
                            HStack(spacing: 12) {
                                Image(systemName: mood.symbol).foregroundStyle(.secondary).frame(width: 24)
                                Text(mood.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(mood.settings.count) lights").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { model.moveMoods(from: $0, to: $1) }
                    .onDelete { offsets in offsets.map { model.moods[$0] }.forEach(model.deleteMood) }
                    Button { router.sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.sheet = .newMood } } label: {
                        Label("Save a mood", systemImage: "plus")
                    }
                }

                Section {
                    LabeledContent("Lights", value: "\(model.bulbs.count)")
                    LabeledContent("This phone's address", value: LocalNetwork.ownAddress() ?? "Not on Wi-Fi")
                } header: {
                    Text("About")
                } footer: {
                    Text("Lumen talks to your lights directly over your home Wi-Fi. Nothing goes through the internet, and it works alongside the WiZ app and Apple Home.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editingRoom) { RoomEditor(existing: $0) }
            .sheet(item: $editingMood) { MoodEditor(existing: $0) }
            .sheet(isPresented: $addingRoom) { RoomEditor(existing: nil) }
            .alert("Add a light", isPresented: $addingAddress) {
                TextField("For example 192.168.1.40", text: $address)
                    .keyboardType(.decimalPad)
                Button("Add") {
                    let value = address.trimmingCharacters(in: .whitespaces)
                    Task { await model.findLights(extraAddress: value) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only needed if a light doesn't turn up by itself. The WiZ app shows each light's address under its settings.")
            }
        }
    }
}

struct BulbDetailView: View {
    let bulbID: String
    @State private var model = LightsModel.shared
    @State private var name = ""
    @State private var confirmForget = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let bulb = model.bulb(bulbID) {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                        .onSubmit { model.rename(bulb, to: name) }
                }
                Section("Room") {
                    Picker("Room", selection: Binding(get: { bulb.roomID }, set: { model.move(bulb.id, to: $0) })) {
                        Text("No room").tag(UUID?.none)
                        ForEach(model.rooms) { room in
                            Label(room.name, systemImage: room.symbol).tag(UUID?.some(room.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Button { model.identify(bulb) } label: { Label("Flash to find it", systemImage: "light.max") }
                }
                Section("Details") {
                    LabeledContent("Type", value: bulb.kind.label)
                    if bulb.kind.hasWhiteTuning {
                        LabeledContent("White range", value: "\(bulb.minKelvin)K to \(bulb.maxKelvin)K")
                    }
                    LabeledContent("Model", value: bulb.model.isEmpty ? "Unknown" : bulb.model)
                    LabeledContent("Address", value: bulb.address)
                    LabeledContent("Status", value: bulb.reachable ? "Responding" : "Not responding")
                    if let signal = bulb.signal {
                        LabeledContent("Wi-Fi signal", value: signal > -60 ? "Strong" : signal > -72 ? "Good" : "Weak")
                    }
                }
                Section {
                    Button("Forget this light", role: .destructive) { confirmForget = true }
                } footer: {
                    Text("It will come back next time you search for lights.")
                }
            }
            .navigationTitle(bulb.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { name = bulb.name }
            .onDisappear { if let current = model.bulb(bulbID), name != current.name { model.rename(current, to: name) } }
            .confirmationDialog("Forget \(bulb.name)?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) {
                    model.forget(bulb)
                    dismiss()
                }
            }
        } else {
            ContentUnavailableView("Light removed", systemImage: "lightbulb.slash")
        }
    }
}
