import Foundation
import WidgetKit

/// Keeps the home set-up in the shared space so the app, widgets, Control Centre buttons and
/// shortcuts all see the same lights, rooms and moods.
enum HomeStore {
    private static let service = "lumen.home"
    private static let account = "setup"

    /// Demo mode keeps its pretend home in memory only.
    nonisolated(unsafe) static var demoHome: HomeSetup?

    static func load() -> HomeSetup {
        if let demoHome { return demoHome }
        guard let data = SharedVault.read(service: service, account: account),
              let home = try? JSONDecoder().decode(HomeSetup.self, from: data) else { return HomeSetup() }
        return home
    }

    static func save(_ home: HomeSetup, refreshWidgets: Bool = true) {
        if demoHome != nil {
            demoHome = home
        } else if let data = try? JSONEncoder().encode(home) {
            SharedVault.write(data, service: service, account: account)
        }
        if refreshWidgets { refreshSystemSurfaces() }
    }

    static func refreshSystemSurfaces() {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}

/// A change to make to one or more lights.
enum LightChange: Hashable {
    case power(Bool)
    case brightness(Int)
    case mode(LightMode)
    case state(LightState)

    func applied(to state: LightState) -> LightState {
        var next = state
        switch self {
        case .power(let on): next.on = on
        case .brightness(let value): next.on = true; next.brightness = min(100, max(10, value))
        case .mode(let mode): next.on = true; next.mode = mode
        case .state(let full): next = full
        }
        return next
    }

    /// The message to send. Switching on only says "on", so each light comes back exactly as it was.
    func params(for bulb: Bulb, newState: LightState) -> [String: Any] {
        switch self {
        case .power(let on):
            return ["state": on]
        case .brightness(let value):
            if bulb.kind == .plug { return ["state": true] }
            return ["state": true, "dimming": min(100, max(10, value))]
        case .mode, .state:
            return newState.pilotParams(for: bulb.kind)
        }
    }
}

/// Sends changes to lights and keeps track of how they look.
enum LightControl {
    /// Applies changes to lights and returns the updated home. Lights that don't answer are looked for
    /// again on the network (their address may have changed) and tried once more.
    static func apply(_ changes: [String: LightChange], in home: HomeSetup) async -> HomeSetup {
        var home = home
        let targets = home.bulbs.filter { changes[$0.id] != nil }
        guard !targets.isEmpty else { return home }

        var failed = await send(changes, to: targets, home: &home)
        if !failed.isEmpty {
            home = await relocate(home)
            let retry = home.bulbs.filter { failed.contains($0.id) }
            failed = await send(changes, to: retry, home: &home)
        }
        for index in home.bulbs.indices where changes[home.bulbs[index].id] != nil {
            home.bulbs[index].reachable = !failed.contains(home.bulbs[index].id)
        }
        return home
    }

    static func apply(_ change: LightChange, to ids: [String], in home: HomeSetup) async -> HomeSetup {
        await apply(Dictionary(uniqueKeysWithValues: ids.map { ($0, change) }), in: home)
    }

