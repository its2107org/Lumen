import SwiftUI

struct HomeView: View {
    @State private var model = LightsModel.shared
    @State private var router = Router.shared

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    moodsRow
                    if !model.home.unassigned.isEmpty && !model.rooms.isEmpty {
                        setUpBanner
                    }
                    ForEach(model.rooms) { room in
                        let lights = model.bulbs(in: room)
                        if !lights.isEmpty {
                            roomSection(room: room, lights: lights)
                        }
                    }
                    let others = model.home.unassigned
                    if !others.isEmpty {
                        roomSection(room: nil, lights: others)
                    }
                    if model.rooms.isEmpty {
                        setUpBanner
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(AmbientBackground(colors: litColors))
            .navigationTitle("Lumen")
            .refreshable { await model.refreshNow() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.sheet = .settings } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button { router.sheet = .newMood } label: { Label("Save a mood", systemImage: "sparkles") }
                        Button { router.sheet = .newRoom } label: { Label("Add a room", systemImage: "square.split.bottomrightquarter") }
                        Button { router.sheet = .setUpLights } label: { Label("Name and arrange lights", systemImage: "lightbulb.2") }
                        Button { Task { await model.findLights() } } label: { Label("Find new lights", systemImage: "magnifyingglass") }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                    Button { model.allOff() } label: {
                        Image(systemName: "power")
                    }
                    .disabled(!model.anyOn)
                    .accessibilityLabel("All lights off")
                }
            }
        }
    }

    private var litColors: [Color] {
        let lit = model.bulbs.filter { $0.state.on && $0.reachable }
        var colors: [Color] = []
        for bulb in lit { for color in bulb.state.displayColors where !colors.contains(color) { colors.append(color) } }
        return Array(colors.prefix(4))
    }

    // MARK: Moods

    private var moodsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Moods")
                .font(.title3.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.moods) { mood in
                        Button { model.applyMood(mood) } label: { MoodChip(mood: mood) }
                            .buttonStyle(PressableStyle())
                            .contextMenu {
                                Button { router.sheet = .editMood(mood.id) } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) { model.deleteMood(mood) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    Button { router.sheet = .newMood } label: {
                        Label(model.moods.isEmpty ? "Save how your lights look now" : "New", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Rooms

    private func roomSection(room: Room?, lights: [Bulb]) -> some View {
        let onCount = lights.filter { $0.state.on }.count
        let ids = lights.map(\.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    router.openRoom(room)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: room?.symbol ?? "lightbulb.2")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(room?.name ?? "Other lights")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(onCount == 0 ? "All off" : onCount == lights.count ? "All on" : "\(onCount) of \(lights.count) on")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                PowerButton(isOn: onCount > 0) { model.toggle(ids) }
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(lights) { bulb in
                    LightTile(bulb: bulb)
                }
            }
        }
    }

    private var setUpBanner: some View {
        Button { router.sheet = .setUpLights } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Name your lights and put them in rooms")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Each light flashes so you can tell which is which.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Pieces

struct LightTile: View {
    let bulb: Bulb
    @State private var model = LightsModel.shared
    @State private var router = Router.shared
    @State private var renaming = false
    @State private var newName = ""

    private var isLit: Bool { bulb.state.on && bulb.reachable }

    var body: some View {
        Button {
            router.openLight(bulb)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Button { model.toggle([bulb.id]) } label: {
                        ZStack {
                            Circle()
                                .fill(isLit ? AnyShapeStyle(bulb.state.displayColor.gradient) : AnyShapeStyle(Color.secondary.opacity(0.18)))
                                .shadow(color: isLit ? bulb.state.displayColor.opacity(0.7) : .clear, radius: 10)
                            Image(systemName: bulb.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isLit ? (bulb.state.isDarkColour ? Color.white : Color.black.opacity(0.75)) : Color.secondary)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.88))
                    .accessibilityLabel(bulb.state.on ? "Turn off \(bulb.name)" : "Turn on \(bulb.name)")
                    Spacer()
                    if bulb.state.on && bulb.kind.hasBrightness && bulb.reachable {
                        Text("\(bulb.state.brightness)%")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                Spacer(minLength: 14)
                Text(bulb.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(bulb.reachable ? bulb.state.summary : "Not responding")
                    .font(.caption)
                    .foregroundStyle(bulb.reachable ? Color.secondary : Color.orange)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        if isLit {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(LinearGradient(colors: bulb.state.displayColors.map { $0.opacity(0.32) } + [.clear],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
            }
            .opacity(bulb.reachable ? 1 : 0.6)
        }
        .buttonStyle(PressableStyle())
        .animation(.smooth(duration: 0.25), value: bulb.state)
        .contextMenu {
            Button { model.toggle([bulb.id]) } label: {
                Label(bulb.state.on ? "Turn off" : "Turn on", systemImage: "power")
            }
            Button { model.identify(bulb) } label: { Label("Flash to find it", systemImage: "light.max") }
            Button { newName = bulb.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
            Menu {
                ForEach(model.rooms) { room in
                    Button { model.move(bulb.id, to: room.id) } label: {
                        if bulb.roomID == room.id { Label(room.name, systemImage: "checkmark") } else { Text(room.name) }
                    }
                }
                Button { model.move(bulb.id, to: nil) } label: { Text("No room") }
            } label: { Label("Move to room", systemImage: "arrow.right.square") }
        }
        .alert("Rename light", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { model.rename(bulb, to: newName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct MoodChip: View {
    let mood: Mood

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(AngularGradient(colors: mood.previewColors + [mood.previewColors.first ?? .orange], center: .center))
                Image(systemName: mood.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .frame(width: 34, height: 34)
            Text(mood.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.leading, 9)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(.thinMaterial, in: Capsule())
    }
}

struct PowerButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isOn ? Color.black.opacity(0.8) : Color.secondary)
                .frame(width: 40, height: 40)
                .background(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.thinMaterial), in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(isOn ? "Turn off" : "Turn on")
    }
}

/// A soft wash of the colours currently lit, behind everything.
struct AmbientBackground: View {
    var colors: [Color]

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            if !colors.isEmpty {
                LinearGradient(colors: colors.map { $0.opacity(0.28) }, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 420)
                    .blur(radius: 60)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.6), value: colors)
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
