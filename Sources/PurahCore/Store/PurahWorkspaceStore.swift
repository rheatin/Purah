// Sources/PurahCore/Store/PurahWorkspaceStore.swift
import Foundation
import AppKit
import SwiftUI
import Observation

public enum DrawerWidthMode: String, Codable, CaseIterable, Sendable {
    case fixed = "fixed"
    case adaptive = "adaptive"
    
    public var displayName: String {
        switch self {
        case .fixed: return "Fixed"
        case .adaptive: return "Adaptive"
        }
    }

    @MainActor
    public var localizedDisplayName: String {
        switch self {
        case .fixed: return "drawer.width.fixed".localized
        case .adaptive: return "drawer.width.adaptive".localized
        }
    }
}

@Observable
@MainActor
public final class PurahWorkspaceStore {
    public var pods: [SlotPod] = []
    public var activeDrawerPodId: String? = nil
    public var activeDrawerItemId: String? = nil
    public var hoveredPodId: String? = nil
    public var isDrawerPinned: Bool = false
    public var pinnedDrawerItemIds: Set<String> = []
    public var isDraggingFromDrawer: Bool = false
    public var currentPreset: PodPreset = .balanced
    public var leftRailOverflowStrategy: RailOverflowStrategy = .dynamicAccordion
    public var rightRailOverflowStrategy: RailOverflowStrategy = .dynamicAccordion

    public var railOverflowStrategy: RailOverflowStrategy {
        get { leftRailOverflowStrategy }
        set {
            setOverflowStrategy(newValue, for: .left)
            setOverflowStrategy(newValue, for: .right)
        }
    }

    public var leftRailPage: Int = 0
    public var rightRailPage: Int = 0
    public var isLeftTopPortalRevealed: Bool = false
    public var isLeftBottomPortalRevealed: Bool = false
    public var isRightTopPortalRevealed: Bool = false
    public var isRightBottomPortalRevealed: Bool = false
    public var isRailsFrozen: Bool = false
    public var isLiveRailEditingMode: Bool = false
    public var hotKeyShortcut: HotKeyShortcut = .defaultShortcut

    @ObservationIgnored
    public var onLiveRailEditingChanged: (@MainActor (Bool) -> Void)?

    @ObservationIgnored
    private var lastKnownTotalHeight: [MountEdge: Double] = [:]

    public func setLiveRailEditingMode(_ enabled: Bool) {
        guard isLiveRailEditingMode != enabled else { return }
        if enabled {
            dismissActiveDrawer()
        }
        isLiveRailEditingMode = enabled
        invalidateLayoutCache()
        if !enabled {
            savePersistentState()
        }
        onLiveRailEditingChanged?(enabled)
        onWindowsRebuildNeeded?()
    }

    public func toggleLiveRailEditingMode() {
        setLiveRailEditingMode(!isLiveRailEditingMode)
    }

    public func mountPod(id: String, to edge: MountEdge) {
        guard let idx = pods.firstIndex(where: { $0.id == id }) else { return }
        pods[idx].edge = edge
        if overflowStrategy(for: edge) == .pagedSpaces {
            pods[idx].pageIndex = max(0, currentRailPage(for: edge))
        } else {
            pods[idx].pageIndex = 0
        }
        if !pods[idx].isEnabled {
            togglePodEnabled(id: id)
        } else {
            invalidateLayoutCache()
            savePersistentState()
            onWindowsRebuildNeeded?()
        }
        if overflowStrategy(for: edge) == .decomposedMajorPod {
            let enabledOnEdge = pods.filter { $0.edge == edge && $0.isEnabled }
            if enabledOnEdge.allSatisfy({ $0.majorGroupId == nil }),
               !userDefaults.bool(forKey: "purah.didSeedMajorGroups.\(edge.rawValue)") {
                seedDefaultMajorGroupsIfNeeded(for: edge)
                invalidateLayoutCache()
                savePersistentState()
            }
        }
    }

    public func isPagePortalRevealed(for edge: MountEdge, isTop: Bool) -> Bool {
        switch (edge, isTop) {
        case (.left, true): return isLeftTopPortalRevealed
        case (.left, false): return isLeftBottomPortalRevealed
        case (.right, true): return isRightTopPortalRevealed
        case (.right, false): return isRightBottomPortalRevealed
        }
    }

    public func updatePagePortalProximity(edge: MountEdge?, isNearTop: Bool, isNearBottom: Bool) {
        let leftTop = (edge == .left && isNearTop)
        let leftBottom = (edge == .left && isNearBottom)
        let rightTop = (edge == .right && isNearTop)
        let rightBottom = (edge == .right && isNearBottom)
        if isLeftTopPortalRevealed != leftTop { isLeftTopPortalRevealed = leftTop }
        if isLeftBottomPortalRevealed != leftBottom { isLeftBottomPortalRevealed = leftBottom }
        if isRightTopPortalRevealed != rightTop { isRightTopPortalRevealed = rightTop }
        if isRightBottomPortalRevealed != rightBottom { isRightBottomPortalRevealed = rightBottom }
    }

    public func overflowStrategy(for edge: MountEdge) -> RailOverflowStrategy {
        edge == .left ? leftRailOverflowStrategy : rightRailOverflowStrategy
    }

