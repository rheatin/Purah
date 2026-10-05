// Sources/PurahCore/LayoutEngine/SpringConstraintSolver.swift
import Foundation

public enum SpringConstraintSolver {
    public static let defaultBounds: ClosedRange<Double> = 0.05...0.95
    public static let minSpacing: Double = 0.008

    /// 求解当某个 Pod 被拖拽/改变尺寸时的全轨道防重叠物理状态
    public static func resolve(
        draggedPodId: String,
        newRange: NormalizedRange,
        allPods: [SlotPod],
        on edge: MountEdge,
        bounds: ClosedRange<Double> = defaultBounds
    ) -> [SlotPod] {
        var edgePods = allPods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }

        guard let targetIndex = edgePods.firstIndex(where: { $0.id == draggedPodId }) else {
            return allPods
        }

        // 1. 约束被拖拽 Pod 的边界 (单向顶部锚定：若是底部拉伸，起点绝对锁定)
        let isResizingOnly = abs(newRange.start - edgePods[targetIndex].range.start) < 0.0001

        var clampedStart = edgePods[targetIndex].range.start
        var clampedLength = newRange.length

        if !isResizingOnly {
            clampedStart = max(newRange.start, bounds.lowerBound)
            let maxAllowedLength = bounds.upperBound - clampedStart
            clampedLength = min(max(newRange.length, edgePods[targetIndex].minLength), maxAllowedLength)
            if clampedStart + clampedLength > bounds.upperBound {
                clampedStart = bounds.upperBound - clampedLength
            }
        } else {
            // 纯单向底部缩放：顶部坐标绝对锁死，杜绝反向向上膨胀
            clampedStart = edgePods[targetIndex].range.start
            let maxAllowed = max(bounds.upperBound - clampedStart, edgePods[targetIndex].minLength)
            clampedLength = min(max(newRange.length, edgePods[targetIndex].minLength), maxAllowed)
        }

        edgePods[targetIndex].range = NormalizedRange(start: clampedStart, length: clampedLength)

        // 2. 向前推挤 (仅在整体移动模块时向前推，底部缩放绝不逆向推挤上方模块)
        if !isResizingOnly && targetIndex > 0 {
            for i in stride(from: targetIndex - 1, through: 0, by: -1) {
                let rightBound = edgePods[i + 1].range.start - minSpacing
                if edgePods[i].range.end > rightBound {
                    var newLength = edgePods[i].range.length
                    var newStart = rightBound - newLength
                    if newStart < bounds.lowerBound {
                        newStart = bounds.lowerBound
                        newLength = max(rightBound - newStart, edgePods[i].minLength)
                    }
                    edgePods[i].range = NormalizedRange(start: newStart, length: newLength)
                }
            }
        }

        // 3. 向后推挤 (Successors: targetIndex + 1 upTo count - 1)
        if targetIndex < edgePods.count - 1 {
            for i in (targetIndex + 1)..<edgePods.count {
                let leftBound = edgePods[i - 1].range.end + minSpacing
                if edgePods[i].range.start < leftBound {
                    let newStart = leftBound
                    var newLength = edgePods[i].range.length
                    if newStart + newLength > bounds.upperBound {
                        newLength = max(bounds.upperBound - newStart, edgePods[i].minLength)
                    }
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
