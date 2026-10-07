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
        let sortedPods = activePods.sorted {
            ($0.preferredZone, -$0.ergonomicWeight) < ($1.preferredZone, -$1.ergonomicWeight)
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

    /// 严格物理零重叠导轨链式求解器 (Strict Physical Non-Overlapping Rail Solver)
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

        // 1. 计算每个 Pod 的有效展开跨度
        var spans: [Double] = edgePods.map { pod in
            if let provider = spanProvider {
                return max(provider(pod), 36.0)
            }
            return max(pod.range.length * totalHeight, 36.0)
        }

        let totalSpans = spans.reduce(0, +)
        let totalGaps = Double(edgePods.count - 1) * gap
        let totalNeeded = totalSpans + totalGaps

        // 若总高度超出可用高度，进行等比平滑收缩保底
        if totalNeeded > availableH && totalSpans > 0 {
            let scale = max((availableH - totalGaps) / totalSpans, 0.65)
            spans = spans.map { max($0 * scale, 36.0) }
        }

        // 2. 正向求解初步起始位置
        var startYs: [Double] = []
        var currentY: Double = safeTop

        for i in 0..<edgePods.count {
            let idealY = max(edgePods[i].range.start * totalHeight, currentY)
            startYs.append(idealY)
            currentY = idealY + spans[i] + gap
        }

        // 3. 反向平推：若底部 Pod 触碰底界，逆向优雅抬升整条链
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

        // 4. 严格零重叠铁律：Pod[i] 必须永远位于 Pod[i-1] 底部之后
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
