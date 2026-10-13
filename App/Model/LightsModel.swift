import Foundation
import SwiftUI
import UIKit

/// The app's live view of the home: lights, rooms and moods, kept in step with the real lights.
@MainActor
@Observable
final class LightsModel {
    static let shared = LightsModel()

    private(set) var home: HomeSetup
    private(set) var isSearching = false
    private(set) var lastSearchMessage: String?
    private(set) var hasSearchedOnce = false

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var quietUntil = Date.distantPast
    @ObservationIgnored private var pending: [String: [String: Any]] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private init() {
        home = HomeStore.load()
    }

    // MARK: Reading

    var rooms: [Room] { home.rooms }
    var moods: [Mood] { home.moods }
    var bulbs: [Bulb] { home.bulbs }

    func bulbs(in room: Room?) -> [Bulb] { home.bulbs(in: room) }

    func bulb(_ id: String) -> Bulb? { home.bulbs.first { $0.id == id } }

    func bulbs(_ ids: [String]) -> [Bulb] { ids.compactMap(bulb) }

    var anyOn: Bool { home.bulbs.contains { $0.state.on } }

    // MARK: Keeping in step with the lights

    func appBecameActive() {
        home = HomeStore.load()
        startPolling()
        if home.bulbs.isEmpty, !hasSearchedOnce {
            Task { await findLights() }
        }
    }

    func appWentToBackground() {
        pollTask?.cancel()
        pollTask = nil
        flushNow()
        HomeStore.save(home)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshIfQuiet()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private func refreshIfQuiet() async {
        guard !home.bulbs.isEmpty, Date() > quietUntil, !WizLink.offline else { return }
        let before = home
        let refreshed = await LightControl.refresh(before)
        // Ignore the answer if the user changed something meanwhile.
        guard Date() > quietUntil else { return }
        var merged = home
        for bulb in refreshed.bulbs {
            guard let index = merged.bulbs.firstIndex(where: { $0.id == bulb.id }) else { continue }
            merged.bulbs[index].state = bulb.state
            merged.bulbs[index].reachable = bulb.reachable
            merged.bulbs[index].address = bulb.address
            merged.bulbs[index].signal = bulb.signal
        }
        if merged != home {
            home = merged
            HomeStore.save(home)
        }
    }

    func refreshNow() async {
        quietUntil = .distantPast
        await refreshIfQuiet()
    }

    /// Looks for lights on the home Wi-Fi. The first time, iOS asks permission while the search runs,
    /// so if nothing turns up Lumen quietly tries again a few times.
    func findLights(extraAddress: String? = nil) async {
        if isSearching {
            // One search at a time: wait for the one already running.
            while isSearching { try? await Task.sleep(for: .milliseconds(100)) }
            if extraAddress == nil { return }
        }
        isSearching = true
        lastSearchMessage = nil
        defer { isSearching = false; hasSearchedOnce = true }

        var added = 0
        var attempts = 0
        repeat {
            let (updated, count) = await LightControl.findLights(in: home, extraAddresses: extraAddress.map { [$0] } ?? [])
            home = updated
            added += count
            attempts += 1
            if home.bulbs.isEmpty, attempts < 4 { try? await Task.sleep(for: .seconds(2.5)) }
        } while home.bulbs.isEmpty && attempts < 4

        HomeStore.save(home)
        if home.bulbs.isEmpty {
            lastSearchMessage = "No lights found yet."
        } else if added == 0 {
            lastSearchMessage = "No new lights. All \(home.bulbs.count) are here."
        } else {
            lastSearchMessage = added == 1 ? "Found 1 new light." : "Found \(added) new lights."
        }
        if added > 0 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    // MARK: Changing lights

    /// Shows the change straight away and sends it to the lights (used for taps).
    func apply(_ change: LightChange, to ids: [String]) {
        apply(Dictionary(uniqueKeysWithValues: ids.map { ($0, change) }))
    }

    func apply(_ changes: [String: LightChange]) {
        guard !changes.isEmpty else { return }
        quietUntil = Date().addingTimeInterval(3)
        for index in home.bulbs.indices {
            if let change = changes[home.bulbs[index].id] {
                home.bulbs[index].state = change.applied(to: home.bulbs[index].state)
            }
        }
        let snapshot = home
        Task {
            let updated = await LightControl.apply(changes, in: snapshot)
            for bulb in updated.bulbs {
                guard let index = home.bulbs.firstIndex(where: { $0.id == bulb.id }) else { continue }
                home.bulbs[index].reachable = bulb.reachable
                home.bulbs[index].address = bulb.address
            }
            scheduleSave()
        }
    }

    /// While a slider is being dragged: updates the screen and streams the change to the lights.
    func preview(_ change: LightChange, to ids: [String]) {
        quietUntil = Date().addingTimeInterval(3)
        for index in home.bulbs.indices where ids.contains(home.bulbs[index].id) {
            let bulb = home.bulbs[index]
            let next = change.applied(to: bulb.state)
            home.bulbs[index].state = next
            pending[bulb.address] = change.params(for: bulb, newState: next)
        }
        if flushTask == nil {
            flushNow()
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(70))
                self?.flushTask = nil
                self?.flushNow()
            }
        }
    }

