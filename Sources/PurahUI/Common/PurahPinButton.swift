// Sources/PurahUI/Common/PurahPinButton.swift
import SwiftUI
import PurahCore

public struct PurahPinButton: View {
    public let isPinned: Bool
    public let tintColor: Color
    public let size: CGFloat
    public let action: () -> Void

    public init(
        isPinned: Bool,
        tintColor: Color,
        size: CGFloat = 22,
        action: @escaping () -> Void
    ) {
        self.isPinned = isPinned
        self.tintColor = tintColor
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button {
            SensoryFeedbackService.shared.performActionHaptic(
                .alignment,
                enabled: (UserDefaults.standard.object(forKey: "purah.isTrackpadHapticsEnabled") as? Bool ?? true) &&
                         (UserDefaults.standard.object(forKey: "purah.isControlHapticEnabled") as? Bool ?? true)
            )
            withAnimation(PurahMotionPolicy.buttonPop) {
                action()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isPinned ? tintColor.opacity(0.18) : Color.primary.opacity(0.06))
                    .frame(width: size, height: size)

                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundColor(isPinned ? tintColor : .secondary)
                    .font(.system(size: size < 20 ? 8 : 9.5, weight: .semibold))
                    .rotationEffect(.degrees(isPinned ? -25 : 0))
                    .scaleEffect(isPinned ? 1.15 : 1.0)
                    .animation(PurahMotionPolicy.buttonPop, value: isPinned)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.tactile)
        .frame(width: size, height: size)
        // `.help` is a mouse tooltip only; VoiceOver needs the semantic label.
        .accessibilityLabel(isPinned ? "Unpin Drawer" : "Pin Drawer")
        .accessibilityAddTraits(isPinned ? [.isSelected] : [])
        .help(isPinned ? "Unpin Drawer" : "Pin Drawer")
    }
}
