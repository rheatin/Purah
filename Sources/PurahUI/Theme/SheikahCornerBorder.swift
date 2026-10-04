// Sources/PurahUI/Theme/SheikahCornerBorder.swift
import SwiftUI

public struct SheikahCornerShape: Shape {
    public var cornerLength: CGFloat
    public var strokeWidth: CGFloat

    public init(cornerLength: CGFloat = 8, strokeWidth: CGFloat = 1.5) {
        self.cornerLength = cornerLength
        self.strokeWidth = strokeWidth
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let l = min(cornerLength, min(w, h) / 2)

        // Top-Left
        path.move(to: CGPoint(x: 0, y: l))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: l, y: 0))

        // Top-Right
        path.move(to: CGPoint(x: w - l, y: 0))
        path.addLine(to: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: l))

        // Bottom-Right
        path.move(to: CGPoint(x: w, y: h - l))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: w - l, y: h))

        // Bottom-Left
        path.move(to: CGPoint(x: l, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: h - l))

        return path
    }
}
