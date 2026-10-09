// Sources/PurahUI/Theme/ThemePalette.swift
import SwiftUI
import AppKit
import PurahCore

public struct ThemePalette: Sendable {
    public let style: AppThemeStyle
    public let primaryAccent: Color
    public let secondaryAccent: Color
    public let background: Color
    public let surfaceBackground: Color
    public let glassBackground: Color
    public let solidDrawerBackground: Color
    public let railBackground: Color
    public let borderColor: Color
    public let highlightBorderColor: Color
    public let warningAccent: Color
    public let dangerAccent: Color
    public let successAccent: Color
    public let useGlow: Bool
    public let useRuneCorners: Bool
    public let cornerRadius: CGFloat
    public let fontTitle: Font
    public let fontMono: Font

    @MainActor
    public func podColor(for podId: String, store: PurahWorkspaceStore? = nil) -> Color {
        // 1. Dynamic color from plugin protocol requirement (e.g. Hardware Vitals dynamic health state)
        if let plugin = PluginRegistry.shared.plugin(for: podId) {
            let pod = store?.pods.first(where: { $0.id == podId }) ?? plugin.manifest.makeDefaultSlotPod()
            let context = PurahPluginContext(
                pod: pod,
                edge: pod.edge,
                railWidth: CGFloat(store?.railBarWidth ?? 8.0),
                slotHeight: 100.0,
                drawerWidth: 280.0,
                isExpanded: false,
                isPinned: false,
                accentColor: primaryAccent,
                palette: self,
                store: store ?? PurahWorkspaceStore(),
                requestExpand: {},
                requestDismiss: {},
                togglePin: {}
            )
            if let dynamic = plugin.dynamicBarColor(context: context) {
                return dynamic
            }
        }

        // 2. Custom user color override
        if let store, let customHex = store.customPodColors[podId] {
            return Color(hex: customHex)
        }

        // 3. Plugin manifest default color hex
        if let manifest = PluginRegistry.shared.catalogPlugin(for: podId)?.manifest {
            return Color(hex: manifest.defaultColorHex)
        }

        // 4. SlotPod default color hex
        if let pod = store?.pods.first(where: { $0.id == podId }) {
            return Color(hex: pod.defaultColorHex)
        }

        // 5. Fallback primary accent
        return primaryAccent
    }

    public static func palette(for style: AppThemeStyle = .native) -> ThemePalette {
        ThemePalette(
            style: .native,
            primaryAccent: Color.accentColor,
            secondaryAccent: Color.secondary,
            background: Color(nsColor: .windowBackgroundColor),
            surfaceBackground: Color(nsColor: .controlBackgroundColor),
            glassBackground: Color(nsColor: .windowBackgroundColor).opacity(0.85),
            solidDrawerBackground: Color(nsColor: .windowBackgroundColor).opacity(0.75),
            railBackground: Color(nsColor: .windowBackgroundColor),
            borderColor: Color(nsColor: .separatorColor).opacity(0.6),
            highlightBorderColor: Color.accentColor.opacity(0.8),
            warningAccent: Color.orange,
            dangerAccent: Color.red,
            successAccent: Color.green,
            useGlow: false,
            useRuneCorners: false,
            cornerRadius: 12.0,
            fontTitle: Font.system(.headline, design: .rounded).weight(.semibold),
            fontMono: Font.system(.caption, design: .monospaced)
        )
    }
}

public extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 245, 212, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }

    func toHex() -> String? {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
