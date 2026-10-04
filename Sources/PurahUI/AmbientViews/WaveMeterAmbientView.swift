// Sources/PurahUI/AmbientViews/WaveMeterAmbientView.swift
import SwiftUI

public struct WaveMeterAmbientView: View {
    public var samples: [Double]
    public var isPlaying: Bool

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(samples: [Double], isPlaying: Bool) {
        self.samples = samples
        self.isPlaying = isPlaying
    }

    public var body: some View {
        VStack(spacing: 2.0) {
            ForEach(samples.indices, id: \.self) { idx in
                let amp = samples[idx]
                Rectangle()
                    .fill(isPlaying ? palette.primaryAccent : palette.borderColor)
                    .frame(width: max(amp * 6.0, 2.0), height: 3.0)
            }
        }
        .modifier(OptionalGlow(color: isPlaying ? palette.primaryAccent : .clear, enabled: palette.useGlow))
    }
}
