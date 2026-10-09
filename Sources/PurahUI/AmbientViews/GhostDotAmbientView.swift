// Sources/PurahUI/AmbientViews/GhostDotAmbientView.swift
import SwiftUI
import PurahCore

public enum AmbientRailBarType {
    case shelf
    case notes
    case generic
}

public struct RailBarAmbientView: View {
    public var type: AmbientRailBarType
    public var hasContent: Bool
    public var color: Color
    public var barWidth: CGFloat

    public init(type: AmbientRailBarType, hasContent: Bool, color: Color, barWidth: CGFloat = 8.0) {
        self.type = type
        self.hasContent = hasContent
        self.color = color
        self.barWidth = barWidth
    }

    public var body: some View {
        let radius = min(barWidth / 2, 4)
        RoundedRectangle(cornerRadius: radius)
            .fill(color.opacity(hasContent ? 0.88 : 0.40))
            .frame(width: barWidth)
            .frame(maxHeight: .infinity)
    }
}

// Backward compatibility alias
public typealias GhostDotAmbientView = RailBarAmbientView

public extension RailBarAmbientView {
    init(hasContent: Bool) {
        self.init(type: .generic, hasContent: hasContent, color: Color.orange)
    }
}
