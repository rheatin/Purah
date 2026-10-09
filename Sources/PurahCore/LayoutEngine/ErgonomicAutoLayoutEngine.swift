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

    /// 最优双轨人机工程学自动排版 (Optimal Bilateral Ergonomic Layout Optimizer)
    /// 针对所有已启用的插件，智能分配左右导轨（双轨平衡），并严格按照三大舒适区（瞥视/黄金/速滑）与权重排布
    public static func optimizeBilateralLayout(
        pods: [SlotPod],
        availableHeight: Double = 800.0,
        safeBounds: ClosedRange<Double> = defaultSafeBounds,
        gap: Double = defaultGap
    ) -> [SlotPod] {
        let enabledPods = pods.filter { $0.isEnabled }
        guard !enabledPods.isEmpty else { return pods }

        func preferredEdge(for pod: SlotPod) -> MountEdge {
            switch pod.id {
            case "vitals", "shelf", "notes", "terminal", "docker":
                return .left
            case "calendar", "todo", "music", "weather":
                return .right
            default:
                return pod.edge
            }
        }

        func zone(for pod: SlotPod) -> ZoneType {
            switch pod.id {
            case "vitals", "weather":
                return .glance
            case "calendar", "todo", "music", "terminal", "docker":
                return .goldenAction
            case "shelf", "notes", "scripts", "git-radar":
                return .quickFlick
            default:
                return pod.preferredZone
            }
        }

        var leftCandidates: [SlotPod] = []
        var rightCandidates: [SlotPod] = []

        for var pod in enabledPods {
            let targetEdge = preferredEdge(for: pod)
            pod.edge = targetEdge
            pod.preferredZone = zone(for: pod)
            if targetEdge == .left {
                leftCandidates.append(pod)
            } else {
                rightCandidates.append(pod)
            }
        }

        // 双轨负载均衡：如果一侧模块数过多，将灵活性最高的模块平衡迁移到另一侧
        let flexibleShiftOrder = ["scripts", "notes", "shelf", "music", "git-radar"]
        while leftCandidates.count > rightCandidates.count + 2 {
            if let shiftIdx = leftCandidates.firstIndex(where: { flexibleShiftOrder.contains($0.id) }) {
                var shifted = leftCandidates.remove(at: shiftIdx)
                shifted.edge = .right
                rightCandidates.append(shifted)
            } else {
                break
            }
        }

        while rightCandidates.count > leftCandidates.count + 2 {
            if let shiftIdx = rightCandidates.firstIndex(where: { flexibleShiftOrder.contains($0.id) }) {
                var shifted = rightCandidates.remove(at: shiftIdx)
                shifted.edge = .left
                leftCandidates.append(shifted)
            } else {
                break
            }
        }

        // 对左右双轨分别执行严密的人机工学区间排序与空间比例分配
        let laidOutLeft = layout(pods: leftCandidates, on: .left, safeBounds: safeBounds, gap: gap)
        let laidOutRight = layout(pods: rightCandidates, on: .right, safeBounds: safeBounds, gap: gap)

        let map = Dictionary(uniqueKeysWithValues: (laidOutLeft + laidOutRight).map { ($0.id, $0) })
        return pods.map { map[$0.id] ?? $0 }
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
