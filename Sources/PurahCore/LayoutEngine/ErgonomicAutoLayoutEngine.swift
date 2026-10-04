// Sources/PurahCore/LayoutEngine/ErgonomicAutoLayoutEngine.swift
import Foundation

public enum ErgonomicAutoLayoutEngine {
    public static let defaultSafeBounds: ClosedRange<Double> = 0.12...0.88
    public static let defaultGap: Double = 0.015

    /// 计算给定边缘的一组槽位模块的最优人机工学排布
    public static func layout(
        pods: [SlotPod],
        on edge: MountEdge,
        safeBounds: ClosedRange<Double> = defaultSafeBounds,
        gap: Double = defaultGap
    ) -> [SlotPod] {
        let activePods = pods.filter { $0.edge == edge && $0.isEnabled }
        guard !activePods.isEmpty else { return [] }

        // 1. 按照人机工学舒适区与权重排序
        let sortedPods = activePods.sorted { p1, p2 in
            let z1 = zoneRank(p1.preferredZone)
            let z2 = zoneRank(p2.preferredZone)
            if z1 != z2 {
                return z1 < z2
            }
            return p1.ergonomicWeight > p2.ergonomicWeight
        }

        // 2. 计算可分配的净空间
        let totalSpan = safeBounds.upperBound - safeBounds.lowerBound
        let totalGaps = Double(sortedPods.count - 1) * gap
        let availableHeight = max(totalSpan - totalGaps, 0.05)

        // 3. 计算权重分配
        let totalWeight = sortedPods.reduce(0.0) { $0 + max($1.ergonomicWeight, 1.0) }
        var targetLengths: [Double] = sortedPods.map { pod in
            let rawLength = availableHeight * (max(pod.ergonomicWeight, 1.0) / totalWeight)
            return max(rawLength, pod.minLength)
        }

        // 若因最小高度限制超出净空间，进行等比压缩缩放
        let sumLengths = targetLengths.reduce(0.0, +)
        if sumLengths > availableHeight {
            let scale = availableHeight / sumLengths
            targetLengths = targetLengths.map { $0 * scale }
        }

        // 4. 从安全区起点顺序安放每个 Pod
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

    private static func zoneRank(_ zone: ZoneType) -> Int {
        switch zone {
        case .glance: return 0
        case .goldenAction: return 1
        case .quickFlick: return 2
        }
    }
}