    /// Returns the ids of lights that didn't answer.
    private static func send(_ changes: [String: LightChange], to bulbs: [Bulb], home: inout HomeSetup) async -> Set<String> {
        let results = await withTaskGroup(of: (String, LightState, Bool).self) { group in
            for bulb in bulbs {
                guard let change = changes[bulb.id] else { continue }
                let newState = change.applied(to: bulb.state)
                let params = change.params(for: bulb, newState: newState)
                group.addTask {
                    var ok = true
                    if !WizLink.offline { ok = await WizLink.setPilot(params, on: bulb.address) }
                    return (bulb.id, newState, ok)
                }
            }
            var collected: [(String, LightState, Bool)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        var failed: Set<String> = []
        for (id, state, ok) in results {
            guard let index = home.bulbs.firstIndex(where: { $0.id == id }) else { continue }
            if ok { home.bulbs[index].state = state } else { failed.insert(id) }
        }
        return failed
    }

    /// Finds lights whose address has changed, by their hardware address.
    static func relocate(_ home: HomeSetup) async -> HomeSetup {
        var home = home
        let found = await WizLink.discover(rounds: 1)
        for light in found {
            if let index = home.bulbs.firstIndex(where: { $0.id == light.mac }) {
                home.bulbs[index].address = light.address
            }
        }
        return home
    }

    /// Asks every light how it looks right now.
    static func refresh(_ home: HomeSetup) async -> HomeSetup {
        var home = home
        let results = await withTaskGroup(of: (String, [String: Any]?).self) { group in
            for bulb in home.bulbs {
                group.addTask {
                    let reply = await WizLink.request("getPilot", to: bulb.address, timeout: 0.6, attempts: 2)
                    return (bulb.id, reply?["result"] as? [String: Any])
                }
            }
            var collected: [(String, [String: Any]?)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        var missing = false
        for (id, pilot) in results {
            guard let index = home.bulbs.firstIndex(where: { $0.id == id }) else { continue }
            if let pilot {
                home.bulbs[index].state = LightState(pilot: pilot, fallback: home.bulbs[index].state)
                home.bulbs[index].signal = pilot["rssi"] as? Int
                home.bulbs[index].reachable = true
            } else {
                home.bulbs[index].reachable = false
                missing = true
            }
        }
        if missing {
            let before = home.bulbs.map(\.address)
            home = await relocate(home)
            if home.bulbs.map(\.address) != before { return await refresh(home) }
        }
        return home
    }

    /// Looks for lights on the network and adds any new ones. Returns the updated home and how many were new.
    static func findLights(in home: HomeSetup, extraAddresses: [String] = []) async -> (HomeSetup, Int) {
        var home = home
        let found = await WizLink.discover(extraAddresses: extraAddresses)
        var added = 0
        for light in found.sorted(by: { $0.address.localizedStandardCompare($1.address) == .orderedAscending }) {
            var pilot: [String: Any] = [:]
            for (key, value) in light.pilot { pilot[key] = value.base }
            if let index = home.bulbs.firstIndex(where: { $0.id == light.mac }) {
                home.bulbs[index].address = light.address
                home.bulbs[index].reachable = true
                home.bulbs[index].state = LightState(pilot: pilot, fallback: home.bulbs[index].state)
                continue
            }
            let details = await WizLink.details(light.address)
            let model = details?.model ?? ""
            let number = home.bulbs.count + 1
            home.bulbs.append(Bulb(
                id: light.mac,
                name: "Light \(number)",
                address: light.address,
                kind: model.isEmpty ? .colour : LightKind(moduleName: model),
                model: model,
                minKelvin: details?.minKelvin ?? 2200,
                maxKelvin: details?.maxKelvin ?? 6500,
                roomID: nil,
                state: LightState(pilot: pilot),
                reachable: true,
                signal: pilot["rssi"] as? Int
            ))
            added += 1
        }
        return (home, added)
    }

    // MARK: Handy group actions (used by widgets, Control Centre and shortcuts)

    static func ids(forRoom roomID: String, in home: HomeSetup) -> [String] {
        if roomID == RoomEntity.everywhereID { return home.bulbs.map(\.id) }
        return home.bulbs.filter { $0.roomID?.uuidString == roomID }.map(\.id)
    }

    static func isOn(roomID: String, in home: HomeSetup) -> Bool {
        let ids = Set(ids(forRoom: roomID, in: home))
        return home.bulbs.contains { ids.contains($0.id) && $0.state.on }
    }

    @discardableResult
    static func setRoom(_ roomID: String, _ change: LightChange) async -> HomeSetup {
        let home = HomeStore.load()
        let updated = await apply(change, to: ids(forRoom: roomID, in: home), in: home)
        HomeStore.save(updated)
        return updated
    }

    @discardableResult
    static func toggleRoom(_ roomID: String) async -> Bool {
        let home = HomeStore.load()
        let turnOn = !isOn(roomID: roomID, in: home)
        let updated = await apply(.power(turnOn), to: ids(forRoom: roomID, in: home), in: home)
        HomeStore.save(updated)
        return turnOn
    }

    static func applyMood(_ moodID: String) async {
        let home = HomeStore.load()
        guard let mood = home.moods.first(where: { $0.id.uuidString == moodID }) else { return }
        let changes = mood.settings.mapValues { LightChange.state($0) }
        HomeStore.save(await apply(changes, in: home))
    }
}
