// Sources/PurahCore/LayoutEngine/SpringConstraintSolver.swift
import Foundation

public enum SpringConstraintSolver {
    public static let defaultBounds: ClosedRange<Double> = 0.01...0.99
    public static let minSpacing: Double = 0.008

    /// Solves the full rail physical non-overlapping state when a pod is dragged or resized
    public static func resolve(
        draggedPodId: String,
        newRange: NormalizedRange,
        allPods: [SlotPod],
        on edge: MountEdge,
        bounds: ClosedRange<Double> = defaultBounds,
        minRatioProvider: ((SlotPod) -> Double)? = nil
    ) -> [SlotPod] {
        var edgePods = allPods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }

        guard let targetIndex = edgePods.firstIndex(where: { $0.id == draggedPodId }) else {
            return allPods
        }

        func effectiveMin(for pod: SlotPod) -> Double {
            if let provider = minRatioProvider {
                return max(pod.minLength, provider(pod))
            }
            return pod.minLength
        }

        let isResizingOnly = abs(newRange.start - edgePods[targetIndex].range.start) < 0.0001
        let targetMinLength = effectiveMin(for: edgePods[targetIndex])

        // 1. Calculate rigid minimum space needed by predecessors above and successors below
        var minSpaceAbove: Double = 0.0
        if targetIndex > 0 {
            for i in 0..<targetIndex {
                minSpaceAbove += effectiveMin(for: edgePods[i]) + minSpacing
            }
        }

        var minSpaceBelow: Double = 0.0
        if targetIndex < edgePods.count - 1 {
            for i in (targetIndex + 1)..<edgePods.count {
                minSpaceBelow += minSpacing + effectiveMin(for: edgePods[i])
            }
        }

        let absoluteMinStart = bounds.lowerBound + minSpaceAbove
        let absoluteMaxEnd = bounds.upperBound - minSpaceBelow

        var clampedStart = edgePods[targetIndex].range.start
        var clampedLength = newRange.length

        if !isResizingOnly {
            // Vertical repositioning: strictly bounded by predecessor/successor minimums, preventing overlap
            clampedStart = min(max(newRange.start, absoluteMinStart), max(absoluteMaxEnd - targetMinLength, absoluteMinStart))
            let maxAllowedLength = max(absoluteMaxEnd - clampedStart, targetMinLength)
            clampedLength = min(max(newRange.length, targetMinLength), maxAllowedLength)
            if clampedStart + clampedLength > absoluteMaxEnd {
                clampedStart = max(absoluteMaxEnd - clampedLength, absoluteMinStart)
            }
        } else {
            // Unidirectional bottom resize: top coordinate anchored, downward stretch cannot push successors past minimums
            clampedStart = edgePods[targetIndex].range.start
            let maxAllowedLength = max(absoluteMaxEnd - clampedStart, targetMinLength)
            clampedLength = min(max(newRange.length, targetMinLength), maxAllowedLength)
        }

        edgePods[targetIndex].range = NormalizedRange(start: clampedStart, length: clampedLength)

        // 2. Elastic upward push (Predecessors: stride backwards from targetIndex - 1 down to 0)
        if !isResizingOnly && targetIndex > 0 {
            for i in stride(from: targetIndex - 1, through: 0, by: -1) {
                let rightBound = edgePods[i + 1].range.start - minSpacing
                if edgePods[i].range.end > rightBound {
                    var minSpaceBeforeI: Double = 0.0
                    for k in 0..<i {
                        minSpaceBeforeI += effectiveMin(for: edgePods[k]) + minSpacing
                    }
                    let minAllowedStart = bounds.lowerBound + minSpaceBeforeI
                    var newLength = edgePods[i].range.length
                    var newStart = rightBound - newLength

                    if newStart < minAllowedStart {
                        newStart = minAllowedStart
                        newLength = max(rightBound - newStart, effectiveMin(for: edgePods[i]))
                    }
                    edgePods[i].range = NormalizedRange(start: newStart, length: newLength)
                }
            }
        }

        // 3. Elastic downward push (Successors: targetIndex + 1 up to count - 1)
        if targetIndex < edgePods.count - 1 {
            for i in (targetIndex + 1)..<edgePods.count {
                let leftBound = edgePods[i - 1].range.end + minSpacing
                if edgePods[i].range.start < leftBound {
                    var minSpaceAfterI: Double = 0.0
                    if i < edgePods.count - 1 {
                        for k in (i + 1)..<edgePods.count {
                            minSpaceAfterI += minSpacing + effectiveMin(for: edgePods[k])
                        }
                    }
                    let maxAllowedEnd = bounds.upperBound - minSpaceAfterI
                    let newStart = leftBound
                    let iMinLen = effectiveMin(for: edgePods[i])
                    let maxLen = max(maxAllowedEnd - newStart, iMinLen)
                    let newLength = min(edgePods[i].range.length, maxLen)
                    edgePods[i].range = NormalizedRange(start: newStart, length: newLength)
                }
            }
        }

        // 4. Merge back to all pods preserving un-mutated rails
        var resultMap = Dictionary(uniqueKeysWithValues: allPods.map { ($0.id, $0) })
        for updated in edgePods {
            resultMap[updated.id] = updated
        }

        return allPods.map { resultMap[$0.id] ?? $0 }
    }
}
