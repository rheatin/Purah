// Sources/PurahUI/AmbientViews/ProgressTimelineAmbientView.swift
import SwiftUI
import PurahCore

public struct ProgressTimelineAmbientView: View {
    public var progress: Double // 0.0 to 1.0 (elapsed time progress)

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(progress: Double = 0.55) {
        self.progress = progress
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Remaining duration background
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.3))
                // Elapsed duration fill
                Rectangle()
                    .fill(Color.gray.opacity(0.45))
                    .frame(height: geo.size.height * progress)
                // Current time needle indicator
                Rectangle()
                    .fill(palette.primaryAccent)
                    .frame(height: 2)
                    .offset(y: geo.size.height * progress)
                    .modifier(OptionalGlow(color: palette.primaryAccent, enabled: palette.useGlow))
            }
            .clipShape(Capsule())
        }
    }
}
