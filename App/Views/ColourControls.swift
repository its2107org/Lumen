import SwiftUI

struct ColourControls: View {
    let ids: [String]
    let state: LightState

    @State private var model = LightsModel.shared

    private var current: RGB? {
        if case .colour(let red, let green, let blue) = state.mode { return RGB(red: red, green: green, blue: blue) }
        return nil
    }

    var body: some View {
        VStack(spacing: 24) {
            ColourWheel(
                selection: current,
                onChange: { model.preview(.mode(.colour(red: $0.red, green: $0.green, blue: $0.blue)), to: ids) },
                onCommit: { model.commit(.mode(.colour(red: $0.red, green: $0.green, blue: $0.blue)), to: ids) }
            )
            .frame(maxWidth: 300)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                Text("Favourites")
                    .font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                    ForEach(model.home.favouriteColours, id: \.self) { colour in
                        let selected = current.map { close($0, colour) } ?? false
                        Button {
                            model.apply(.mode(.colour(red: colour.red, green: colour.green, blue: colour.blue)), to: ids)
                        } label: {
                            Circle()
                                .fill(colour.color.gradient)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.9 : 0.06), lineWidth: selected ? 3 : 1))
                        }
                        .buttonStyle(PressableStyle(scale: 0.88))
                        .contextMenu {
                            Button(role: .destructive) { model.removeFavourite(colour) } label: { Label("Remove", systemImage: "trash") }
                        }
                        .accessibilityLabel(ColourNamer.name(red: colour.red, green: colour.green, blue: colour.blue))
                    }
                    if let current, !model.home.favouriteColours.contains(where: { close($0, current) }) {
                        Button { model.addFavourite(current) } label: {
                            Circle()
                                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(Image(systemName: "plus").font(.headline).foregroundStyle(.secondary))
                        }
                        .buttonStyle(PressableStyle(scale: 0.88))
                        .accessibilityLabel("Add this colour to favourites")
                    }
                }
            }
        }
    }

    private func close(_ a: RGB, _ b: RGB) -> Bool {
        abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue) < 24
    }
}

/// Drag around the circle to pick a colour: around the edge changes the colour, towards the middle makes it paler.
struct ColourWheel: View {
    let selection: RGB?
    let onChange: (RGB) -> Void
    let onCommit: (RGB) -> Void

    @State private var dragPoint: (hue: Double, saturation: Double)?

    private var point: (hue: Double, saturation: Double)? {
        if let dragPoint { return dragPoint }
        guard let selection else { return nil }
        return Color.hueSaturation(red: selection.red, green: selection.green, blue: selection.blue)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { Color(hue: $0, saturation: 1, brightness: 1) },
                                          center: .center))
                Circle()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                if let point {
                    let rgb = Color.rgb(hue: point.hue, saturation: point.saturation)
                    let angle = CGFloat(point.hue * 2 * .pi)
                    let distance = CGFloat(point.saturation) * (radius - 18)
                    Circle()
                        .fill(rgb.color)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                        .frame(width: dragPoint == nil ? 36 : 48, height: dragPoint == nil ? 36 : 48)
                        .position(x: radius + cos(angle) * distance, y: radius + sin(angle) * distance)
                        .animation(.snappy(duration: 0.15), value: dragPoint == nil)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let dx = Double(drag.location.x - radius)
                        let dy = Double(drag.location.y - radius)
                        var hue = atan2(dy, dx) / (2 * .pi)
                        if hue < 0 { hue += 1 }
                        let saturation = min(1, hypot(dx, dy) / Double(radius - 18))
                        let previous = dragPoint
                        dragPoint = (hue, saturation)
                        let rgb = Color.rgb(hue: hue, saturation: saturation)
                        if previous == nil || abs(previous!.hue - hue) > 0.004 || abs(previous!.saturation - saturation) > 0.01 {
                            onChange(rgb)
                        }
                    }
                    .onEnded { _ in
                        if let dragPoint { onCommit(Color.rgb(hue: dragPoint.hue, saturation: dragPoint.saturation)) }
                        UISelectionFeedbackGenerator().selectionChanged()
                        dragPoint = nil
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Colour wheel")
        .accessibilityValue(selection.map { ColourNamer.name(red: $0.red, green: $0.green, blue: $0.blue) } ?? "No colour")
    }
}
