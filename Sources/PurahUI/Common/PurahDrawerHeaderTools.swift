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
        HStack(spacing: 4) {
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    // Icon-only buttons have no text for VoiceOver to read.
                    .accessibilityHidden(true)
            }
            .buttonStyle(.tactile)
            .accessibilityLabel(settingsHelp)
            .help(settingsHelp)

            PurahPinButton(isPinned: isPinned, tintColor: tintColor, action: onTogglePin)
        }
    }
}
