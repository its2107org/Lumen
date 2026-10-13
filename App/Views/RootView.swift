import SwiftUI

struct RootView: View {
    @State private var model = LightsModel.shared
    @State private var router = Router.shared

    var body: some View {
        Group {
            if model.bulbs.isEmpty {
                WelcomeView()
            } else {
                HomeView()
            }
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .lights(let ids, let title, let roomID, let tab):
                LightControlSheet(ids: ids, title: title, roomID: roomID, initialTab: tab)
            case .settings:
                SettingsView()
            case .newMood:
                MoodEditor(existing: nil)
            case .editMood(let id):
                MoodEditor(existing: model.moods.first { $0.id == id })
            case .newRoom:
                RoomEditor(existing: nil)
            case .setUpLights:
                SetUpLightsView()
            }
        }
        .tint(.accentColor)
    }
}

// MARK: - First run

struct WelcomeView: View {
    @State private var model = LightsModel.shared

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            GlowOrb(colors: [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 1, green: 0.35, blue: 0.45), Color(red: 0.45, green: 0.4, blue: 1)],
                    animate: model.isSearching)
                .frame(width: 180, height: 180)
            VStack(spacing: 10) {
                Text("Lumen")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(model.isSearching ? "Looking for your WiZ lights…" : "Control your WiZ lights directly over your home Wi-Fi.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 32)

            if let message = model.lastSearchMessage, !model.isSearching, model.bulbs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.headline)
                    Text("Check your phone is on the same Wi-Fi as the lights, and that the lights are switched on at the wall.")
                    Text("If you tapped Don't Allow when asked about devices on your network, turn on Local Network for Lumen in Settings.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 24)
            }

            Spacer()

            Button {
                Task { await model.findLights() }
            } label: {
                HStack(spacing: 10) {
                    if model.isSearching { ProgressView().tint(.white) }
                    Text(model.isSearching ? "Searching" : "Find my lights")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(model.isSearching)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .animation(.smooth, value: model.isSearching)
        .animation(.smooth, value: model.lastSearchMessage)
    }
}

/// A soft glowing ball of light.
struct GlowOrb: View {
    var colors: [Color]
    var animate = false
    @State private var turning = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: colors + [colors.first ?? .orange], center: .center))
                .blur(radius: 40)
                .opacity(0.85)
                .rotationEffect(.degrees(turning ? 360 : 0))
            Circle()
                .fill(RadialGradient(colors: [.white, .white.opacity(0.0)], center: .center, startRadius: 2, endRadius: 70))
                .blendMode(.plusLighter)
                .padding(30)
            Circle()
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                .padding(36)
        }
        .onAppear { if animate { start() } }
        .onChange(of: animate) { _, on in if on { start() } }
    }

    private func start() {
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { turning = true }
    }
}
