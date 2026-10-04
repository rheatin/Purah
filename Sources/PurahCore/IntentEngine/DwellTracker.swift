// Sources/PurahCore/IntentEngine/DwellTracker.swift
import Foundation

public enum DwellState: Sendable, Equatable {
    case idle
    case dwelling(podId: String, progress: Double)
    case triggered(podId: String)
}

public final class DwellTracker: @unchecked Sendable {
    public let threshold: TimeInterval
    private var currentPodId: String?
    private var dwellStartTime: Date?
    private var isTriggered: Bool = false

    public init(threshold: TimeInterval = 0.16) {
        self.threshold = threshold
    }

    public func update(podId: String?, intent: FlingIntent, timestamp: Date = Date()) -> DwellState {
        guard let podId = podId, intent == .candidateDwell else {
            reset()
            return .idle
        }

        if currentPodId != podId {
            currentPodId = podId
            dwellStartTime = timestamp
            isTriggered = false
            return .dwelling(podId: podId, progress: 0.0)
        }

        guard let startTime = dwellStartTime else {
            dwellStartTime = timestamp
            return .dwelling(podId: podId, progress: 0.0)
        }

        if isTriggered {
            return .triggered(podId: podId)
        }

        let elapsed = timestamp.timeIntervalSince(startTime)
        if elapsed >= threshold {
            isTriggered = true
            return .triggered(podId: podId)
        } else {
            let progress = min(elapsed / threshold, 1.0)
            return .dwelling(podId: podId, progress: progress)
        }
    }

    public func reset() {
        currentPodId = nil
        dwellStartTime = nil
        isTriggered = false
    }
}
