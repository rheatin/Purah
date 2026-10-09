// Sources/PurahCore/LayoutEngine/ErgonomicAutoLayoutEngine.swift
import Foundation

public struct ResolvedPodLayoutItem: Identifiable, Sendable {
    public var id: String { pod.id }
    public let pod: SlotPod
    public let startY: Double
    public let spanH: Double

    public init(pod: SlotPod, startY: Double, spanH: Double) {
        self.pod = pod
        self.startY = startY
        self.spanH = spanH
    }
}

public enum ErgonomicAutoLayoutEngine {
    public static let defaultSafeBounds: ClosedRange<Double> = 0.02...0.98
    public static let defaultGap: Double = 0.012

    /// Computes optimal ergonomic slot pod layout along a given edge
    public static func layout(
        pods: [SlotPod],
        on edge: MountEdge,
        safeBounds: ClosedRange<Double> = defaultSafeBounds,
        gap: Double = defaultGap
    ) -> [SlotPod] {
        let activePods = pods.filter { $0.edge == edge && $0.isEnabled }
        guard !activePods.isEmpty else { return [] }

        // 1. Sort pods by ergonomic zone hierarchy and weight
        let sortedPods = activePods.sorted {
            ($0.preferredZone, -$0.ergonomicWeight) < ($1.preferredZone, -$1.ergonomicWeight)
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
        let excess = targetLengths.reduce(0.0, +) - availableHeight
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
        let laidOutLeft = layout(pods: leftCandidates, on: .left, safeBounds: safeBounds, gap: gap)
        let laidOutRight = layout(pods: rightCandidates, on: .right, safeBounds: safeBounds, gap: gap)

        let map = Dictionary(uniqueKeysWithValues: (laidOutLeft + laidOutRight).map { ($0.id, $0) })
        return pods.map { map[$0.id] ?? $0 }
    }

    /// Strict physical non-overlapping rail layout solver
    public static func resolvePhysicalRailLayout(
        pods: [SlotPod],
        on edge: MountEdge,
        totalHeight: Double,
        gap: Double = 8.0,
        safeTop: Double = 16.0,
        safeBottom: Double? = nil,
        spanProvider: ((SlotPod) -> Double)? = nil
    ) -> [ResolvedPodLayoutItem] {
        let edgePods = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        guard !edgePods.isEmpty else { return [] }

        let bottomLimit = safeBottom ?? (totalHeight - 16.0)
        let availableH = max(bottomLimit - safeTop, 100.0)

        // 1. Compute effective expanded span for each pod
        var spans: [Double] = edgePods.map { pod in
            if let provider = spanProvider {
                return max(provider(pod), 36.0)
            }
            return max(pod.range.length * totalHeight, 36.0)
        }

        let totalSpans = spans.reduce(0, +)
        let totalGaps = Double(edgePods.count - 1) * gap
        let totalNeeded = totalSpans + totalGaps

        // If total needed height exceeds available height, apply smooth proportional compression
        if totalNeeded > availableH && totalSpans > 0 {
            let scale = max((availableH - totalGaps) / totalSpans, 0.65)
            spans = spans.map { max($0 * scale, 36.0) }
        }

        // 2. Forward pass to establish initial anchor positions
        var startYs: [Double] = []
        var currentY: Double = safeTop

        for i in 0..<edgePods.count {
            let idealY = max(edgePods[i].range.start * totalHeight, currentY)
            startYs.append(idealY)
            currentY = idealY + spans[i] + gap
        }

        // 3. Backward pass: if bottom pod exceeds boundary, gracefully push chain upwards
        if let lastStart = startYs.last, let lastSpan = spans.last {
            let overflow = (lastStart + lastSpan) - bottomLimit
            if overflow > 0 {
                var targetBottom = bottomLimit
                for i in stride(from: edgePods.count - 1, through: 0, by: -1) {
                    let maxAllowedStart = targetBottom - spans[i]
                    startYs[i] = min(startYs[i], maxAllowedStart)
                    targetBottom = startYs[i] - gap
                }
            }
        }

        // 4. Strict zero-overlap invariant: Pod[i] must always follow Pod[i-1] bottom edge
        for i in 0..<edgePods.count {
            if i == 0 {
                startYs[i] = max(startYs[i], safeTop)
            } else {
                startYs[i] = max(startYs[i], startYs[i - 1] + spans[i - 1] + gap)
            }
        }

        return (0..<edgePods.count).map {
            ResolvedPodLayoutItem(pod: edgePods[$0], startY: startYs[$0], spanH: spans[$0])
        }
    }
}
