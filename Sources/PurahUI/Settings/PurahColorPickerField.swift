// Sources/PurahUI/Settings/PurahColorPickerField.swift
import SwiftUI
import Foundation
import PurahCore

/// A colour held as hue, saturation and brightness rather than as bytes.
///
/// Reading a hue back out of a hex loses it the moment the colour is grey or
/// black, so the picker keeps its own hue and only borrows saturation and
/// brightness from the stored value.
public struct PurahHSB: Sendable, Equatable {
    public var hue: Double
    public var saturation: Double
    public var brightness: Double

    public init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = Self.clamp(hue)
        self.saturation = Self.clamp(saturation)
        self.brightness = Self.clamp(brightness)
    }

    public init(hex: String) {
        let components = HexColor.parse(hex)
            ?? HexColor.Components(red: 0, green: 245.0 / 255.0, blue: 212.0 / 255.0, alpha: 1)
        self.init(red: components.red, green: components.green, blue: components.blue)
    }

    private init(red: Double, green: Double, blue: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue

        var hue = 0.0
        if delta > 0 {
            if maxValue == red {
                hue = (green - blue) / delta
            } else if maxValue == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }

        self.hue = hue
        self.saturation = maxValue == 0 ? 0 : delta / maxValue
        self.brightness = maxValue
    }

    public var color: Color {
        let rgb = rgbComponents
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// `#RRGGBB`, uppercase, round-tripping the bytes the value was built from.
    public var hex: String {
        let rgb = rgbComponents
        return String(
            format: "#%02X%02X%02X",
            Self.byte(rgb.red),
            Self.byte(rgb.green),
            Self.byte(rgb.blue)
        )
    }

    /// Adopts a hex the parent supplied (a preset tap, a Reset) while keeping
    /// the hue the person chose: a grey or black has no hue of its own, so
    /// taking one from it would snap the wheel back to red.
    public static func reconciled(from hex: String, preservingHue hue: Double) -> PurahHSB {
        var next = PurahHSB(hex: hex)
        guard next.saturation > 0, next.brightness > 0 else {
            next.hue = Self.clamp(hue)
            return next
        }
        return next
    }

    /// `#0AF` → `#00AAFF`, `00e5a3` → `#00E5A3`. Anything the hex parser
    /// refuses returns `current` unchanged, so a typo reverts instead of
    /// committing a colour nobody asked for.
    public static func normalizedHex(_ input: String, fallingBackTo current: String) -> String {
        guard HexColor.parse(input) != nil else { return current }
        return PurahHSB(hex: input).hex
    }

    private var rgbComponents: (red: Double, green: Double, blue: Double) {
        let sectorPosition = (hue - hue.rounded(.down)) * 6
        let sector = Int(sectorPosition.rounded(.down)) % 6
        let fraction = sectorPosition - sectorPosition.rounded(.down)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))

        switch sector {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }

    private static func byte(_ component: Double) -> Int {
        min(255, max(0, Int((component * 255).rounded())))
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

/// One swatch in the accent row. The name exists for VoiceOver: two tiles of
/// similar greens are indistinguishable when read as hex.
public struct PurahColorPreset: Sendable, Equatable, Identifiable {
    public let hex: String
    public let name: String

    public var id: String { hex }

    public init(hex: String) {
        self.hex = hex.uppercased().hasPrefix("#") ? hex.uppercased() : "#" + hex.uppercased()
        self.name = PurahColorPreset.name(forHex: self.hex)
    }

    var color: Color { Color(hex: hex) }

    private static func name(forHex hex: String) -> String {
        guard HexColor.parse(hex) != nil else { return hex }
        let hsb = PurahHSB(hex: hex)
        if hsb.saturation < 0.12 { return "Grey accent" }
        let degrees = hsb.hue * 360
        let name: String
        switch degrees {
        case ..<15, 345...: name = "Red"
        case ..<40: name = "Orange"
        case ..<65: name = "Amber"
        case ..<100: name = "Lime"
        case ..<150: name = "Green"
        case ..<175: name = "Teal"
        case ..<200: name = "Cyan"
        case ..<235: name = "Sky"
        case ..<265: name = "Blue"
        case ..<290: name = "Indigo"
        case ..<315: name = "Violet"
        case ..<345: name = "Pink"
        default: name = "Red"
        }
        return "\(name) accent"
    }
}

/// The accents the built-in pods ship with, de-duplicated in catalog order.
public enum PurahColorPresets {
    public static let maximum = 6

    /// - Parameter defaultHex: the edited pod's own default. When it is not
    ///   already in the first six it replaces the last entry, so an
    ///   uncustomised pod always has one selected tile.
    public static func standard(
        defaultHex: String? = nil,
        catalog: [PurahPluginManifest] = PurahPluginManifest.builtInCatalog
    ) -> [PurahColorPreset] {
        var seen = Set<String>()
        var hexes: [String] = []
        for manifest in catalog {
            let hex = manifest.defaultColorHex.uppercased()
            if seen.insert(hex).inserted {
                hexes.append(hex)
                if hexes.count == maximum { break }
            }
        }

        if let defaultHex {
            let own = defaultHex.uppercased().hasPrefix("#")
                ? defaultHex.uppercased()
                : "#" + defaultHex.uppercased()
            if !hexes.contains(own) {
                if hexes.count >= maximum {
                    hexes[hexes.count - 1] = own
                } else {
                    hexes.append(own)
                }
            }
        }

        return hexes.map(PurahColorPreset.init(hex:))
    }
}

/// The accent row plus its inline HSB panel.
///
/// The row is the same sentence the pods themselves speak — their manifest
/// accents — with one extra tile for a colour of the person's own. The panel is
/// drawn here rather than by a system colour well so the surface, type and
/// motion match the rest of the drawer.
public struct PurahColorPickerField: View {
    public let store: PurahWorkspaceStore
    public let podId: String
    /// The pod's manifest accent, used to keep one tile selected for a pod whose
    /// default is not among the six.
    public let defaultHex: String
    /// Whether a colour was explicitly chosen for this pod, as opposed to the
    /// pod merely having a default outside the preset six.
    public let isCustom: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPanelPresented: Bool
    @State private var hueState: Double
    @State private var hexDraft: String
    @FocusState private var isHexFocused: Bool

    private var palette: ThemePalette { ThemeManager.shared.palette }

    public init(
        store: PurahWorkspaceStore,
        podId: String,
        defaultHex: String,
        isCustom: Bool
    ) {
        self.store = store
        self.podId = podId
        self.defaultHex = defaultHex
        self.isCustom = isCustom

        let current = store.customPodColors[podId] ?? defaultHex
        let presets = PurahColorPresets.standard(defaultHex: defaultHex)
        let isPreset = presets.contains { $0.hex.caseInsensitiveCompare(current) == .orderedSame }
        self._isPanelPresented = State(initialValue: isCustom && !isPreset)
        self._hueState = State(initialValue: PurahHSB(hex: current).hue)
        self._hexDraft = State(initialValue: current.uppercased())
    }

    private var presets: [PurahColorPreset] {
        PurahColorPresets.standard(defaultHex: defaultHex)
    }

    private var currentHex: String {
        (store.customPodColors[podId] ?? defaultHex).uppercased()
    }

    private var selectedPresetHex: String? {
        presets.first { $0.hex.caseInsensitiveCompare(currentHex) == .orderedSame }?.hex
    }

    private var displayed: PurahHSB {
        PurahHSB.reconciled(from: currentHex, preservingHue: hueState)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(presets) { preset in
                    presetSwatch(preset)
                }
                customTile
                Spacer(minLength: 0)
            }

            if isPanelPresented {
                finePanel
            }
        }
        .animation(
            reduceMotion ? nil : PurahMotionPolicy.surface,
            value: isPanelPresented
        )
        .onChange(of: currentHex) { _, newValue in
            hueState = PurahHSB.reconciled(from: newValue, preservingHue: hueState).hue
            hexDraft = newValue
        }
    }

    // MARK: - Swatches

    private func presetSwatch(_ preset: PurahColorPreset) -> some View {
        let isSelected = selectedPresetHex == preset.hex
        return Button {
            apply(hex: preset.hex)
        } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(preset.color)
                .frame(width: 18, height: 18)
                .overlay(checkmark(for: preset, isSelected: isSelected))
                .overlay(selectionRing(isSelected: isSelected, cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customTile: some View {
        let isSelected = selectedPresetHex == nil
        return Button {
            isPanelPresented.toggle()
        } label: {
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: Self.hueWheelColors),
                        center: .center
                    )
                )
                .frame(width: 18, height: 18)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(displayed.color.highContrastInk)
                    }
                }
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1.5)
                )
                .overlay(selectionRing(isSelected: isSelected, cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Custom accent")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func checkmark(for preset: PurahColorPreset, isSelected: Bool) -> some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(preset.color.highContrastInk)
        }
    }

    @ViewBuilder
    private func selectionRing(isSelected: Bool, cornerRadius: CGFloat) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(palette.primaryAccent, lineWidth: 2)
                .padding(-2)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius - 2, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
        }
    }

    // MARK: - Fine panel

    private var finePanel: some View {
        VStack(spacing: 10) {
            saturationField
            hueStrip
            hexRow
        }
    }

    private var saturationField: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let tint = PurahHSB(hue: displayed.hue, saturation: 1, brightness: 1).color

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [.white, tint],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                    .position(
                        x: min(max(displayed.saturation * width, 6), width - 6),
                        y: min(max((1 - displayed.brightness) * height, 6), height - 6)
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        emit(
                            hue: displayed.hue,
                            saturation: value.location.x / width,
                            brightness: 1 - value.location.y / height
                        )
                    }
            )
        }
        .frame(height: 96)
        .cornerRadius(8)
        .accessibilityElement()
        .accessibilityLabel("Saturation and brightness")
        .accessibilityValue(
            "Saturation \(Int((displayed.saturation * 100).rounded()))%, "
                + "brightness \(Int((displayed.brightness * 100).rounded()))%"
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                emit(hue: displayed.hue, saturation: displayed.saturation, brightness: displayed.brightness + 0.02)
            case .decrement:
                emit(hue: displayed.hue, saturation: displayed.saturation, brightness: displayed.brightness - 0.02)
            @unknown default:
                break
            }
        }
    }

    private var hueStrip: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                LinearGradient(
                    gradient: Gradient(colors: Self.hueWheelColors),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 10)
                .cornerRadius(5)

                Circle()
                    .fill(PurahHSB(hue: displayed.hue, saturation: 0.9, brightness: 1).color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                    .position(x: min(max(displayed.hue * width, 7), width - 7), y: proxy.size.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        emit(
                            hue: value.location.x / width,
                            saturation: displayed.saturation,
                            brightness: displayed.brightness
                        )
                    }
            )
        }
        // The strip is drawn 10pt tall; the 6pt of slack above and below keeps
        // it a comfortable target without changing what is drawn.
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Hue")
        .accessibilityValue("hue \(Int((displayed.hue * 360).rounded()))°")
        .accessibilityAdjustableAction { direction in
            let step = 10.0 / 360.0
            switch direction {
            case .increment:
                emit(hue: displayed.hue + step, saturation: displayed.saturation, brightness: displayed.brightness)
            case .decrement:
                emit(hue: displayed.hue - step, saturation: displayed.saturation, brightness: displayed.brightness)
            @unknown default:
                break
            }
        }
    }

    private var hexRow: some View {
        HStack(spacing: 6) {
            TextField("", text: $hexDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .focused($isHexFocused)
                .onSubmit { commitHexDraft() }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(palette.borderColor.opacity(0.7), lineWidth: 0.8)
        )
        .onChange(of: isHexFocused) { _, focused in
            if !focused { commitHexDraft() }
        }
        .accessibilityLabel("Accent colour hex value")
    }

    // MARK: - Actions

    private func apply(hex: String) {
        let next = PurahHSB.reconciled(from: hex, preservingHue: hueState)
        hueState = next.hue
        store.setPodColorHex(podId: podId, hex: next.hex)
    }

    private func emit(hue: Double, saturation: Double, brightness: Double) {
        let next = PurahHSB(hue: hue, saturation: saturation, brightness: brightness)
        hueState = next.hue
        let hex = next.hex
        guard hex.caseInsensitiveCompare(currentHex) != .orderedSame else { return }
        store.setPodColorHex(podId: podId, hex: hex)
    }

    private func commitHexDraft() {
        let committed = PurahHSB.normalizedHex(hexDraft, fallingBackTo: currentHex)
        hexDraft = committed
        let next = PurahHSB.reconciled(from: committed, preservingHue: hueState)
        hueState = next.hue
        if committed.caseInsensitiveCompare(currentHex) != .orderedSame {
            store.setPodColorHex(podId: podId, hex: committed)
        }
    }

    private static let hueWheelColors: [Color] = (0...12).map {
        Color(hue: Double($0 % 12) / 12, saturation: 1, brightness: 1)
    }
}
