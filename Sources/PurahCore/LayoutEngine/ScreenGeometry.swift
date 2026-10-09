// Sources/PurahCore/LayoutEngine/ScreenGeometry.swift
import Foundation

public struct ScreenGeometry: Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = max(width, 1.0)
        self.height = max(height, 1.0)
    }

    /// Converts normalized Y (0.0 top to 1.0 bottom) to macOS Cocoa coordinate space (0.0 bottom to height top)
    public func cocoaY(for normalizedY: Double, elementHeight: Double = 0.0) -> Double {
        height * (1.0 - normalizedY) - elementHeight
    }

    /// Converts normalized Y to screen pixel point Y (measured from top)
    public func pixelY(for normalizedY: Double) -> Double {
        normalizedY * height
    }

    /// Converts normalized length to physical pixel height
    public func pixelHeight(for normalizedLength: Double) -> Double {
        normalizedLength * height
    }
}
