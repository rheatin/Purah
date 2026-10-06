// Sources/PurahCore/IntentEngine/VelocityTracker.swift
import Foundation
import CoreGraphics

public struct VelocityTracker: Sendable {
    private struct Sample: Sendable {
        let point: CGPoint
        let timestamp: Date
    }

    private var samples: [Sample] = []
    private let maxWindow: TimeInterval = 0.10 // 100ms 采样窗口

    public init() {}

    public mutating func add(point: CGPoint, timestamp: Date = Date()) {
        samples.append(Sample(point: point, timestamp: timestamp))
        let cutoff = timestamp.addingTimeInterval(-maxWindow)
        samples.removeAll { $0.timestamp < cutoff }
    }

    public func currentVelocity() -> CGPoint {
        guard samples.count >= 2,
              let first = samples.first,
              let last = samples.last else {
            return .zero
        }
        let dt = last.timestamp.timeIntervalSince(first.timestamp)
        guard dt > 0.001 else { return .zero }
        let dx = last.point.x - first.point.x
        let dy = last.point.y - first.point.y
        return CGPoint(x: dx / dt, y: dy / dt)
    }

    public mutating func reset() {
        samples.removeAll()
    }
}
