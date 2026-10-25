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

public enum OnboardingGuideStep: Int, CaseIterable, Codable, Sendable, Identifiable {
    case mountPods = 0          // Step 1: Empty Rails -> Mount Pods to Left & Right
    case decomposeDemo = 1      // Step 2: Decompose Mode -> Composite vs Stepped Chips
    case stackDemo = 2          // Step 3: Stack Mode -> Merge Pods & Auto-Disable Decompose
    case pageDemo = 3           // Step 4: Multi-Page Deck -> +Page & Top/Bottom Portals
    case breathingDemo = 4      // Step 5: Dynamic Breathing -> Compact & In-Place Accordion
    case antiTouchCalibration = 5 // Step 6: Anti-Accidental Touch -> Dwell vs Push Force & Sensitivity

    public var id: Int { rawValue }
}

@Observable
@MainActor
public final class PurahWorkspaceStore {
    public var pods: [SlotPod] = []
    public var activeDrawerPodId: String? = nil
    public var activeDrawerItemId: String? = nil
    public var activePodId: String? {
        get { activeDrawerPodId }
        set { activeDrawerPodId = newValue }
    }
    public var hoveredPodId: String? = nil
    @ObservationIgnored private var pendingHoverPodId: String? = nil
    public var isDrawerPinned: Bool = false
    public var pinnedDrawerItemIds: Set<String> = []
    public var isDraggingFromDrawer: Bool = false
    public var isDynamicBreathingEnabled: Bool = true
    public var isAlwaysCompactBreathing: Bool = false
    @ObservationIgnored
    public var onToast: ((String, String?) -> Void)? = nil

    public var isOnboardingGuideActive: Bool = false
    public var onboardingStep: OnboardingGuideStep = .mountPods
    public var isRehearsingBreathingInSculptor: Bool = false
    @ObservationIgnored private var onboardingRehearsalTask: Task<Void, Never>? = nil
    @ObservationIgnored private var userPodsSnapshotBeforeRehearsal: [SlotPod]? = nil
    @ObservationIgnored private var userDynamicFlagBeforeRehearsal: Bool? = nil
    public var isUsingTemporaryDemoSandbox: Bool = false
    public var isInteractionSettingsTelemetryActive: Bool = false
    public var isGateTelemetryTrackingEnabled: Bool {
        (isOnboardingGuideActive && onboardingStep == .antiTouchCalibration) || isInteractionSettingsTelemetryActive
    }
    @ObservationIgnored
    public var onDecomposedStateSync: (@MainActor (String, Bool) -> Void)? = nil

    public var onboardingDidToggleDecompose: Bool = false
    public var onboardingDidCreateStack: Bool = false
    public var onboardingDidCreatePage: Bool = false
    public var onboardingDidSwitchPage: Bool = false
    public var onboardingBreathingHoveredPods: Set<String> = []
    public var onboardingDidSwitchTriggerMode: Bool = false
    public var onboardingDidTriggerEdgeDrawer: Bool = false

    public enum OnboardingGateTelemetryState: String, Sendable {
        case idle
        case dwelling
        case pushing
        case suppressedFling
        case opened
    }

    public var onboardingGateState: OnboardingGateTelemetryState = .idle
    public var onboardingGateProgress: Double = 0.0
    public var onboardingGateCurrentValue: Int = 0
    public var onboardingGateTargetValue: Int = 150

    public var isCurrentOnboardingMissionCompleted: Bool {
        switch onboardingStep {
        case .mountPods:
            return pods.contains { $0.edge == .left && $0.isEnabled } && pods.contains { $0.edge == .right && $0.isEnabled }
        case .decomposeDemo:
            return onboardingDidToggleDecompose
        case .stackDemo:
            return onboardingDidCreateStack || pods.contains { $0.isEnabled && isInSharedMajorPod(podId: $0.id) }
        case .pageDemo:
            return onboardingDidCreatePage && onboardingDidSwitchPage
        case .breathingDemo:
            return isDynamicBreathingEnabled && onboardingBreathingHoveredPods.count >= 2
        case .antiTouchCalibration:
            return onboardingDidTriggerEdgeDrawer
        }
    }

    public var hasCompletedOnboarding: Bool {
        get { userDefaults.bool(forKey: "purah.hasCompletedOnboarding") }
        set { userDefaults.set(newValue, forKey: "purah.hasCompletedOnboarding") }
    }

    public var railWidth: Double {
        Double(railBarWidth)
    }

