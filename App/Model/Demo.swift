import Foundation

/// Pretend homes for screenshots, and an automatic check against a pretend light (used by the build checks).
enum Demo {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var isDemo: Bool { arguments.contains { $0.hasPrefix("-LumenDemo") } }

    /// Runs before anything loads, so the app starts with the pretend home.
    @MainActor
    static func prepareIfRequested() {
        guard isDemo else { return }
        WizLink.offline = true
        HomeStore.demoHome = arguments.contains("-LumenDemoWelcome") ? HomeSetup() : sampleHome()
        LightsModel.shared.replaceHome(HomeStore.load())
    }

    @MainActor
    static func runIfRequested() async {
        if arguments.contains("-LumenSelfTest") {
            await SelfTest.run()
            return
        }
        guard isDemo else { return }
        try? await Task.sleep(for: .milliseconds(300))
        let model = LightsModel.shared
        let router = Router.shared
        let living = model.rooms.first
        let bedroom = model.rooms.dropFirst().first
        if arguments.contains("-LumenDemoRoom") { router.openRoom(living, tab: .white) }
        if arguments.contains("-LumenDemoColour") { router.openRoom(bedroom, tab: .colour) }
        if arguments.contains("-LumenDemoScenes") { router.openRoom(living, tab: .scenes) }
        if arguments.contains("-LumenDemoSettings") { router.sheet = .settings }
        if arguments.contains("-LumenDemoMood") { router.sheet = .newMood }
    }

