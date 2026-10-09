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

        // 1. If vertical velocity substantially exceeds horizontal velocity and is significant, suppress
        if absVy > (absVx * verticalFlingRatio) && absVy > verticalMinSpeed {
            return .verticalFlingSuppressed
        }

        // 2. Determine whether cursor is resting against edge with minimal vertical drift
        let nearEdge: Bool
        switch edge {
        case .left:
            nearEdge = point.x <= edgeMargin
        case .right:
            nearEdge = point.x >= -edgeMargin // Relative to right edge
        }

        if nearEdge && absVy <= maxVerticalDrift {
            return .candidateDwell
        }

        return .none
    }
}
