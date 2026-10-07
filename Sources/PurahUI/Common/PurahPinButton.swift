// Sources/PurahUI/Common/PurahPinButton.swift
import SwiftUI

public struct PurahPinButton: View {
    public let isPinned: Bool
    public let tintColor: Color
    public let action: () -> Void

    public init(
        isPinned: Bool,
        tintColor: Color,
        action: @escaping () -> Void
    ) {
        self.isPinned = isPinned
        self.tintColor = tintColor
        self.action = action
    }

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                action()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isPinned ? tintColor.opacity(0.18) : Color.primary.opacity(0.06))
                    .frame(width: 22, height: 22)

                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundColor(isPinned ? tintColor : .secondary)
                    .font(.system(size: 9.5, weight: .semibold))
                    .rotationEffect(.degrees(isPinned ? -25 : 0))
                    .scaleEffect(isPinned ? 1.15 : 1.0)
                    .animation(.spring(response: 0.26, dampingFraction: 0.55), value: isPinned)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.tactile)
        .help(isPinned ? "Unpin Drawer" : "Pin Drawer")
    }
}
