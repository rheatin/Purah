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
        ZStack(alignment: .top) {
            // 全高实心导轨长条底板
            RoundedRectangle(cornerRadius: radius)
                .fill(color.opacity(hasContent ? 0.85 : 0.4))
                .frame(width: barWidth)

            // 内部微刻度刻线
            VStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: max(barWidth - 2, 2), height: 1.5)
                }
            }
            .padding(.top, 8)
        }
        .frame(width: barWidth)
        .frame(maxHeight: .infinity)
    }
}

// 保持兼容旧调用的别名
public typealias GhostDotAmbientView = RailBarAmbientView

public extension RailBarAmbientView {
    init(hasContent: Bool) {
        self.init(type: .generic, hasContent: hasContent, color: Color.orange)
    }
}
