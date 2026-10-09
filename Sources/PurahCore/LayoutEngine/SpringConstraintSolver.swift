// Sources/PurahCore/LayoutEngine/SpringConstraintSolver.swift
import Foundation

public enum SpringConstraintSolver {
    public static let defaultBounds: ClosedRange<Double> = 0.01...0.99
    public static let minSpacing: Double = 0.008

    /// 求解当某个 Pod 被拖拽/改变尺寸时的全轨道防重叠物理状态
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

        // 1. 计算被拖拽 Pod 前方所有 Predecessors 与后方所有 Successors 的刚性最小空间
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
            // 整体上下移动：严格受制于前后所有模块最小尺寸边界，绝不骑到上方或下方模块头上
            clampedStart = min(max(newRange.start, absoluteMinStart), max(absoluteMaxEnd - targetMinLength, absoluteMinStart))
            let maxAllowedLength = max(absoluteMaxEnd - clampedStart, targetMinLength)
            clampedLength = min(max(newRange.length, targetMinLength), maxAllowedLength)
            if clampedStart + clampedLength > absoluteMaxEnd {
                clampedStart = max(absoluteMaxEnd - clampedLength, absoluteMinStart)
            }
        } else {
            // 纯单向底部缩放：顶部坐标绝对锁死，向下拉伸不能挤出下方所有模块的最小底线
            clampedStart = edgePods[targetIndex].range.start
            let maxAllowedLength = max(absoluteMaxEnd - clampedStart, targetMinLength)
            clampedLength = min(max(newRange.length, targetMinLength), maxAllowedLength)
        }

        edgePods[targetIndex].range = NormalizedRange(start: clampedStart, length: clampedLength)

        // 2. 向上弹性推挤 (Predecessors: stride backwards from targetIndex - 1 down to 0)
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

        // 3. 向下弹性推挤 (Successors: targetIndex + 1 up to count - 1)
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

        // 4. 合并回全量 Pods 并维持其他轨道未变
        var resultMap = Dictionary(uniqueKeysWithValues: allPods.map { ($0.id, $0) })
        for updated in edgePods {
            resultMap[updated.id] = updated
        }

        return allPods.map { resultMap[$0.id] ?? $0 }
    }
}
