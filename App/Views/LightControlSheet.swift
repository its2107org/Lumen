import SwiftUI

enum ControlTab: String, CaseIterable, Identifiable, Hashable {
    case white = "White"
    case colour = "Colour"
    case scenes = "Scenes"

    var id: Self { self }
}

/// Controls for one light, a room, or every light.
struct LightControlSheet: View {
    let ids: [String]
    let title: String
    let roomID: UUID?
    let initialTab: ControlTab?

    @State private var model = LightsModel.shared
    @State private var tab: ControlTab = .white
    @Environment(\.dismiss) private var dismiss

    private var lights: [Bulb] { model.bulbs(ids) }
    private var kinds: Set<LightKind> { Set(lights.map(\.kind)) }
    /// The light whose settings the controls show (the first one that's on).
    private var lead: Bulb? { lights.first { $0.state.on } ?? lights.first }
    private var state: LightState { lead?.state ?? .default }
    private var isOn: Bool { lights.contains { $0.state.on } }

    private var tabs: [ControlTab] {
        var tabs: [ControlTab] = []
        if kinds.contains(where: \.hasWhiteTuning) { tabs.append(.white) }
        if kinds.contains(where: \.hasColour) { tabs.append(.colour) }
        if kinds.contains(where: \.hasScenes) { tabs.append(.scenes) }
        return tabs
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    if kinds.contains(where: \.hasBrightness) {
                        BrightnessSlider(
                            value: state.brightness,
                            isOn: isOn,
                            colors: state.displayColors,
                            darkFill: state.isDarkColour,
                            onChange: { model.preview(.brightness($0), to: ids) },
                            onCommit: { model.commit(.brightness($0), to: ids) }
                        )
                    }
                    if tabs.count > 1 {
                        Picker("Mode", selection: $tab) {
                            ForEach(tabs) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Group {
                        switch tab {
                        case .white: whiteControls
                        case .colour: ColourControls(ids: ids, state: state)
                        case .scenes: ScenePicker(ids: ids, kinds: kinds, state: state)
                        }
                    }
                    .transition(.opacity)
                    if ids.count > 1 { membersList }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .animation(.smooth(duration: 0.25), value: tab)
            }
            .background(AmbientBackground(colors: isOn ? state.displayColors : []))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if let initialTab, tabs.contains(initialTab) {
                tab = initialTab
            } else {
                tab = defaultTab
            }
        }
    }

    private var defaultTab: ControlTab {
        switch state.mode {
        case .colour where tabs.contains(.colour): .colour
        case .scene where tabs.contains(.scenes): .scenes
        default: tabs.first ?? .white
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            Toggle("Power", isOn: Binding(get: { isOn }, set: { model.apply(.power($0), to: ids) }))
                .labelsHidden()
                .controlSize(.large)
                .sensoryFeedback(.impact(weight: .medium), trigger: isOn)
        }
        .padding(.top, 4)
    }

    private var subtitle: String {
        if lights.allSatisfy({ !$0.reachable }) { return "Not responding" }
        if !isOn { return "Off" }
        let onCount = lights.filter { $0.state.on }.count
        let prefix = ids.count > 1 ? "\(onCount) of \(lights.count) on · " : ""
        return prefix + state.summary
    }

    // MARK: White

    private var kelvinRange: ClosedRange<Int> {
        let tunable = lights.filter { $0.kind.hasWhiteTuning }
        let low = tunable.map(\.minKelvin).min() ?? 2200
        let high = tunable.map(\.maxKelvin).max() ?? 6500
        return low...max(low + 100, high)
    }

    private var currentKelvin: Int? {
        if case .white(let kelvin) = state.mode { return kelvin }
        return nil
    }

