import AppIntents

struct LumenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApplyMoodIntent(),
            phrases: [
                "Set \(\.$mood) in \(.applicationName)",
                "\(.applicationName) \(\.$mood)",
                "Set a mood in \(.applicationName)"
            ],
            shortTitle: "Set Mood",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: TurnOnIntent(),
            phrases: [
                "Turn on \(\.$room) with \(.applicationName)",
                "Turn on lights with \(.applicationName)"
            ],
            shortTitle: "Turn On",
            systemImageName: "lightbulb.fill"
        )
        AppShortcut(
            intent: TurnOffIntent(),
            phrases: [
                "Turn off \(\.$room) with \(.applicationName)",
                "Turn off lights with \(.applicationName)"
            ],
            shortTitle: "Turn Off",
            systemImageName: "lightbulb.slash"
        )
        AppShortcut(
            intent: AllOffIntent(),
            phrases: [
                "Turn off all lights with \(.applicationName)",
                "\(.applicationName) all off",
                "\(.applicationName) goodnight"
            ],
            shortTitle: "All Off",
            systemImageName: "power"
        )
        AppShortcut(
            intent: ToggleRoomIntent(),
            phrases: [
                "Toggle \(\.$room) with \(.applicationName)",
                "Switch \(\.$room) with \(.applicationName)"
            ],
            shortTitle: "Toggle Room",
            systemImageName: "light.recessed"
        )
        AppShortcut(
            intent: SetColourIntent(),
            phrases: [
                "Make lights \(\.$colour) with \(.applicationName)",
                "Set lights to \(\.$colour) in \(.applicationName)"
            ],
            shortTitle: "Set Colour",
            systemImageName: "paintpalette.fill"
        )
        AppShortcut(
            intent: SetSceneIntent(),
            phrases: [
                "Play \(\.$scene) in \(.applicationName)",
                "Start \(\.$scene) with \(.applicationName)"
            ],
            shortTitle: "Play Scene",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: SetBrightnessIntent(),
            phrases: [
                "Set brightness with \(.applicationName)",
                "Dim lights with \(.applicationName)"
            ],
            shortTitle: "Brightness",
            systemImageName: "sun.max.fill"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
