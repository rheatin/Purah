// Sources/PurahUI/AmbientViews/SegmentGaugeAmbientView.swift
import SwiftUI

public struct SegmentGaugeAmbientView: View {
    public var totalCount: Int
    public var completedCount: Int

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(totalCount: Int, completedCount: Int) {
        self.totalCount = max(totalCount, 1)
        self.completedCount = completedCount
    }

    public var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<totalCount, id: \.self) { idx in
                let isDone = idx < completedCount
                Rectangle()
                    .fill(isDone ? Color.gray.opacity(0.3) : palette.primaryAccent)
                    .modifier(OptionalGlow(color: isDone ? .clear : palette.primaryAccent, enabled: palette.useGlow))
                    .frame(maxWidth: .infinity)
            }
        }
        .clipShape(Capsule())
    }
}
