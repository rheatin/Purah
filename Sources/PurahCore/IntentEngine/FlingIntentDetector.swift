// Sources/PurahCore/IntentEngine/FlingIntentDetector.swift
import Foundation
import CoreGraphics

public enum FlingIntent: Sendable, Equatable {
    case none
    case verticalFlingSuppressed
    case candidateDwell
}

public struct FlingIntentDetector: Sendable {
    public var verticalFlingRatio: Double = 1.5
    public var verticalMinSpeed: Double = 600.0 // pt/s
    public var maxVerticalDrift: Double = 350.0 // pt/s

    public init() {}

    public func evaluate(
        point: CGPoint,
        velocity: CGPoint,
        edge: MountEdge,
        edgeMargin: Double = 8.0
    ) -> FlingIntent {
        let absVx = abs(velocity.x)
        let absVy = abs(velocity.y)

        // 1. 若纵向速度远高于横向速度，且速度显著，立即判定为抑制
        if absVy > (absVx * verticalFlingRatio) && absVy > verticalMinSpeed {
            return .verticalFlingSuppressed
        }

        // 2. 判定是否为边缘顶住与低漂移驻留
        let nearEdge: Bool
        switch edge {
        case .left:
            nearEdge = point.x <= edgeMargin
        case .right:
            nearEdge = point.x >= -edgeMargin // 相对右边缘
        }

        if nearEdge && absVy <= maxVerticalDrift {
            return .candidateDwell
        }

        return .none
    }
}
