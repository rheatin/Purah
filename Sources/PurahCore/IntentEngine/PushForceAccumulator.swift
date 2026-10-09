// Sources/PurahCore/IntentEngine/PushForceAccumulator.swift
import Foundation
import CoreGraphics

/// Edge push force accumulator (Barrier / Input Leap physical resistance barrier model).
///
/// Overcomes the macOS hardware boundary coordinate clamping dilemma where cursor velocity drops to zero at screen edges:
/// Accumulates relative hardware motion deltas (Raw Motion Delta), triggering drawer activation upon breaking through the resistance threshold.
public struct PushForceAccumulator: Sendable {
    /// Accumulated push force magnitude (points/pixels)
    public private(set) var accumulatedForce: Double = 0.0
    /// Timestamp of the last valid outward motion delta
    public private(set) var lastPushTime: Date?

    /// Leaky bucket decay timeout: resets accumulated force after stopping edge push
    public let decayTimeout: TimeInterval = 0.18

    public init() {}

    /// Records outward edge push event and accumulates motion delta
    /// - Parameters:
    ///   - outwardDelta: Outward physical displacement component perpendicular to edge (pushing outward > 0)
    ///   - timestamp: Event timestamp
    ///   - threshold: Breakthrough resistance threshold (default 36.0px)
    /// - Returns: True if resistance barrier was breached
    public mutating func push(
        outwardDelta: Double,
        timestamp: Date = Date(),
        threshold: Double = 36.0
    ) -> Bool {
        // 1. Definite inward retreat resets accumulator immediately (anti-accidental touch protection)
        if outwardDelta <= -8.0 {
            reset()
            return false
        }

        // Minor physiological jitter (-8.0 < outwardDelta < 0) deducts force without hard reset
        if outwardDelta < 0 {
            accumulatedForce = max(accumulatedForce + outwardDelta, 0.0)
            return false
        }

        // Filter valid outward movement increments (>= 0.2px)
        guard outwardDelta >= 0.2 else {
            // Inactivity timeout decays force via leaky bucket mechanism
            if let last = lastPushTime, timestamp.timeIntervalSince(last) > decayTimeout {
                reset()
            }
            return false
        }

        // 2. Leaky bucket decay: restart accumulation if interval exceeds decayTimeout
        if let last = lastPushTime, timestamp.timeIntervalSince(last) > decayTimeout {
            accumulatedForce = 0.0
        }

        // 3. Accumulate physical push force
        accumulatedForce += outwardDelta
        lastPushTime = timestamp

        // 4. Resistance barrier breakthrough check
        if accumulatedForce >= threshold {
            reset()
            return true
        }

        return false
    }

    /// Resets push force accumulator
    public mutating func reset() {
        accumulatedForce = 0.0
        lastPushTime = nil
    }
}