    public func setOverflowStrategy(_ strategy: RailOverflowStrategy, for edge: MountEdge) {
        if edge == .left {
            leftRailOverflowStrategy = strategy
        } else {
            rightRailOverflowStrategy = strategy
        }
        if strategy != .pagedSpaces {
            setRailPage(0, for: edge)
            for i in pods.indices where pods[i].edge == edge {
                pods[i].pageIndex = 0
            }
        }
        if strategy == .decomposedMajorPod {
            seedDefaultMajorGroupsIfNeeded(for: edge)
        } else if strategy == .pagedSpaces {
            seedDefaultPagesIfNeeded(for: edge)
        }
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func currentRailPage(for edge: MountEdge) -> Int {
        edge == .left ? leftRailPage : rightRailPage
    }

    public func setRailPage(_ page: Int, for edge: MountEdge) {
        let clamped = max(page, 0)
        if edge == .left {
            leftRailPage = clamped
        } else {
            rightRailPage = clamped
        }
        invalidateLayoutCache()
    }

    public func setPodPage(id: String, pageIndex: Int) {
        guard let idx = pods.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(0, pageIndex)
        let edge = pods[idx].edge
        pods[idx].pageIndex = clamped
        normalizePageRanges(for: edge)
        setRailPage(clamped, for: edge)
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func seedDefaultPagesIfNeeded(for edge: MountEdge) {
        let enabledIndices = pods.indices.filter { pods[$0].edge == edge && pods[$0].isEnabled }
            .sorted { pods[$0].range.start < pods[$1].range.start }
        guard !enabledIndices.isEmpty else { return }
        let allZero = enabledIndices.allSatisfy { pods[$0].pageIndex == 0 }
        guard allZero else { return }

        let screenH = Double(availableScreenHeight(for: edge))
        let pageBudget = max(screenH - 96.0, 260.0)
        let totalRequired = enabledIndices.reduce(0.0) { $0 + Double(minimumDrawerHeight(for: pods[$1].id)) + 12.0 }
        guard totalRequired > pageBudget else { return }

        var curPage = 0
        var curHeight = 0.0
        for idx in enabledIndices {
            let podNeeded = Double(minimumDrawerHeight(for: pods[idx].id)) + 12.0
            if curHeight > 0 && (curHeight + podNeeded) > pageBudget {
                curPage += 1
                curHeight = podNeeded
            } else {
                curHeight += podNeeded
            }
            pods[idx].pageIndex = curPage
        }
        normalizePageRanges(for: edge)
    }

    private func normalizePageRanges(for edge: MountEdge) {
        let enabledIndices = pods.indices.filter { pods[$0].edge == edge && pods[$0].isEnabled }
        let groupedByPage = Dictionary(grouping: enabledIndices, by: { max(0, pods[$0].pageIndex) })
        let pageCount = groupedByPage.count
        let safeStart = pageCount > 1 ? (48.0 / 900.0) : 0.02
        let safeTotalSpan = pageCount > 1 ? ((900.0 - 96.0) / 900.0) : 0.94
        let gap = 8.0 / 900.0
        for (_, pagePodIndices) in groupedByPage {
            let sortedIndices = pagePodIndices.sorted { pods[$0].range.start < pods[$1].range.start }
            guard !sortedIndices.isEmpty else { continue }
            let totalGaps = Double(max(sortedIndices.count - 1, 0)) * gap
            let usableSpan = max(safeTotalSpan - totalGaps, Double(sortedIndices.count) * 0.08)
            let weights = sortedIndices.map { max(pods[$0].range.length, pods[$0].minLength, 0.08) }
            let weightSum = max(weights.reduce(0.0, +), 0.0001)
            var curStart = safeStart
            for (offset, idx) in sortedIndices.enumerated() {
                let len = max(usableSpan * (weights[offset] / weightSum), pods[idx].minLength)
                pods[idx].range = NormalizedRange(
                    start: min(curStart, 0.95),
                    length: min(len, max(0.98 - curStart, pods[idx].minLength))
                )
                curStart += len + gap
            }
        }
    }

    public func canMergePodWithNext(id: String) -> Bool {
        guard let currentPod = pods.first(where: { $0.id == id && $0.isEnabled }) else { return false }
        let edgePods = pods.filter { $0.edge == currentPod.edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        guard let idx = edgePods.firstIndex(where: { $0.id == id }),
              idx < edgePods.count - 1 else { return false }
        let nextPod = edgePods[idx + 1]
        if let g1 = currentPod.majorGroupId, let g2 = nextPod.majorGroupId, g1 == g2 {
            return false
        }
        let currentGroupCount: Int = {
            guard let g1 = currentPod.majorGroupId else { return 1 }
            return edgePods.filter { $0.majorGroupId == g1 }.count
        }()
        let nextGroupCount: Int = {
            guard let g2 = nextPod.majorGroupId else { return 1 }
            return edgePods.filter { $0.majorGroupId == g2 }.count
        }()
        return (currentGroupCount + nextGroupCount) <= 32
    }

    public func mergePodWithNext(id: String) {
        guard canMergePodWithNext(id: id),
              let currentPod = pods.first(where: { $0.id == id && $0.isEnabled }) else { return }
        let edge = currentPod.edge
        let edgePods = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        guard let edgeIdx = edgePods.firstIndex(where: { $0.id == id }),
              edgeIdx < edgePods.count - 1 else { return }
        let nextPod = edgePods[edgeIdx + 1]

        let groupId = currentPod.majorGroupId ?? nextPod.majorGroupId ?? "major_\(edge.rawValue)_\(UUID().uuidString.prefix(4))"
        if let nextGroup = nextPod.majorGroupId, currentPod.majorGroupId != nil {
            for i in pods.indices where pods[i].edge == edge && pods[i].majorGroupId == nextGroup {
                pods[i].majorGroupId = groupId
            }
        }
        if let curIdx = pods.firstIndex(where: { $0.id == currentPod.id }) {
            pods[curIdx].majorGroupId = groupId
        }
        if let nxtIdx = pods.firstIndex(where: { $0.id == nextPod.id }) {
            pods[nxtIdx].majorGroupId = groupId
        }
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func splitPodFromMajorGroup(id: String) {
        guard let idx = pods.firstIndex(where: { $0.id == id }) else { return }
        let edge = pods[idx].edge
        let oldGroupId = pods[idx].majorGroupId
        pods[idx].majorGroupId = nil

        if let oldGroupId = oldGroupId {
            let remainingIndices = pods.indices.filter {
                pods[$0].edge == edge && pods[$0].isEnabled && pods[$0].majorGroupId == oldGroupId
            }
            if remainingIndices.count < 2 {
                for remIdx in remainingIndices {
                    pods[remIdx].majorGroupId = nil
                }
            }
        }
        userDefaults.set(true, forKey: "purah.didSeedMajorGroups.\(edge.rawValue)")
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func addPodToMajorGroup(podId: String, groupPodId: String) {
        addPodToMajorGroup(podId: podId, targetPodId: groupPodId)
    }

    public func addPodToMajorGroup(podId: String, targetPodId: String) {
        guard podId != targetPodId,
              let srcIdx = pods.firstIndex(where: { $0.id == podId && $0.isEnabled }),
              let dstIdx = pods.firstIndex(where: { $0.id == targetPodId && $0.isEnabled }) else { return }
        let edge = pods[dstIdx].edge
        guard pods[srcIdx].edge == edge else { return }

        let oldSrcGroup = pods[srcIdx].majorGroupId
        let targetGroupId = pods[dstIdx].majorGroupId ?? "major_\(edge.rawValue)_\(UUID().uuidString.prefix(4))"

        pods[dstIdx].majorGroupId = targetGroupId
        pods[srcIdx].majorGroupId = targetGroupId

        if let oldSrcGroup = oldSrcGroup, oldSrcGroup != targetGroupId {
            let remainingOldIndices = pods.indices.filter {
                pods[$0].edge == edge && pods[$0].isEnabled && pods[$0].majorGroupId == oldSrcGroup
            }
            if remainingOldIndices.count < 2 {
                for remIdx in remainingOldIndices {
                    pods[remIdx].majorGroupId = nil
                }
            }
        }

        // Reorder enabled pods on this edge so podId sits immediately adjacent to targetPodId's group
        var orderedIds = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
            .map(\.id)
        orderedIds.removeAll { $0 == podId }

        if let lastGroupMemberIdx = orderedIds.lastIndex(where: { memberId in
            guard let p = pods.first(where: { $0.id == memberId }) else { return false }
            return p.majorGroupId == targetGroupId
        }) {
            orderedIds.insert(podId, at: lastGroupMemberIdx + 1)
        } else {
            orderedIds.append(podId)
        }

        let gap = 0.015
        let totalGaps = Double(max(orderedIds.count - 1, 0)) * gap
        let usableSpan = max(0.94 - totalGaps, Double(orderedIds.count) * 0.05)
        let weights = orderedIds.map { id -> Double in
            guard let p = pods.first(where: { $0.id == id }) else { return 0.1 }
            return max(p.range.length, 0.05)
        }
        let weightSum = max(weights.reduce(0.0, +), 0.0001)
        let scale = weightSum > usableSpan ? (usableSpan / weightSum) : 1.0
        var curStart = 0.02
        for (offset, id) in orderedIds.enumerated() {
            if let pIdx = pods.firstIndex(where: { $0.id == id }) {
                let len = max(weights[offset] * scale, 0.04)
                pods[pIdx].range.start = curStart
                pods[pIdx].range.length = len
                curStart += len + gap
            }
        }

        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func unstackMajorGroup(groupId: String, on edge: MountEdge? = nil) {
        var matchedAny = false
        for i in pods.indices where pods[i].majorGroupId == groupId && (edge == nil || pods[i].edge == edge) {
            pods[i].majorGroupId = nil
            matchedAny = true
        }
        if !matchedAny, let edge = edge {
            for i in pods.indices where pods[i].edge == edge {
                pods[i].majorGroupId = nil
            }
        }
        if let edge = edge {
            userDefaults.set(true, forKey: "purah.didSeedMajorGroups.\(edge.rawValue)")
        } else {
            userDefaults.set(true, forKey: "purah.didSeedMajorGroups.left")
            userDefaults.set(true, forKey: "purah.didSeedMajorGroups.right")
        }
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func resizeMajorGroup(groupId: String, on edge: MountEdge? = nil, newTotalSpanRatio: Double) {
        let groupIndices = pods.indices.filter {
            pods[$0].isEnabled && pods[$0].majorGroupId == groupId && (edge == nil || pods[$0].edge == edge)
        }.sorted { pods[$0].range.start < pods[$1].range.start }
        guard !groupIndices.isEmpty else { return }

        let currentLengths = groupIndices.map { max(pods[$0].range.length, 0.02) }
        let currentTotalRatio = max(currentLengths.reduce(0.0, +), 0.04)
        let minClusterRatio = max(Double(groupIndices.count) * 0.035, 0.10)
        let firstStart = pods[groupIndices[0]].range.start
        let maxClusterRatio = max(0.96 - firstStart, minClusterRatio)
        let clampedTotalRatio = min(max(newTotalSpanRatio, minClusterRatio), maxClusterRatio)
        let scale = clampedTotalRatio / currentTotalRatio
        let subGap = 0.004

        var curStart = firstStart
        for idx in groupIndices {
            let newLen = max(pods[idx].range.length * scale, 0.035)
            pods[idx].range.start = curStart
            pods[idx].range.length = newLen
            pods[idx].minLength = min(pods[idx].minLength, 0.04)
            curStart += newLen + subGap
        }

        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func resizeMajorGroup(groupId: String, on edge: MountEdge, deltaRatio: Double) {
        let groupIndices = pods.indices.filter {
            pods[$0].isEnabled && pods[$0].edge == edge && pods[$0].majorGroupId == groupId
        }
        guard !groupIndices.isEmpty else { return }
        let currentTotalRatio = groupIndices.reduce(0.0) { $0 + max(pods[$1].range.length, 0.02) }
        resizeMajorGroup(groupId: groupId, on: edge, newTotalSpanRatio: currentTotalRatio + deltaRatio)
    }

    public func autoStackMajorPods(for edge: MountEdge) {
        for i in pods.indices where pods[i].edge == edge {
            pods[i].majorGroupId = nil
        }
        let enabledIndices = pods.indices.filter { pods[$0].edge == edge && pods[$0].isEnabled }
            .sorted { pods[$0].range.start < pods[$1].range.start }
        guard enabledIndices.count >= 2 else {
            invalidateLayoutCache()
            savePersistentState()
            onWindowsRebuildNeeded?()
            return
        }

        var groupCounter = 0
        var i = 0
        while i + 1 < enabledIndices.count {
            let gid = "major_\(edge.rawValue)_\(groupCounter)"
            if enabledIndices.count - i == 3 {
                pods[enabledIndices[i]].majorGroupId = gid
                pods[enabledIndices[i + 1]].majorGroupId = gid
                pods[enabledIndices[i + 2]].majorGroupId = gid
                i += 3
            } else {
                pods[enabledIndices[i]].majorGroupId = gid
                pods[enabledIndices[i + 1]].majorGroupId = gid
                i += 2
            }
            groupCounter += 1
        }
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func resetMajorGroups(for edge: MountEdge) {
        for i in pods.indices where pods[i].edge == edge {
            pods[i].majorGroupId = nil
        }
        userDefaults.set(true, forKey: "purah.didSeedMajorGroups.\(edge.rawValue)")
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func stackAllPodsIntoSingleMajorGroup(for edge: MountEdge) {
        let groupId = "major_\(edge.rawValue)_all"
        for i in pods.indices where pods[i].edge == edge {
            pods[i].majorGroupId = pods[i].isEnabled ? groupId : nil
        }
        userDefaults.set(true, forKey: "purah.didSeedMajorGroups.\(edge.rawValue)")
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func seedDefaultMajorGroupsIfNeeded(for edge: MountEdge) {
        let seedKey = "purah.didSeedMajorGroups.\(edge.rawValue)"
        guard !userDefaults.bool(forKey: seedKey) else { return }
        let enabledIndices = pods.indices.filter { pods[$0].edge == edge && pods[$0].isEnabled }
            .sorted { pods[$0].range.start < pods[$1].range.start }
        guard enabledIndices.count >= 2 else { return }
        let allNil = enabledIndices.allSatisfy { pods[$0].majorGroupId == nil }
        guard allNil else { return }

        var groupCounter = 0
        var i = 0
        while i + 1 < enabledIndices.count {
            let gid = "major_\(edge.rawValue)_\(groupCounter)"
            pods[enabledIndices[i]].majorGroupId = gid
            pods[enabledIndices[i + 1]].majorGroupId = gid
            groupCounter += 1
            i += 2
        }
    }

    public func majorPodClusters(for edge: MountEdge) -> [[SlotPod]] {
        let railPods = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        var clusters: [[SlotPod]] = []
        for pod in railPods {
            if let gid = pod.majorGroupId {
                if let last = clusters.last, last.first?.majorGroupId == gid {
                    clusters[clusters.count - 1].append(pod)
                } else {
                    clusters.append([pod])
                }
            } else {
                clusters.append([pod])
            }
        }
        return clusters
    }

    public func isInSharedMajorPod(podId: String) -> Bool {
        guard let pod = pods.first(where: { $0.id == podId && $0.isEnabled }) else { return false }
        guard overflowStrategy(for: pod.edge) == .decomposedMajorPod else { return false }
        if let gid = pod.majorGroupId {
            let peers = pods.filter { $0.edge == pod.edge && $0.isEnabled && $0.majorGroupId == gid }
            if peers.count >= 2 { return true }
        }
        return false
    }

    public func cycleRailPage(for edge: MountEdge, delta: Int = 1) {
        let refH = lastKnownTotalHeight[edge] ?? max(Double(availableScreenHeight(for: edge)), 600.0)
        let pages = paginatedPods(for: edge, totalHeight: refH)
        let count = max(pages.count, 1)
        guard count > 1 else {
            setRailPage(0, for: edge)
            return
        }
        let cur = currentRailPage(for: edge)
        let next = ((cur + delta) % count + count) % count
        setRailPage(next, for: edge)
    }

    @ObservationIgnored
    public var onRequestOpenPluginSettings: (@MainActor (String) -> Void)?

    public func openPluginSettings(id: String) {
        onRequestOpenPluginSettings?(id)
    }

    @ObservationIgnored
    private var capabilityProviders: [String: any PurahPodCapabilityProvider] = [:]

    @ObservationIgnored
    private var _marketManager: PluginMarketManager?

    public var marketManager: PluginMarketManager {
        if let existing = _marketManager {
            return existing
        }
        let manager = PluginMarketManager(store: self)
        _marketManager = manager
        return manager
    }

    public func setMarketManager(_ manager: PluginMarketManager) {
        self._marketManager = manager
    }

    public func registerCapabilityProvider(_ provider: any PurahPodCapabilityProvider) {
        capabilityProviders[provider.podId] = provider
    }

    public func unregisterCapabilityProvider(for podId: String) {
        capabilityProviders.removeValue(forKey: podId)
    }

    public func capabilityProvider(for podId: String) -> (any PurahPodCapabilityProvider)? {
        capabilityProviders[podId]
    }

    public func toggleFreezeRails() {
        isRailsFrozen.toggle()
    }

    public func togglePinItem(id: String) {
        if pinnedDrawerItemIds.contains(id) {
            pinnedDrawerItemIds.remove(id)
        } else {
            pinnedDrawerItemIds.insert(id)
        }
        invalidateLayoutCache()
    }

    public static var isTestingEnvironment: Bool {
        NSClassFromString("XCTest") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.arguments.contains(where: { $0.contains("swiftpm-testing-helper") || $0.contains("xctest") })
    }

    public func isItemPinned(id: String) -> Bool {
        pinnedDrawerItemIds.contains(id)
    }

    public func activateDrawer(podId: String, itemId: String? = nil) {
        let isAlreadyExpanded = (activeDrawerPodId != nil || activeDrawerItemId != nil)
        let targetEdge = pods.first(where: { $0.id == podId })?.edge ?? .right
        onRequestExpandCanvas?(targetEdge)

        let targetItemId = itemId ?? podId

        if !isAlreadyExpanded && !Self.isTestingEnvironment && overflowStrategy(for: targetEdge) == .dynamicAccordion {
            // Two-stage choreographed expansion:
            // Stage 1 (t = 0ms): Stretch rail bar in-place under cursor
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
                hoveredPodId = podId
                invalidateLayoutCache()
            }
            // Stage 2 (t = 80ms): Extrude drawer card from the stretched rail bar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self = self else { return }
                if self.hoveredPodId == podId {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
                        self.activeDrawerPodId = podId
                        self.activeDrawerItemId = targetItemId
                        self.invalidateLayoutCache()
                    }
                }
            }
        } else if isAlreadyExpanded || Self.isTestingEnvironment {
            // Already expanded or unit test runner: 0ms instant transition without frame-wait
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
                activeDrawerPodId = podId
                activeDrawerItemId = targetItemId
                hoveredPodId = podId
                invalidateLayoutCache()
            }
        } else {
            // Frame-pacing ready queue: expand canvas on frame 0, animate card on frame 1 (~16ms)
            // This prevents SwiftUI container width interpolation from dragging card from screen center!
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
                hoveredPodId = podId
                invalidateLayoutCache()
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.hoveredPodId == podId {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
                        self.activeDrawerPodId = podId
                        self.activeDrawerItemId = targetItemId
                        self.invalidateLayoutCache()
                    }
                }
            }
        }
    }

    public func dismissActiveDrawer() {
        activeDrawerPodId = nil
        activeDrawerItemId = nil
        hoveredPodId = nil
        invalidateLayoutCache()
    }

    public func hasPinnedItem(on edge: MountEdge) -> Bool {
        if isDrawerPinned { return true }
        for pod in pods where pod.edge == edge && pod.isEnabled {
            if isItemPinned(id: pod.id) { return true }
            if let provider = capabilityProvider(for: pod.id), provider.hasPinnedChild(store: self) {
                return true
            }
        }
        return false
    }

    public func pod(forItemId id: String) -> SlotPod? {
        if let p = pods.first(where: { $0.id == id }) {
            return p
        }
        for (podId, provider) in capabilityProviders {
            if provider.ownsSubItemId(id, store: self) {
                return pods.first(where: { $0.id == podId })
            }
        }
        return nil
    }

    public var activePod: SlotPod? {
        if let podId = activeDrawerPodId, let p = pods.first(where: { $0.id == podId }) {
            return p
        }
        if let itemId = activeDrawerItemId {
            return pod(forItemId: itemId)
        }
        return nil
    }

    // Multi-display behavior
    public var displayTargetMode: DisplayTargetMode = .followCursor

    // Edge Trigger Mode (Hover Dwell vs Push Force - Mutually Exclusive)
    public var edgeTriggerMode: EdgeTriggerMode = .hoverDwell

    // Dynamic Attention Alert Settings
    public var alertStyle: PluginAlertStyle = .breathingBeacon
    public var dismissAlertOnHover: Bool = true
    public var isEventToastAlertEnabled: Bool = true
    public var acknowledgedAlertIds: Set<String> = []
    public var notifiedToastEventIds: Set<String> = []

    // Sensory Feedback Settings
    public var isToastSoundEnabled: Bool = true
    public var toastNotificationSound: ToastNotificationSound = .glass
    public var isTrackpadHapticsEnabled: Bool = true
    public var isDrawerPopHapticEnabled: Bool = true
    public var isControlHapticEnabled: Bool = true

    @discardableResult
    public func triggerEdgePopHaptic(isInitialOpen: Bool = true, now: Date = Date()) -> Bool {
        SensoryFeedbackService.shared.performEdgePopHaptic(
            triggerMode: edgeTriggerMode,
            enabled: isTrackpadHapticsEnabled && isDrawerPopHapticEnabled,
            isInitialOpen: isInitialOpen,
            now: now
        )
    }

    @discardableResult
    public func triggerControlHaptic(_ type: PurahHapticType = .alignment) -> Bool {
        SensoryFeedbackService.shared.performActionHaptic(
            type,
            enabled: isTrackpadHapticsEnabled && isControlHapticEnabled
        )
    }

    @discardableResult
    public func triggerToastSound() -> Bool {
        SensoryFeedbackService.shared.playToastSound(
            toastNotificationSound,
            enabled: isToastSoundEnabled
        )
    }

    @discardableResult
    public func previewToastSound() -> Bool {
        _ = triggerControlHaptic(.alignment)
        return SensoryFeedbackService.shared.playToastSound(
            toastNotificationSound,
            enabled: true
        )
    }

    public func acknowledgeAlert(id: String) {
        acknowledgedAlertIds.insert(id)
    }

    public func isAlertAcknowledged(id: String) -> Bool {
        acknowledgedAlertIds.contains(id)
    }

    public func resetAlertAcknowledgment(id: String) {
        acknowledgedAlertIds.remove(id)
    }

    public func postToastNotification(id: String, message: String) {
        guard isEventToastAlertEnabled, !notifiedToastEventIds.contains(id) else { return }
        notifiedToastEventIds.insert(id)
        onCapacityWarningToast?(message)
    }

    // Edge Trigger Intentionality Sensitivity & Calibration
    public var edgeTriggerSensitivity: EdgeTriggerSensitivity = .balanced
    public var customInitialDwellMs: Double = 150.0
    public var customExitGraceMs: Double = 280.0
    public var customCatchCorridorPt: Double = 50.0
    public var customPushForceThreshold: Double = 380.0
    public var customPushResistanceBarrier: Double = 40.0

    public var activeInitialDwellSeconds: Double {
        edgeTriggerSensitivity == .custom ? (customInitialDwellMs / 1000.0) : edgeTriggerSensitivity.initialDwellSeconds
    }

    public var activeDeepEdgeDwellSeconds: Double {
        edgeTriggerSensitivity == .custom ? min(customInitialDwellMs / 2000.0, 0.12) : edgeTriggerSensitivity.deepEdgeDwellSeconds
    }

    public var activeExitGraceSeconds: Double {
        edgeTriggerSensitivity == .custom ? (customExitGraceMs / 1000.0) : edgeTriggerSensitivity.exitGraceDurationSeconds
    }

    public var activeCatchCorridor: Double {
        edgeTriggerSensitivity == .custom ? customCatchCorridorPt : edgeTriggerSensitivity.overshootCatchCorridor
    }

    public var activePushForceThreshold: Double {
        edgeTriggerSensitivity == .custom ? customPushForceThreshold : edgeTriggerSensitivity.pushForceThreshold
    }

    public var activePushResistanceBarrier: Double {
        edgeTriggerSensitivity == .custom ? customPushResistanceBarrier : edgeTriggerSensitivity.pushResistanceBarrier
    }

    public func applySensitivityPreset(_ preset: EdgeTriggerSensitivity) {
        edgeTriggerSensitivity = preset
        if preset != .custom {
            customInitialDwellMs = preset.initialDwellSeconds * 1000.0
            customExitGraceMs = preset.exitGraceDurationSeconds * 1000.0
            customCatchCorridorPt = preset.overshootCatchCorridor
            customPushForceThreshold = preset.pushForceThreshold
            customPushResistanceBarrier = preset.pushResistanceBarrier
        }
        savePersistentState()
    }

    // Internal revision tracker for observation propagation of decoupled plugin storage
    private var _pluginStorageRevision: Int = 0

    // Real-time synchronization flags and scopes
    public var isUsingRealCalendar: Bool = false
    public var isUsingRealReminders: Bool = false

    public var calendarScope: CalendarTimeScope {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "calendar", defaults: userDefaults)
            return storage.codable(forKey: "scope", as: CalendarTimeScope.self) ?? .today
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "calendar", defaults: userDefaults)
            storage.setCodable(newValue, forKey: "scope")
        }
    }

    public var remindersScope: RemindersScope {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "todo", defaults: userDefaults)
            return storage.codable(forKey: "scope", as: RemindersScope.self) ?? .allIncomplete
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "todo", defaults: userDefaults)
            storage.setCodable(newValue, forKey: "scope")
        }
    }

    public var calendarMaxRailEvents: Int {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "calendar", defaults: userDefaults)
            let val = storage.int(forKey: "maxRailEvents")
            return val > 0 ? val : 4
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "calendar", defaults: userDefaults)
            storage.set(max(newValue, 1), forKey: "maxRailEvents")
        }
    }

    public var todoMaxRailTasks: Int {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "todo", defaults: userDefaults)
            let val = storage.int(forKey: "maxRailTodos")
            return val > 0 ? val : 6
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "todo", defaults: userDefaults)
            storage.set(max(newValue, 1), forKey: "maxRailTodos")
        }
    }

    public var clipboardMaxRailItems: Int {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "clipboard", defaults: userDefaults)
            let val = storage.int(forKey: "maxRailItems")
            return val > 0 ? val : 4
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "clipboard", defaults: userDefaults)
            storage.set(max(newValue, 1), forKey: "maxRailItems")
        }
    }

    public var isMusicWaveformAnimationEnabled: Bool {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "music", defaults: userDefaults)
            if let codableVal = storage.codable(forKey: "isWaveformAnimationEnabled", as: Bool.self) {
                return codableVal
            }
            if storage.string(forKey: "isWaveformAnimationEnabled") != nil {
                return storage.bool(forKey: "isWaveformAnimationEnabled")
            }
            return true
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "music", defaults: userDefaults)
            storage.setCodable(newValue, forKey: "isWaveformAnimationEnabled")
        }
    }

    public var isEventGlowAlertEnabled: Bool {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "calendar", defaults: userDefaults)
            return storage.codable(forKey: "isEventGlowAlertEnabled", as: Bool.self) ?? true
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "calendar", defaults: userDefaults)
            storage.setCodable(newValue, forKey: "isEventGlowAlertEnabled")
        }
    }

    public var calendarOverflowStrategy: CalendarOverflowStrategy {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "calendar", defaults: userDefaults)
            return storage.codable(forKey: "overflowStrategy", as: CalendarOverflowStrategy.self) ?? .smartFold
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "calendar", defaults: userDefaults)
            storage.setCodable(newValue, forKey: "overflowStrategy")
        }
    }

    // User-configurable rail width (4px ~ 16px) and drawer extrusion settings
    public var railBarWidth: Double = 8.0
    public var drawerWidthMode: DrawerWidthMode = .fixed
    public var fixedDrawerWidth: Double = 290.0 // Bounds: 220px ~ 330px
    public var customPodColors: [String: String] = [:]

    public func effectiveDrawerWidth(for text: String = "", baseWidth: Double = 290.0, podId: String = "") -> CGFloat {
        let resolvedPodId: String = {
            if !podId.isEmpty { return podId }
            let lower = text.lowercased()
            if let matched = pods.first(where: { lower.contains($0.id.lowercased()) || lower.contains($0.name.lowercased()) }) {
                return matched.id
            }
            return ""
        }()

        // 1. Autonomous Plugin Adaptive Width Resolution (Open-Closed Principle)
        if !resolvedPodId.isEmpty,
           let provider = capabilityProvider(for: resolvedPodId),
           let pluginAdaptiveWidth = provider.adaptiveDrawerWidth(store: self) {
            switch drawerWidthMode {
            case .fixed:
                return CGFloat(max(fixedDrawerWidth, Double(pluginAdaptiveWidth)))
            case .adaptive:
                return pluginAdaptiveWidth
            }
        }

        // 2. Base Fallback Estimation (Text length and baseline fallback)
        switch drawerWidthMode {
        case .fixed:
            return CGFloat(min(max(fixedDrawerWidth, 220.0), 330.0))
        case .adaptive:
            let charCount = text.count
            let textBonus = Double(charCount) * 5.0
            let extraOffset = max(baseWidth - 280.0, 0.0)
            let calculated = 230.0 + textBonus + extraOffset
            let clamped = min(max(calculated, 230.0 + extraOffset), 330.0)
            return CGFloat(clamped)
        }
    }

    public func minimumDrawerHeight(for podId: String) -> CGFloat {
        if let provider = capabilityProvider(for: podId) {
            return provider.minimumDrawerHeight(store: self)
        }
        return 120.0
    }

    public func preferredDrawerHeight(for podId: String) -> CGFloat {
        let minH = minimumDrawerHeight(for: podId)
        if let pod = pods.first(where: { $0.id == podId }),
           let customPref = pod.preferredExpandedHeight,
           customPref >= Double(minH) {
            return CGFloat(customPref)
        }
        switch podId {
        case "notes":
            return 280.0
        case "terminal":
            return 280.0
        case "clipboard":
            return 280.0
        case "calendar":
            return max(minH, 260.0)
        case "todo":
            return max(minH, 250.0)
        case "vitals":
            return max(minH, 260.0)
        case "scripts":
            return max(minH, 240.0)
        case "shelf":
            return 250.0
        case "music":
            return 220.0
        default:
            return max(minH * 1.5, 240.0)
        }
    }

    // MARK: - Rail Capacity & Ergonomic Height Budget
    public func totalRequiredHeight(for edge: MountEdge) -> CGFloat {
        let edgePods = pods.filter { $0.edge == edge && $0.isEnabled }
        guard !edgePods.isEmpty else { return 0 }
        let gap: CGFloat = 10.0
        var total: CGFloat = CGFloat(edgePods.count - 1) * gap
        for pod in edgePods {
            total += minimumDrawerHeight(for: pod.id)
        }
        return total
    }

    public func availableScreenHeight(for edge: MountEdge) -> CGFloat {
        let screens = NSScreen.screens
        let mainScreen = NSScreen.main ?? screens.first
        guard let screen = mainScreen else { return 980.0 }
        return max(screen.visibleFrame.height - 30.0, 400.0)
    }

    public func capacityRatio(for edge: MountEdge) -> Double {
        let avail = availableScreenHeight(for: edge)
        guard avail > 0 else { return 0.0 }
        let required = totalRequiredHeight(for: edge)
        return Double(required / avail)
    }

    public func isRailOverloaded(edge: MountEdge) -> Bool {
        guard overflowStrategy(for: edge) == .strictCeiling else { return false }
        return capacityRatio(for: edge) > 1.0
    }

    public var onCapacityWarningToast: ((String) -> Void)?
    public var onLocalMouseMove: (@MainActor (NSEvent) -> Void)?
    public var onPodEnabledChanged: (@MainActor (String, Bool) -> Void)?
    public var onWindowsRebuildNeeded: (@MainActor () -> Void)?
    public var onRequestExpandCanvas: (@MainActor (MountEdge) -> Void)?
    private var lastCapacityAlertTime: Date?

    public func notifyCapacityWarningIfNeeded() {
        let now = Date()
        if let last = lastCapacityAlertTime, now.timeIntervalSince(last) < 6.0 {
            return
        }
        if isRailOverloaded(edge: .left) {
            lastCapacityAlertTime = now
            let req = Int(totalRequiredHeight(for: .left))
            let avail = Int(availableScreenHeight(for: .left))
            onCapacityWarningToast?("⚠️ Left rail capacity overload (\(req)pt / \(avail)pt available). Consider moving pods to the right rail.")
        } else if isRailOverloaded(edge: .right) {
            lastCapacityAlertTime = now
            let req = Int(totalRequiredHeight(for: .right))
            let avail = Int(availableScreenHeight(for: .right))
            onCapacityWarningToast?("⚠️ Right rail capacity overload (\(req)pt / \(avail)pt available). Consider moving pods to the left rail.")
        }
    }

    public func hasPinnedChild(for podId: String) -> Bool {
        capabilityProvider(for: podId)?.hasPinnedChild(store: self) ?? false
    }

    public func hasActiveOrPinnedChild(for podId: String) -> Bool {
        if let provider = capabilityProvider(for: podId) {
            return provider.hasPinnedChild(store: self) || (activeDrawerPodId == podId)
        }
        return false
    }

    public func isPodDecomposed(_ id: String) -> Bool {
        capabilityProvider(for: id)?.isDecomposed(store: self) ?? false
    }

    public func maxVisualHeight(for podId: String, totalHeight: Double) -> Double {
        if isPodDecomposed(podId), let provider = capabilityProvider(for: podId) {
            let policy = provider.decomposedPolicy(store: self)
            let rawCount = max(provider.subItemCount(store: self), 1)
            let count = min(rawCount, max(policy.maxRailItems, 1))
            let maxVisual = Double(CGFloat(count) * policy.maxChipHeight + CGFloat(max(count - 1, 0)) * policy.spacing)
            return max(maxVisual, 36.0)
        }
        return totalHeight
    }

    public func effectivePodSpan(for pod: SlotPod, totalHeight: CGFloat) -> CGFloat {
        let podHeight = max(pod.range.length * totalHeight, 48.0)
        if isLiveRailEditingMode || pod.minLength <= 0.06 {
            return podHeight
        }
        let minReserved = minimumDrawerHeight(for: pod.id)
        return max(podHeight, minReserved)
    }

    public func isPodExpanded(_ pod: SlotPod) -> Bool {
        if hoveredPodId == pod.id || activeDrawerPodId == pod.id || activeDrawerItemId == pod.id || isItemPinned(id: pod.id) {
            return true
        }
        if hasPinnedChild(for: pod.id) {
            return true
        }
        if let itemId = activeDrawerItemId, self.pod(forItemId: itemId)?.id == pod.id {
            return true
        }
        return false
    }

    public func shouldRenderDrawer(for item: ResolvedPodLayoutItem, in allItems: [ResolvedPodLayoutItem]) -> Bool {
        let podId = item.pod.id
        let isHoveredActive = (activeDrawerPodId == podId || activeDrawerItemId == podId || activePod?.id == podId)
        let isPinned = isItemPinned(id: podId) || hasPinnedChild(for: podId)

        guard isHoveredActive || isPinned else { return false }

        if overflowStrategy(for: item.pod.edge) == .decomposedMajorPod, let groupId = item.majorGroupId {
            let groupPeers = allItems.filter { $0.majorGroupId == groupId }
            if groupPeers.count > 1 {
                if let hoveredPeer = groupPeers.first(where: { peer in
                    let pid = peer.pod.id
                    return activeDrawerPodId == pid || activeDrawerItemId == pid || activePod?.id == pid
                }) {
                    return hoveredPeer.pod.id == podId
                }
                if let pinnedPeer = groupPeers.first(where: { peer in
                    let pid = peer.pod.id
                    return isItemPinned(id: pid) || hasPinnedChild(for: pid)
                }) {
                    return pinnedPeer.pod.id == podId
                }
            }
        }

        return isHoveredActive || isPinned
    }

    public func paginatedPods(for edge: MountEdge, totalHeight: Double) -> [[SlotPod]] {
        lastKnownTotalHeight[edge] = totalHeight
        let allEdgePods = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        guard !allEdgePods.isEmpty else { return [] }

        let hasExplicitPages = allEdgePods.contains { $0.pageIndex > 0 }
        if hasExplicitPages {
            let grouped = Dictionary(grouping: allEdgePods, by: { max(0, $0.pageIndex) })
            let sortedPageKeys = grouped.keys.sorted()
            return sortedPageKeys.compactMap { key in
                let pagePods = (grouped[key] ?? []).sorted { $0.range.start < $1.range.start }
                return pagePods.isEmpty ? nil : pagePods
            }
        }

        let pageBudget = max(totalHeight - 96.0, 260.0)
        var pages: [[SlotPod]] = []
        var currentPage: [SlotPod] = []
        var currentHeight: Double = 0.0

        for pod in allEdgePods {
            let minH = Double(minimumDrawerHeight(for: pod.id))
            let podNeeded = minH + 12.0
            if !currentPage.isEmpty && (currentHeight + podNeeded) > pageBudget {
                pages.append(currentPage)
                currentPage = [pod]
                currentHeight = podNeeded
            } else {
                currentPage.append(pod)
                currentHeight += podNeeded
            }
        }
        if !currentPage.isEmpty {
            pages.append(currentPage)
        }
        return pages
    }

    private struct LayoutCacheEntry {
        let height: Double
        let podsCount: Int
        let enabledSignature: String
        let strategy: RailOverflowStrategy
        let hoveredPodId: String?
        let activePodId: String?
        let activeItemId: String?
        let pinnedIds: Set<String>
        let page: Int
        let items: [ResolvedPodLayoutItem]
        let timestamp: Double
    }

    @ObservationIgnored
    private var cachedResolvedLayouts: [MountEdge: LayoutCacheEntry] = [:]

    public func invalidateLayoutCache() {
        cachedResolvedLayouts.removeAll()
    }

    public func resolvedPhysicalLayout(for edge: MountEdge, totalHeight: Double) -> [ResolvedPodLayoutItem] {
        lastKnownTotalHeight[edge] = totalHeight
        let now = Date().timeIntervalSinceReferenceDate
        let allEdgePods = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        guard !allEdgePods.isEmpty else { return [] }

        let signature = allEdgePods.map {
            "\($0.id):\($0.range.start):\($0.range.length):\($0.pageIndex):\($0.majorGroupId ?? ""):\($0.preferredExpandedHeight ?? 0)"
        }.joined(separator: "|")
        let curPage = currentRailPage(for: edge)
        let edgeStrategy = overflowStrategy(for: edge)

        if let cached = cachedResolvedLayouts[edge],
           abs(cached.height - totalHeight) < 0.5,
           cached.podsCount == allEdgePods.count,
           cached.enabledSignature == signature,
           cached.strategy == edgeStrategy,
           cached.hoveredPodId == hoveredPodId,
           cached.activePodId == activeDrawerPodId,
           cached.activeItemId == activeDrawerItemId,
           cached.pinnedIds == pinnedDrawerItemIds,
           cached.page == curPage,
           (now - cached.timestamp) < 0.05 {
            return cached.items
        }

        let items: [ResolvedPodLayoutItem]
        switch edgeStrategy {
        case .dynamicAccordion:
            items = solveDynamicAccordionLayout(edgePods: allEdgePods, edge: edge, totalHeight: totalHeight)
        case .decomposedMajorPod:
            items = solveDecomposedMajorPodLayout(edgePods: allEdgePods, edge: edge, totalHeight: totalHeight)
        case .pagedSpaces:
            items = solvePagedSpacesLayout(edge: edge, totalHeight: totalHeight)
        case .strictCeiling:
            items = ErgonomicAutoLayoutEngine.resolvePhysicalRailLayout(
                pods: pods,
                on: edge,
                totalHeight: totalHeight,
                gap: 8.0,
                safeTop: 16.0,
                safeBottom: totalHeight - 16.0
            ) { [weak self] pod in
                guard let self = self else { return max(pod.range.length * totalHeight, 36.0) }
                return Double(self.effectivePodSpan(for: pod, totalHeight: CGFloat(totalHeight)))
            }
        }

        cachedResolvedLayouts[edge] = LayoutCacheEntry(
            height: totalHeight,
            podsCount: allEdgePods.count,
            enabledSignature: signature,
            strategy: edgeStrategy,
            hoveredPodId: hoveredPodId,
            activePodId: activeDrawerPodId,
            activeItemId: activeDrawerItemId,
            pinnedIds: pinnedDrawerItemIds,
            page: curPage,
            items: items,
            timestamp: now
        )
        return items
    }

    private func solveDynamicAccordionLayout(edgePods: [SlotPod], edge: MountEdge, totalHeight: Double) -> [ResolvedPodLayoutItem] {
        let safeTop = 16.0
        let safeBottom = totalHeight - 16.0
        let availableH = max(safeBottom - safeTop, 120.0)
        let gap = 8.0
        let totalGaps = Double(max(edgePods.count - 1, 0)) * gap

        // High-density accordion solver: compute idleSpans directly from user-configured pod.range.length without forced fillScale inflation
        let netAvailable = max(availableH - totalGaps, Double(edgePods.count) * 20.0)
        let minIdleBaseBarH = min(28.0, netAvailable / Double(edgePods.count))
        let weights = edgePods.map { pod in
            max(pod.range.length, 0.035)
        }
        let maxVisuals = edgePods.map { maxVisualHeight(for: $0.id, totalHeight: totalHeight) }
        var idleSpans = edgePods.enumerated().map { idx, pod in
            min(max(pod.range.length * totalHeight, minIdleBaseBarH), maxVisuals[idx])
        }
        let sumIdleSpans = idleSpans.reduce(0.0, +)
        if sumIdleSpans > netAvailable && sumIdleSpans > 0 {
            let avgSlotH = netAvailable / Double(max(edgePods.count, 1))
            let lockedMask = edgePods.indices.map { i in
                edgePods[i].minLength <= 0.06 && idleSpans[i] <= avgSlotH
            }
            let lockedSum = edgePods.indices.reduce(0.0) { acc, i in
                acc + (lockedMask[i] ? idleSpans[i] : 0.0)
            }
            let scalableSum = sumIdleSpans - lockedSum
            let remainingAvailable = max(netAvailable - lockedSum, 20.0)
            if scalableSum > remainingAvailable && scalableSum > 0 {
                let scale = remainingAvailable / scalableSum
                idleSpans = idleSpans.enumerated().map { i, val in
                    lockedMask[i] ? val : max(val * scale, 20.0)
                }
            } else {
                let scale = netAvailable / sumIdleSpans
                idleSpans = idleSpans.map { $0 * scale }
            }
        }

        let fullSpans: [Double] = edgePods.enumerated().map { idx, pod in
            let pref = Double(preferredDrawerHeight(for: pod.id))
            let cappedPref = min(pref, maxVisuals[idx])
            return max(idleSpans[idx], cappedPref)
        }

        var idleStartYs: [Double] = []
        var curIdleY = safeTop
        for span in idleSpans {
            idleStartYs.append(curIdleY)
            curIdleY += span + gap
        }

        let expandedFlags = edgePods.map { isPodExpanded($0) }
        let expandedCount = expandedFlags.filter { $0 }.count
        let idleCount = edgePods.count - expandedCount

        if expandedCount == 0 {
            return (0..<edgePods.count).map { idx in
                ResolvedPodLayoutItem(pod: edgePods[idx], startY: idleStartYs[idx], spanH: idleSpans[idx])
            }
        }

        var spans = Array(repeating: 0.0, count: edgePods.count)
        let minIdleBarH = min(26.0, (netAvailable * 0.45) / Double(max(idleCount, 1)))
        let idleReserved = Double(idleCount) * minIdleBarH
        let expandedBudget = max(netAvailable - idleReserved, 160.0)

        let requestedExpanded: [Double] = edgePods.enumerated().map { idx, _ in
            expandedFlags[idx] ? fullSpans[idx] : 0.0
        }
        let totalRequestedExpanded = requestedExpanded.reduce(0.0, +)

        let primaryHoveredId = hoveredPodId ?? activeDrawerPodId ?? activePod?.id
        let anchorIdx = edgePods.indices.first(where: { edgePods[$0].id == primaryHoveredId && expandedFlags[$0] })
            ?? expandedFlags.firstIndex(of: true)

        if expandedCount == 1, let anchorIdx = anchorIdx {
            let aboveCount = anchorIdx
            let belowCount = edgePods.count - 1 - anchorIdx
            let minAboveSpace = Double(aboveCount) * (18.0 + gap)
            let minBelowSpace = Double(belowCount) * (18.0 + gap)
            let maxSingleSpan = max(availableH - minAboveSpace - minBelowSpace, 160.0)
            let anchorSpan = min(fullSpans[anchorIdx], maxSingleSpan)
            spans[anchorIdx] = anchorSpan

            let idleTop = idleStartYs[anchorIdx]
            let idleBottom = idleTop + idleSpans[anchorIdx]
            let idleCenter = (idleTop + idleBottom) * 0.5

            var idealAnchorStart = idleCenter - (anchorSpan * 0.5)
            // Ensure the expanded bar covers the entire idle bar [idleTop, idleBottom] so the cursor never falls outside!
            if idealAnchorStart > idleTop { idealAnchorStart = idleTop }
            if idealAnchorStart + anchorSpan < idleBottom { idealAnchorStart = idleBottom - anchorSpan }
            let minAllowedAnchorStart = safeTop + minAboveSpace
            let maxAllowedAnchorStart = max(minAllowedAnchorStart, safeBottom - anchorSpan - minBelowSpace)
            let anchorStartY = min(max(idealAnchorStart, minAllowedAnchorStart), maxAllowedAnchorStart)

            var startYs = Array(repeating: 0.0, count: edgePods.count)
            startYs[anchorIdx] = anchorStartY

            if aboveCount > 0 {
                let aboveGaps = Double(max(aboveCount - 1, 0)) * gap
                let aboveNetSpace = max(anchorStartY - gap - safeTop - aboveGaps, Double(aboveCount) * 18.0)
                let aboveWeightSum = max((0..<aboveCount).reduce(0.0) { $0 + weights[$1] }, 0.0001)
                var aboveSpans = (0..<aboveCount).map { i in
                    min(max(aboveNetSpace * (weights[i] / aboveWeightSum), 18.0), maxVisuals[i])
                }
                let aboveSum = aboveSpans.reduce(0.0, +)
                if aboveSum > aboveNetSpace && aboveSum > 0 {
                    let scale = aboveNetSpace / aboveSum
                    aboveSpans = aboveSpans.map { $0 * scale }
                } else if aboveSum < aboveNetSpace {
                    let leftover = aboveNetSpace - aboveSum
                    let uncapped = (0..<aboveCount).filter { aboveSpans[$0] < maxVisuals[$0] - 0.5 }
                    if !uncapped.isEmpty {
                        let uncappedWeight = max(uncapped.reduce(0.0) { $0 + weights[$1] }, 0.0001)
                        for i in uncapped {
                            aboveSpans[i] = min(aboveSpans[i] + leftover * (weights[i] / uncappedWeight), maxVisuals[i])
                        }
                    }
                    let finalAboveSum = aboveSpans.reduce(0.0, +)
                    if finalAboveSum < aboveNetSpace && aboveCount > 0 {
                        let extraEach = (aboveNetSpace - finalAboveSum) / Double(aboveCount)
                        for i in 0..<aboveCount {
                            aboveSpans[i] += extraEach
                        }
                    }
                }
                var curY = safeTop
                for i in 0..<aboveCount {
                    spans[i] = aboveSpans[i]
                    startYs[i] = curY
                    curY += aboveSpans[i] + gap
                }
            }

            if belowCount > 0 {
                let belowStart = anchorStartY + anchorSpan + gap
                let belowGaps = Double(max(belowCount - 1, 0)) * gap
                let belowNetSpace = max(safeBottom - belowStart - belowGaps, Double(belowCount) * 18.0)
                let belowIndices = Array((anchorIdx + 1)..<edgePods.count)
                let belowWeightSum = max(belowIndices.reduce(0.0) { $0 + weights[$1] }, 0.0001)
                var belowSpans = belowIndices.map { i in
                    min(max(belowNetSpace * (weights[i] / belowWeightSum), 18.0), maxVisuals[i])
                }
                let belowSum = belowSpans.reduce(0.0, +)
                if belowSum > belowNetSpace && belowSum > 0 {
                    let scale = belowNetSpace / belowSum
                    belowSpans = belowSpans.map { $0 * scale }
                } else if belowSum < belowNetSpace {
                    let leftover = belowNetSpace - belowSum
                    let uncappedOffsets = belowIndices.indices.filter { belowSpans[$0] < maxVisuals[belowIndices[$0]] - 0.5 }
                    if !uncappedOffsets.isEmpty {
                        let uncappedWeight = max(uncappedOffsets.reduce(0.0) { $0 + weights[belowIndices[$1]] }, 0.0001)
                        for offset in uncappedOffsets {
                            let podIdx = belowIndices[offset]
                            belowSpans[offset] = min(
                                belowSpans[offset] + leftover * (weights[podIdx] / uncappedWeight),
                                maxVisuals[podIdx]
                            )
                        }
                    }
                    let finalBelowSum = belowSpans.reduce(0.0, +)
                    if finalBelowSum < belowNetSpace && belowCount > 0 {
                        let extraEach = (belowNetSpace - finalBelowSum) / Double(belowCount)
                        for offset in 0..<belowCount {
                            belowSpans[offset] += extraEach
                        }
                    }
                }
                var curY = belowStart
                for (offset, podIdx) in belowIndices.enumerated() {
                    spans[podIdx] = belowSpans[offset]
                    startYs[podIdx] = curY
                    curY += belowSpans[offset] + gap
                }
            }

            return (0..<edgePods.count).map { idx in
                ResolvedPodLayoutItem(pod: edgePods[idx], startY: startYs[idx], spanH: spans[idx])
            }
        }

        // Multi-pod expansion (e.g. 1 Pinned pod + 1 Hovered pod)
        if totalRequestedExpanded <= expandedBudget {
            for idx in edgePods.indices where expandedFlags[idx] {
                spans[idx] = requestedExpanded[idx]
            }
        } else {
            var remainingExpandedBudget = expandedBudget
            var pinnedExpandedIndices: [Int] = []

            for idx in edgePods.indices where expandedFlags[idx] {
                if idx == anchorIdx {
                    let minH = Double(max(minimumDrawerHeight(for: edgePods[idx].id), 120.0))
                    let granted = min(max(fullSpans[idx], minH), expandedBudget * 0.55)
                    spans[idx] = max(granted, 110.0)
                    remainingExpandedBudget = max(expandedBudget - spans[idx], 90.0)
                } else {
                    pinnedExpandedIndices.append(idx)
                }
            }

            if !pinnedExpandedIndices.isEmpty {
                let share = remainingExpandedBudget / Double(pinnedExpandedIndices.count)
                for idx in pinnedExpandedIndices {
                    spans[idx] = max(share, 110.0)
                }
            }
        }

        for idx in edgePods.indices where !expandedFlags[idx] {
            spans[idx] = 18.0
        }

        let minSumSpans = spans.reduce(0.0, +)
        if minSumSpans > netAvailable && minSumSpans > 0 {
            let scale = netAvailable / minSumSpans
            spans = spans.map { $0 * scale }
        } else if idleCount > 0 {
            let totalSlack = max(netAvailable - minSumSpans, 0.0)
            if let anchorIdx = anchorIdx {
                let aboveIdleIndices = (0..<anchorIdx).filter { !expandedFlags[$0] }
                let belowIdleIndices = ((anchorIdx + 1)..<edgePods.count).filter { !expandedFlags[$0] }

                if !aboveIdleIndices.isEmpty && !belowIdleIndices.isEmpty {
                    let minAnchorY = safeTop + (0..<anchorIdx).reduce(0.0) { $0 + spans[$1] + gap }
                    let anchorSpan = spans[anchorIdx]
                    let idleTop = idleStartYs[anchorIdx]
                    let idleBottom = idleTop + idleSpans[anchorIdx]
                    let idleCenter = (idleTop + idleBottom) * 0.5
                    var idealAnchorStart = idleCenter - (anchorSpan * 0.5)
                    if idealAnchorStart > idleTop { idealAnchorStart = idleTop }
                    if idealAnchorStart + anchorSpan < idleBottom { idealAnchorStart = idleBottom - anchorSpan }

                    let slackBefore = min(max(idealAnchorStart - minAnchorY, 0.0), totalSlack)
                    let slackAfter = max(totalSlack - slackBefore, 0.0)

                    let aboveWeightSum = max(aboveIdleIndices.reduce(0.0) { $0 + weights[$1] }, 0.0001)
                    for idx in aboveIdleIndices {
                        let w = weights[idx]
                        spans[idx] = spans[idx] + slackBefore * (w / aboveWeightSum)
                    }

                    let belowWeightSum = max(belowIdleIndices.reduce(0.0) { $0 + weights[$1] }, 0.0001)
                    for idx in belowIdleIndices {
                        let w = weights[idx]
                        spans[idx] = spans[idx] + slackAfter * (w / belowWeightSum)
                    }
                } else {
                    let idleIndices = edgePods.indices.filter { !expandedFlags[$0] }
                    let idleWeightSum = max(idleIndices.reduce(0.0) { $0 + weights[$1] }, 0.0001)
                    for idx in idleIndices {
                        let w = weights[idx]
                        spans[idx] = spans[idx] + totalSlack * (w / idleWeightSum)
                    }
                }
            } else {
                let idleIndices = edgePods.indices.filter { !expandedFlags[$0] }
                let idleWeightSum = max(idleIndices.reduce(0.0) { $0 + weights[$1] }, 0.0001)
                for idx in idleIndices {
                    let w = weights[idx]
                    spans[idx] = spans[idx] + totalSlack * (w / idleWeightSum)
                }
            }
        }

        var currentY = safeTop
        var result: [ResolvedPodLayoutItem] = []
        for (idx, pod) in edgePods.enumerated() {
            let span = spans[idx]
            result.append(ResolvedPodLayoutItem(pod: pod, startY: currentY, spanH: span))
            currentY += span + gap
        }
        return result
    }

    private func solveDecomposedMajorPodLayout(edgePods: [SlotPod], edge: MountEdge, totalHeight: Double) -> [ResolvedPodLayoutItem] {
        let safeTop = 16.0
        let safeBottom = totalHeight - 16.0
        let availableH = max(safeBottom - safeTop, 180.0)

        var clusters: [[SlotPod]] = []
        for pod in edgePods {
            if let gid = pod.majorGroupId {
                if let lastCluster = clusters.last, lastCluster.first?.majorGroupId == gid {
                    clusters[clusters.count - 1].append(pod)
                } else {
                    clusters.append([pod])
                }
            } else {
                clusters.append([pod])
            }
        }

        let majorGap = 10.0
        let totalMajorGaps = Double(max(clusters.count - 1, 0)) * majorGap
        let netMajorAvailable = max(availableH - totalMajorGaps, 150.0)

        var majorSpans: [Double] = clusters.map { grp in
            if grp.count == 1 {
                let pod = grp[0]
                let minFloor = (isLiveRailEditingMode || pod.minLength <= 0.06)
                    ? 48.0
                    : Double(minimumDrawerHeight(for: pod.id))
                return max(pod.range.length * totalHeight, minFloor)
            } else {
                let subGap = 3.0
                let totalSubGaps = Double(max(grp.count - 1, 0)) * subGap
                let sumSubLengths = grp.reduce(0.0) { $0 + max($1.range.length * totalHeight, 22.0) } + totalSubGaps
                let hasManualResize = isLiveRailEditingMode || grp.contains(where: { $0.minLength <= 0.06 })
                let clusterMinFloor = hasManualResize ? max(96.0, Double(grp.count) * 24.0) : 155.0
                return max(sumSubLengths, clusterMinFloor)
            }
        }
        let sumMajorSpans = majorSpans.reduce(0.0, +)
        if sumMajorSpans > netMajorAvailable && sumMajorSpans > 0 {
            let lockedClusterMask = clusters.indices.map { idx in
                clusters[idx].count == 1 && clusters[idx][0].minLength <= 0.06 && majorSpans[idx] <= 100.0
            }
            let lockedSum = clusters.indices.reduce(0.0) { acc, idx in
                acc + (lockedClusterMask[idx] ? majorSpans[idx] : 0.0)
            }
            let scalableSum = sumMajorSpans - lockedSum
            let remainingMajorAvailable = max(netMajorAvailable - lockedSum, 120.0)
            if scalableSum > remainingMajorAvailable && scalableSum > 0 {
                let scale = remainingMajorAvailable / scalableSum
                majorSpans = clusters.enumerated().map { idx, grp in
                    if lockedClusterMask[idx] { return majorSpans[idx] }
                    let floorH = grp.count >= 2 ? 150.0 : 48.0
                    return max(majorSpans[idx] * scale, floorH)
                }
            } else {
                let scale = netMajorAvailable / sumMajorSpans
                majorSpans = clusters.enumerated().map { idx, grp in
                    let floorH = grp.count >= 2 ? 150.0 : 48.0
                    return max(majorSpans[idx] * scale, floorH)
                }
            }
        }

        var result: [ResolvedPodLayoutItem] = []
        var currentMajorY = safeTop

        for (cIdx, cluster) in clusters.enumerated() {
            let majorSpanH = majorSpans[cIdx]
            if cluster.count == 1 {
                let pod = cluster[0]
                result.append(
                    ResolvedPodLayoutItem(
                        pod: pod,
                        startY: currentMajorY,
                        spanH: majorSpanH,
                        drawerStartY: currentMajorY,
                        drawerSpanH: majorSpanH,
                        majorGroupId: nil
                    )
                )
            } else {
                let gid = cluster.first?.majorGroupId ?? "major_\(edge.rawValue)_\(cIdx)"
                let m = cluster.count
                let subGap = 3.0
                let totalSubGaps = Double(max(m - 1, 0)) * subGap
                let availableSubSpan = max(majorSpanH - totalSubGaps, Double(m) * 18.0)
                let desiredSubSpans = cluster.map { max($0.range.length * totalHeight, 18.0) }
                let lockedSubMask = cluster.indices.map { i in
                    cluster[i].minLength <= 0.06 && desiredSubSpans[i] <= min(100.0, availableSubSpan - Double(m - 1) * 20.0)
                }
                let lockedSubSum = cluster.indices.reduce(0.0) { acc, i in
                    acc + (lockedSubMask[i] ? desiredSubSpans[i] : 0.0)
                }
                let unlockedIndices = cluster.indices.filter { !lockedSubMask[$0] }
                let unlockedDesiredSum = max(unlockedIndices.reduce(0.0) { $0 + desiredSubSpans[$1] }, 1.0)
                let unlockedAvailable = max(availableSubSpan - lockedSubSum, Double(unlockedIndices.count) * 18.0)

                var subSpans: [Double] = cluster.indices.map { i in
                    if lockedSubMask[i] {
                        return desiredSubSpans[i]
                    }
                    return max(unlockedAvailable * (desiredSubSpans[i] / unlockedDesiredSum), 18.0)
                }
                let subSum = subSpans.reduce(0.0, +)
                if subSum > availableSubSpan && subSum > 0 {
                    let s = availableSubSpan / subSum
                    subSpans = subSpans.map { max($0 * s, 18.0) }
                }

                var curSubY = currentMajorY
                for (subIdx, pod) in cluster.enumerated() {
                    let subSpanH = subSpans[subIdx]
                    let subStartY = curSubY
                    curSubY += subSpanH + subGap
                    let drawerStartY = currentMajorY
                    let drawerSpanH = majorSpanH
                    result.append(
                        ResolvedPodLayoutItem(
                            pod: pod,
                            startY: subStartY,
                            spanH: subSpanH,
                            drawerStartY: drawerStartY,
                            drawerSpanH: drawerSpanH,
                            majorGroupId: gid
                        )
                    )
                }
            }
            currentMajorY += majorSpanH + majorGap
        }

        return result
    }

    private func solvePagedSpacesLayout(edge: MountEdge, totalHeight: Double) -> [ResolvedPodLayoutItem] {
        let pages = paginatedPods(for: edge, totalHeight: totalHeight)
        guard !pages.isEmpty else { return [] }

        let pageIdx = min(max(currentRailPage(for: edge), 0), pages.count - 1)
        let pagePods = pages[pageIdx]
        guard !pagePods.isEmpty else { return [] }

        let safeTop = isLiveRailEditingMode ? 72.0 : (pages.count > 1 ? 48.0 : 16.0)
        let safeBottom = pages.count > 1 ? (totalHeight - 48.0) : (totalHeight - 16.0)
        let gap = 8.0
        let availableH = max(safeBottom - safeTop, 160.0)
        let totalGaps = Double(max(pagePods.count - 1, 0)) * gap
        let netAvailable = max(availableH - totalGaps, 120.0)

        let minSpans: [Double] = pagePods.map { pod in
            if isLiveRailEditingMode || pod.minLength <= 0.06 {
                return 48.0
            }
            return Double(minimumDrawerHeight(for: pod.id))
        }
        var targetSpans = pagePods.enumerated().map { idx, pod in
            max(pod.range.length * totalHeight, minSpans[idx])
        }

        let totalTarget = targetSpans.reduce(0.0, +)
        if totalTarget > netAvailable {
            let excess = totalTarget - netAvailable
            let slackSum = targetSpans.enumerated().reduce(0.0) { acc, pair in
                acc + max(pair.element - minSpans[pair.offset], 0.0)
            }
            if slackSum >= excess && slackSum > 0 {
                for i in targetSpans.indices {
                    let slack = max(targetSpans[i] - minSpans[i], 0.0)
                    targetSpans[i] = max(targetSpans[i] - excess * (slack / slackSum), minSpans[i])
                }
            } else {
                let minTotal = minSpans.reduce(0.0, +)
                if minTotal > netAvailable && minTotal > 0 {
                    let scale = netAvailable / minTotal
                    targetSpans = minSpans.map { max($0 * scale, 48.0) }
                } else {
                    targetSpans = minSpans
                }
            }
        }

        let spanMap = Dictionary(uniqueKeysWithValues: zip(pagePods.map(\.id), targetSpans))
        return ErgonomicAutoLayoutEngine.resolvePhysicalRailLayout(
            pods: pagePods,
            on: edge,
            totalHeight: totalHeight,
            gap: gap,
            safeTop: safeTop,
            safeBottom: safeBottom
        ) { pod in
            spanMap[pod.id] ?? max(pod.range.length * totalHeight, 48.0)
        }
    }

    public func activeDrawerCardFrames(for edge: MountEdge, totalHeight: Double, windowWidth: Double = 580.0) -> [CGRect] {
        guard !isRailsFrozen else { return [] }
        var frames: [CGRect] = []
        let layoutItems = resolvedPhysicalLayout(for: edge, totalHeight: totalHeight)
        let corridor = activeCatchCorridor
        let edgeStrategy = overflowStrategy(for: edge)

        for item in layoutItems {
            let pod = item.pod
            let isPodActive = (activeDrawerItemId == pod.id || activeDrawerPodId == pod.id)
            let isPodPinned = isItemPinned(id: pod.id)
            let hasChild = hasActiveOrPinnedChild(for: pod.id)

            // High-performance prune: Skip completely idle pods that have neither active nor pinned drawers
            guard isPodActive || isPodPinned || hasChild else { continue }

            // In Shared Major Pod mode, check if this pod is the active drawer owner in its Major Group
            let isSharedMajorSubBar = (edgeStrategy == .decomposedMajorPod && abs(item.drawerSpanH - item.spanH) > 1.0)
            if isSharedMajorSubBar {
                guard shouldRenderDrawer(for: item, in: layoutItems) else { continue }
                let topOfPodY = totalHeight - item.drawerStartY
                let bottomOfPodY = topOfPodY - item.drawerSpanH
                let minY = max(bottomOfPodY - 6.0, 0.0)
                let maxY = min(topOfPodY + 6.0, totalHeight)

                let drawerW = min(effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id) + corridor, windowWidth)
                let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                continue
            }

            if isPodDecomposed(pod.id), let provider = capabilityProvider(for: pod.id) {
                let policy = provider.decomposedPolicy(store: self)
                let rawCount = provider.subItemCount(store: self)
                let minChipH = Double(policy.minChipHeight)
                let maxChipH = Double(policy.maxChipHeight)
                let spacing = Double(policy.spacing)
                let isDynamicAccordion = (edgeStrategy == .dynamicAccordion)
                let isUnboundedStretch = (edgeStrategy == .dynamicAccordion || edgeStrategy == .pagedSpaces)
                let maxAllowed = isDynamicAccordion
                    ? max(policy.maxRailItems, 1)
                    : max(min(Int((item.spanH + spacing) / (minChipH + spacing)), policy.maxRailItems), 1)
                let count = min(rawCount, maxAllowed)
                let safeCount = max(count, 1)
                let totalSpacing = spacing * Double(safeCount - 1)
                let effectiveMinChipH = isDynamicAccordion ? 6.0 : minChipH
                let itemH = isUnboundedStretch
                    ? max((item.spanH - totalSpacing) / Double(safeCount), effectiveMinChipH)
                    : min(max((item.spanH - totalSpacing) / Double(safeCount), effectiveMinChipH), maxChipH)
                let cardH = max(itemH, minChipH, 48.0)

                var matchedSubItem = false
                for idx in 0..<count {
                    let isSmartFoldSlot = (policy.overflowStrategy == .smartFold && rawCount > maxAllowed && maxAllowed >= 2 && idx == count - 1)
                    let subId = isSmartFoldSlot ? "\(pod.id)_more_items" : provider.subItemId(at: idx, store: self)
                    guard let subId = subId else { continue }
                    let itemActive = (activeDrawerItemId == subId) || (isSmartFoldSlot && pod.id == "calendar" && activeDrawerItemId == "calendar_more_events")
                    let itemPinned = isItemPinned(id: subId) || (isSmartFoldSlot && pod.id == "calendar" && isItemPinned(id: "calendar_more_events"))

                    if itemActive || itemPinned {
                        matchedSubItem = true
                        let itemTop = item.startY + Double(idx) * (itemH + spacing)
                        let itemBottom = itemTop + cardH
                        let maxAllowedY = totalHeight - 12.0
                        let shift = itemActive ? max(itemBottom - maxAllowedY, 0.0) : 0.0
                        let effTop = itemTop - shift

                        let appKitTop = totalHeight - effTop
                        let appKitBottom = appKitTop - cardH
                        let minY = max(appKitBottom - 10.0, 0.0)
                        let maxY = min(appKitTop + 10.0, totalHeight)

                        let subTitle = isSmartFoldSlot ? "More" : (provider.subItemTitle(at: idx, store: self) ?? "")
                        let drawerW = min(effectiveDrawerWidth(for: subTitle, baseWidth: pod.drawerWidth, podId: pod.id) + corridor, windowWidth)
                        let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                        frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                    }
                }

                if !matchedSubItem && (isPodActive || isPodPinned || hasChild) {
                    let topOfPodY = totalHeight - item.drawerStartY
                    let bottomOfPodY = topOfPodY - item.drawerSpanH
                    let minY = max(bottomOfPodY - 6.0, 0.0)
                    let maxY = min(topOfPodY + 6.0, totalHeight)
                    let drawerW = min(effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id) + corridor, windowWidth)
                    let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                    frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                }
                continue
            }

            // Full-pod Composite Drawers (Music, Shelf, Notes, and custom plugins)
            if isPodPinned || isPodActive || hasChild {
                let topOfPodY = totalHeight - item.drawerStartY
                let bottomOfPodY = topOfPodY - item.drawerSpanH
                let minY = max(bottomOfPodY - 6.0, 0.0)
                let maxY = min(topOfPodY + 6.0, totalHeight)

                let drawerW = min(effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id) + corridor, windowWidth)
                let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
            }
        }
        return frames
    }

    public func defaultColorHex(for podId: String) -> String {
        pods.first(where: { $0.id == podId })?.defaultColorHex ?? "#00F5D4"
    }

    public func podColorHex(for podId: String) -> String {
        customPodColors[podId] ?? defaultColorHex(for: podId)
    }

    public func setPodColorHex(podId: String, hex: String) {
        customPodColors[podId] = hex
        savePersistentState()
    }

    // Internal backing storage for compatibility shims / default capability providers
    package var _calendarEvents: [CalendarEventItem] = PurahWorkspaceStore.defaultEvents()
    package var _todos: [TodoItem] = PurahWorkspaceStore.defaultTodos()
    package var _musicTrack: MusicTrackInfo = .init()
    package var _shelfFiles: [ShelfFileItem] = PurahWorkspaceStore.defaultShelfFiles()
    package var _quickNote: NoteContent = .init()
    package var _isVitalsDecomposed: Bool {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "vitals", defaults: userDefaults)
            if storage.string(forKey: "isDecomposed") != nil {
                return storage.bool(forKey: "isDecomposed")
            }
            if userDefaults.object(forKey: "purah.vitals.isDecomposed") != nil {
                return userDefaults.bool(forKey: "purah.vitals.isDecomposed")
            }
            return true
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "vitals", defaults: userDefaults)
            storage.set(newValue, forKey: "isDecomposed")
        }
    }
    package var _vitalsEnabledMetrics: [VitalsMetricType] {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "vitals", defaults: userDefaults)
            if let metrics = storage.codable(forKey: "enabledMetrics", as: [VitalsMetricType].self) {
                return metrics
            }
            if let arr = userDefaults.stringArray(forKey: "purah.vitals.enabledMetrics") {
                let parsed = arr.compactMap { VitalsMetricType(rawValue: $0) }
                if !parsed.isEmpty { return parsed }
            }
            return [.cpu, .ram, .power, .disk]
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "vitals", defaults: userDefaults)
            storage.setCodable(newValue, forKey: "enabledMetrics")
        }
    }
    package var _vitalsThresholds: VitalsColorThresholds {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "vitals", defaults: userDefaults)
            if let thresh = storage.codable(forKey: "thresholds", as: VitalsColorThresholds.self) {
                return thresh
            }
            if let data = userDefaults.data(forKey: "purah.vitals.thresholds"),
               let decoded = try? JSONDecoder().decode(VitalsColorThresholds.self, from: data) {
                return decoded
            }
            return VitalsColorThresholds()
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "vitals", defaults: userDefaults)
            storage.setCodable(newValue, forKey: "thresholds")
        }
    }
    package var _isScriptsDecomposed: Bool {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "scripts", defaults: userDefaults)
            if storage.string(forKey: "isDecomposed") != nil {
                return storage.bool(forKey: "isDecomposed")
            }
            if userDefaults.object(forKey: "purah.scripts.isDecomposed") != nil {
                return userDefaults.bool(forKey: "purah.scripts.isDecomposed")
            }
            return true
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "scripts", defaults: userDefaults)
            storage.set(newValue, forKey: "isDecomposed")
        }
    }
    package var _scriptsEnabledActionIds: [String] {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "scripts", defaults: userDefaults)
            if let ids = storage.codable(forKey: "enabledActionIds", as: [String].self) {
                return ids
            }
            return userDefaults.stringArray(forKey: "purah.scripts.enabledActionIds") ?? []
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "scripts", defaults: userDefaults)
            storage.setCodable(newValue, forKey: "enabledActionIds")
        }
    }
    package var _terminalFontFamily: String {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "terminal", defaults: userDefaults)
            return storage.string(forKey: "fontFamily") ?? "Auto (Nerd Font)"
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "terminal", defaults: userDefaults)
            storage.set(newValue, forKey: "fontFamily")
        }
    }
    package var _terminalFontSize: Double {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "terminal", defaults: userDefaults)
            let size = storage.double(forKey: "fontSize")
            return size > 0 ? size : 11.5
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "terminal", defaults: userDefaults)
            storage.set(newValue, forKey: "fontSize")
        }
    }

    public var scriptsEnabledActions: [ScriptActionItem] {
        let all = ScriptRunwayService.shared.actions
        let ids = _scriptsEnabledActionIds
        if ids.isEmpty {
            return all
        }
        let filtered = all.filter { ids.contains($0.id) }
        return filtered.isEmpty ? all : filtered
    }

    private static func defaultEvents() -> [CalendarEventItem] {
        let cal = Calendar.current
        let today = Date()
        let d1 = cal.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? today
        let d2 = cal.date(bySettingHour: 11, minute: 30, second: 0, of: today) ?? today
        let d3 = cal.date(bySettingHour: 14, minute: 0, second: 0, of: today) ?? today
        let d4 = cal.date(bySettingHour: 15, minute: 0, second: 0, of: today) ?? today
        return [
            CalendarEventItem(id: "default-event-1", title: "Architecture Review", location: "Central Workshop", startTime: d1, endTime: d2),
            CalendarEventItem(id: "default-event-2", title: "Environmental Monitoring", location: "Observation Station", startTime: d3, endTime: d4)
        ]
    }

    private static func defaultTodos() -> [TodoItem] {
        [
            TodoItem(title: "Calibrate left tactile edge sensor", isCompleted: true),
            TodoItem(title: "Update energy waveform telemetry", isCompleted: false),
            TodoItem(title: "Verify multi-display adaptive layout", isCompleted: false),
            TodoItem(title: "Tune Fitts Law flick threshold filtering", isCompleted: false)
        ]
    }

    private static func defaultShelfFiles() -> [ShelfFileItem] {
        [
            ShelfFileItem(name: "macOS_Workflow_Spec.pdf", sizeDescription: "2.4 MB", fileExtension: "pdf"),
            ShelfFileItem(name: "Architecture_Diagram.png", sizeDescription: "4.8 MB", fileExtension: "png")
        ]
    }

    @ObservationIgnored
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.pods = Self.defaultPods()
        registerDefaultCapabilityProviders()
        let hasCustomPods = userDefaults.object(forKey: "purah.pods") != nil
        loadPersistentState()
        if !hasCustomPods {
            autoLayoutAll()
        } else {
            // Re-apply dynamic minLength calculation without resetting custom shortened layouts
            for idx in pods.indices {
                let pod = pods[idx]
                let screenH = max(Double(availableScreenHeight(for: pod.edge)), 400.0)
                if overflowStrategy(for: pod.edge) == .dynamicAccordion {
                    pods[idx].minLength = max(28.0 / screenH, 0.035)
                } else if pod.minLength > 0.06 {
                    let minPt = Double(minimumDrawerHeight(for: pod.id))
                    pods[idx].minLength = min(max(minPt / screenH, 0.07), max(pod.range.length, 0.07))
                }
            }
            invalidateLayoutCache()
        }
    }

    private func registerDefaultCapabilityProviders() {
        registerCapabilityProvider(DefaultCalendarCapabilityProvider())
        registerCapabilityProvider(DefaultTodoCapabilityProvider())
        registerCapabilityProvider(DefaultVitalsCapabilityProvider())
        registerCapabilityProvider(DefaultScriptsCapabilityProvider())
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "music", minHeight: 110.0, adaptiveWidth: 360.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "shelf", minHeight: 130.0, adaptiveWidth: 360.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "notes", minHeight: 130.0, adaptiveWidth: 320.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "terminal", minHeight: 120.0, adaptiveWidth: 520.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "clipboard", minHeight: 150.0, adaptiveWidth: 380.0))
    }

    // MARK: - Local Persistence
    public static func resetToFactoryDefaults(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "purah.pods")
        defaults.removeObject(forKey: "purah.currentPreset")
    }

    public func loadPersistentState() {
        let defaults = userDefaults

        if let data = defaults.data(forKey: "purah.pods"),
           let savedPods = try? JSONDecoder().decode([SlotPod].self, from: data),
           !savedPods.isEmpty {
            var merged = savedPods
            let savedIds = Set(savedPods.map(\.id))
            for var def in Self.defaultPods() where !savedIds.contains(def.id) {
                def.isEnabled = false
                merged.append(def)
            }
            self.pods = merged
        }

        if let colors = defaults.dictionary(forKey: "purah.customPodColors") as? [String: String] {
            self.customPodColors = colors
        }

        if let modeStr = defaults.string(forKey: "purah.drawerWidthMode"),
           let mode = DrawerWidthMode(rawValue: modeStr) {
            self.drawerWidthMode = mode
        }

        let savedFixedW = defaults.double(forKey: "purah.fixedDrawerWidth")
        if savedFixedW >= 220.0 {
            self.fixedDrawerWidth = savedFixedW
        }

        let savedRailW = defaults.double(forKey: "purah.railBarWidth")
        if savedRailW >= 4.0 {
            self.railBarWidth = savedRailW
        }

        // Migrate legacy root keys into ScopedPluginStorage partition
        if defaults.object(forKey: "purah.calendarMaxRailEvents") != nil {
            let legacy = defaults.integer(forKey: "purah.calendarMaxRailEvents")
            if legacy > 0 { self.calendarMaxRailEvents = legacy }
            defaults.removeObject(forKey: "purah.calendarMaxRailEvents")
        }
        if defaults.object(forKey: "purah.todoMaxRailTasks") != nil {
            let legacy = defaults.integer(forKey: "purah.todoMaxRailTasks")
            if legacy > 0 { self.todoMaxRailTasks = legacy }
            defaults.removeObject(forKey: "purah.todoMaxRailTasks")
        }
        if defaults.object(forKey: "purah.clipboardMaxRailItems") != nil {
            let legacy = defaults.integer(forKey: "purah.clipboardMaxRailItems")
            if legacy > 0 { self.clipboardMaxRailItems = legacy }
            defaults.removeObject(forKey: "purah.clipboardMaxRailItems")
        }
        if defaults.object(forKey: "purah.vitals.isDecomposed") != nil {
            let legacy = defaults.bool(forKey: "purah.vitals.isDecomposed")
            ScopedPluginStorage(pluginId: "vitals", defaults: defaults).set(legacy, forKey: "isDecomposed")
            defaults.removeObject(forKey: "purah.vitals.isDecomposed")
        }
        if let legacyArr = defaults.stringArray(forKey: "purah.vitals.enabledMetrics") {
            let parsed = legacyArr.compactMap { VitalsMetricType(rawValue: $0) }
            if !parsed.isEmpty {
                ScopedPluginStorage(pluginId: "vitals", defaults: defaults).setCodable(parsed, forKey: "enabledMetrics")
            }
            defaults.removeObject(forKey: "purah.vitals.enabledMetrics")
        }
        if let legacyData = defaults.data(forKey: "purah.vitals.thresholds") {
            if let decoded = try? JSONDecoder().decode(VitalsColorThresholds.self, from: legacyData) {
                ScopedPluginStorage(pluginId: "vitals", defaults: defaults).setCodable(decoded, forKey: "thresholds")
            }
            defaults.removeObject(forKey: "purah.vitals.thresholds")
        }
        if defaults.object(forKey: "purah.scripts.isDecomposed") != nil {
            let legacy = defaults.bool(forKey: "purah.scripts.isDecomposed")
            ScopedPluginStorage(pluginId: "scripts", defaults: defaults).set(legacy, forKey: "isDecomposed")
            defaults.removeObject(forKey: "purah.scripts.isDecomposed")
        }
        if let legacyActionIds = defaults.stringArray(forKey: "purah.scripts.enabledActionIds") {
            ScopedPluginStorage(pluginId: "scripts", defaults: defaults).setCodable(legacyActionIds, forKey: "enabledActionIds")
            defaults.removeObject(forKey: "purah.scripts.enabledActionIds")
        }

        if let presetStr = defaults.string(forKey: "purah.currentPreset"),
           let preset = PodPreset(rawValue: presetStr) {
            self.currentPreset = preset
        }

        if let overflowStr = defaults.string(forKey: "purah.railOverflowStrategy"),
           let strategy = RailOverflowStrategy(rawValue: overflowStr) {
            self.leftRailOverflowStrategy = strategy
            self.rightRailOverflowStrategy = strategy
        }
        if let leftStr = defaults.string(forKey: "purah.leftRailOverflowStrategy"),
           let leftStrategy = RailOverflowStrategy(rawValue: leftStr) {
            self.leftRailOverflowStrategy = leftStrategy
        }
        if let rightStr = defaults.string(forKey: "purah.rightRailOverflowStrategy"),
           let rightStrategy = RailOverflowStrategy(rawValue: rightStr) {
            self.rightRailOverflowStrategy = rightStrategy
        }

        if defaults.object(forKey: "purah.hotkey.keyCode") != nil {
            let code = UInt32(defaults.integer(forKey: "purah.hotkey.keyCode"))
            let mods = UInt32(defaults.integer(forKey: "purah.hotkey.modifiers"))
            self.hotKeyShortcut = HotKeyShortcut(keyCode: code, modifiers: mods)
        }

        if let modeStr = defaults.string(forKey: "purah.edgeTriggerMode"),
           let mode = EdgeTriggerMode(rawValue: modeStr) {
            self.edgeTriggerMode = mode
        }
        if let alertStr = defaults.string(forKey: "purah.alertStyle"),
           let style = PluginAlertStyle(rawValue: alertStr) {
            self.alertStyle = style
        }
        if defaults.object(forKey: "purah.dismissAlertOnHover") != nil {
            self.dismissAlertOnHover = defaults.bool(forKey: "purah.dismissAlertOnHover")
        }
        if defaults.object(forKey: "purah.isEventToastAlertEnabled") != nil {
            self.isEventToastAlertEnabled = defaults.bool(forKey: "purah.isEventToastAlertEnabled")
        }

        if let dispModeStr = defaults.string(forKey: "purah.displayTargetMode"),
           let dispMode = DisplayTargetMode(rawValue: dispModeStr) {
            self.displayTargetMode = dispMode
        }

        if let sensStr = defaults.string(forKey: "purah.edgeTriggerSensitivity"),
           let sens = EdgeTriggerSensitivity(rawValue: sensStr) {
            self.edgeTriggerSensitivity = sens
        }
        let dwellMs = defaults.double(forKey: "purah.customInitialDwellMs")
        if dwellMs > 0 { self.customInitialDwellMs = dwellMs }
        let graceMs = defaults.double(forKey: "purah.customExitGraceMs")
        if graceMs > 0 { self.customExitGraceMs = graceMs }
        let corridorPt = defaults.double(forKey: "purah.customCatchCorridorPt")
        if corridorPt > 0 { self.customCatchCorridorPt = corridorPt }
        let pushForce = defaults.double(forKey: "purah.customPushForceThreshold")
        if pushForce > 0 { self.customPushForceThreshold = pushForce }
        let barrier = defaults.double(forKey: "purah.customPushResistanceBarrier")
        if barrier >= 15.0 && barrier <= 150.0 {
            self.customPushResistanceBarrier = barrier
        } else {
            self.customPushResistanceBarrier = 40.0
        }

        if defaults.object(forKey: "purah.isToastSoundEnabled") != nil {
            self.isToastSoundEnabled = defaults.bool(forKey: "purah.isToastSoundEnabled")
        }
        if let soundStr = defaults.string(forKey: "purah.toastNotificationSound"),
           let sound = ToastNotificationSound(rawValue: soundStr) {
            self.toastNotificationSound = sound
        }
        if defaults.object(forKey: "purah.isTrackpadHapticsEnabled") != nil {
            self.isTrackpadHapticsEnabled = defaults.bool(forKey: "purah.isTrackpadHapticsEnabled")
        }
        if defaults.object(forKey: "purah.isDrawerPopHapticEnabled") != nil {
            self.isDrawerPopHapticEnabled = defaults.bool(forKey: "purah.isDrawerPopHapticEnabled")
        }
        if defaults.object(forKey: "purah.isControlHapticEnabled") != nil {
            self.isControlHapticEnabled = defaults.bool(forKey: "purah.isControlHapticEnabled")
        }
    }

    public func savePersistentState() {
        let defaults = userDefaults
        if let data = try? JSONEncoder().encode(pods) {
            defaults.set(data, forKey: "purah.pods")
        }
        defaults.set(customPodColors, forKey: "purah.customPodColors")
        defaults.set(drawerWidthMode.rawValue, forKey: "purah.drawerWidthMode")
        defaults.set(fixedDrawerWidth, forKey: "purah.fixedDrawerWidth")
        defaults.set(railBarWidth, forKey: "purah.railBarWidth")
        defaults.set(currentPreset.rawValue, forKey: "purah.currentPreset")
        defaults.set(leftRailOverflowStrategy.rawValue, forKey: "purah.railOverflowStrategy")
        defaults.set(leftRailOverflowStrategy.rawValue, forKey: "purah.leftRailOverflowStrategy")
        defaults.set(rightRailOverflowStrategy.rawValue, forKey: "purah.rightRailOverflowStrategy")
        defaults.set(Int(hotKeyShortcut.keyCode), forKey: "purah.hotkey.keyCode")
        defaults.set(Int(hotKeyShortcut.modifiers), forKey: "purah.hotkey.modifiers")
        defaults.set(displayTargetMode.rawValue, forKey: "purah.displayTargetMode")
        defaults.set(edgeTriggerMode.rawValue, forKey: "purah.edgeTriggerMode")
        defaults.set(alertStyle.rawValue, forKey: "purah.alertStyle")
        defaults.set(dismissAlertOnHover, forKey: "purah.dismissAlertOnHover")
        defaults.set(isEventToastAlertEnabled, forKey: "purah.isEventToastAlertEnabled")
        defaults.set(isToastSoundEnabled, forKey: "purah.isToastSoundEnabled")
        defaults.set(toastNotificationSound.rawValue, forKey: "purah.toastNotificationSound")
        defaults.set(isTrackpadHapticsEnabled, forKey: "purah.isTrackpadHapticsEnabled")
        defaults.set(isDrawerPopHapticEnabled, forKey: "purah.isDrawerPopHapticEnabled")
        defaults.set(isControlHapticEnabled, forKey: "purah.isControlHapticEnabled")
        defaults.set(edgeTriggerSensitivity.rawValue, forKey: "purah.edgeTriggerSensitivity")
        defaults.set(customInitialDwellMs, forKey: "purah.customInitialDwellMs")
        defaults.set(customExitGraceMs, forKey: "purah.customExitGraceMs")
        defaults.set(customCatchCorridorPt, forKey: "purah.customCatchCorridorPt")
        defaults.set(customPushForceThreshold, forKey: "purah.customPushForceThreshold")
        defaults.set(customPushResistanceBarrier, forKey: "purah.customPushResistanceBarrier")
        defaults.synchronize()
        notifyCapacityWarningIfNeeded()
    }

    public func autoLayoutAll() {
        // Dynamically update each pod's minLength to reflect capability provider's minimum required height
        for idx in pods.indices {
            let pod = pods[idx]
            let screenH = max(Double(availableScreenHeight(for: pod.edge)), 400.0)
            if overflowStrategy(for: pod.edge) == .dynamicAccordion {
                pods[idx].minLength = max(28.0 / screenH, 0.035)
            } else {
                let minPt = Double(minimumDrawerHeight(for: pod.id))
                pods[idx].minLength = max(minPt / screenH, 0.07)
            }
        }

        pods = ErgonomicAutoLayoutEngine.optimizeBilateralLayout(
            pods: pods,
            reassignEdges: false,
            availableHeight: Double(availableScreenHeight(for: .left))
        )
        if overflowStrategy(for: .left) == .pagedSpaces {
            normalizePageRanges(for: .left)
        }
        if overflowStrategy(for: .right) == .pagedSpaces {
            normalizePageRanges(for: .right)
        }
        invalidateLayoutCache()
        savePersistentState()
        notifyCapacityWarningIfNeeded()
    }

    public func togglePodEnabled(id: String) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        let pod = pods[index]
        if !pod.isEnabled {
            if overflowStrategy(for: pod.edge) == .strictCeiling {
                // Guard minimum height: reject enabling if required height overflows screen budget
                let currentReq = totalRequiredHeight(for: pod.edge)
                let additional = minimumDrawerHeight(for: pod.id) + 10.0
                let available = availableScreenHeight(for: pod.edge)
                if (currentReq + additional) > available {
                    let reqTotal = Int(currentReq + additional)
                    let availInt = Int(available)
                    onCapacityWarningToast?("⚠️ Insufficient rail capacity (\(reqTotal)pt / \(availInt)pt). Cannot mount \(pod.name) without squashing existing pods.")
                    return
                }
            }
            pods[index].isEnabled = true
            let screenH = max(Double(availableScreenHeight(for: pod.edge)), 400.0)
            if overflowStrategy(for: pod.edge) == .dynamicAccordion {
                pods[index].minLength = max(28.0 / screenH, 0.035)
            } else {
                let minPt = Double(minimumDrawerHeight(for: pod.id))
                pods[index].minLength = max(minPt / screenH, 0.07)
            }
            if overflowStrategy(for: pod.edge) == .decomposedMajorPod {
                seedDefaultMajorGroupsIfNeeded(for: pod.edge)
            }
            onPodEnabledChanged?(id, true)
        } else {
            let oldGroupId = pods[index].majorGroupId
            pods[index].isEnabled = false
            pods[index].majorGroupId = nil
            if let oldGroupId = oldGroupId {
                let remainingIndices = pods.indices.filter {
                    pods[$0].edge == pod.edge && pods[$0].isEnabled && pods[$0].majorGroupId == oldGroupId
                }
                if remainingIndices.count < 2 {
                    for remIdx in remainingIndices {
                        pods[remIdx].majorGroupId = nil
                    }
                }
            }
            onPodEnabledChanged?(id, false)
        }
        _marketManager?.enabledPluginIds = Set(pods.filter(\.isEnabled).map(\.id))
        _marketManager?.savePersistentState()
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func fillRail(podId: String) {
        guard let currentPod = pods.first(where: { $0.id == podId && $0.isEnabled }) else { return }
        let edge = currentPod.edge
        let isPaged = (overflowStrategy(for: edge) == .pagedSpaces)
        let railPods = pods.filter {
            $0.edge == edge && $0.isEnabled && (!isPaged || $0.pageIndex == currentPod.pageIndex)
        }.sorted { $0.range.start < $1.range.start }
        guard let currentIndex = railPods.firstIndex(where: { $0.id == podId }),
              let podIndex = pods.firstIndex(where: { $0.id == podId }) else { return }

        if isPaged && railPods.count >= 2 {
            // In Paged Spaces, expand target pod to fill maximum space on its page while compressing siblings on the same page to minLength
            let screenH = max(Double(availableScreenHeight(for: edge)), 600.0)
            let gap = 0.015
            let totalGaps = Double(max(railPods.count - 1, 0)) * gap
            let otherMins = railPods.enumerated().reduce(0.0) { acc, pair in
                if pair.offset == currentIndex { return acc }
                let minH = Double(minimumDrawerHeight(for: pair.element.id))
                return acc + max(pair.element.minLength, minH / screenH)
            }
            let targetLen = max(0.94 - totalGaps - otherMins, max(currentPod.minLength, Double(minimumDrawerHeight(for: podId)) / screenH))
            var curStart = 0.02
            for (offset, p) in railPods.enumerated() {
                if let idx = pods.firstIndex(where: { $0.id == p.id }) {
                    let minH = Double(minimumDrawerHeight(for: p.id))
                    let len = (offset == currentIndex) ? targetLen : max(p.minLength, minH / screenH)
                    pods[idx].range = NormalizedRange(start: curStart, length: len)
                    curStart += len + gap
                }
            }
        } else if currentIndex == railPods.count - 1 {
            // Last pod on the rail (e.g. Music): expand length down to 0.98 to fill all remaining space!
            let start = pods[podIndex].range.start
            let newLength = max(0.98 - start, currentPod.minLength)
            pods[podIndex].range.length = newLength
        } else {
            // Expand towards successor above/below
            let nextPod = railPods[currentIndex + 1]
            let start = pods[podIndex].range.start
            let newLength = max(nextPod.range.start - start - 0.015, currentPod.minLength)
            pods[podIndex].range.length = newLength
        }

        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func applyPreset(_ preset: PodPreset) {
        currentPreset = preset
        switch preset {
        case .balanced:
            // Left Rail: Vitals, Shelf, Notes (~480pt budget)
            setPod(id: "vitals", edge: .left, zone: .glance, weight: 30, isEnabled: true)
            setPod(id: "shelf", edge: .left, zone: .goldenAction, weight: 35, isEnabled: true)
            setPod(id: "notes", edge: .left, zone: .quickFlick, weight: 30, isEnabled: true)

            // Right Rail: Calendar, Todo, Scripts, Music (~600pt budget)
            setPod(id: "calendar", edge: .right, zone: .goldenAction, weight: 40, isEnabled: true)
            setPod(id: "todo", edge: .right, zone: .goldenAction, weight: 35, isEnabled: true)
            setPod(id: "scripts", edge: .right, zone: .quickFlick, weight: 25, isEnabled: true)
            setPod(id: "music", edge: .right, zone: .quickFlick, weight: 20, isEnabled: true)

        case .sprintProductivity:
            // Left Rail: Scripts Runway, Notes, Shelf (~440pt budget)
            setPod(id: "scripts", edge: .left, zone: .goldenAction, weight: 45, isEnabled: true)
            setPod(id: "notes", edge: .left, zone: .goldenAction, weight: 35, isEnabled: true)
            setPod(id: "shelf", edge: .left, zone: .quickFlick, weight: 25, isEnabled: true)

            // Right Rail: Tasks, Calendar, Vitals (~520pt budget)
            setPod(id: "todo", edge: .right, zone: .goldenAction, weight: 45, isEnabled: true)
            setPod(id: "calendar", edge: .right, zone: .goldenAction, weight: 40, isEnabled: true)
            setPod(id: "vitals", edge: .right, zone: .glance, weight: 25, isEnabled: true)

            // Mute music in sprint focus
            setPod(id: "music", edge: .right, zone: .quickFlick, weight: 10, isEnabled: false)

        case .immersiveMultimedia:
            // Left Rail: Showcase Music & Notes (~250pt budget, large stage for vinyl)
            setPod(id: "music", edge: .left, zone: .goldenAction, weight: 65, isEnabled: true)
            setPod(id: "notes", edge: .left, zone: .quickFlick, weight: 25, isEnabled: true)
            setPod(id: "shelf", edge: .left, zone: .quickFlick, weight: 10, isEnabled: false)

            // Right Rail: Calendar & Vitals (~360pt budget)
            setPod(id: "calendar", edge: .right, zone: .glance, weight: 50, isEnabled: true)
            setPod(id: "vitals", edge: .right, zone: .glance, weight: 30, isEnabled: true)

            // Disable distracting productivity tasks
            setPod(id: "todo", edge: .right, zone: .quickFlick, weight: 10, isEnabled: false)
            setPod(id: "scripts", edge: .right, zone: .quickFlick, weight: 10, isEnabled: false)
        }
        autoLayoutAll()
    }

    public func updatePodRange(id: String, newRange: NormalizedRange) {
        guard let pod = pods.first(where: { $0.id == id }) else { return }
        let screenH = max(Double(availableScreenHeight(for: pod.edge)), 600.0)
        let minManualRatio = max(48.0 / screenH, 0.05)
        let edgeStrategy = overflowStrategy(for: pod.edge)
        let isDynamicAccordion = (edgeStrategy == .dynamicAccordion)
        if edgeStrategy == .pagedSpaces {
            let pagePods = pods.filter { $0.edge == pod.edge && $0.isEnabled && $0.pageIndex == pod.pageIndex }
            let resolvedPagePods = SpringConstraintSolver.resolve(
                draggedPodId: id,
                newRange: newRange,
                allPods: pagePods,
                on: pod.edge,
                minRatioProvider: { _ in
                    minManualRatio
                }
            )
            var resolvedMap = Dictionary(uniqueKeysWithValues: resolvedPagePods.map { ($0.id, $0) })
            if var updatedTarget = resolvedMap[id] {
                updatedTarget.minLength = min(updatedTarget.minLength, 0.05)
                resolvedMap[id] = updatedTarget
            }
            pods = pods.map { resolvedMap[$0.id] ?? $0 }
        } else {
            var resolved = SpringConstraintSolver.resolve(
                draggedPodId: id,
                newRange: newRange,
                allPods: pods,
                on: pod.edge,
                minRatioProvider: { _ in
                    if isDynamicAccordion {
                        return min(28.0 / screenH, minManualRatio)
                    }
                    return minManualRatio
                }
            )
            if let idx = resolved.firstIndex(where: { $0.id == id }) {
                resolved[idx].minLength = min(resolved[idx].minLength, 0.05)
            }
            pods = resolved
        }
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func movePod(id: String, to edge: MountEdge) {
        guard pods.contains(where: { $0.id == id }) else { return }
        splitPodFromMajorGroup(id: id)
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        pods[index].edge = edge
        pods[index].majorGroupId = nil
        pods[index].pageIndex = 0
        autoLayoutAll()
        onWindowsRebuildNeeded?()
    }

    // MARK: - Pod Reordering & Position Swapping
    public enum PodMoveDirection: Sendable {
        case up
        case down
    }

    public func canMovePod(id: String, direction: PodMoveDirection) -> Bool {
        guard let currentPod = pods.first(where: { $0.id == id && $0.isEnabled }) else { return false }
        let railPods = pods.filter { $0.edge == currentPod.edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        guard let currentIndex = railPods.firstIndex(where: { $0.id == id }) else { return false }
        switch direction {
        case .up:
            return currentIndex > 0
        case .down:
            return currentIndex < railPods.count - 1
        }
    }

    public func movePodInOrder(id: String, direction: PodMoveDirection) {
        guard let currentPod = pods.first(where: { $0.id == id && $0.isEnabled }) else { return }
        let edge = currentPod.edge
        let railPods = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }

        guard let currentIndex = railPods.firstIndex(where: { $0.id == id }) else { return }

        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = currentIndex - 1
        case .down:
            targetIndex = currentIndex + 1
        }

        guard targetIndex >= 0 && targetIndex < railPods.count else { return }
        let targetPod = railPods[targetIndex]

        swapPods(id1: currentPod.id, id2: targetPod.id)
    }

    public func swapPods(id1: String, id2: String) {
        guard let idx1 = pods.firstIndex(where: { $0.id == id1 }),
              let idx2 = pods.firstIndex(where: { $0.id == id2 }) else { return }

        let p1 = pods[idx1]
        let p2 = pods[idx2]
        guard p1.edge == p2.edge else { return }

        let start1 = p1.range.start
        let start2 = p2.range.start

        if start1 < start2 {
            // p1 is above p2 -> p2 moves up, p1 moves down
            let newP2Start = start1
            let newP1Start = start1 + p2.range.length + 0.02
            pods[idx2].range.start = newP2Start
            pods[idx1].range.start = newP1Start
        } else {
            // p1 is below p2 -> p1 moves up, p2 moves down
            let newP1Start = start2
            let newP2Start = start2 + p1.range.length + 0.02
            pods[idx1].range.start = newP1Start
            pods[idx2].range.start = newP2Start
        }

        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    // MARK: - Magnetic Pod Snapping
    public enum SnapTarget: Sendable {
        case predecessor // Snap to bottom of the pod above
        case successor   // Snap to top of the pod below
        case top         // Snap to top of the rail
    }

    public func hasGapAbove(id: String) -> Bool {
        guard let currentPod = pods.first(where: { $0.id == id && $0.isEnabled }) else { return false }
        let railPods = pods.filter { $0.edge == currentPod.edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        guard let currentIndex = railPods.firstIndex(where: { $0.id == id }), currentIndex > 0 else { return false }
        let prev = railPods[currentIndex - 1]
        let gap = currentPod.range.start - (prev.range.start + prev.range.length)
        let bottomGap = (currentIndex == railPods.count - 1) ? (0.98 - (currentPod.range.start + currentPod.range.length)) : 0.0
        return gap > 0.015 || bottomGap > 0.04
    }

    public func snapPod(id: String, to target: SnapTarget) {
        guard let currentPod = pods.first(where: { $0.id == id && $0.isEnabled }) else { return }
        let edge = currentPod.edge
        let railPods = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }

        guard let currentIndex = railPods.firstIndex(where: { $0.id == id }) else { return }
        guard let podIndex = pods.firstIndex(where: { $0.id == id }) else { return }

        let minGap = 0.012

        switch target {
        case .predecessor:
            if currentIndex > 0 {
                let prev = railPods[currentIndex - 1]
                let newStart = prev.range.start + prev.range.length + minGap
                pods[podIndex].range.start = min(newStart, 0.96 - currentPod.range.length)
                // If this is the last pod on the rail, stretch length down to fill all remaining space to 0.98!
                if currentIndex == railPods.count - 1 {
                    let availableDown = max(0.98 - pods[podIndex].range.start, currentPod.minLength)
                    pods[podIndex].range.length = availableDown
                }
            } else {
                pods[podIndex].range.start = 0.02
            }
        case .successor:
            if currentIndex < railPods.count - 1 {
                let next = railPods[currentIndex + 1]
                let newStart = next.range.start - currentPod.range.length - minGap
                pods[podIndex].range.start = max(newStart, 0.02)
            }
        case .top:
            pods[podIndex].range.start = 0.02
        }

        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    private func setPod(id: String, edge: MountEdge, zone: ZoneType, weight: Double, isEnabled: Bool = true) {
        if let idx = pods.firstIndex(where: { $0.id == id }) {
            pods[idx].edge = edge
            pods[idx].preferredZone = zone
            pods[idx].ergonomicWeight = weight
            pods[idx].isEnabled = isEnabled
        }
    }

    public static func defaultPods() -> [SlotPod] {
        [
            SlotPod(id: "calendar", name: "Calendar Timeline", systemIcon: "calendar", edge: .right, range: .init(start: 0.15, length: 0.35), ambientStyle: .progressTimeline, preferredZone: .goldenAction, ergonomicWeight: 40, minLength: 0.15, defaultColorHex: "#FF5A60"),
            SlotPod(id: "todo", name: "Todo Checklist", systemIcon: "checklist", edge: .right, range: .init(start: 0.52, length: 0.25), ambientStyle: .segmentGauge, preferredZone: .goldenAction, ergonomicWeight: 35, minLength: 0.15, defaultColorHex: "#FF9E0A"),
            SlotPod(id: "music", name: "Music Waveform", systemIcon: "waveform", edge: .right, range: .init(start: 0.79, length: 0.14), ambientStyle: .waveLevelMeter, preferredZone: .quickFlick, ergonomicWeight: 25, minLength: 0.12, defaultColorHex: "#FF2D55"),
            SlotPod(id: "vitals", name: "Hardware Vitals", systemIcon: "waveform.path.ecg", edge: .left, range: .init(start: 0.08, length: 0.22), ambientStyle: .progressTimeline, preferredZone: .glance, ergonomicWeight: 35, minLength: 0.18, defaultColorHex: "#00E5A3"),
            SlotPod(id: "shelf", name: "Temporary Shelf", systemIcon: "tray.fill", edge: .left, range: .init(start: 0.32, length: 0.20), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 35, minLength: 0.16, defaultColorHex: "#2ED573"),
            SlotPod(id: "notes", name: "Quick Notes", systemIcon: "note.text", edge: .left, range: .init(start: 0.54, length: 0.14), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 30, minLength: 0.12, isEnabled: false, defaultColorHex: "#FFD166"),
            SlotPod(id: "scripts", name: "Script Runway", systemIcon: "terminal.fill", edge: .left, range: .init(start: 0.54, length: 0.20), ambientStyle: .ghostDot, preferredZone: .quickFlick, ergonomicWeight: 30, minLength: 0.16, isEnabled: true, defaultColorHex: "#6C5CE7"),
            SlotPod(id: "terminal", name: "Terminal", systemIcon: "apple.terminal.fill", edge: .left, range: .init(start: 0.76, length: 0.20), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 25, minLength: 0.14, isEnabled: true, drawerWidth: 520, defaultColorHex: "#00F5D4"),
            SlotPod(id: "clipboard", name: "Clipboard", systemIcon: "doc.on.clipboard.fill", edge: .left, range: .init(start: 0.88, length: 0.08), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 20, minLength: 0.08, isEnabled: false, drawerWidth: 260, defaultColorHex: "#FF9F0A")
        ]
    }
}
