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

    public init(type: AmbientRailBarType, hasContent: Bool, color: Color) {
        self.type = type
        self.hasContent = hasContent
        self.color = color
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // 全高实心导轨长条底板 (完全取代小圆点设计)
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(hasContent ? 0.85 : 0.4))
                .frame(width: 6)

            // 内部微刻度刻线 (便签横格线 / 暂存架卡槽刻度)
            VStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 4, height: 1.5)
                }
            }
            .padding(.top, 8)
        }
        .frame(width: 6)
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