    public func setDynamicBreathingEnabled(_ enabled: Bool) {
        isDynamicBreathingEnabled = enabled
        if isOnboardingGuideActive {
            onboardingDidCreateStack = true
        }
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func setAlwaysCompactBreathing(_ enabled: Bool) {
        isAlwaysCompactBreathing = enabled
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public var leftRailPage: Int = 0
    public var rightRailPage: Int = 0
    public var isLeftTopPortalRevealed: Bool = false
    public var isLeftBottomPortalRevealed: Bool = false
    public var isRightTopPortalRevealed: Bool = false
    public var isRightBottomPortalRevealed: Bool = false
    public var isRailsFrozen: Bool = false
    public var isLiveRailEditingMode: Bool = false
    public var externalDraggedPodId: String? = nil
    public var externalDragScreenLocation: CGPoint? = nil
    public var externalDragTargetEdge: MountEdge? = nil
    public var externalDragTargetPodId: String? = nil
    public var hotKeyShortcut: HotKeyShortcut = .defaultShortcut
    public var sculptorHotKeyShortcut: HotKeyShortcut = .defaultSculptorShortcut
    public var activePreviewScreenFrame: CGRect? = nil

    @ObservationIgnored
    public var onDismissPreviewPanel: (@MainActor () -> Void)? = nil

    @ObservationIgnored
    public var onLiveRailEditingChanged: (@MainActor (Bool) -> Void)?

    @ObservationIgnored
    private var lastKnownTotalHeight: [MountEdge: Double] = [:]

    public func setLiveRailEditingMode(_ enabled: Bool) {
        guard isLiveRailEditingMode != enabled else { return }
        if enabled {
            dismissActiveDrawer()
        } else {
            externalDraggedPodId = nil
            externalDragScreenLocation = nil
            externalDragTargetEdge = nil
            externalDragTargetPodId = nil
            if isOnboardingGuideActive {
                isOnboardingGuideActive = false
                hasCompletedOnboarding = true
                cancelOnboardingRehearsal()
            }
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

    public func updateExternalPodDrag(
        podId: String,
        screenPoint: CGPoint,
        screenFrame: CGRect,
        leftStripWidth: CGFloat = 215,
        rightStripWidth: CGFloat = 215
    ) {
        externalDraggedPodId = podId
        externalDragScreenLocation = screenPoint

        let targetEdge: MountEdge?
        if screenPoint.x <= screenFrame.minX + leftStripWidth {
            targetEdge = .left
        } else if screenPoint.x >= screenFrame.maxX - rightStripWidth {
            targetEdge = .right
        } else {
            targetEdge = nil
        }

        if let edge = targetEdge {
            let railY = Double(screenFrame.maxY - screenPoint.y)
            let items = resolvedPhysicalLayout(for: edge, totalHeight: Double(screenFrame.height))
            let matchedItem = items.first { item in
                guard item.pod.id != podId else { return false }
                let minY = item.drawerStartY + 6.0
                let maxY = item.drawerStartY + item.drawerSpanH - 6.0
                return maxY > minY && railY >= minY && railY <= maxY
            }
            if externalDragTargetPodId != matchedItem?.pod.id && matchedItem != nil {
                triggerControlHaptic(.levelChange)
            }
            externalDragTargetEdge = edge
            externalDragTargetPodId = matchedItem?.pod.id
        } else {
            externalDragTargetEdge = nil
            externalDragTargetPodId = nil
        }
    }

    public func commitExternalPodDrag(podId: String, screenFrame: CGRect) {
        defer {
            externalDraggedPodId = nil
            externalDragScreenLocation = nil
            externalDragTargetEdge = nil
            externalDragTargetPodId = nil
        }
        guard let targetEdge = externalDragTargetEdge else { return }
        let targetPodId = externalDragTargetPodId

        if targetPodId != nil {
            userDefaults.set(true, forKey: "purah.didSeedMajorGroups.\(targetEdge.rawValue)")
        }

        if let existingPod = pods.first(where: { $0.id == podId }) {
            if existingPod.isEnabled && existingPod.edge != targetEdge {
                splitPodFromMajorGroup(id: podId)
            }
            if !existingPod.isEnabled || existingPod.edge != targetEdge {
                mountPod(id: podId, to: targetEdge)
            }
        }

        if let targetPodId = targetPodId, targetPodId != podId {
            addPodToMajorGroup(podId: podId, targetPodId: targetPodId)
            triggerControlHaptic(.levelChange)
        } else {
            triggerControlHaptic(.alignment)
        }

        if !isDynamicBreathingEnabled {
            let screenH = max(Double(availableScreenHeight(for: targetEdge)), 600.0)
            let pages = paginatedPods(for: targetEdge, totalHeight: screenH)
            if pages.count > 1 {
                setRailPage(pages.count - 1, for: targetEdge)
                DiagnosticLogger.shared.warn("Store", "Page overflow toast triggered for edge=\(targetEdge)")
                onCapacityWarningToast?("layout.toast.pageOverflow".localized)
            }
        }
    }

    public func mountPod(id: String, to edge: MountEdge) {
        guard let idx = pods.firstIndex(where: { $0.id == id }) else { return }
        pods[idx].edge = edge
        pods[idx].pageIndex = max(0, currentRailPage(for: edge))
        if !pods[idx].isEnabled {
            togglePodEnabled(id: id)
        } else {
            invalidateLayoutCache()
            savePersistentState()
            onWindowsRebuildNeeded?()
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

    public func currentRailPage(for edge: MountEdge) -> Int {
        edge == .left ? leftRailPage : rightRailPage
    }

    @ObservationIgnored private var isSettingPodPage: Bool = false

    public func setRailPage(_ page: Int, for edge: MountEdge) {
        let clamped = max(page, 0)
        if edge == .left {
            leftRailPage = clamped
        } else {
            rightRailPage = clamped
        }
        if isOnboardingGuideActive && !isSettingPodPage {
            onboardingDidSwitchPage = true
        }
        DiagnosticLogger.shared.info("Store", "Rail page switched: edge=\(edge), page=\(clamped)")
        invalidateLayoutCache()
    }

    public func setPodPage(id: String, pageIndex: Int) {
        guard let idx = pods.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(0, pageIndex)
        let edge = pods[idx].edge
        pods[idx].pageIndex = clamped
        if isOnboardingGuideActive && clamped >= 1 {
            onboardingDidCreatePage = true
        }
        let screenH = max(Double(availableScreenHeight(for: edge)), 600.0)
        let minPt = Double(minimumDrawerHeight(for: id))
        pods[idx].range.length = max(minPt / screenH, 0.10)
        normalizePageRanges(for: edge)
        isSettingPodPage = true
        setRailPage(clamped, for: edge)
        isSettingPodPage = false
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func normalizePageRanges(for edge: MountEdge) {
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
            let avgShare = usableSpan / Double(sortedIndices.count)
            let weights = sortedIndices.map { idx in
                let curLen = pods[idx].range.length
                let effectiveLen = (sortedIndices.count >= 2 && curLen > avgShare * 1.6) ? avgShare : curLen
                return max(effectiveLen, pods[idx].minLength, 0.08)
            }
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
        if isOnboardingGuideActive {
            onboardingDidCreateStack = true
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

    public func detachPodFromMajorGroup(id: String, targetCenterY: Double, totalHeight: Double) {
        guard let initialIdx = pods.firstIndex(where: { $0.id == id }) else { return }
        let edge = pods[initialIdx].edge
        let oldGroupId = pods[initialIdx].majorGroupId
        let originalGroupStart: Double? = {
            guard let gid = oldGroupId else { return nil }
            return pods.filter { $0.edge == edge && $0.isEnabled && $0.majorGroupId == gid }
                .map(\.range.start)
                .min()
        }()

        splitPodFromMajorGroup(id: id)
        guard let idx = pods.firstIndex(where: { $0.id == id }) else { return }

        let safeTotalH = max(totalHeight, 400.0)
        let podLength = pods[idx].range.length
        var newStart = min(
            max((targetCenterY / safeTotalH) - (podLength * 0.5), 0.02),
            max(0.96 - podLength, 0.02)
        )

        if let oldGroupId = oldGroupId {
            let remainingIndices = pods.indices.filter {
                pods[$0].edge == edge && pods[$0].isEnabled && pods[$0].majorGroupId == oldGroupId
            }.sorted { pods[$0].range.start < pods[$1].range.start }

            if remainingIndices.count >= 2 {
                let subGap = 0.004
                var curStart = originalGroupStart ?? pods[remainingIndices[0]].range.start
                for remIdx in remainingIndices {
                    pods[remIdx].range.start = curStart
                    curStart += pods[remIdx].range.length + subGap
                }
                let groupStart = pods[remainingIndices[0]].range.start
                let groupEnd = curStart - subGap
                let groupMid = (groupStart + groupEnd) * 0.5
                if newStart >= groupStart - 0.01 && newStart <= groupEnd + 0.01 {
                    if (targetCenterY / safeTotalH) < groupMid {
                        newStart = max(groupStart - podLength - 0.02, 0.02)
                    } else {
                        newStart = min(groupEnd + 0.02, max(0.96 - podLength, 0.02))
                    }
                }
                if (targetCenterY / safeTotalH) < groupMid && (newStart + podLength + 0.01) > groupStart {
                    var shiftedStart = min(newStart + podLength + 0.015, max(0.94 - (groupEnd - groupStart), 0.04))
                    for remIdx in remainingIndices {
                        pods[remIdx].range.start = shiftedStart
                        shiftedStart += pods[remIdx].range.length + subGap
                    }
                }
            }
        }

        pods[idx].range.start = newStart
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func moveMajorGroup(groupId: String, on edge: MountEdge, newStartRatio: Double) {
        let groupIndices = pods.indices.filter {
            pods[$0].isEnabled && pods[$0].edge == edge && pods[$0].majorGroupId == groupId
        }.sorted { pods[$0].range.start < pods[$1].range.start }
        guard !groupIndices.isEmpty else { return }

        let subGap = 0.004
        let totalSpan = groupIndices.reduce(0.0) { $0 + pods[$1].range.length }
            + Double(max(groupIndices.count - 1, 0)) * subGap
        let clampedStart = min(max(newStartRatio, 0.02), max(0.96 - totalSpan, 0.02))

        var curStart = clampedStart
        for idx in groupIndices {
            pods[idx].range.start = curStart
            curStart += pods[idx].range.length + subGap
        }

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
        userDefaults.set(true, forKey: "purah.didSeedMajorGroups.\(edge.rawValue)")

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

        if isOnboardingGuideActive {
            onboardingDidCreateStack = true
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
        scheduleSavePersistentState()
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

    public func resizeSubPodInMajorGroup(podId: String, on edge: MountEdge, deltaRatio: Double) {
        guard let targetIdx = pods.firstIndex(where: { $0.id == podId && $0.isEnabled && $0.edge == edge }) else { return }
        let minSubRatio = 0.03
        guard let groupId = pods[targetIdx].majorGroupId else {
            let newLen = min(max(pods[targetIdx].range.length + deltaRatio, minSubRatio), 0.85)
            pods[targetIdx].range.length = newLen
            pods[targetIdx].minLength = min(pods[targetIdx].minLength, minSubRatio)
            invalidateLayoutCache()
            scheduleSavePersistentState()
            onWindowsRebuildNeeded?()
            return
        }

        let groupIndices = pods.indices.filter {
            pods[$0].isEnabled && pods[$0].edge == edge && pods[$0].majorGroupId == groupId
        }.sorted { pods[$0].range.start < pods[$1].range.start }

        guard let k = groupIndices.firstIndex(of: targetIdx) else { return }

        if k < groupIndices.count - 1 {
            let curIdx = groupIndices[k]
            let nextIdx = groupIndices[k + 1]
            let curLen = max(pods[curIdx].range.length, minSubRatio)
            let nextLen = max(pods[nextIdx].range.length, minSubRatio)
            let pairSum = curLen + nextLen
            let newCurLen = min(max(curLen + deltaRatio, minSubRatio), max(pairSum - minSubRatio, minSubRatio))
            let newNextLen = max(pairSum - newCurLen, minSubRatio)
            pods[curIdx].range.length = newCurLen
            pods[curIdx].minLength = min(pods[curIdx].minLength, minSubRatio)
            pods[nextIdx].range.length = newNextLen
            pods[nextIdx].minLength = min(pods[nextIdx].minLength, minSubRatio)
        } else {
            let curIdx = groupIndices[k]
            let curLen = max(pods[curIdx].range.length, minSubRatio)
            let newCurLen = min(max(curLen + deltaRatio, minSubRatio), 0.85)
            pods[curIdx].range.length = newCurLen
            pods[curIdx].minLength = min(pods[curIdx].minLength, minSubRatio)
        }

        let subGap = 0.004
        var curStart = pods[groupIndices[0]].range.start
        for idx in groupIndices {
            pods[idx].range.start = curStart
            curStart += pods[idx].range.length + subGap
        }

        invalidateLayoutCache()
        scheduleSavePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func resizeSubPodInMajorGroup(podId: String, on edge: MountEdge, newSubSpanRatio: Double) {
        guard let targetIdx = pods.firstIndex(where: { $0.id == podId && $0.isEnabled && $0.edge == edge }) else { return }
        let currentRatio = max(pods[targetIdx].range.length, 0.03)
        resizeSubPodInMajorGroup(podId: podId, on: edge, deltaRatio: newSubSpanRatio - currentRatio)
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

    public func clusterPods(_ pods: [SlotPod]) -> [[SlotPod]] {
        var clusters: [[SlotPod]] = []
        for pod in pods {
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

    public func majorPodClusters(for edge: MountEdge) -> [[SlotPod]] {
        let railPods = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        return clusterPods(railPods)
    }

    public func isInSharedMajorPod(podId: String) -> Bool {
        guard let pod = pods.first(where: { $0.id == podId && $0.isEnabled }) else { return false }
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
        let isNowPinned: Bool
        if pinnedDrawerItemIds.contains(id) {
            pinnedDrawerItemIds.remove(id)
            isNowPinned = false
        } else {
            pinnedDrawerItemIds.insert(id)
            isNowPinned = true
        }
        DiagnosticLogger.shared.info("Store", "Item pin toggled: id=\(id), isPinned=\(isNowPinned)")
        invalidateLayoutCache()
    }

    public func togglePin(for id: String) {
        togglePinItem(id: id)
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
        DiagnosticLogger.shared.info("Store", "Drawer activated: podId=\(podId), itemId=\(itemId ?? podId)")
        if isGateTelemetryTrackingEnabled {
            onboardingDidTriggerEdgeDrawer = true
            onboardingGateState = .opened
            onboardingGateProgress = 1.0
            onboardingGateCurrentValue = onboardingGateTargetValue
        }
        if isOnboardingGuideActive {
            if onboardingStep == .breathingDemo {
                onboardingBreathingHoveredPods.insert(podId)
            } else if onboardingStep == .decomposeDemo {
                onboardingDidToggleDecompose = true
            }
        }
        if dismissAlertOnHover {
            acknowledgeAllAlerts(forPodId: podId)
            if let itemId {
                acknowledgeAlert(id: itemId)
            }
        }

        let isAlreadyExpanded = (activeDrawerPodId != nil || activeDrawerItemId != nil)
        let targetEdge = pods.first(where: { $0.id == podId })?.edge ?? .right
        let targetItemId = itemId ?? podId
        pendingHoverPodId = podId

        // Overview ↔ chip switches inside one pod play sequenced: the current
        // drawer retracts first, then the next one springs out — the stack-like
        // collapse-then-pop feel. Hover must still be on the pod when the
        // deferred activation fires, or it is dropped.
        let previousItemId = activeDrawerItemId
        // One direction only: N+ → chip retracts first, then the chip drawer
        // springs out. Chip → N+ activates immediately (the merged state
        // already animates the sibling chips away).
        let isOverviewSwitch = previousItemId != nil
            && previousItemId != targetItemId
            && PurahPluginSubItem.isMoreItemsID(previousItemId!)
            && !PurahPluginSubItem.isMoreItemsID(targetItemId)
            && pod(forItemId: previousItemId!)?.id == podId
        if isOverviewSwitch {
            onRequestExpandCanvas?(targetEdge)
            withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                hoveredPodId = podId
                activeDrawerPodId = nil
                activeDrawerItemId = nil
                invalidateLayoutCache()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                guard let self, self.hoveredPodId == podId || self.pendingHoverPodId == podId else { return }
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                    self.activeDrawerPodId = podId
                    self.activeDrawerItemId = targetItemId
                    self.invalidateLayoutCache()
                }
            }
            return
        }

        if isAlreadyExpanded || Self.isTestingEnvironment {
            onRequestExpandCanvas?(targetEdge)
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
                activeDrawerPodId = podId
                activeDrawerItemId = targetItemId
                hoveredPodId = podId
                invalidateLayoutCache()
            }
        } else {
            // Frame 0: Expand NSPanel canvas from 28pt to 580pt WITHOUT any withAnimation transaction!
            // Do NOT mutate hoveredPodId, activeDrawerPodId, or activeDrawerItemId inside withAnimation on Frame 0!
            onRequestExpandCanvas?(targetEdge)

            // Frame 1 (~16ms): Now that NSPanel is 580pt wide and anchored at final screen coordinates:
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.pendingHoverPodId == podId else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    self.hoveredPodId = podId
                    self.activeDrawerPodId = podId
                    self.activeDrawerItemId = targetItemId
                    self.invalidateLayoutCache()
                }
            }
        }
    }

    public func dismissActiveDrawer() {
        DiagnosticLogger.shared.info("Store", "Active drawer dismissed")
        onDismissPreviewPanel?()
        activePreviewScreenFrame = nil
        pendingHoverPodId = nil
        activeDrawerPodId = nil
        activeDrawerItemId = nil
        hoveredPodId = nil
        if isGateTelemetryTrackingEnabled {
            onboardingGateState = .idle
            onboardingGateProgress = 0.0
            onboardingGateCurrentValue = 0
        }
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
    public var activePluginAlertIds: Set<String> = []
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

    /// Alert bookkeeping is keyed by item id and never persisted, so without a
    /// bound these sets grow for every event the user has ever acknowledged
    /// during a session. They are pruned once they exceed this many entries.
    private static let alertIDRetentionLimit = 256

    /// Drops acknowledgements and toast receipts that no longer refer to
    /// anything live: departed calendar events, removed pods, and the fixed
    /// set of vitals metric ids are the only ids worth keeping.
    public func pruneStaleAlertIDs(force: Bool = false) {
        guard force
            || acknowledgedAlertIds.count > Self.alertIDRetentionLimit
            || notifiedToastEventIds.count > Self.alertIDRetentionLimit else { return }
        let liveEventIDs = Set(_calendarEvents.map(\.id))
        let podIDs = Set(pods.map(\.id))
        func isLive(_ id: String) -> Bool {
            liveEventIDs.contains(id) || podIDs.contains(id) || id.hasPrefix("vitals-")
        }
        acknowledgedAlertIds = acknowledgedAlertIds.filter(isLive)
        notifiedToastEventIds = notifiedToastEventIds.filter { liveEventIDs.contains($0) }
    }

    public func acknowledgeAlert(id: String) {
        acknowledgedAlertIds.insert(id)
        pruneStaleAlertIDs()
    }

    public func isAlertAcknowledged(id: String) -> Bool {
        acknowledgedAlertIds.contains(id)
    }

    public func resetAlertAcknowledgment(id: String) {
        acknowledgedAlertIds.remove(id)
    }

    public func setPluginAlert(id: String, isAlerting: Bool) {
        if isAlerting {
            activePluginAlertIds.insert(id)
            acknowledgedAlertIds.remove(id)
        } else {
            activePluginAlertIds.remove(id)
        }
    }

    public func triggerAlert(id: String) {
        setPluginAlert(id: id, isAlerting: true)
    }

    public func isPodAlerting(podId: String) -> Bool {
        if activePluginAlertIds.contains(podId) && !isAlertAcknowledged(id: podId) {
            return true
        }
        if podId == "calendar" {
            if isEventGlowAlertEnabled && alertStyle != .off {
                if _calendarEvents.contains(where: { ($0.isOngoing || $0.isImminent) && !isAlertAcknowledged(id: $0.id) }) {
                    return true
                }
            }
        }
        if podId == "vitals" {
            if alertStyle != .off && !isAlertAcknowledged(id: "vitals") {
                let m = HardwareVitalsService.shared.metrics
                let t = _vitalsThresholds
                if (m.cpuUsage > t.cpuDanger && !isAlertAcknowledged(id: "vitals-cpu")) ||
                   (m.memoryUsage > t.ramDanger && !isAlertAcknowledged(id: "vitals-ram")) {
                    return true
                }
            }
        }
        return false
    }

    public func acknowledgeAllAlerts(forPodId podId: String) {
        acknowledgedAlertIds.insert(podId)
        if podId == "calendar" {
            for event in _calendarEvents where (event.isOngoing || event.isImminent) {
                acknowledgedAlertIds.insert(event.id)
            }
        }
        if podId == "vitals" {
            for metricId in ["vitals-cpu", "vitals-ram", "vitals-gpu", "vitals-power", "vitals-disk", "vitals-network"] {
                acknowledgedAlertIds.insert(metricId)
            }
        }
    }

    /// Returns the set of page indices (0..<pages.count) on `edge` that contain at least one alerting pod.
    public func alertingPageIndices(for edge: MountEdge, totalHeight: Double) -> Set<Int> {
        let pages = paginatedPods(for: edge, totalHeight: totalHeight)
        var result: Set<Int> = []
        for (pIdx, pagePods) in pages.enumerated() {
            if pagePods.contains(where: { isPodAlerting(podId: $0.id) }) {
                result.insert(pIdx)
            }
        }
        return result
    }

    /// Returns the first alerting pod on a non-current page for `edge`, if any.
    public func firstOffPageAlertingPod(for edge: MountEdge, totalHeight: Double) -> (pageIndex: Int, pod: SlotPod)? {
        let pages = paginatedPods(for: edge, totalHeight: totalHeight)
        guard pages.count > 1 else { return nil }
        let curPage = min(max(currentRailPage(for: edge), 0), pages.count - 1)
        for (pIdx, pagePods) in pages.enumerated() where pIdx != curPage {
            if let alertingPod = pagePods.first(where: { isPodAlerting(podId: $0.id) }) {
                return (pIdx, alertingPod)
            }
        }
        return nil
    }

    public func postToastNotification(id: String, message: String) {
        guard isEventToastAlertEnabled, !notifiedToastEventIds.contains(id) else { return }
        notifiedToastEventIds.insert(id)
        pruneStaleAlertIDs()
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

    public var aiMaxRailRoles: Int {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "ai", defaults: userDefaults)
            let val = storage.int(forKey: "maxRailRoles")
            return val > 0 ? min(max(val, 2), 8) : 4
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "ai", defaults: userDefaults)
            storage.set(min(max(newValue, 2), 8), forKey: "maxRailRoles")
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

    public var calendarAlertLeadTime: CalendarAlertLeadTime {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "calendar", defaults: userDefaults)
            return storage.codable(forKey: "alertLeadTime", as: CalendarAlertLeadTime.self) ?? .fifteenMinutes
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "calendar", defaults: userDefaults)
            storage.setCodable(newValue, forKey: "alertLeadTime")
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

    public func standaloneMinimumRailHeight(for podId: String) -> Double {
        if isPodDecomposed(podId), let provider = capabilityProvider(for: podId) {
            return max(Double(provider.decomposedPolicy(store: self).minChipHeight) * 1.5, 72.0)
        }
        return Double(minimumDrawerHeight(for: podId))
    }

    public func preferredDrawerHeight(for podId: String) -> CGFloat {
        let minH = minimumDrawerHeight(for: podId)
        if let pod = pods.first(where: { $0.id == podId }),
           let customPref = pod.preferredExpandedHeight,
           customPref >= Double(minH) {
            return CGFloat(customPref)
        }
        if let provider = capabilityProviders[podId] {
            return max(minH, provider.preferredDrawerHeight(store: self))
        }
        return max(minH * 1.5, 240.0)
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
        let targetScreen: NSScreen? = {
            switch displayTargetMode {
            case .primaryOnly:
                return screens.first
            case .externalOnly:
                return screens.dropFirst().first ?? screens.first
            case .followCursor:
                return NSScreen.main ?? screens.first
            }
        }()
        guard let screen = targetScreen else { return 980.0 }
        return max(screen.visibleFrame.height - 30.0, 400.0)
    }

    public func capacityRatio(for edge: MountEdge) -> Double {
        let avail = availableScreenHeight(for: edge)
        guard avail > 0 else { return 0.0 }
        let required = totalRequiredHeight(for: edge)
        return Double(required / avail)
    }

    public func isBreathingActive(for edge: MountEdge, totalHeight: Double? = nil) -> Bool {
        guard (!isLiveRailEditingMode || isRehearsingBreathingInSculptor) && isDynamicBreathingEnabled else { return false }
        if isAlwaysCompactBreathing { return true }
        let refH = totalHeight ?? lastKnownTotalHeight[edge] ?? max(Double(availableScreenHeight(for: edge)), 600.0)
        let pages = paginatedPods(for: edge, totalHeight: refH)
        guard !pages.isEmpty else { return false }
        let curPage = min(max(currentRailPage(for: edge), 0), pages.count - 1)
        let pagePods = pages[curPage]
        let clusters = clusterPods(pagePods)
        let safeTop = pages.count > 1 ? 48.0 : 16.0
        let safeBottom = pages.count > 1 ? (refH - 48.0) : (refH - 16.0)
        let availableH = max(safeBottom - safeTop, 160.0)
        let clusterGap = 8.0
        let totalClusterGaps = Double(max(clusters.count - 1, 0)) * clusterGap
        let netAvailable = max(availableH - totalClusterGaps, Double(clusters.count) * 24.0)

        let isSculptingRails = isLiveRailEditingMode && !isRehearsingBreathingInSculptor
        let clusterMinFloors: [Double] = clusters.map { cluster in
            if cluster.count == 1 {
                let pod = cluster[0]
                return Double(minimumDrawerHeight(for: pod.id))
            } else {
                let hasManualResize = isSculptingRails || cluster.contains(where: { $0.minLength <= 0.06 })
                return hasManualResize ? max(96.0, Double(cluster.count) * 24.0) : 155.0
            }
        }
        let sumMinRequired = clusterMinFloors.reduce(0.0, +)
        return sumMinRequired > netAvailable
    }

    @ObservationIgnored
    public var onCapacityWarningToast: ((String) -> Void)?
    @ObservationIgnored
    public var onLocalMouseMove: (@MainActor (NSEvent) -> Void)?
    @ObservationIgnored
    public var onPodEnabledChanged: (@MainActor (String, Bool) -> Void)?
    @ObservationIgnored
    public var onWindowsRebuildNeeded: (@MainActor () -> Void)?
    @ObservationIgnored
    public var onRequestExpandCanvas: (@MainActor (MountEdge) -> Void)?
    private var lastCapacityAlertTime: Date?

    public func notifyCapacityWarningIfNeeded() {
        let now = Date()
        if !Self.isTestingEnvironment, let last = lastCapacityAlertTime, now.timeIntervalSince(last) < 6.0 {
            return
        }
        for edge in [MountEdge.left, MountEdge.right] {
            let screenH = max(Double(availableScreenHeight(for: edge)), 600.0)
            let pages = paginatedPods(for: edge, totalHeight: screenH)
            if pages.count > 1 {
                lastCapacityAlertTime = now
                DiagnosticLogger.shared.warn("Store", "Page overflow toast triggered for edge=\(edge)")
                onCapacityWarningToast?("layout.toast.pageOverflow".localized)
                return
            } else if isBreathingActive(for: edge, totalHeight: screenH) {
                lastCapacityAlertTime = now
                DiagnosticLogger.shared.info("Store", "Dynamic breathing mode toast triggered for edge=\(edge)")
                onCapacityWarningToast?("layout.toast.breathingActivated".localized)
                return
            }
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
        if isInSharedMajorPod(podId: id) { return false }
        return capabilityProvider(for: id)?.isDecomposed(store: self) ?? false
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
        let isSculptingRails = isLiveRailEditingMode && !isRehearsingBreathingInSculptor
        let minStandalone = CGFloat(standaloneMinimumRailHeight(for: pod.id))
        let podHeight = max(pod.range.length * totalHeight, minStandalone)
        let isShortened = pod.minLength <= 0.06 && (pod.range.length * totalHeight < Double(minimumDrawerHeight(for: pod.id)) - 1.0)
        if isSculptingRails || isShortened {
            return podHeight
        }
        let minReserved = minimumDrawerHeight(for: pod.id)
        return max(podHeight, minReserved)
    }

    /// Universal rail-slot admission check for decomposed pods. Base knows the
    /// counts (subItemCount vs policy.maxRailItems) — plugins call this before
    /// enabling an entry and reject the enable when it returns false.
    public func canEnableSubItem(for podId: String) -> Bool {
        guard isPodDecomposed(podId), let provider = capabilityProvider(for: podId) else { return true }
        let policy = provider.decomposedPolicy(store: self)
        return provider.subItemCount(store: self) < policy.maxRailItems
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

        if let groupId = item.majorGroupId {
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
        let enabledPods = pods.filter { $0.edge == edge && $0.isEnabled }
        guard !enabledPods.isEmpty else { return [] }

        let signature = enabledPods.map { "\($0.id):\($0.range.start):\($0.range.length):\($0.pageIndex):\($0.majorGroupId ?? ""):\(minimumDrawerHeight(for: $0.id))" }.joined(separator: "|")
        let isSculpting = isLiveRailEditingMode && !isRehearsingBreathingInSculptor
        let now = ProcessInfo.processInfo.systemUptime

        if let cached = cachedPaginatedPods[edge],
           abs(cached.height - totalHeight) < 0.5,
           cached.podsCount == enabledPods.count,
           cached.enabledSignature == signature,
           cached.isDynamicBreathingEnabled == isDynamicBreathingEnabled,
           cached.isSculptingRails == isSculpting,
           (now - cached.timestamp) < 0.05 {
            return cached.pages
        }

        var allEdgePods = enabledPods
            .sorted { (max(0, $0.pageIndex), $0.range.start) < (max(0, $1.pageIndex), $1.range.start) }

        // Ensure pods sharing the same majorGroupId have the same pageIndex (using first member's pageIndex)
        var groupPageMap: [String: Int] = [:]
        for pod in allEdgePods {
            if let gid = pod.majorGroupId, groupPageMap[gid] == nil {
                groupPageMap[gid] = max(0, pod.pageIndex)
            }
        }
        for i in allEdgePods.indices {
            if let gid = allEdgePods[i].majorGroupId, let pIdx = groupPageMap[gid] {
                allEdgePods[i].pageIndex = pIdx
            }
        }
        allEdgePods.sort { (max(0, $0.pageIndex), $0.range.start) < (max(0, $1.pageIndex), $1.range.start) }

        let explicitGroups = Dictionary(grouping: allEdgePods, by: { max(0, $0.pageIndex) })
        let sortedPageKeys = explicitGroups.keys.sorted()

        let pageBudget = max(totalHeight - 96.0, 260.0)
        var pages: [[SlotPod]] = []

        for pageKey in sortedPageKeys {
            guard let rawPagePods = explicitGroups[pageKey], !rawPagePods.isEmpty else { continue }
            let pagePods = rawPagePods.sorted { $0.range.start < $1.range.start }
            let clusters = clusterPods(pagePods)

            var currentPage: [SlotPod] = []
            var currentHeight: Double = 0.0

            for cluster in clusters {
                let clusterNeeded: Double
                if !isDynamicBreathingEnabled {
                    if cluster.count >= 2 {
                        let hasManual = (isLiveRailEditingMode && !isRehearsingBreathingInSculptor) || cluster.contains(where: { $0.minLength <= 0.06 && ($0.range.length * totalHeight < Double(minimumDrawerHeight(for: $0.id)) - 1.0) })
                        clusterNeeded = hasManual ? max(96.0, Double(cluster.count) * 24.0) : max(155.0, Double(cluster.count) * 48.0)
                    } else {
                        let pod = cluster[0]
                        let isSculpting = isLiveRailEditingMode && !isRehearsingBreathingInSculptor
                        let isShortened = pod.minLength <= 0.06 && (pod.range.length * totalHeight < Double(minimumDrawerHeight(for: pod.id)) - 1.0)
                        clusterNeeded = (isSculpting || isShortened) ? standaloneMinimumRailHeight(for: pod.id) : Double(minimumDrawerHeight(for: pod.id))
                    }
                } else {
                    if cluster.count >= 2 {
                        clusterNeeded = Double(cluster.count) * 26.0
                    } else {
                        clusterNeeded = 42.0
                    }
                }

                let addition = currentPage.isEmpty ? clusterNeeded : (clusterNeeded + 8.0)
                if !currentPage.isEmpty && (currentHeight + addition) > (pageBudget + 0.5) {
                    pages.append(currentPage)
                    currentPage = cluster
                    currentHeight = clusterNeeded
                } else {
                    currentPage.append(contentsOf: cluster)
                    currentHeight += addition
                }
            }

            if !currentPage.isEmpty {
                pages.append(currentPage)
            }
        }

        cachedPaginatedPods[edge] = PaginationCacheEntry(
            height: totalHeight,
            podsCount: enabledPods.count,
            enabledSignature: signature,
            isDynamicBreathingEnabled: isDynamicBreathingEnabled,
            isSculptingRails: isSculpting,
            pages: pages,
            timestamp: now
        )
        return pages
    }

    private struct PaginationCacheEntry {
        let height: Double
        let podsCount: Int
        let enabledSignature: String
        let isDynamicBreathingEnabled: Bool
        let isSculptingRails: Bool
        let pages: [[SlotPod]]
        let timestamp: Double
    }

    @ObservationIgnored
    private var cachedPaginatedPods: [MountEdge: PaginationCacheEntry] = [:]

    private struct LayoutCacheEntry {
        let height: Double
        let podsCount: Int
        let enabledSignature: String
        let isDynamicBreathingEnabled: Bool
        let isAlwaysCompactBreathing: Bool
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
        cachedPaginatedPods.removeAll()
    }

    public func recalculateLayout() {
        invalidateLayoutCache()
        onWindowsRebuildNeeded?()
    }

    /// Sub-item heights for an expanded decomposed pod.
    ///
    /// Only the chip under the cursor may grow. Every other chip keeps the exact
    /// height it had while docked, which means the active chip's top edge stays
    /// put (all preceding chips and gaps are unchanged) and the pod grows
    /// downward into its neighbours. The previous implementation split the
    /// pod's preferred height evenly across *all* chips, so hovering a lower
    /// chip shoved it a hundred points down the rail and the drawer appeared to
    /// spring out of the middle of the pod.
    private func calculateExpandedSubSpans(
        for cluster: [SlotPod],
        expandedSpan: Double,
        idleSpan: Double,
        activeIndex: Int,
        subGap: Double = 3.0
    ) -> [Double] {
        let idleSpans = calculateSubSpans(for: cluster, clusterSpan: idleSpan, subGap: subGap)
        guard cluster.indices.contains(activeIndex) else { return idleSpans }

        var spans = idleSpans
        let otherGaps = subGap * Double(max(cluster.count - 1, 0))
        let othersSum = idleSpans.enumerated().reduce(0.0) { acc, pair in
            pair.offset == activeIndex ? acc : acc + pair.element
        }
        // Everything the pod did not spend on neighbours goes to the hovered chip.
        spans[activeIndex] = max(expandedSpan - othersSum - otherGaps, idleSpans[activeIndex])
        return spans
    }

    /// Chip positions for one decomposed pod.
    ///
    /// `expandedSpan` is the pod's span while its drawer is open; pass the idle
    /// span when nothing is expanded. The active chip is reported with its
    /// expanded card height and an unchanged `top`, so the drawer extrudes from
    /// the chip the cursor is actually over.
    public func resolvedChipSlots(
        for pod: SlotPod,
        startY: Double,
        idleSpan: Double,
        expandedSpan: Double,
        totalHeight: Double,
        isDynamicAccordion: Bool
    ) -> [PodChipSlot] {
        guard !isSharedMajorSubBar(for: pod.id),
              isPodDecomposed(pod.id),
              let provider = capabilityProvider(for: pod.id) else { return [] }

        let rawCount = provider.subItemCount(store: self)
        guard rawCount > 0, !_isMergedOverviewActive(inPodId: pod.id) else { return [] }

        let policy = provider.decomposedPolicy(store: self)
        let spacing = Double(policy.spacing)
        // Cap by the real item count; while breathing, every item is shown even
        // if the pod is squeezed below its ergonomic floor.
        let fitCount = policy.visibleChipCount(in: idleSpan, isDynamicAccordion: isDynamicAccordion)
        let rawVisible = isDynamicAccordion
            ? min(rawCount, fitCount)
            : min(rawCount, max(policy.maxRailItems, 1))
        let count = max(rawVisible, 1)

        let chipH = Double(policy.chipHeight(in: idleSpan, chipCount: count, isDynamicAccordion: isDynamicAccordion))

        let activeIdx: Int? = (0..<count).first { idx in
            guard let subId = subItemId(provider: provider, pod: pod, index: idx, rawCount: rawCount, count: count, policy: policy) else { return false }
            return subId == activeDrawerItemId || isItemPinned(id: subId)
        }

        var heights = [Double](repeating: chipH, count: count)
        var tops = [Double](repeating: 0, count: count)
        for i in 0..<count {
            tops[i] = startY + Double(i) * (chipH + spacing)
        }
        if let h = activeIdx {
            // Only this chip absorbs the pod's expanded height; neighbours keep
            // the exact height they had while docked. Because every preceding
            // chip and gap is untouched, `tops[h]` (and everything above it) is
            // unchanged, so the card extrudes from under the cursor instead of
            // being pushed down the rail.
            let otherChips = chipH * Double(count - 1)
            let gaps = spacing * Double(max(count - 1, 0))
            let grown = max(expandedSpan - otherChips - gaps, Double(policy.expandedCardHeight(chipH: CGFloat(chipH))))
            heights[h] = grown
            // Every chip below slides down by exactly the active chip's growth.
            let growth = grown - chipH
            if h + 1 < count {
                for i in (h + 1)..<count {
                    tops[i] += growth
                }
            }
        }

        return (0..<count).compactMap { idx in
            guard let subId = subItemId(
                provider: provider, pod: pod, index: idx,
                rawCount: rawCount, count: count, policy: policy
            ) else { return nil }
            return PodChipSlot(
                id: subId,
                top: tops[idx],
                height: heights[idx],
                isActive: idx == activeIdx,
                cardHeight: heights[idx]
            )
        }
    }

    /// Chip slots for pods whose solver pass produced none (shared major bars).
    private func fallbackChipSlots(
        for item: ResolvedPodLayoutItem,
        provider: any PurahPodCapabilityProvider,
        edge: MountEdge,
        totalHeight: Double
    ) -> [PodChipSlot] {
        let policy = provider.decomposedPolicy(store: self)
        let isDynamicAccordion = isBreathingActive(for: edge, totalHeight: totalHeight)
        let count = policy.visibleChipCount(in: item.spanH, isDynamicAccordion: isDynamicAccordion)
        let rawCount = provider.subItemCount(store: self)
        let chipH = Double(policy.chipHeight(in: item.spanH, chipCount: count, isDynamicAccordion: isDynamicAccordion))
        let spacing = Double(policy.spacing)
        return (0..<count).compactMap { idx in
            guard let subId = subItemId(
                provider: provider, pod: item.pod, index: idx,
                rawCount: rawCount, count: count, policy: policy
            ) else { return nil }
            let isActive = activeDrawerItemId == subId || isItemPinned(id: subId)
            return PodChipSlot(
                id: subId,
                top: item.startY + Double(idx) * (chipH + spacing),
                height: chipH,
                isActive: isActive,
                cardHeight: isActive ? Double(policy.expandedCardHeight(chipH: CGFloat(chipH))) : chipH
            )
        }
    }

    /// Resolves a rail chip's sub-item id, mirroring the smart-fold capsule rule.
    private func subItemId(
        provider: any PurahPodCapabilityProvider,
        pod: SlotPod,
        index: Int,
        rawCount: Int,
        count: Int,
        policy: PurahDecomposedPolicy
    ) -> String? {
        let isSmartFoldSlot = policy.overflowStrategy == .smartFold
            && rawCount > count
            && count >= 2
            && index == count - 1
        if isSmartFoldSlot { return "\(pod.id)_more_items" }
        return provider.subItemId(at: index, store: self)
    }

    private func _isMergedOverviewActive(inPodId podId: String) -> Bool {
        guard let activeDrawerItemId, PurahPluginSubItem.isMoreItemsID(activeDrawerItemId) else { return false }
        return pod(forItemId: activeDrawerItemId)?.id == podId
    }

    private func isSharedMajorSubBar(for podId: String) -> Bool {
        guard let pod = pods.first(where: { $0.id == podId }) else { return false }
        guard let gid = pod.majorGroupId else { return false }
        return pods.contains { $0.isEnabled && $0.edge == pod.edge && $0.majorGroupId == gid && $0.id != podId }
    }

    private func calculateSubSpans(for cluster: [SlotPod], clusterSpan: Double, subGap: Double = 3.0) -> [Double] {
        let m = cluster.count
        guard m > 0 else { return [] }
        let totalSubGaps = Double(max(m - 1, 0)) * subGap
        let minSubFloor = min(28.0, max((clusterSpan - totalSubGaps) / Double(max(m, 1)), 18.0))
        let netSubSpan = max(clusterSpan - totalSubGaps, Double(m) * minSubFloor)
        let subWeights = cluster.map { max($0.range.length, 0.025) }
        let subWeightSum = max(subWeights.reduce(0.0, +), 0.0001)

        var subSpans: [Double] = subWeights.map { weight in
            max(netSubSpan * (weight / subWeightSum), minSubFloor)
        }
        let subSum = subSpans.reduce(0.0, +)
        if subSum > netSubSpan && subSum > 0 {
            let excess = subSum - netSubSpan
            let slackIndices = subSpans.indices.filter { subSpans[$0] > minSubFloor + 0.01 }
            let totalSlack = slackIndices.reduce(0.0) { $0 + (subSpans[$1] - minSubFloor) }
            if totalSlack >= excess && totalSlack > 0 {
                for idx in slackIndices {
                    let itemSlack = subSpans[idx] - minSubFloor
                    subSpans[idx] -= excess * (itemSlack / totalSlack)
                }
            } else {
                let s = netSubSpan / subSum
                subSpans = subSpans.map { max($0 * s, 18.0) }
            }
        }
        return subSpans
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

        if let cached = cachedResolvedLayouts[edge],
           abs(cached.height - totalHeight) < 0.5,
           cached.podsCount == allEdgePods.count,
           cached.enabledSignature == signature,
           cached.isDynamicBreathingEnabled == isDynamicBreathingEnabled,
           cached.isAlwaysCompactBreathing == isAlwaysCompactBreathing,
           cached.hoveredPodId == hoveredPodId,
           cached.activePodId == activeDrawerPodId,
           cached.activeItemId == activeDrawerItemId,
           cached.pinnedIds == pinnedDrawerItemIds,
           cached.page == curPage,
           (now - cached.timestamp) < 0.05 {
            return cached.items
        }

        let pages = paginatedPods(for: edge, totalHeight: totalHeight)
        guard !pages.isEmpty else { return [] }

        let pageIdx = min(max(curPage, 0), pages.count - 1)
        let pagePods = pages[pageIdx]
        guard !pagePods.isEmpty else { return [] }

        let isSculptingRails = isLiveRailEditingMode && !isRehearsingBreathingInSculptor
        let safeTop = isSculptingRails ? 72.0 : (pages.count > 1 ? 48.0 : 16.0)
        let safeBottom = pages.count > 1 ? (totalHeight - 48.0) : (totalHeight - 16.0)
        let availableH = max(safeBottom - safeTop, 160.0)

        let clusters = clusterPods(pagePods)
        guard !clusters.isEmpty else { return [] }

        var standardSpans: [Double] = []
        var clusterMaxVisuals: [Double] = []
        var clusterMinFloors: [Double] = []

        for (_, cluster) in clusters.enumerated() {
            if cluster.count == 1 {
                let pod = cluster[0]
                let isShortened = pod.minLength <= 0.06 && (pod.range.length * totalHeight < Double(minimumDrawerHeight(for: pod.id)) - 1.0)
                let minFloor = (isSculptingRails || isShortened) ? standaloneMinimumRailHeight(for: pod.id) : Double(minimumDrawerHeight(for: pod.id))
                let maxVis = maxVisualHeight(for: pod.id, totalHeight: totalHeight)
                let span = min(max(pod.range.length * totalHeight, minFloor), max(maxVis, minFloor))
                standardSpans.append(span)
                clusterMaxVisuals.append(max(maxVis, minFloor))
                clusterMinFloors.append(minFloor)
            } else {
                let subGap = 3.0
                let totalSubGaps = Double(cluster.count - 1) * subGap
                let sumSubLengths = cluster.reduce(0.0) { $0 + max($1.range.length * totalHeight, 22.0) } + totalSubGaps
                let hasManualResize = isSculptingRails || cluster.contains(where: { $0.minLength <= 0.06 && ($0.range.length * totalHeight < Double(minimumDrawerHeight(for: $0.id)) - 1.0) })
                let clusterMinFloor = hasManualResize ? max(96.0, Double(cluster.count) * 24.0) : 155.0
                let span = max(sumSubLengths, clusterMinFloor)
                standardSpans.append(span)
                let maxVis = max(cluster.reduce(0.0) { $0 + maxVisualHeight(for: $1.id, totalHeight: totalHeight) } + totalSubGaps, span)
                clusterMaxVisuals.append(maxVis)
                clusterMinFloors.append(clusterMinFloor)
            }
        }

        let clusterGap = 8.0
        let totalClusterGaps = Double(max(clusters.count - 1, 0)) * clusterGap
        let netAvailable = max(availableH - totalClusterGaps, Double(clusters.count) * 24.0)
        let sumStandard = standardSpans.reduce(0.0, +)
        let sumMinRequired = clusters.reduce(0.0) { acc, cluster in
            if cluster.count == 1 {
                return acc + Double(minimumDrawerHeight(for: cluster[0].id))
            } else {
                let hasManualResize = isSculptingRails || cluster.contains(where: { $0.minLength <= 0.06 })
                return acc + (hasManualResize ? max(96.0, Double(cluster.count) * 24.0) : 155.0)
            }
        }
        let isBreathingActiveOnPage = (!isLiveRailEditingMode || isRehearsingBreathingInSculptor) && isDynamicBreathingEnabled && (isAlwaysCompactBreathing || sumMinRequired > netAvailable)

        let clusterWeights = clusters.map { cl in cl.reduce(0.0) { $0 + max($1.range.length, 0.035) } }

        var clusterSpans = Array(repeating: 0.0, count: clusters.count)
        var clusterStartYs = Array(repeating: 0.0, count: clusters.count)

        let expandedFlags = clusters.map { cl in cl.contains(where: { isPodExpanded($0) }) }
        let expandedCount = expandedFlags.filter { $0 }.count

        var preferredExpandedSpans: [Double] = []
        for (cIdx, cluster) in clusters.enumerated() {
            if cluster.count == 1 {
                let pod = cluster[0]
                let pref = Double(preferredDrawerHeight(for: pod.id))
                preferredExpandedSpans.append(max(pref, clusterMaxVisuals[cIdx]))
            } else {
                let activeSub = cluster.first(where: { isPodExpanded($0) }) ?? cluster[0]
                let pref = Double(preferredDrawerHeight(for: activeSub.id))
                preferredExpandedSpans.append(max(pref, 180.0))
            }
        }

        let hasExpandingCluster = clusters.indices.contains(where: { idx in
            expandedFlags[idx] && preferredExpandedSpans[idx] > standardSpans[idx]
        })
        _ = hasExpandingCluster

        var idleClusterSpans: [Double] = []
        var idleClusterStartYs: [Double] = []
        let primaryHoveredId = hoveredPodId ?? activeDrawerPodId ?? activePod?.id
        var anchorIdx = 0
        if expandedCount > 0 {
            anchorIdx = clusters.indices.first(where: { idx in
                expandedFlags[idx] && clusters[idx].contains(where: { $0.id == primaryHoveredId })
            }) ?? expandedFlags.firstIndex(of: true) ?? 0
        }

        if isBreathingActiveOnPage {
            if isAlwaysCompactBreathing {
                idleClusterSpans = clusters.indices.map { cIdx in
                    min(standardSpans[cIdx], max(42.0, Double(clusters[cIdx].count) * 28.0))
                }
                let sumIdle = idleClusterSpans.reduce(0.0, +)
                if sumIdle > netAvailable && sumIdle > 0 {
                    let scale = netAvailable / sumIdle
                    idleClusterSpans = idleClusterSpans.enumerated().map { idx, val in
                        max(val * scale, max(20.0, Double(clusters[idx].count) * 20.0))
                    }
                }
            } else if sumStandard > netAvailable {
                let avgSlotH = netAvailable / Double(max(clusters.count, 1))
                let lockedMask = clusters.indices.map { i in
                    clusters[i].count == 1 && clusters[i][0].minLength <= 0.06 && standardSpans[i] <= avgSlotH
                }
                let lockedSum = clusters.indices.reduce(0.0) { acc, i in
                    acc + (lockedMask[i] ? standardSpans[i] : 0.0)
                }
                let scalableSum = sumStandard - lockedSum
                let remainingAvailable = max(netAvailable - lockedSum, 20.0)
                if scalableSum > remainingAvailable && scalableSum > 0 {
                    let scale = remainingAvailable / scalableSum
                    idleClusterSpans = clusters.indices.map { i in
                        if lockedMask[i] { return standardSpans[i] }
                        let floor = max(20.0, Double(clusters[i].count) * 20.0)
                        return max(standardSpans[i] * scale, floor)
                    }
                } else {
                    let scale = netAvailable / sumStandard
                    idleClusterSpans = clusters.indices.map { i in
                        let floor = max(20.0, Double(clusters[i].count) * 20.0)
                        return max(standardSpans[i] * scale, floor)
                    }
                }
            } else {
                idleClusterSpans = standardSpans
            }

            if !isAlwaysCompactBreathing {
                let sumIdle = idleClusterSpans.reduce(0.0, +)
                if sumIdle > 0 && abs(sumIdle - netAvailable) > 0.001 {
                    let scale = netAvailable / sumIdle
                    idleClusterSpans = idleClusterSpans.map { $0 * scale }
                }
            }

            idleClusterStartYs = []
            if !isAlwaysCompactBreathing || sumStandard > netAvailable || isAlwaysCompactBreathing {
                var curY = safeTop
                for span in idleClusterSpans {
                    idleClusterStartYs.append(curY)
                    curY += span + clusterGap
                }
            } else {
                var curY = safeTop
                for cIdx in 0..<clusters.count {
                    let desired = clusters[cIdx][0].range.start * totalHeight
                    let startY = max(desired, curY)
                    idleClusterStartYs.append(startY)
                    curY = startY + idleClusterSpans[cIdx] + clusterGap
                }
                if let lastStart = idleClusterStartYs.last, let lastSpan = idleClusterSpans.last {
                    let overflow = (lastStart + lastSpan) - safeBottom
                    if overflow > 0 {
                        var targetBottom = safeBottom
                        for cIdx in stride(from: clusters.count - 1, through: 0, by: -1) {
                            let maxAllowed = targetBottom - idleClusterSpans[cIdx]
                            idleClusterStartYs[cIdx] = min(idleClusterStartYs[cIdx], maxAllowed)
                            targetBottom = idleClusterStartYs[cIdx] - clusterGap
                        }
                    }
                }
                for cIdx in 0..<clusters.count {
                    if cIdx == 0 {
                        idleClusterStartYs[cIdx] = max(idleClusterStartYs[cIdx], safeTop)
                    } else {
                        idleClusterStartYs[cIdx] = max(idleClusterStartYs[cIdx], idleClusterStartYs[cIdx - 1] + idleClusterSpans[cIdx - 1] + clusterGap)
                    }
                }
            }

            let fullClusterSpans: [Double] = clusters.indices.map { cIdx in
                if clusters[cIdx].count == 1 {
                    let pod = clusters[cIdx][0]
                    return max(idleClusterSpans[cIdx], Double(preferredDrawerHeight(for: pod.id)))
                } else {
                    let activeSub = clusters[cIdx].first(where: { isPodExpanded($0) }) ?? clusters[cIdx][0]
                    return max(idleClusterSpans[cIdx], Double(preferredDrawerHeight(for: activeSub.id)), 180.0)
                }
            }

            if expandedCount == 0 {
                clusterSpans = idleClusterSpans
                clusterStartYs = idleClusterStartYs
            } else {
                if expandedCount == 1 {
                    let aboveCount = anchorIdx
                    let belowCount = clusters.count - 1 - anchorIdx
                    let minAboveSpace = (0..<aboveCount).reduce(0.0) { $0 + max(18.0, Double(clusters[$1].count) * 18.0) + clusterGap }
                    let minBelowSpace = ((anchorIdx + 1)..<clusters.count).reduce(0.0) { $0 + max(18.0, Double(clusters[$1].count) * 18.0) + clusterGap }
                    let maxSingleSpan = max(availableH - minAboveSpace - minBelowSpace, 160.0)
                    let anchorSpan = min(max(fullClusterSpans[anchorIdx], idleClusterSpans[anchorIdx]), maxSingleSpan)

                    clusterSpans[anchorIdx] = anchorSpan

                    let idleTop = idleClusterStartYs[anchorIdx]
                    let idleBottom = idleTop + idleClusterSpans[anchorIdx]
                    let idleCenter = (idleTop + idleBottom) * 0.5
                    var idealAnchorStart = idleCenter - (anchorSpan * 0.5)
                    if idealAnchorStart > idleTop { idealAnchorStart = idleTop }
                    if idealAnchorStart + anchorSpan < idleBottom { idealAnchorStart = idleBottom - anchorSpan }
                    let minAllowedAnchorStart = safeTop + minAboveSpace
                    let maxAllowedAnchorStart = max(minAllowedAnchorStart, safeBottom - anchorSpan - minBelowSpace)
                    var anchorStartY = min(max(idealAnchorStart, minAllowedAnchorStart), maxAllowedAnchorStart)

                    if clusters[anchorIdx].count >= 2,
                       let hoveredSubIdx = clusters[anchorIdx].firstIndex(where: { $0.id == primaryHoveredId }) {
                        let subGap = 3.0
                        let idleSubSpans = calculateSubSpans(for: clusters[anchorIdx], clusterSpan: idleClusterSpans[anchorIdx], subGap: subGap)
                        let expSubSpans = calculateSubSpans(for: clusters[anchorIdx], clusterSpan: anchorSpan, subGap: subGap)

                        let idleSubOffset = (0..<hoveredSubIdx).reduce(0.0) { $0 + idleSubSpans[$1] + subGap }
                        let idleSubStartY = idleTop + idleSubOffset
                        let idleSubEndY = idleSubStartY + idleSubSpans[hoveredSubIdx]

                        let expSubOffset = (0..<hoveredSubIdx).reduce(0.0) { $0 + expSubSpans[$1] + subGap }
                        let expSubSpan = expSubSpans[hoveredSubIdx]

                        let maxAnchorForHover = idleSubStartY - expSubOffset
                        let minAnchorForHover = idleSubEndY - expSubOffset - expSubSpan
                        if minAnchorForHover <= maxAnchorForHover {
                            anchorStartY = min(max(anchorStartY, minAnchorForHover), maxAnchorForHover)
                        }
                        anchorStartY = min(max(anchorStartY, minAllowedAnchorStart), maxAllowedAnchorStart)
                    }

                    clusterStartYs[anchorIdx] = anchorStartY

                    if aboveCount > 0 {
                        let aboveGaps = Double(max(aboveCount - 1, 0)) * clusterGap
                        let minAboveSum = (0..<aboveCount).reduce(0.0) { $0 + max(18.0, Double(clusters[$1].count) * 18.0) }
                        let aboveNetSpace = max(anchorStartY - clusterGap - safeTop - aboveGaps, minAboveSum)
                        let idleAboveSum = (0..<aboveCount).reduce(0.0) { $0 + idleClusterSpans[$1] }

                        if idleAboveSum <= aboveNetSpace {
                            let aboveSpans = (0..<aboveCount).map { idleClusterSpans[$0] }
                            var curY = safeTop
                            for i in 0..<aboveCount {
                                clusterSpans[i] = aboveSpans[i]
                                let remainingNeeded = ((i + 1)..<aboveCount).reduce(0.0) { $0 + aboveSpans[$1] + clusterGap } + aboveSpans[i]
                                let targetY = min(max(idleClusterStartYs[i], curY), anchorStartY - clusterGap - remainingNeeded)
                                clusterStartYs[i] = targetY
                                curY = targetY + aboveSpans[i] + clusterGap
                            }
                        } else {
                            let scale = aboveNetSpace / max(idleAboveSum, 0.0001)
                            var aboveSpans = (0..<aboveCount).map { i in
                                let minH = max(18.0, Double(clusters[i].count) * 18.0)
                                return max(idleClusterSpans[i] * scale, minH)
                            }
                            let currentSum = aboveSpans.reduce(0.0, +)
                            if currentSum > aboveNetSpace && currentSum > 0 {
                                let secondScale = aboveNetSpace / currentSum
                                aboveSpans = aboveSpans.map { $0 * secondScale }
                            }
                            var curY = safeTop
                            for i in 0..<aboveCount {
                                clusterSpans[i] = aboveSpans[i]
                                clusterStartYs[i] = curY
                                curY += aboveSpans[i] + clusterGap
                            }
                        }
                    }

                    if belowCount > 0 {
                        let belowStart = anchorStartY + anchorSpan + clusterGap
                        let belowIndices = Array((anchorIdx + 1)..<clusters.count)
                        let belowGaps = Double(max(belowCount - 1, 0)) * clusterGap
                        let minBelowSum = belowIndices.reduce(0.0) { $0 + max(18.0, Double(clusters[$1].count) * 18.0) }
                        let belowNetSpace = max(safeBottom - belowStart - belowGaps, minBelowSum)
                        let idleBelowSum = belowIndices.reduce(0.0) { $0 + idleClusterSpans[$1] }

                        if idleBelowSum <= belowNetSpace {
                            let belowSpans = belowIndices.map { idleClusterSpans[$0] }
                            var curY = belowStart
                            for (offset, cI) in belowIndices.enumerated() {
                                clusterSpans[cI] = belowSpans[offset]
                                clusterStartYs[cI] = max(idleClusterStartYs[cI], curY)
                                curY = clusterStartYs[cI] + clusterSpans[cI] + clusterGap
                            }
                        } else {
                            let scale = belowNetSpace / max(idleBelowSum, 0.0001)
                            var belowSpans = belowIndices.map { cI in
                                let minH = max(18.0, Double(clusters[cI].count) * 18.0)
                                return max(idleClusterSpans[cI] * scale, minH)
                            }
                            let currentSum = belowSpans.reduce(0.0, +)
                            if currentSum > belowNetSpace && currentSum > 0 {
                                let secondScale = belowNetSpace / currentSum
                                belowSpans = belowSpans.map { $0 * secondScale }
                            }
                            var curY = belowStart
                            for (offset, cI) in belowIndices.enumerated() {
                                clusterSpans[cI] = belowSpans[offset]
                                clusterStartYs[cI] = curY
                                curY += belowSpans[offset] + clusterGap
                            }
                        }
                    }
                } else {
                    let idleReserved = clusters.indices.filter { !expandedFlags[$0] }
                        .reduce(0.0) { $0 + max(18.0, Double(clusters[$1].count) * 18.0) }
                    let expandedBudget = max(netAvailable - idleReserved, 160.0)
                    var remainingExpandedBudget = expandedBudget
                    var otherExpandedIndices: [Int] = []

                    for idx in clusters.indices where expandedFlags[idx] {
                        if idx == anchorIdx {
                            let granted = min(max(fullClusterSpans[idx], 120.0), expandedBudget * 0.55)
                            clusterSpans[idx] = max(granted, 110.0)
                            remainingExpandedBudget = max(expandedBudget - clusterSpans[idx], 90.0)
                        } else {
                            otherExpandedIndices.append(idx)
                        }
                    }
                    if !otherExpandedIndices.isEmpty {
                        let share = remainingExpandedBudget / Double(otherExpandedIndices.count)
                        for idx in otherExpandedIndices {
                            clusterSpans[idx] = max(share, 110.0)
                        }
                    }
                    for idx in clusters.indices where !expandedFlags[idx] {
                        clusterSpans[idx] = max(18.0, Double(clusters[idx].count) * 18.0)
                    }
                    let minSumSpans = clusterSpans.reduce(0.0, +)
                    if minSumSpans > netAvailable && minSumSpans > 0 {
                        let scale = netAvailable / minSumSpans
                        clusterSpans = clusterSpans.map { $0 * scale }
                    } else {
                        let totalSlack = max(netAvailable - minSumSpans, 0.0)
                        let idleIndices = clusters.indices.filter { !expandedFlags[$0] }
                        if !idleIndices.isEmpty {
                            let idleWeightSum = max(idleIndices.reduce(0.0) { $0 + clusterWeights[$1] }, 0.0001)
                            for idx in idleIndices {
                                clusterSpans[idx] += totalSlack * (clusterWeights[idx] / idleWeightSum)
                            }
                        }
                    }
                    var curY = safeTop
                    for i in 0..<clusters.count {
                        clusterStartYs[i] = curY
                        curY += clusterSpans[i] + clusterGap
                    }
                }
            }
        } else {
            clusterSpans = standardSpans
            if sumStandard > netAvailable && sumStandard > 0 {
                if sumMinRequired <= netAvailable {
                    let availableExtra = max(netAvailable - sumMinRequired, 0.0)
                    let currentExtra = zip(standardSpans, clusterMinFloors).reduce(0.0) { $0 + max($1.0 - $1.1, 0.0) }
                    if currentExtra > 0 {
                        let extraScale = availableExtra / currentExtra
                        clusterSpans = zip(standardSpans, clusterMinFloors).map { std, floor in
                            floor + max(std - floor, 0.0) * extraScale
                        }
                    } else {
                        clusterSpans = clusterMinFloors
                    }
                    let currentSum = clusterSpans.reduce(0.0, +)
                    if currentSum > 0 && abs(currentSum - netAvailable) > 0.001 {
                        let scale = netAvailable / currentSum
                        clusterSpans = clusterSpans.map { $0 * scale }
                    }
                } else {
                    let scale = netAvailable / sumStandard
                    clusterSpans = standardSpans.map { $0 * scale }
                }
            }
            if sumStandard > netAvailable {
                var curY = safeTop
                for cIdx in 0..<clusters.count {
                    clusterStartYs[cIdx] = curY
                    curY += clusterSpans[cIdx] + clusterGap
                }
            } else {
                var curY = safeTop
                for cIdx in 0..<clusters.count {
                    let desired = clusters[cIdx][0].range.start * totalHeight
                    let startY = max(desired, curY)
                    clusterStartYs[cIdx] = startY
                    curY = startY + clusterSpans[cIdx] + clusterGap
                }
                if let lastStart = clusterStartYs.last, let lastSpan = clusterSpans.last {
                    let overflow = (lastStart + lastSpan) - safeBottom
                    if overflow > 0 {
                        var targetBottom = safeBottom
                        for cIdx in stride(from: clusters.count - 1, through: 0, by: -1) {
                            let maxAllowed = targetBottom - clusterSpans[cIdx]
                            clusterStartYs[cIdx] = min(clusterStartYs[cIdx], maxAllowed)
                            targetBottom = clusterStartYs[cIdx] - clusterGap
                        }
                    }
                }
                for cIdx in 0..<clusters.count {
                    if cIdx == 0 {
                        clusterStartYs[cIdx] = max(clusterStartYs[cIdx], safeTop)
                    } else {
                        clusterStartYs[cIdx] = max(clusterStartYs[cIdx], clusterStartYs[cIdx - 1] + clusterSpans[cIdx - 1] + clusterGap)
                    }
                }
            }
        }

        var result: [ResolvedPodLayoutItem] = []
        for (cIdx, cluster) in clusters.enumerated() {
            let clusterY = clusterStartYs[cIdx]
            let clusterSpan = clusterSpans[cIdx]
            if cluster.count == 1 {
                let pod = cluster[0]
                // Decomposed pods: resolve one chip per visible sub-item so the
                // hovered chip stays exactly where the cursor found it and only
                // that chip grows. Idle span comes from the same solver pass so
                // top-of-pod anchoring is stable.
                let idleSpan = idleClusterSpans.indices.contains(cIdx) ? idleClusterSpans[cIdx] : clusterSpan
                let slots = resolvedChipSlots(
                    for: pod,
                    startY: clusterY,
                    idleSpan: idleSpan,
                    expandedSpan: clusterSpan,
                    totalHeight: totalHeight,
                    isDynamicAccordion: isBreathingActiveOnPage
                )
                result.append(
                    ResolvedPodLayoutItem(
                        pod: pod,
                        startY: clusterY,
                        spanH: clusterSpan,
                        drawerStartY: clusterY,
                        drawerSpanH: clusterSpan,
                        majorGroupId: nil,
                        chipSlots: slots
                    )
                )
            } else {
                let gid = cluster.first?.majorGroupId ?? "major_\(edge.rawValue)_\(cIdx)"
                let subGap = 3.0
                var subSpans = calculateSubSpans(for: cluster, clusterSpan: clusterSpan, subGap: subGap)

                if isBreathingActiveOnPage && expandedFlags[cIdx] && cIdx == anchorIdx,
                   let hoveredSubIdx = cluster.firstIndex(where: { $0.id == primaryHoveredId }) {
                    let idleSubSpans = calculateSubSpans(for: cluster, clusterSpan: idleClusterSpans[cIdx], subGap: subGap)
                    let idleSubOffset = (0..<hoveredSubIdx).reduce(0.0) { $0 + idleSubSpans[$1] + subGap }
                    let idleSubStartY = idleClusterStartYs[cIdx] + idleSubOffset
                    let idleSubEndY = idleSubStartY + idleSubSpans[hoveredSubIdx]

                    let minFloor = 18.0
                    var curOffset = (0..<hoveredSubIdx).reduce(0.0) { $0 + subSpans[$1] + subGap }
                    let targetMaxOffset = idleSubStartY - clusterY
                    if curOffset > targetMaxOffset && hoveredSubIdx > 0 {
                        let excess = curOffset - targetMaxOffset
                        let reducible = (0..<hoveredSubIdx).reduce(0.0) { $0 + max(subSpans[$1] - minFloor, 0.0) }
                        if reducible > 0 {
                            let amountToCut = min(excess, reducible)
                            for i in 0..<hoveredSubIdx {
                                let slack = max(subSpans[i] - minFloor, 0.0)
                                subSpans[i] -= amountToCut * (slack / reducible)
                            }
                            subSpans[hoveredSubIdx] += amountToCut
                        }
                    }

                    curOffset = (0..<hoveredSubIdx).reduce(0.0) { $0 + subSpans[$1] + subGap }
                    let curSubEndY = clusterY + curOffset + subSpans[hoveredSubIdx]
                    if curSubEndY < idleSubEndY && hoveredSubIdx < cluster.count - 1 {
                        let deficit = idleSubEndY - curSubEndY
                        let succIndices = Array((hoveredSubIdx + 1)..<cluster.count)
                        let reducible = succIndices.reduce(0.0) { $0 + max(subSpans[$1] - minFloor, 0.0) }
                        if reducible > 0 {
                            let amountToCut = min(deficit, reducible)
                            for i in succIndices {
                                let slack = max(subSpans[i] - minFloor, 0.0)
                                subSpans[i] -= amountToCut * (slack / reducible)
                            }
                            subSpans[hoveredSubIdx] += amountToCut
                        }
                    }
                }

                var curSubY = clusterY
                for (subIdx, pod) in cluster.enumerated() {
                    let subSpanH = subSpans[subIdx]
                    let subStartY = curSubY
                    curSubY += subSpanH + subGap
                    result.append(
                        ResolvedPodLayoutItem(
                            pod: pod,
                            startY: subStartY,
                            spanH: subSpanH,
                            drawerStartY: clusterY,
                            drawerSpanH: clusterSpan,
                            majorGroupId: gid
                        )
                    )
                }
            }
        }

        cachedResolvedLayouts[edge] = LayoutCacheEntry(
            height: totalHeight,
            podsCount: allEdgePods.count,
            enabledSignature: signature,
            isDynamicBreathingEnabled: isDynamicBreathingEnabled,
            isAlwaysCompactBreathing: isAlwaysCompactBreathing,
            hoveredPodId: hoveredPodId,
            activePodId: activeDrawerPodId,
            activeItemId: activeDrawerItemId,
            pinnedIds: pinnedDrawerItemIds,
            page: curPage,
            items: result,
            timestamp: now
        )
        return result
    }

    public func activeDrawerCardFrames(for edge: MountEdge, totalHeight: Double, windowWidth: Double = 580.0) -> [CGRect] {
        guard !isRailsFrozen else { return [] }
        var frames: [CGRect] = []
        let layoutItems = resolvedPhysicalLayout(for: edge, totalHeight: totalHeight)
        let corridor = activeCatchCorridor

        for item in layoutItems {
            let pod = item.pod
            let isPodActive = (activeDrawerItemId == pod.id || activeDrawerPodId == pod.id)
            let isPodPinned = isItemPinned(id: pod.id)
            let hasChild = hasActiveOrPinnedChild(for: pod.id)

            // High-performance prune: Skip completely idle pods that have neither active nor pinned drawers
            guard isPodActive || isPodPinned || hasChild else { continue }

            // In Shared Major Pod mode, check if this pod is the active drawer owner in its Major Group
            let isSharedMajorSubBar = (item.majorGroupId != nil && abs(item.drawerSpanH - item.spanH) > 1.0)
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

            if isPodDecomposed(pod.id), let provider = capabilityProvider(for: pod.id), provider.subItemCount(store: self) > 0 {
                let rawCount = provider.subItemCount(store: self)
                _ = rawCount

                var matchedSubItem = false
                // Read the solver's own chip positions instead of re-deriving a
                // uniform height: the two used to disagree whenever a chip was
                // expanded, which let the click-through corridor miss the card.
                let slots: [PodChipSlot] = item.chipSlots.isEmpty
                    ? fallbackChipSlots(for: item, provider: provider, edge: edge, totalHeight: totalHeight)
                    : item.chipSlots

                for slot in slots {
                    let isMergedOverview = PurahPluginSubItem.isMoreItemsID(slot.id)
                    let itemActive = activeDrawerItemId == slot.id
                        || (isMergedOverview && pod.id == "calendar" && activeDrawerItemId == "calendar_more_events")
                    let itemPinned = isItemPinned(id: slot.id)
                        || (isMergedOverview && pod.id == "calendar" && isItemPinned(id: "calendar_more_events"))

                    if itemActive || itemPinned {
                        matchedSubItem = true

                        // Merged overview state: the "+N" chip owns the pod's full
                        // span — its drawer is exactly pod-height, so the hit box
                        // must be the whole pod frame, not the chip slot.
                        let frameTop: Double
                        let frameBottom: Double
                        if isMergedOverview {
                            frameTop = item.startY
                            frameBottom = item.startY + item.spanH
                        } else {
                            frameTop = slot.top
                            frameBottom = slot.top + (slot.isActive ? slot.cardHeight : slot.height)
                        }
                        let maxAllowedY = totalHeight - 12.0
                        let shift = max(frameBottom - maxAllowedY, 0.0)
                        let shiftedTop = frameTop - shift
                        let shiftedBottom = frameBottom - shift
                        let topOfCardY = totalHeight - shiftedTop
                        let bottomOfCardY = totalHeight - shiftedBottom
                        let minY = max(bottomOfCardY - 6.0, 0.0)
                        let maxY = min(topOfCardY + 6.0, totalHeight)

                        let drawerW = min(effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id) + corridor, windowWidth)
                        let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                        frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                    }
                }
                if matchedSubItem { continue }
            }

            let topOfPodY = totalHeight - item.startY
            let bottomOfPodY = topOfPodY - item.spanH
            let minY = max(bottomOfPodY - 6.0, 0.0)
            let maxY = min(topOfPodY + 6.0, totalHeight)

            let drawerW = min(effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id) + corridor, windowWidth)
            let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
            frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
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
    public var _isAIDecomposed: Bool {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "ai", defaults: userDefaults)
            if storage.string(forKey: "isDecomposed") != nil {
                return storage.bool(forKey: "isDecomposed")
            }
            if userDefaults.object(forKey: "purah.ai.isDecomposed") != nil {
                return userDefaults.bool(forKey: "purah.ai.isDecomposed")
            }
            return false
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "ai", defaults: userDefaults)
            storage.set(newValue, forKey: "isDecomposed")
        }
    }
    public var _aiRolePresets: [AIRolePreset] {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "ai", defaults: userDefaults)
            if let presets = storage.codable(forKey: "rolePresets", as: [AIRolePreset].self) {
                return presets
            }
            if let data = userDefaults.data(forKey: "purah.ai.rolePresets"),
               let decoded = try? JSONDecoder().decode([AIRolePreset].self, from: data) {
                return decoded
            }
            return AIRolePreset.defaultPresets
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "ai", defaults: userDefaults)
            storage.setCodable(newValue, forKey: "rolePresets")
            let enabledActionTypes = newValue.filter(\.isEnabled).compactMap { AIQuickActionType(rawValue: $0.id) }
            storage.setCodable(enabledActionTypes, forKey: "enabledActions")
        }
    }
    public var _aiEnabledActions: [AIQuickActionType] {
        get {
            _ = _pluginStorageRevision
            let storage = ScopedPluginStorage(pluginId: "ai", defaults: userDefaults)
            if let actions = storage.codable(forKey: "enabledActions", as: [AIQuickActionType].self) {
                return actions
            }
            if let arr = userDefaults.stringArray(forKey: "purah.ai.enabledActions") {
                let parsed = arr.compactMap { AIQuickActionType(rawValue: $0) }
                if !parsed.isEmpty { return parsed }
            }
            return [.ask, .translate, .polish, .explainCode]
        }
        set {
            _pluginStorageRevision &+= 1
            let storage = ScopedPluginStorage(pluginId: "ai", defaults: userDefaults)
            storage.setCodable(newValue, forKey: "enabledActions")
            var currentPresets = self._aiRolePresets
            for i in currentPresets.indices {
                if let action = AIQuickActionType(rawValue: currentPresets[i].id) {
                    currentPresets[i].isEnabled = newValue.contains(action)
                }
            }
            storage.setCodable(currentPresets, forKey: "rolePresets")
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
                if isDynamicBreathingEnabled {
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
        registerCapabilityProvider(DefaultAICapabilityProvider())
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "music", minHeight: 110.0, adaptiveWidth: 360.0, preferredHeight: 295.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "shelf", minHeight: 130.0, adaptiveWidth: 360.0, preferredHeight: 250.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "notes", minHeight: 130.0, adaptiveWidth: 320.0, preferredHeight: 280.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "terminal", minHeight: 120.0, adaptiveWidth: 520.0, preferredHeight: 280.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "clipboard", minHeight: 150.0, adaptiveWidth: 380.0, preferredHeight: 280.0))
    }

    // MARK: - Local Persistence
    public static func resetToFactoryDefaults(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "purah.pods")
    }

    public func loadPersistentState() {
        let defaults = userDefaults

        if defaults.data(forKey: "purah.pods") != nil && defaults.object(forKey: "purah.hasCompletedOnboarding") == nil {
            defaults.set(true, forKey: "purah.hasCompletedOnboarding")
        }

        if let data = defaults.data(forKey: "purah.pods"),
           let savedPods = try? JSONDecoder().decode([SlotPod].self, from: data),
           !savedPods.isEmpty {
            var merged = savedPods
            let savedIds = Set(savedPods.map(\.id))
            for var def in Self.defaultPods() where !savedIds.contains(def.id) {
                if def.id == "ai" && !defaults.bool(forKey: "purah.didAutoInstallAIPlugin") {
                    def.isEnabled = true
                } else {
                    def.isEnabled = false
                }
                merged.append(def)
            }
            self.pods = merged
        }

        var didRepairPods = false
        if !defaults.bool(forKey: "purah.didRepairLegacyAutoStacks_v1") {
            let legacyPattern = try? NSRegularExpression(pattern: #"^major_(left|right)_[0-9]+$"#)
            for idx in self.pods.indices {
                if let gid = self.pods[idx].majorGroupId {
                    let range = NSRange(location: 0, length: gid.utf16.count)
                    if legacyPattern?.firstMatch(in: gid, range: range) != nil {
                        self.pods[idx].majorGroupId = nil
                        didRepairPods = true
                    }
                }
            }
            defaults.set(true, forKey: "purah.didRepairLegacyAutoStacks_v1")
            normalizePageRanges(for: .left)
            normalizePageRanges(for: .right)
            didRepairPods = true
        }

        for edge in [MountEdge.left, MountEdge.right] {
            let edgePods = self.pods.filter { $0.edge == edge && $0.isEnabled }
            let groupedByPage = Dictionary(grouping: edgePods, by: { max(0, $0.pageIndex) })
            var needsNormalize = false
            for (_, pagePods) in groupedByPage {
                let sorted = pagePods.sorted { $0.range.start < $1.range.start }
                if sorted.count >= 2 {
                    for i in 1..<sorted.count {
                        if sorted[i].range.start < sorted[i - 1].range.end - 0.005 {
                            needsNormalize = true
                            break
                        }
                    }
                }
                let sumLengths = sorted.reduce(0.0) { $0 + $1.range.length }
                if sumLengths > 0.96 {
                    needsNormalize = true
                }
                if needsNormalize { break }
            }
            if needsNormalize {
                normalizePageRanges(for: edge)
                didRepairPods = true
            }
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

        if defaults.object(forKey: "purah.isDynamicBreathingEnabled") != nil {
            self.isDynamicBreathingEnabled = defaults.bool(forKey: "purah.isDynamicBreathingEnabled")
        } else {
            self.isDynamicBreathingEnabled = true
        }
        if defaults.object(forKey: "purah.isAlwaysCompactBreathing") != nil {
            self.isAlwaysCompactBreathing = defaults.bool(forKey: "purah.isAlwaysCompactBreathing")
        }

        if defaults.object(forKey: "purah.hotkey.keyCode") != nil {
            let code = UInt32(defaults.integer(forKey: "purah.hotkey.keyCode"))
            let mods = UInt32(defaults.integer(forKey: "purah.hotkey.modifiers"))
            self.hotKeyShortcut = HotKeyShortcut(keyCode: code, modifiers: mods)
        }
        if defaults.object(forKey: "purah.sculptorHotkey.keyCode") != nil {
            let code = UInt32(defaults.integer(forKey: "purah.sculptorHotkey.keyCode"))
            let mods = UInt32(defaults.integer(forKey: "purah.sculptorHotkey.modifiers"))
            self.sculptorHotKeyShortcut = HotKeyShortcut(keyCode: code, modifiers: mods)
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

        if didRepairPods {
            savePersistentState()
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
        defaults.set(isDynamicBreathingEnabled, forKey: "purah.isDynamicBreathingEnabled")
        defaults.set(isAlwaysCompactBreathing, forKey: "purah.isAlwaysCompactBreathing")
        defaults.set(Int(hotKeyShortcut.keyCode), forKey: "purah.hotkey.keyCode")
        defaults.set(Int(hotKeyShortcut.modifiers), forKey: "purah.hotkey.modifiers")
        defaults.set(Int(sculptorHotKeyShortcut.keyCode), forKey: "purah.sculptorHotkey.keyCode")
        defaults.set(Int(sculptorHotKeyShortcut.modifiers), forKey: "purah.sculptorHotkey.modifiers")
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
    }

    @ObservationIgnored private var debouncedSaveTask: Task<Void, Never>? = nil

    public func scheduleSavePersistentState() {
        if Self.isTestingEnvironment {
            savePersistentState()
            return
        }
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.savePersistentState()
        }
    }

    public func autoLayoutAll() {
        // 1. Reset Manual Overrides & Update Minimum Floors
        for idx in pods.indices {
            pods[idx].preferredExpandedHeight = nil
            let screenH = max(Double(availableScreenHeight(for: pods[idx].edge)), 600.0)
            pods[idx].minLength = isDynamicBreathingEnabled ? max(28.0 / screenH, 0.035) : max(Double(minimumDrawerHeight(for: pods[idx].id)) / screenH, 0.07)
        }

        // 2. Smart Page & Stack Consolidation per Edge (.left, .right)
        for edge in [MountEdge.left, .right] {
            let screenH = max(Double(availableScreenHeight(for: edge)), 600.0)
            let enabledIndices = pods.indices.filter { pods[$0].edge == edge && pods[$0].isEnabled }
            guard !enabledIndices.isEmpty else { continue }

            // Group enabledIndices into Stack-preserving clusters
            var clusters: [[Int]] = []
            var visitedGroupIds = Set<String>()
            var visitedIndices = Set<Int>()

            for idx in enabledIndices {
                if visitedIndices.contains(idx) { continue }
                if let groupId = pods[idx].majorGroupId {
                    if !visitedGroupIds.contains(groupId) {
                        visitedGroupIds.insert(groupId)
                        let groupIndices = enabledIndices.filter { pods[$0].majorGroupId == groupId }
                        let sortedGroup = groupIndices.sorted { pods[$0].range.start < pods[$1].range.start }
                        clusters.append(sortedGroup)
                        visitedIndices.formUnion(sortedGroup)
                    }
                } else {
                    clusters.append([idx])
                    visitedIndices.insert(idx)
                }
            }

            // Sort clusters ergonomically by (firstPod.preferredZone, -clusterAvgWeight, firstPod.range.start)
            clusters.sort { c1, c2 in
                let p1 = pods[c1[0]]
                let p2 = pods[c2[0]]
                if p1.preferredZone != p2.preferredZone {
                    return p1.preferredZone < p2.preferredZone
                }
                let w1 = c1.reduce(0.0) { $0 + pods[$1].ergonomicWeight } / Double(c1.count)
                let w2 = c2.reduce(0.0) { $0 + pods[$1].ergonomicWeight } / Double(c2.count)
                if w1 != w2 {
                    return w1 > w2
                }
                return p1.range.start < p2.range.start
            }

            // Assign pageIndex based on isDynamicBreathingEnabled
            if isDynamicBreathingEnabled {
                let compactFloorSum = clusters.reduce(0.0) { sum, cluster in
                    sum + (cluster.count >= 2 ? Double(cluster.count) * 26.0 : 42.0) + 8.0
                }
                let pageBudget = max(screenH - 96.0, 260.0)
                if compactFloorSum <= pageBudget {
                    for cluster in clusters {
                        for idx in cluster {
                            pods[idx].pageIndex = 0
                        }
                    }
                    setRailPage(0, for: edge)
                } else {
                    var curPage = 0
                    var curPageHeight = 0.0
                    for cluster in clusters {
                        let clusterH = (cluster.count >= 2 ? Double(cluster.count) * 26.0 : 42.0) + 8.0
                        if curPageHeight > 0 && curPageHeight + clusterH > pageBudget {
                            curPage += 1
                            curPageHeight = 0.0
                        }
                        for idx in cluster {
                            pods[idx].pageIndex = curPage
                        }
                        curPageHeight += clusterH
                    }
                    setRailPage(min(currentRailPage(for: edge), curPage), for: edge)
                }
            } else {
                let pageBudget = max(screenH - 96.0, 260.0)
                var curPage = 0
                var curPageHeight = 0.0
                for cluster in clusters {
                    let clusterRequiredH: Double
                    if cluster.count >= 2 {
                        clusterRequiredH = max(155.0, Double(cluster.count) * 48.0)
                    } else {
                        clusterRequiredH = Double(minimumDrawerHeight(for: pods[cluster[0]].id))
                    }
                    let clusterTotalH = clusterRequiredH + 8.0
                    if curPageHeight > 0 && curPageHeight + clusterTotalH > pageBudget {
                        curPage += 1
                        curPageHeight = 0.0
                    }
                    for idx in cluster {
                        pods[idx].pageIndex = curPage
                    }
                    curPageHeight += clusterTotalH
                }
                setRailPage(min(currentRailPage(for: edge), curPage), for: edge)
            }

            // Distribute Full-Rail Golden Proportions Within Each Page
            let sortedPodIndices = clusters.flatMap { $0 }
            let pageIndices = Array(Set(sortedPodIndices.map { pods[$0].pageIndex })).sorted()
            var groupedByPage: [(Int, [Int])] = []
            for page in pageIndices {
                let pagePods = sortedPodIndices.filter { pods[$0].pageIndex == page }
                groupedByPage.append((page, pagePods))
            }

            let pageCount = groupedByPage.count
            let safeStart = pageCount > 1 ? (48.0 / screenH) : 0.02
            let safeTotalSpan = pageCount > 1 ? ((screenH - 96.0) / screenH) : 0.94
            let gap = 8.0 / screenH

            for (_, pagePodIndices) in groupedByPage {
                let totalGaps = Double(max(pagePodIndices.count - 1, 0)) * gap
                let usableSpan = max(safeTotalSpan - totalGaps, Double(pagePodIndices.count) * 0.05)

                var weights: [Double] = []
                var minRatios: [Double] = []
                for idx in pagePodIndices {
                    let prefH = Double(preferredDrawerHeight(for: pods[idx].id))
                    let minH = Double(minimumDrawerHeight(for: pods[idx].id))
                    let weight = max(pods[idx].ergonomicWeight, 15.0) * max(prefH, minH)
                    weights.append(weight)
                    minRatios.append(minH / screenH)
                }

                let totalWeight = max(weights.reduce(0.0, +), 1.0)
                let sumMinRatios = minRatios.reduce(0.0, +)

                var lengths: [Double] = []
                if sumMinRatios <= usableSpan {
                    let surplus = usableSpan - sumMinRatios
                    for i in pagePodIndices.indices {
                        let len = minRatios[i] + surplus * (weights[i] / totalWeight)
                        lengths.append(len)
                    }
                } else {
                    for i in pagePodIndices.indices {
                        let len = usableSpan * (weights[i] / totalWeight)
                        lengths.append(len)
                    }
                }

                var curStart = safeStart
                for (offset, idx) in pagePodIndices.enumerated() {
                    let len = lengths[offset]
                    pods[idx].range = NormalizedRange(start: curStart, length: len)
                    curStart += len + gap
                }
            }
        }

        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func togglePodEnabled(id: String) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        let pod = pods[index]
        if !pod.isEnabled {
            pods[index].isEnabled = true
            let screenH = max(Double(availableScreenHeight(for: pod.edge)), 400.0)
            if !isDynamicBreathingEnabled {
                let minPt = Double(minimumDrawerHeight(for: pod.id))
                pods[index].minLength = max(minPt / screenH, 0.07)
            }
            if !isDynamicBreathingEnabled {
                let pages = paginatedPods(for: pod.edge, totalHeight: screenH)
                if pages.count > 1 {
                    setRailPage(pages.count - 1, for: pod.edge)
                    DiagnosticLogger.shared.warn("Store", "Page overflow toast triggered for edge=\(pod.edge)")
                    onCapacityWarningToast?("layout.toast.pageOverflow".localized)
                }
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
        let screenH = max(Double(availableScreenHeight(for: edge)), 600.0)
        let pages = paginatedPods(for: edge, totalHeight: screenH)
        let isPaged = pages.count > 1
        // Sorted *ids*: the array below is a value snapshot, so a mutation made
        // earlier in this function would leave stale `range` values behind.
        let railPodIds = pods.filter {
            $0.edge == edge && $0.isEnabled && (!isPaged || $0.pageIndex == currentPod.pageIndex)
        }.sorted { $0.range.start < $1.range.start }.map(\.id)
        guard let currentIndex = railPodIds.firstIndex(of: podId),
              let podIndex = pods.firstIndex(where: { $0.id == podId }) else { return }
        // Live lookup: `railPods` below is indexed by id, never by snapshot.
        func livePod(_ id: String) -> SlotPod? { pods.first(where: { $0.id == id }) }

        // The layout engine spaces pods by a physical 8pt; deriving the gap the
        // same way here keeps "fill rail" consistent with auto-layout instead of
        // drifting to a different value on non-900pt screens.
        let railGap = 8.0 / screenH

        if isPaged && railPodIds.count >= 2 {
            // In Paged Spaces, expand target pod to fill maximum space on its page while compressing siblings on the same page to minLength
            let gap = railGap
            let totalGaps = Double(max(railPodIds.count - 1, 0)) * gap
            let otherMins = railPodIds.enumerated().reduce(0.0) { acc, pair in
                if pair.offset == currentIndex { return acc }
                guard let p = livePod(pair.element) else { return acc }
                let minH = Double(minimumDrawerHeight(for: p.id))
                return acc + max(p.minLength, minH / screenH)
            }
            let targetLen = max(0.94 - totalGaps - otherMins, max(currentPod.minLength, Double(minimumDrawerHeight(for: podId)) / screenH))
            var curStart = 0.02
            for (offset, id) in railPodIds.enumerated() {
                guard let p = livePod(id),
                      let idx = pods.firstIndex(where: { $0.id == id }) else { continue }
                let minH = Double(minimumDrawerHeight(for: p.id))
                let len = (offset == currentIndex) ? targetLen : max(p.minLength, minH / screenH)
                pods[idx].range = NormalizedRange(start: curStart, length: len)
                curStart += len + gap
            }
        } else if currentIndex == railPodIds.count - 1 {
            // Last pod on the rail (e.g. Music): expand length down to 0.98 to fill all remaining space!
            let start = pods[podIndex].range.start
            let newLength = max(0.98 - start, currentPod.minLength)
            pods[podIndex].range.length = newLength
        } else {
            // Expand towards successor above/below, stopping one rail gap short so
            // the rigid zero-overlap invariant still holds. When the successor
            // already sits closer than the pod's *current* length (tightly packed
            // rail) there is nothing ergonomically sane to gain, so leave the pod
            // untouched instead of shrinking it or spilling over the neighbour.
            guard let nextPod = livePod(railPodIds[currentIndex + 1]) else { return }
            let start = pods[podIndex].range.start
            let allowedLength = nextPod.range.start - start - railGap
            guard allowedLength > pods[podIndex].range.length, allowedLength >= currentPod.minLength else { return }
            pods[podIndex].range.length = allowedLength
        }

        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func updatePodRange(id: String, newRange: NormalizedRange) {
        guard let pod = pods.first(where: { $0.id == id }) else { return }
        let screenH = max(Double(availableScreenHeight(for: pod.edge)), 600.0)
        let pages = paginatedPods(for: pod.edge, totalHeight: screenH)
        let isPaged = pages.count > 1
        if isPaged {
            let pagePods = pods.filter { $0.edge == pod.edge && $0.isEnabled && $0.pageIndex == pod.pageIndex }
            let resolvedPagePods = SpringConstraintSolver.resolve(
                draggedPodId: id,
                newRange: newRange,
                allPods: pagePods,
                on: pod.edge,
                minRatioProvider: { p in
                    let minH = self.standaloneMinimumRailHeight(for: p.id)
                    return max(minH / screenH, 0.05)
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
                minRatioProvider: { p in
                    if self.isDynamicBreathingEnabled || p.majorGroupId != nil {
                        return max(28.0 / screenH, 0.035)
                    }
                    let minH = self.standaloneMinimumRailHeight(for: p.id)
                    return max(minH / screenH, 0.05)
                }
            )
            if let idx = resolved.firstIndex(where: { $0.id == id }) {
                resolved[idx].minLength = min(resolved[idx].minLength, 0.05)
            }
            pods = resolved
        }
        invalidateLayoutCache()
        scheduleSavePersistentState()
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

    // MARK: - Interactive Onboarding Guide & Live Rehearsal Engine

    public func saveUserLayoutSnapshotIfNeeded() {
        if userPodsSnapshotBeforeRehearsal == nil {
            userPodsSnapshotBeforeRehearsal = pods
            userDynamicFlagBeforeRehearsal = isDynamicBreathingEnabled
        }
    }

    public func restoreUserLayoutSnapshotIfNeeded() {
        if let saved = userPodsSnapshotBeforeRehearsal {
            pods = saved
            userPodsSnapshotBeforeRehearsal = nil
        }
        if let savedDyn = userDynamicFlagBeforeRehearsal {
            isDynamicBreathingEnabled = savedDyn
            userDynamicFlagBeforeRehearsal = nil
        }
        isUsingTemporaryDemoSandbox = false
        let leftPageCount = max(paginatedPods(for: .left, totalHeight: max(Double(availableScreenHeight(for: .left)), 600.0)).count, 1)
        let rightPageCount = max(paginatedPods(for: .right, totalHeight: max(Double(availableScreenHeight(for: .right)), 600.0)).count, 1)
        if leftRailPage >= leftPageCount { leftRailPage = max(0, leftPageCount - 1) }
        if rightRailPage >= rightPageCount { rightRailPage = max(0, rightPageCount - 1) }
        invalidateLayoutCache()
        onWindowsRebuildNeeded?()
    }

    public func toggleTemporaryBreathingSandbox() {
        if isUsingTemporaryDemoSandbox {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                restoreUserLayoutSnapshotIfNeeded()
            }
        } else {
            saveUserLayoutSnapshotIfNeeded()
            isUsingTemporaryDemoSandbox = true
            isDynamicBreathingEnabled = true
            let leftDemoIds = ["vitals", "shelf", "notes", "clipboard", "scripts", "terminal", "music"]
            setRailPage(0, for: .left)
            for id in leftDemoIds {
                mountPod(id: id, to: .left)
                if let idx = pods.firstIndex(where: { $0.id == id }) {
                    pods[idx].pageIndex = 0
                    pods[idx].majorGroupId = nil
                }
            }
            resetMajorGroups(for: .left)
            normalizePageRanges(for: .left)
            invalidateLayoutCache()
            onWindowsRebuildNeeded?()
        }
    }

    public func cancelOnboardingRehearsal() {
        onboardingRehearsalTask?.cancel()
        onboardingRehearsalTask = nil
        isRehearsingBreathingInSculptor = false
        isAlwaysCompactBreathing = false
        restoreUserLayoutSnapshotIfNeeded()
        dismissActiveDrawer()
        invalidateLayoutCache()
        onWindowsRebuildNeeded?()
    }

    public func startInteractiveOnboarding(clearAllPods: Bool = true) {
        cancelOnboardingRehearsal()
        userPodsSnapshotBeforeRehearsal = nil
        userDynamicFlagBeforeRehearsal = nil
        isUsingTemporaryDemoSandbox = false
        onboardingDidToggleDecompose = false
        onboardingDidCreateStack = false
        onboardingDidCreatePage = false
        onboardingDidSwitchPage = false
        onboardingBreathingHoveredPods.removeAll()
        onboardingDidSwitchTriggerMode = false
        onboardingDidTriggerEdgeDrawer = false
        if clearAllPods {
            for i in pods.indices {
                pods[i].isEnabled = false
                pods[i].majorGroupId = nil
                pods[i].pageIndex = 0
            }
            leftRailPage = 0
            rightRailPage = 0
        }
        onboardingStep = .mountPods
        isOnboardingGuideActive = true
        setLiveRailEditingMode(true)
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func selectOnboardingStep(_ step: OnboardingGuideStep) {
        cancelOnboardingRehearsal()
        onboardingStep = step
        switch step {
        case .mountPods:
            isRehearsingBreathingInSculptor = false
        case .decomposeDemo:
            isRehearsingBreathingInSculptor = false
            let hasDecomposable = pods.contains { $0.isEnabled && ["vitals", "scripts", "clipboard", "ai", "calendar"].contains($0.id) }
            if !hasDecomposable {
                mountPod(id: "vitals", to: .left)
                splitPodFromMajorGroup(id: "vitals")
            }
            if pods.contains(where: { $0.id == "vitals" && $0.isEnabled }) {
                _isVitalsDecomposed = false
                capabilityProvider(for: "vitals")?.setDecomposed(false, store: self)
                onDecomposedStateSync?("vitals", false)
            }
            normalizePageRanges(for: .left)
            normalizePageRanges(for: .right)
        case .stackDemo:
            isRehearsingBreathingInSculptor = false
            let leftPods = pods.filter { $0.edge == .left && $0.isEnabled }
            let rightPods = pods.filter { $0.edge == .right && $0.isEnabled }
            if leftPods.count < 2 && rightPods.count < 2 {
                mountPod(id: "vitals", to: .left)
                mountPod(id: "shelf", to: .left)
                normalizePageRanges(for: .left)
            }
        case .pageDemo:
            isRehearsingBreathingInSculptor = false
            let leftPods = pods.filter { $0.edge == .left && $0.isEnabled }
            let rightPods = pods.filter { $0.edge == .right && $0.isEnabled }
            if leftPods.count < 2 && rightPods.count < 2 {
                mountPod(id: "calendar", to: .right)
                mountPod(id: "scripts", to: .right)
                normalizePageRanges(for: .right)
            }
        case .breathingDemo:
            onboardingBreathingHoveredPods.removeAll()
            let leftPods = pods.filter { $0.edge == .left && $0.isEnabled }
            let rightPods = pods.filter { $0.edge == .right && $0.isEnabled }
            if leftPods.isEmpty && rightPods.isEmpty {
                mountPod(id: "vitals", to: .left)
                mountPod(id: "scripts", to: .right)
                normalizePageRanges(for: .left)
                normalizePageRanges(for: .right)
            }
            isAlwaysCompactBreathing = false
            isRehearsingBreathingInSculptor = true
        case .antiTouchCalibration:
            dismissActiveDrawer()
            if edgeTriggerSensitivity == .custom || edgeTriggerSensitivity == .agile {
                edgeTriggerSensitivity = .balanced
            }
            onboardingDidTriggerEdgeDrawer = false
            onboardingGateState = .idle
            onboardingGateProgress = 0.0
            onboardingGateCurrentValue = 0
            onboardingGateTargetValue = Int(activeInitialDwellSeconds * 1000)
            let leftPods = pods.filter { $0.edge == .left && $0.isEnabled }
            let rightPods = pods.filter { $0.edge == .right && $0.isEnabled }
            if leftPods.count < 2 && rightPods.count < 2 {
                mountPod(id: "vitals", to: .left)
                mountPod(id: "shelf", to: .left)
                mountPod(id: "calendar", to: .right)
                mountPod(id: "scripts", to: .right)
                normalizePageRanges(for: .left)
                normalizePageRanges(for: .right)
            }
            isAlwaysCompactBreathing = false
            isRehearsingBreathingInSculptor = true
        }
        invalidateLayoutCache()
        onWindowsRebuildNeeded?()
    }

    public func togglePodDecomposedInSculptor(podId: String) {
        let current = isPodDecomposed(podId)
        let next = !current
        switch podId {
        case "vitals":
            _isVitalsDecomposed = next
            capabilityProvider(for: "vitals")?.setDecomposed(next, store: self)
        case "scripts":
            _isScriptsDecomposed = next
            capabilityProvider(for: "scripts")?.setDecomposed(next, store: self)
        case "ai":
            _isAIDecomposed = next
            capabilityProvider(for: "ai")?.setDecomposed(next, store: self)
        case "clipboard":
            let storage = ScopedPluginStorage(pluginId: "clipboard", defaults: userDefaults)
            storage.set(next, forKey: "isDecomposed")
            capabilityProvider(for: "clipboard")?.setDecomposed(next, store: self)
        case "calendar":
            let nextStrategy: CalendarOverflowStrategy = (calendarOverflowStrategy == .smartFold) ? .continuousStream : .smartFold
            calendarOverflowStrategy = nextStrategy
            capabilityProvider(for: "calendar")?.setDecomposed(nextStrategy == .smartFold, store: self)
        default:
            capabilityProvider(for: podId)?.setDecomposed(next, store: self)
        }
        onDecomposedStateSync?(podId, next)
        onboardingDidToggleDecompose = true
        _ = triggerControlHaptic(.alignment)
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func nextOnboardingStep() {
        if let next = OnboardingGuideStep(rawValue: onboardingStep.rawValue + 1) {
            selectOnboardingStep(next)
        } else {
            finishOnboarding(useRecommendedLayout: false)
        }
    }

    public func skipCurrentOnboardingStep() {
        if let next = OnboardingGuideStep(rawValue: onboardingStep.rawValue + 1) {
            selectOnboardingStep(next)
        } else {
            finishOnboarding(useRecommendedLayout: false)
        }
    }

    public func previousOnboardingStep() {
        if let prev = OnboardingGuideStep(rawValue: onboardingStep.rawValue - 1) {
            selectOnboardingStep(prev)
        }
    }

    public func skipAllOnboardingAndLoadDefaults() {
        finishOnboarding(useRecommendedLayout: true)
    }

    public func finishOnboarding(useRecommendedLayout: Bool = false) {
        cancelOnboardingRehearsal()
        if useRecommendedLayout || !pods.contains(where: \.isEnabled) {
            pods = PurahWorkspaceStore.defaultPods()
            autoLayoutAll()
        }
        hasCompletedOnboarding = true
        isOnboardingGuideActive = false
        setLiveRailEditingMode(false)
        savePersistentState()
        invalidateLayoutCache()
        onWindowsRebuildNeeded?()
    }

    public func rehearseMountSamplePods() {
        mountPod(id: "vitals", to: .left)
        mountPod(id: "shelf", to: .left)
        mountPod(id: "calendar", to: .right)
        mountPod(id: "scripts", to: .right)
        normalizePageRanges(for: .left)
        normalizePageRanges(for: .right)
        _ = triggerControlHaptic(.alignment)
        invalidateLayoutCache()
        onWindowsRebuildNeeded?()
    }

    public func rehearseDecomposeDemo(decomposed: Bool? = nil) {
        if !pods.contains(where: { $0.id == "scripts" && $0.isEnabled }) {
            mountPod(id: "scripts", to: .right)
        }
        splitPodFromMajorGroup(id: "scripts")
        if !pods.contains(where: { $0.id == "vitals" && $0.isEnabled }) {
            mountPod(id: "vitals", to: .left)
        }
        splitPodFromMajorGroup(id: "vitals")

        let newVal = decomposed ?? !_isScriptsDecomposed
        _isScriptsDecomposed = newVal
        _isVitalsDecomposed = newVal
        capabilityProvider(for: "scripts")?.setDecomposed(newVal, store: self)
        capabilityProvider(for: "vitals")?.setDecomposed(newVal, store: self)
        onDecomposedStateSync?("scripts", newVal)
        onDecomposedStateSync?("vitals", newVal)
        onboardingDidToggleDecompose = true

        isRehearsingBreathingInSculptor = true
        invalidateLayoutCache()
        onWindowsRebuildNeeded?()
        _ = triggerControlHaptic(.alignment)

        onboardingRehearsalTask?.cancel()
        onboardingRehearsalTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self.isRehearsingBreathingInSculptor = false
            self.invalidateLayoutCache()
            self.onWindowsRebuildNeeded?()
        }
    }

    public func rehearseStackMerge() {
        saveUserLayoutSnapshotIfNeeded()
        isRehearsingBreathingInSculptor = false
        var leftPods = pods.filter { $0.edge == .left && $0.isEnabled }
        if leftPods.count < 2 {
            mountPod(id: "vitals", to: .left)
            mountPod(id: "shelf", to: .left)
            normalizePageRanges(for: .left)
            leftPods = pods.filter { $0.edge == .left && $0.isEnabled }
        }
        if leftPods.count >= 2 {
            addPodToMajorGroup(podId: leftPods[1].id, targetPodId: leftPods[0].id)
        }
        onboardingDidCreateStack = true
        _ = triggerControlHaptic(.alignment)
        invalidateLayoutCache()
        onWindowsRebuildNeeded?()

        onboardingRehearsalTask?.cancel()
        onboardingRehearsalTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                self.restoreUserLayoutSnapshotIfNeeded()
            }
        }
    }

    public func rehearsePaginationFlip() {
        saveUserLayoutSnapshotIfNeeded()
        isRehearsingBreathingInSculptor = false
        var rightPods = pods.filter { $0.edge == .right && $0.isEnabled }
        if rightPods.count < 2 {
            mountPod(id: "calendar", to: .right)
            mountPod(id: "scripts", to: .right)
            normalizePageRanges(for: .right)
            rightPods = pods.filter { $0.edge == .right && $0.isEnabled }
        }
        if let last = rightPods.last {
            setPodPage(id: last.id, pageIndex: 1)
        }
        isRightTopPortalRevealed = true
        isRightBottomPortalRevealed = true
        setRailPage(1, for: .right)
        onboardingDidCreatePage = true
        onboardingDidSwitchPage = true
        _ = triggerControlHaptic(.levelChange)
        invalidateLayoutCache()
        onWindowsRebuildNeeded?()

        onboardingRehearsalTask?.cancel()
        onboardingRehearsalTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                self.setRailPage(0, for: .right)
                self.restoreUserLayoutSnapshotIfNeeded()
            }
        }
    }

    public func rehearseDynamicBreathing() {
        saveUserLayoutSnapshotIfNeeded()
        isUsingTemporaryDemoSandbox = true
        let leftDemoIds = ["vitals", "shelf", "notes", "clipboard", "scripts", "terminal", "music"]
        setRailPage(0, for: .left)
        for id in leftDemoIds {
            mountPod(id: id, to: .left)
            if let idx = pods.firstIndex(where: { $0.id == id }) {
                pods[idx].pageIndex = 0
                pods[idx].majorGroupId = nil
            }
        }
        resetMajorGroups(for: .left)
        normalizePageRanges(for: .left)
        isDynamicBreathingEnabled = true
        isAlwaysCompactBreathing = false
        isRehearsingBreathingInSculptor = true
        invalidateLayoutCache()
        onWindowsRebuildNeeded?()

        let demoExpandIds = Array(leftDemoIds.prefix(3))
        onboardingRehearsalTask?.cancel()
        onboardingRehearsalTask = Task { @MainActor in
            for podId in demoExpandIds {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                    self.hoveredPodId = podId
                    self.activeDrawerPodId = podId
                    self.activeDrawerItemId = podId
                    self.onboardingBreathingHoveredPods.insert(podId)
                    self.invalidateLayoutCache()
                }
                self.onWindowsRebuildNeeded?()
                try? await Task.sleep(nanoseconds: 550_000_000)
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                self.dismissActiveDrawer()
                self.restoreUserLayoutSnapshotIfNeeded()
            }
            self.onboardingBreathingHoveredPods = ["vitals", "shelf"]
            self.isAlwaysCompactBreathing = false
            self.isRehearsingBreathingInSculptor = false
            self.invalidateLayoutCache()
            self.onWindowsRebuildNeeded?()
        }
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
            SlotPod(id: "ai", name: "AI Assistant", systemIcon: "sparkles", edge: .right, range: .init(start: 0.85, length: 0.26), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 38, minLength: 0.20, isEnabled: true, drawerWidth: 420, defaultColorHex: "#A855F7"),
            SlotPod(id: "vitals", name: "Hardware Vitals", systemIcon: "waveform.path.ecg", edge: .left, range: .init(start: 0.08, length: 0.22), ambientStyle: .progressTimeline, preferredZone: .glance, ergonomicWeight: 35, minLength: 0.18, defaultColorHex: "#00E5A3"),
            SlotPod(id: "shelf", name: "Temporary Shelf", systemIcon: "tray.fill", edge: .left, range: .init(start: 0.32, length: 0.20), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 35, minLength: 0.16, defaultColorHex: "#2ED573"),
            SlotPod(id: "notes", name: "Quick Notes", systemIcon: "note.text", edge: .left, range: .init(start: 0.54, length: 0.14), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 30, minLength: 0.12, isEnabled: false, defaultColorHex: "#FFD166"),
            SlotPod(id: "scripts", name: "Script Runway", systemIcon: "terminal.fill", edge: .left, range: .init(start: 0.54, length: 0.20), ambientStyle: .ghostDot, preferredZone: .quickFlick, ergonomicWeight: 30, minLength: 0.16, isEnabled: true, defaultColorHex: "#6C5CE7"),
            SlotPod(id: "terminal", name: "Terminal", systemIcon: "apple.terminal.fill", edge: .left, range: .init(start: 0.76, length: 0.20), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 25, minLength: 0.14, isEnabled: true, drawerWidth: 520, defaultColorHex: "#00F5D4"),
            SlotPod(id: "clipboard", name: "Clipboard", systemIcon: "doc.on.clipboard.fill", edge: .left, range: .init(start: 0.88, length: 0.08), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 20, minLength: 0.08, isEnabled: false, drawerWidth: 260, defaultColorHex: "#FF9F0A")
        ]
    }
}
