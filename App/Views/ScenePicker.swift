import SwiftUI

/// WiZ's built-in scenes, with a speed control for the moving ones.
struct ScenePicker: View {
    let ids: [String]
    let kinds: Set<LightKind>
    let state: LightState

    @State private var model = LightsModel.shared
    @State private var speedDrag: Double?

    private var currentScene: (id: Int, speed: Int)? {
        if state.on, case .scene(let id, let speed) = state.mode { return (id, speed) }
        return nil
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        let available = WizScene.available(for: kinds.subtracting([.plug]))
        VStack(alignment: .leading, spacing: 22) {
            if let currentScene, let scene = WizScene.find(currentScene.id), scene.isDynamic {
                speedControl(scene: scene, speed: currentScene.speed)
            }
            ForEach(WizScene.Category.allCases, id: \.self) { category in
                let scenes = available.filter { $0.group == category }
                if !scenes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(category.rawValue)
                            .font(.headline)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(scenes) { scene in
                                SceneCard(scene: scene, selected: currentScene?.id == scene.id) {
                                    model.apply(.mode(.scene(id: scene.id, speed: currentScene?.speed ?? 100)), to: ids)
                                }
                            }
                        }
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: currentScene?.id)
    }

    private func speedControl(scene: WizScene, speed: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Speed", systemImage: "hare.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(speedLabel(Int(speedDrag ?? Double(speed))))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { speedDrag ?? Double(speed) },
                    set: { speedDrag = $0 }
                ),
                in: 10...200,
                step: 10,
                onEditingChanged: { editing in
                    if !editing, let speedDrag {
                        model.commit(.mode(.scene(id: scene.id, speed: Int(speedDrag))), to: ids)
                        self.speedDrag = nil
                    }
                }
            )
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func speedLabel(_ value: Int) -> String {
        switch value {
        case ..<50: "Very slow"
        case ..<90: "Slow"
        case ..<120: "Normal"
        case ..<160: "Fast"
        default: "Very fast"
        }
    }
}

struct SceneCard: View {
    let scene: WizScene
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: scene.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2)
                Spacer(minLength: 12)
                Text(scene.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: scene.colors.count > 1 ? scene.colors : [scene.colors[0], scene.colors[0].opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .saturation(0.9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [.clear, .black.opacity(0.22)], startPoint: .top, endPoint: .bottom))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 3)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.93))
        .accessibilityLabel(scene.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
