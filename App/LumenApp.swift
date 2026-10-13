import AppIntents
import SwiftUI

@main
struct LumenApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Demo.prepareIfRequested()
        LumenShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { Router.shared.handle($0) }
                .task { await Demo.runIfRequested() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: LightsModel.shared.appBecameActive()
            case .background: LightsModel.shared.appWentToBackground()
            default: break
            }
        }
    }
}

/// Which sheet is showing. Widgets and links can open one.
@MainActor
@Observable
final class Router {
    static let shared = Router()

    var sheet: Sheet?

    enum Sheet: Identifiable, Hashable {
        case lights(ids: [String], title: String, roomID: UUID?, tab: ControlTab?)
        case settings
        case newMood
        case editMood(UUID)
        case newRoom
        case setUpLights

        var id: String {
            switch self {
            case .lights(let ids, let title, _, _): "lights-\(title)-\(ids.joined())"
            case .settings: "settings"
            case .newMood: "new-mood"
            case .editMood(let id): "mood-\(id)"
            case .newRoom: "new-room"
            case .setUpLights: "set-up"
            }
        }
    }

    private init() {}

    func openRoom(_ room: Room?, tab: ControlTab? = nil) {
        let model = LightsModel.shared
        let ids = model.bulbs(in: room).map(\.id)
        guard !ids.isEmpty else { return }
        sheet = .lights(ids: ids, title: room?.name ?? "Other lights", roomID: room?.id, tab: tab)
    }

    func openLight(_ bulb: Bulb, tab: ControlTab? = nil) {
        sheet = .lights(ids: [bulb.id], title: bulb.name, roomID: nil, tab: tab)
    }

    /// lumen://room/<id> opens a room's controls.
    func handle(_ url: URL) {
        guard url.scheme == "lumen" else { return }
        let model = LightsModel.shared
        switch url.host() {
        case "room":
            let id = url.lastPathComponent
            if id == RoomEntity.everywhereID {
                sheet = .lights(ids: model.bulbs.map(\.id), title: "All lights", roomID: nil, tab: nil)
            } else if let room = model.rooms.first(where: { $0.id.uuidString == id }) {
                openRoom(room)
            }
        case "settings":
            sheet = .settings
        default:
            sheet = nil
        }
    }
}