    private var whiteControls: some View {
        VStack(spacing: 20) {
            KelvinSlider(
                value: currentKelvin ?? 2700,
                range: kelvinRange,
                isActive: currentKelvin != nil && isOn,
                onChange: { model.preview(.mode(.white(kelvin: $0)), to: ids) },
                onCommit: { model.commit(.mode(.white(kelvin: $0)), to: ids) }
            )
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
                ForEach(WhitePreset.allCases.filter { kelvinRange.contains($0.kelvin) || $0 == .candle || $0 == .cool }) { preset in
                    let selected = currentKelvin.map { abs($0 - preset.kelvin) < 150 } ?? false
                    Button {
                        model.apply(.mode(.white(kelvin: min(kelvinRange.upperBound, max(kelvinRange.lowerBound, preset.kelvin)))), to: ids)
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(Color.kelvin(preset.kelvin).gradient)
                                .frame(width: 54, height: 54)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.9 : 0.08), lineWidth: selected ? 3 : 1))
                                .shadow(color: Color.kelvin(preset.kelvin).opacity(0.6), radius: selected ? 10 : 0)
                            Text(preset.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Lights in a room

    private var membersList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lights")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(lights) { bulb in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(bulb.state.on && bulb.reachable ? AnyShapeStyle(bulb.state.displayColor.gradient) : AnyShapeStyle(Color.secondary.opacity(0.2)))
                            .frame(width: 30, height: 30)
                            .overlay(Image(systemName: bulb.symbol).font(.caption.weight(.bold)).foregroundStyle(bulb.state.on ? Color.black.opacity(0.7) : .secondary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bulb.name).font(.body)
                            Text(bulb.reachable ? (bulb.state.on ? "\(bulb.state.brightness)% · \(bulb.state.summary)" : "Off") : "Not responding")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(bulb.name, isOn: Binding(get: { bulb.state.on }, set: { model.apply(.power($0), to: [bulb.id]) }))
                            .labelsHidden()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    if bulb.id != lights.last?.id { Divider().padding(.leading, 56) }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.top, 6)
    }
}

// MARK: - Sliders

/// A big, chunky brightness slider in the style of Control Centre.
struct BrightnessSlider: View {
    let value: Int
    let isOn: Bool
    let colors: [Color]
    var darkFill = false
    let onChange: (Int) -> Void
    let onCommit: (Int) -> Void

    @State private var dragValue: Double?
    @State private var startValue: Double = 0

    private var shown: Double { dragValue ?? Double(value) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = (shown - 10) / 90
            ZStack(alignment: .leading) {
                Rectangle().fill(.regularMaterial)
                Rectangle()
                    .fill(LinearGradient(colors: isOn ? colors.map { $0.opacity(0.95) } : [Color.secondary.opacity(0.35)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(56, width * (0.12 + 0.88 * fraction)))
                HStack {
                    Image(systemName: shown < 40 ? "sun.min.fill" : "sun.max.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Text("\(Int(shown.rounded()))%")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(isOn ? (darkFill ? Color.white : Color.black.opacity(0.72)) : Color.secondary)
                .padding(.horizontal, 20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let base = dragValue == nil ? Double(value) : startValue
                        if dragValue == nil { startValue = base }
                        let delta = drag.translation.width / width * 90
                        let next = min(100, max(10, base + delta))
                        if Int(next.rounded()) != Int(shown.rounded()) {
                            onChange(Int(next.rounded()))
                            if Int(next.rounded()) == 10 || Int(next.rounded()) == 100 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                        dragValue = next
                    }
                    .onEnded { _ in
                        if let dragValue { onCommit(Int(dragValue.rounded())) }
                        dragValue = nil
                    }
            )
        }
        .frame(height: 68)
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(value) per cent")
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment ? min(100, value + 10) : max(10, value - 10)
            onCommit(next)
        }
    }
}

/// Warm to cool white.
struct KelvinSlider: View {
    let value: Int
    let range: ClosedRange<Int>
    let isActive: Bool
    let onChange: (Int) -> Void
    let onCommit: (Int) -> Void

    @State private var dragValue: Double?

    private var shown: Double { dragValue ?? Double(min(range.upperBound, max(range.lowerBound, value))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width
                let span = Double(range.upperBound - range.lowerBound)
                let fraction = (shown - Double(range.lowerBound)) / span
                let stops = stride(from: range.lowerBound, through: range.upperBound, by: max(100, (range.upperBound - range.lowerBound) / 8)).map { Color.kelvin($0) }
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing))
                    Circle()
                        .fill(Color.kelvin(Int(shown)))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                        .frame(width: 44, height: 44)
                        .offset(x: (width - 44) * fraction)
                        .opacity(isActive || dragValue != nil ? 1 : 0.35)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let position = min(1, max(0, (drag.location.x - 22) / (width - 44)))
                            let kelvin = Double(range.lowerBound) + position * span
                            let snapped = (kelvin / 50).rounded() * 50
                            if Int(snapped) != Int(shown) { onChange(Int(snapped)) }
                            dragValue = snapped
                        }
                        .onEnded { _ in
                            if let dragValue { onCommit(Int(dragValue)) }
                            dragValue = nil
                        }
                )
            }
            .frame(height: 44)
            HStack {
                Text("Warm")
                Spacer()
                Text("\(Int(shown))K")
                    .monospacedDigit()
                    .opacity(isActive || dragValue != nil ? 1 : 0)
                Spacer()
                Text("Cool")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement()
        .accessibilityLabel("Warmth")
        .accessibilityValue("\(value) kelvin")
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment ? min(range.upperBound, value + 300) : max(range.lowerBound, value - 300)
            onCommit(next)
        }
    }
}
