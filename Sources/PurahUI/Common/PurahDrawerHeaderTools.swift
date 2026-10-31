// Sources/PurahUI/Common/PurahDrawerHeaderTools.swift
import SwiftUI

/// Unified header tools for stepped drawer cards: settings gear + pin.
/// Base-owned anatomy — plugins call this instead of hand-rolling their own
/// gear/pin pair, so every stepped card reads and behaves identically.
public struct PurahDrawerHeaderTools: View {
    private let onSettings: () -> Void
    private let settingsHelp: String
    private let isPinned: Bool
    private let tintColor: Color
    private let onTogglePin: () -> Void

    public init(
        onSettings: @escaping () -> Void,
        settingsHelp: String = "Open Plugin Settings",
        isPinned: Bool,
        tintColor: Color,
        onTogglePin: @escaping () -> Void
    ) {
        self.onSettings = onSettings
        self.settingsHelp = settingsHelp
        self.isPinned = isPinned
        self.tintColor = tintColor
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        // One look everywhere: a faint plate holding both tools. A plugin cannot
        // choose a flat or disc-ed variant, so no card drifts from the standard.
        PurahHeaderGroup(showsSurface: true) {
            PurahHeaderButton(systemImage: "gearshape", help: settingsHelp, action: onSettings)
            PurahPinButton(isPinned: isPinned, tintColor: tintColor, showsDisc: false, action: onTogglePin)
        }
    }
}