    private func flushNow() {
        for (address, params) in pending { WizLink.fire("setPilot", params: params, to: address) }
        pending.removeAll()
    }

    /// When a slider is let go: makes sure every light got the final value.
    func commit(_ change: LightChange, to ids: [String]) {
        flushTask?.cancel()
        flushTask = nil
        pending.removeAll()
        apply(change, to: ids)
    }

    func toggle(_ ids: [String]) {
        let lights = bulbs(ids)
        let turnOn = !lights.contains { $0.state.on }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        apply(.power(turnOn), to: ids)
    }

    func allOff() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        apply(.power(false), to: home.bulbs.map(\.id))
    }

    func applyMood(_ mood: Mood) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        apply(mood.settings.mapValues { LightChange.state($0) })
    }

    /// Flashes a light twice so you can tell which one it is.
    func identify(_ bulb: Bulb) {
        let original = bulb.state
        let address = bulb.address
        let kind = bulb.kind
        quietUntil = Date().addingTimeInterval(4)
        Task {
            for _ in 0..<2 {
                await WizLink.setPilot(["state": true, "dimming": 100, "temp": 6500], on: address)
                try? await Task.sleep(for: .milliseconds(350))
                await WizLink.setPilot(["state": false], on: address)
                try? await Task.sleep(for: .milliseconds(350))
            }
            await WizLink.setPilot(original.pilotParams(for: kind), on: address)
        }
    }

    // MARK: Organising

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            HomeStore.save(self.home)
        }
    }

    private func update(_ change: (inout HomeSetup) -> Void) {
        change(&home)
        HomeStore.save(home)
    }

    func rename(_ bulb: Bulb, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update { home in
            if let index = home.bulbs.firstIndex(where: { $0.id == bulb.id }) { home.bulbs[index].name = trimmed }
        }
    }

    func move(_ bulbID: String, to roomID: UUID?) {
        update { home in
            if let index = home.bulbs.firstIndex(where: { $0.id == bulbID }) { home.bulbs[index].roomID = roomID }
        }
    }

    func forget(_ bulb: Bulb) {
        update { home in
            home.bulbs.removeAll { $0.id == bulb.id }
            for index in home.moods.indices { home.moods[index].settings[bulb.id] = nil }
        }
    }

    @discardableResult
    func addRoom(name: String, symbol: String) -> Room {
        let room = Room(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol)
        update { $0.rooms.append(room) }
        return room
    }

    func updateRoom(_ room: Room) {
        update { home in
            if let index = home.rooms.firstIndex(where: { $0.id == room.id }) { home.rooms[index] = room }
        }
    }

    func deleteRoom(_ room: Room) {
        update { home in
            home.rooms.removeAll { $0.id == room.id }
            for index in home.bulbs.indices where home.bulbs[index].roomID == room.id { home.bulbs[index].roomID = nil }
        }
    }

    func moveRooms(from source: IndexSet, to destination: Int) {
        update { $0.rooms.move(fromOffsets: source, toOffset: destination) }
    }

    /// Saves how the chosen lights look right now as a mood.
    @discardableResult
    func saveMood(name: String, symbol: String, lightIDs: [String], replacing existing: Mood? = nil) -> Mood {
        var settings: [String: LightState] = [:]
        for bulb in bulbs(lightIDs) { settings[bulb.id] = bulb.state }
        let mood = Mood(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol, settings: settings)
        update { home in
            if let index = home.moods.firstIndex(where: { $0.id == mood.id }) {
                home.moods[index] = mood
            } else {
                home.moods.append(mood)
            }
        }
        return mood
    }

    func renameMood(_ mood: Mood, name: String, symbol: String) {
        update { home in
            if let index = home.moods.firstIndex(where: { $0.id == mood.id }) {
                home.moods[index].name = name
                home.moods[index].symbol = symbol
            }
        }
    }

    func deleteMood(_ mood: Mood) {
        update { $0.moods.removeAll { $0.id == mood.id } }
    }

    func moveMoods(from source: IndexSet, to destination: Int) {
        update { $0.moods.move(fromOffsets: source, toOffset: destination) }
    }

    func addFavourite(_ colour: RGB) {
        update { home in
            home.favouriteColours.removeAll { $0 == colour }
            home.favouriteColours.insert(colour, at: 0)
            if home.favouriteColours.count > 12 { home.favouriteColours.removeLast() }
        }
    }

    func removeFavourite(_ colour: RGB) {
        update { $0.favouriteColours.removeAll { $0 == colour } }
    }

    /// Replaces everything (used by demo mode).
    func replaceHome(_ newHome: HomeSetup) {
        home = newHome
        HomeStore.save(home, refreshWidgets: false)
    }
}
