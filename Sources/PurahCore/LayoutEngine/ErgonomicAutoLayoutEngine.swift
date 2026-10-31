// Sources/PurahCore/LayoutEngine/ErgonomicAutoLayoutEngine.swift
import Foundation

public struct ResolvedPodLayoutItem: Identifiable, Sendable {
    public var id: String { pod.id }
    public let pod: SlotPod
    public let startY: Double
    public let spanH: Double
    public let drawerStartY: Double
    public let drawerSpanH: Double
    public let majorGroupId: String?

    public init(
        pod: SlotPod,
        startY: Double,
        spanH: Double,
        drawerStartY: Double? = nil,
        drawerSpanH: Double? = nil,
        majorGroupId: String? = nil
    ) {
        self.pod = pod
        self.startY = startY
        self.spanH = spanH
        self.drawerStartY = drawerStartY ?? startY
        self.drawerSpanH = drawerSpanH ?? spanH
        self.majorGroupId = majorGroupId
    }
}

public enum ErgonomicAutoLayoutEngine {
    public static let defaultSafeBounds: ClosedRange<Double> = 0.02...0.98
    public static let defaultGap: Double = 0.012

    /// Computes optimal ergonomic slot pod layout along a given edge
    public static func layout(
        pods: [SlotPod],
        on edge: MountEdge,
        preserveCustomOrder: Bool = true,
        safeBounds: ClosedRange<Double> = defaultSafeBounds,
        gap: Double = defaultGap
    ) -> [SlotPod] {
        let activePods = pods.filter { $0.edge == edge && $0.isEnabled }
        guard !activePods.isEmpty else { return [] }

        // 1. Sort pods: if preserveCustomOrder and pods have distinct start positions, respect user order ($0.range.start)
        var sortedPods: [SlotPod]
        let hasDistinctStarts = Set(activePods.map { Int($0.range.start * 1000) }).count == activePods.count
        if preserveCustomOrder && hasDistinctStarts {
            sortedPods = activePods.sorted { $0.range.start < $1.range.start }
        } else {
            sortedPods = activePods.sorted {
                ($0.preferredZone, -$0.ergonomicWeight) < ($1.preferredZone, -$1.ergonomicWeight)
            }
        }

        // 2. Compute available net vertical height
        let totalSpan = safeBounds.upperBound - safeBounds.lowerBound
        let totalGaps = Double(sortedPods.count - 1) * gap
        let availableHeight = max(totalSpan - totalGaps, 0.05)

        // 3. Proportional weight allocation to calculate target lengths
        let totalWeight = sortedPods.reduce(0.0) { $0 + max($1.ergonomicWeight, 1.0) }
        var targetLengths: [Double] = sortedPods.map { pod in
            let rawLength = availableHeight * (max(pod.ergonomicWeight, 1.0) / totalWeight)
            return max(rawLength, pod.minLength)
        }

        // 4. If space is exceeded, compress pods with surplus slack while strictly defending minLength floors
        let totalTargetLength = targetLengths.reduce(0.0, +)
        let excess = totalTargetLength - availableHeight
        if excess > 0 {
            // Sum up all compressible slack above minLength
            let compressableSlack = targetLengths.enumerated().reduce(0.0) { total, item in
                let podMin = sortedPods[item.offset].minLength
                return total + max(item.element - podMin, 0.0)
            }

            if compressableSlack >= excess && compressableSlack > 0 {
                // Sufficient slack: only compress pods with surplus space, never violating minLength floors
                for i in targetLengths.indices {
                    let podMin = sortedPods[i].minLength
                    let slack = max(targetLengths[i] - podMin, 0.0)
                    if slack > 0 {
                        let reduction = excess * (slack / compressableSlack)
                        targetLengths[i] = max(targetLengths[i] - reduction, podMin)
                    }
                }
            } else {
                // Insufficient slack (physical overload): clamp all pods to their minLength floors
                for i in targetLengths.indices {
                    targetLengths[i] = sortedPods[i].minLength
                }
                // Under overload, scale proportionally to fit available screen height
                let minSum = targetLengths.reduce(0.0, +)
                if minSum > availableHeight && minSum > 0 {
                    let overflowScale = availableHeight / minSum
                    targetLengths = targetLengths.map { $0 * overflowScale }
                }
            }
        } else if excess < -0.001 && totalTargetLength > 0 {
            // Surplus space remains: expand pods proportionally to gracefully fill the entire rail without dead blank space!
            let fillScale = availableHeight / totalTargetLength
            targetLengths = targetLengths.map { $0 * fillScale }
        }

        // 5. Sequence pods starting from safe boundary
        var currentY = safeBounds.lowerBound
        var resolvedPods: [SlotPod] = []

        for (index, pod) in sortedPods.enumerated() {
            var updated = pod
            let length = targetLengths[index]
            updated.range = NormalizedRange(start: currentY, length: length)
            resolvedPods.append(updated)
            currentY += length + gap
        }

        return resolvedPods
    }

    /// Optimal Bilateral Ergonomic Layout Optimizer
    /// Rebalances enabled pods across left and right rails according to ergonomic zones and weights
    /// - Parameter reassignEdges: Whether to repartition rail assignments (default false: strictly preserves user-chosen edge)
    public static func optimizeBilateralLayout(
        pods: [SlotPod],
        reassignEdges: Bool = false,
        availableHeight: Double = 800.0,
        safeBounds: ClosedRange<Double> = defaultSafeBounds,
        gap: Double = defaultGap
    ) -> [SlotPod] {
        let enabledPods = pods.filter { $0.isEnabled }
        guard !enabledPods.isEmpty else { return pods }

        var leftCandidates: [SlotPod] = []
        var rightCandidates: [SlotPod] = []

        if reassignEdges {
            for var pod in enabledPods {
                let targetEdge = pod.defaultEdge ?? pod.edge
                pod.edge = targetEdge
                if targetEdge == .left {
                    leftCandidates.append(pod)
                } else {
                    rightCandidates.append(pod)
                }
            }

            // Bilateral load balancing: migrate lowest-weight flexible pods when one rail has a surplus
            while leftCandidates.count > rightCandidates.count + 2 {
                if let minIdx = leftCandidates.indices.min(by: { leftCandidates[$0].ergonomicWeight < leftCandidates[$1].ergonomicWeight }) {
                    var shifted = leftCandidates.remove(at: minIdx)
                    shifted.edge = .right
                    rightCandidates.append(shifted)
                } else {
                    break
                }
            }

            while rightCandidates.count > leftCandidates.count + 2 {
                if let minIdx = rightCandidates.indices.min(by: { rightCandidates[$0].ergonomicWeight < rightCandidates[$1].ergonomicWeight }) {
                    var shifted = rightCandidates.remove(at: minIdx)
                    shifted.edge = .left
                    leftCandidates.append(shifted)
                } else {
                    break
                }
            }
        } else {
            // Strictly preserve user-assigned left/right rail choices
            for pod in enabledPods {
                if pod.edge == .left {
                    leftCandidates.append(pod)
                } else {
                    rightCandidates.append(pod)
                }
            }
        }

        // Solve ergonomic ordering and proportional distribution independently on left and right rails
        let laidOutLeft = layout(pods: leftCandidates, on: .left, preserveCustomOrder: !reassignEdges, safeBounds: safeBounds, gap: gap)
        let laidOutRight = layout(pods: rightCandidates, on: .right, preserveCustomOrder: !reassignEdges, safeBounds: safeBounds, gap: gap)

        let map = Dictionary((laidOutLeft + laidOutRight).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return pods.map { map[$0.id] ?? $0 }
    }
}
