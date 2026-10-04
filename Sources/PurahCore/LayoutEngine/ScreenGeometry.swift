// Sources/PurahCore/LayoutEngine/ScreenGeometry.swift
import Foundation

public struct ScreenGeometry: Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = max(width, 1.0)
        self.height = max(height, 1.0)
    }

    /// 将归一化 Y (0.0 顶部 ~ 1.0 底部) 转换为 macOS Cocoa 坐标系 (0.0 底部 ~ height 顶部)
    public func cocoaY(for normalizedY: Double, elementHeight: Double = 0.0) -> Double {
        height * (1.0 - normalizedY) - elementHeight
    }

    /// 将归一化 Y 转换为屏幕像素点 Y (从顶部起算)
    public func pixelY(for normalizedY: Double) -> Double {
        normalizedY * height
    }

    /// 将归一化长度转换为物理像素高度
    public func pixelHeight(for normalizedLength: Double) -> Double {
        normalizedLength * height
    }
}
