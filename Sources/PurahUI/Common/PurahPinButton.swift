// Sources/PurahUI/Common/PurahPinButton.swift
import SwiftUI
import PurahCore

public struct PurahPinButton: View {
    public let isPinned: Bool
    public let tintColor: Color
    public let size: CGFloat
    /// False where the pin already sits on a header plate. A disc inside the
    /// plate reads as a plate within a plate, so those sites take the shared
    /// header chrome — hover fill while resting, tint fill while pinned.
    public let showsDisc: Bool
    public let action: () -> Void

    public init(
        isPinned: Bool,
        tintColor: Color,
        size: CGFloat = 22,
        showsDisc: Bool = true,
        action: @escaping () -> Void
    ) {
        self.isPinned = isPinned
        self.tintColor = tintColor
        self.size = size
        self.showsDisc = showsDisc
        self.action = action
    }

    public var body: some View {
        if showsDisc {
            discButton
        } else {
            PurahHeaderButton(
                help: helpText,
                tint: tintColor,
                isActive: isPinned,
                action: perform
            ) {
                pinGlyph(pointSize: PurahHeaderMetrics.glyphSize)
            }
        }
    }

    private var discButton: some View {
        Button(action: perform) {
            ZStack {
                Circle()
                    .fill(isPinned ? tintColor.opacity(0.18) : Color.primary.opacity(0.06))
                    .frame(width: size, height: size)

                pinGlyph(pointSize: size < 20 ? 8 : 9.5)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.tactile)
        .frame(width: size, height: size)
        // `.help` is a mouse tooltip only; VoiceOver needs the semantic label.
        .accessibilityLabel(helpText)
        .accessibilityAddTraits(isPinned ? [.isSelected] : [])
        .help(helpText)
    }

    private var helpText: String {
        isPinned ? "Unpin Drawer" : "Pin Drawer"
    }

    private func pinGlyph(pointSize: CGFloat) -> some View {
        Image(systemName: isPinned ? "pin.fill" : "pin")
            .foregroundColor(isPinned ? tintColor : .secondary)
            .font(.system(size: pointSize, weight: .semibold))
            .rotationEffect(.degrees(isPinned ? -25 : 0))
            .scaleEffect(isPinned ? 1.15 : 1.0)
            .animation(PurahMotionPolicy.buttonPop, value: isPinned)
    }

    private func perform() {
        SensoryFeedbackService.shared.performActionHaptic(
            .alignment,
            enabled: (UserDefaults.standard.object(forKey: "purah.isTrackpadHapticsEnabled") as? Bool ?? true) &&
                     (UserDefaults.standard.object(forKey: "purah.isControlHapticEnabled") as? Bool ?? true)
        )
        withAnimation(PurahMotionPolicy.buttonPop) {
            action()
        }
    }
}
