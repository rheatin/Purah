// Sources/PurahUI/AmbientViews/GhostDotAmbientView.swift
import SwiftUI

public struct GhostDotAmbientView: View {
    public var hasContent: Bool
    @State private var isBreathing = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(hasContent: Bool) {
        self.hasContent = hasContent
    }

    public var body: some View {
        VStack {
            Spacer()
            Circle()
                .fill(hasContent ? palette.warningAccent : palette.borderColor)
                .frame(width: 5, height: 5)
                .scaleEffect(isBreathing && hasContent ? 1.4 : 1.0)
                .opacity(isBreathing && hasContent ? 1.0 : 0.6)
                .modifier(OptionalGlow(color: hasContent ? palette.warningAccent : .clear, enabled: palette.useGlow))
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}
