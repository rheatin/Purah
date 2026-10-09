// Sources/PurahCore/IntentEngine/VelocityTracker.swift
import Foundation
import CoreGraphics

public struct VelocityTracker: Sendable {
    private struct Sample: Sendable {
        let point: CGPoint
        let timestamp: Date
    }

    private var samples: [Sample] = []
    private let maxWindow: TimeInterval = 0.10 // 100ms sample window

    public init() {}

    public mutating func add(point: CGPoint, timestamp: Date = Date()) {
        // Prevent duplicate events within sub-millisecond window from collapsing dt
        if let last = samples.last, abs(timestamp.timeIntervalSince(last.timestamp)) < 0.003 {
            samples[samples.count - 1] = Sample(point: point, timestamp: timestamp)
            return
        }

        samples.append(Sample(point: point, timestamp: timestamp))
        let cutoff = timestamp.addingTimeInterval(-maxWindow)
        samples.removeAll { $0.timestamp < cutoff }
    }

    public func currentVelocity() -> CGPoint {
        guard samples.count >= 2,
              let last = samples.last else {
            return .zero
        }
        // Find earliest sample separated by at least 12ms to guarantee stable velocity
        guard let first = samples.first(where: { last.timestamp.timeIntervalSince($0.timestamp) >= 0.012 }) ?? samples.first else {
            return .zero
        }
        let dt = last.timestamp.timeIntervalSince(first.timestamp)
        guard dt > 0.003 else { return .zero }
        let dx = last.point.x - first.point.x
        let dy = last.point.y - first.point.y
        return CGPoint(x: dx / dt, y: dy / dt)
    }

    public mutating func reset() {
        samples.removeAll()
    }
}