    static func sampleHome() -> HomeSetup {
        let living = Room(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Living room", symbol: "sofa.fill")
        let bedroom = Room(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Bedroom", symbol: "bed.double.fill")
        let kitchen = Room(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, name: "Kitchen", symbol: "cooktop.fill")

        func bulb(_ number: Int, _ name: String, _ room: Room, _ kind: LightKind, _ state: LightState) -> Bulb {
            Bulb(id: String(format: "a8bb50%06d", number), name: name, address: "192.168.1.\(40 + number)", kind: kind,
                 model: kind == .colour ? "ESP01_SHRGB1C_31" : "ESP06_SHDW9_01", minKelvin: 2200, maxKelvin: 6500,
                 roomID: room.id, state: state, reachable: true, signal: -55)
        }

        let bulbs = [
            bulb(1, "Floor lamp", living, .colour, LightState(on: true, brightness: 70, mode: .white(kelvin: 2700))),
            bulb(2, "Sofa lamp", living, .colour, LightState(on: true, brightness: 55, mode: .white(kelvin: 2400))),
            bulb(3, "Ceiling", living, .colour, LightState(on: false, brightness: 100, mode: .white(kelvin: 4000))),
            bulb(4, "Bookshelf", living, .colour, LightState(on: true, brightness: 40, mode: .colour(red: 255, green: 110, blue: 30))),
            bulb(5, "Bedside left", bedroom, .colour, LightState(on: true, brightness: 35, mode: .colour(red: 150, green: 60, blue: 255))),
            bulb(6, "Bedside right", bedroom, .colour, LightState(on: true, brightness: 35, mode: .colour(red: 255, green: 60, blue: 160))),
            bulb(7, "Pendant", kitchen, .colour, LightState(on: true, brightness: 100, mode: .white(kelvin: 4000))),
            bulb(8, "Under cabinets", kitchen, .dimmable, LightState(on: false, brightness: 80, mode: .white(kelvin: 2700)))
        ]

        func settings(_ pairs: [(Int, LightState)]) -> [String: LightState] {
            Dictionary(uniqueKeysWithValues: pairs.map { (bulbs[$0.0 - 1].id, $0.1) })
        }

        let moods = [
            Mood(id: UUID(), name: "Evening", symbol: "moon.stars.fill", settings: settings([
                (1, LightState(on: true, brightness: 60, mode: .white(kelvin: 2400))),
                (2, LightState(on: true, brightness: 45, mode: .white(kelvin: 2200))),
                (4, LightState(on: true, brightness: 40, mode: .colour(red: 255, green: 110, blue: 30)))
            ])),
            Mood(id: UUID(), name: "Film night", symbol: "film.fill", settings: settings([
                (1, LightState(on: false, brightness: 30, mode: .white(kelvin: 2200))),
                (3, LightState(on: false, brightness: 30, mode: .white(kelvin: 2200))),
                (4, LightState(on: true, brightness: 20, mode: .colour(red: 40, green: 80, blue: 255)))
            ])),
            Mood(id: UUID(), name: "Fireside", symbol: "flame.fill", settings: settings([
                (1, LightState(on: true, brightness: 50, mode: .scene(id: 5, speed: 100))),
                (2, LightState(on: true, brightness: 50, mode: .scene(id: 29, speed: 100)))
            ])),
            Mood(id: UUID(), name: "Bright", symbol: "sun.max.fill", settings: settings([
                (1, LightState(on: true, brightness: 100, mode: .white(kelvin: 4500))),
                (3, LightState(on: true, brightness: 100, mode: .white(kelvin: 4500)))
            ]))
        ]
        return HomeSetup(bulbs: bulbs, rooms: [living, bedroom, kitchen], moods: moods)
    }
}

/// End-to-end check against a pretend WiZ light running on the build machine: finds it, reads it,
/// changes it, and writes the result to Documents/selftest.json.
enum SelfTest {
    @MainActor
    static func run() async {
        var report: [String: Any] = [:]
        var problems: [String] = []
        let model = LightsModel.shared

        // Model-name parsing and message building.
        if LightKind(moduleName: "ESP01_SHRGB1C_31") != .colour { problems.append("colour model not recognised") }
        if LightKind(moduleName: "ESP15_SHTW1_01I") != .tunableWhite { problems.append("tunable white model not recognised") }
        if LightKind(moduleName: "ESP06_SHDW9_01") != .dimmable { problems.append("dimmable model not recognised") }
        let warm = LightState(on: true, brightness: 5, mode: .white(kelvin: 2700)).pilotParams(for: .colour)
        if warm["dimming"] as? Int != 10 || warm["temp"] as? Int != 2700 { problems.append("white message wrong: \(warm)") }

        // Discovery. If the build machine blocks the network search, fall back to asking it directly.
        await model.findLights()
        let searchWorked = !model.bulbs.isEmpty
        report["networkSearchFoundIt"] = searchWorked
        if !searchWorked { await model.findLights(extraAddress: "127.0.0.1") }
        report["found"] = model.bulbs.map { ["name": $0.name, "address": $0.address, "kind": $0.kind.rawValue, "model": $0.model, "range": "\($0.minKelvin)-\($0.maxKelvin)"] }
        guard let bulb = model.bulbs.first else {
            problems.append("no light found (own address \(LocalNetwork.ownAddress() ?? "none"), \(LocalNetwork.neighbourAddresses().count) addresses searched)")
            finish(report, problems)
            return
        }
        if bulb.kind != .colour { problems.append("pretend light should be colour, got \(bulb.kind)") }
        if bulb.minKelvin != 2200 { problems.append("white range not read: \(bulb.minKelvin)") }

        // Changes.
        let room = model.addRoom(name: "Test room", symbol: "sofa.fill")
        model.move(bulb.id, to: room.id)
        var home = HomeStore.load()
        home = await LightControl.apply(.mode(.colour(red: 255, green: 0, blue: 128)), to: [bulb.id], in: home)
        home = await LightControl.apply(.brightness(42), to: [bulb.id], in: home)
        HomeStore.save(home)
        let pilot = await WizLink.getPilot(bulb.address)
        var after: [String: String] = [:]
        for (key, value) in pilot ?? [:] { after[key] = "\(value)" }
        report["after"] = after
        if pilot?["r"] as? Int != 255 || pilot?["b"] as? Int != 128 { problems.append("colour not applied: \(String(describing: pilot))") }
        if pilot?["dimming"] as? Int != 42 { problems.append("brightness not applied") }

        // Shortcut-style actions.
        let turnedOn = await LightControl.toggleRoom(room.id.uuidString)
        if turnedOn { problems.append("toggle should have switched the room off") }
        let offPilot = await WizLink.getPilot(bulb.address)
        if offPilot?["state"] as? Bool != false { problems.append("toggle off not applied") }
        await LightControl.setRoom(RoomEntity.everywhereID, .mode(.scene(id: 5, speed: 150)))
        let scenePilot = await WizLink.getPilot(bulb.address)
        if scenePilot?["sceneId"] as? Int != 5 || scenePilot?["speed"] as? Int != 150 { problems.append("scene not applied") }

        // A light that changed address is found again.
        guard searchWorked else {
            finish(report, problems)
            return
        }
        var moved = HomeStore.load()
        if let index = moved.bulbs.firstIndex(where: { $0.id == bulb.id }) { moved.bulbs[index].address = "10.255.255.1" }
        moved = await LightControl.apply(.power(true), to: [bulb.id], in: moved)
        if moved.bulbs.first?.address != bulb.address { problems.append("moved light not found again") }

        finish(report, problems)
    }

    @MainActor
    private static func finish(_ report: [String: Any], _ problems: [String]) {
        var report = report
        report["problems"] = problems
        report["result"] = problems.isEmpty ? "all passed" : "failed"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("selftest.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
}
