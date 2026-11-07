import SwiftUI

/// Shows the dimmer widget at each size, for the build checks' screenshots.
struct WidgetGallery: View {
    @State private var model = LightsModel.shared

    var body: some View {
        let home = model.home
        let rooms = RoomInfo.all(in: home)
        let living = rooms.first
        let bedroom = rooms.dropFirst().first ?? living
        ScrollView {
            VStack(spacing: 18) {
                tile(width: 364, height: 170) { DimmerWidgetView(room: living, home: home, layout: .medium) }
                HStack(spacing: 22) {
                    tile(width: 170, height: 170) { DimmerWidgetView(room: bedroom, home: home, layout: .small) }
                    DimmerWidgetView(room: living, home: home, layout: .lockScreen)
                        .foregroundStyle(.white)
                        .frame(width: 160, height: 72)
                        .padding(6)
                        .background(LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .environment(\.colorScheme, .dark)
                }
                tile(width: 364, height: 382) { DimmerWidgetView(room: bedroom, home: home, layout: .large) }
            }
            .padding(.top, 60)
            .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: [Color(red: 0.55, green: 0.6, blue: 0.8), Color(red: 0.85, green: 0.7, blue: 0.75)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func tile(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(16)
            .frame(width: width, height: height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
