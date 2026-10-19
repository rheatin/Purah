// Sources/PurahUI/AmbientViews/LiveRailSculptorStripView.swift
import SwiftUI
import AppKit
import PurahCore

public struct SculptRailCluster: Identifiable {
    public let id: String
    public let groupId: String?
    public let items: [ResolvedPodLayoutItem]

    public var pods: [SlotPod] {
        items.map(\.pod)
    }

    public var isSharedMajorCluster: Bool {
        groupId != nil && items.count >= 2
    }

    public var drawerStartY: Double {
        guard let first = items.first else { return 0 }
        return isSharedMajorCluster ? first.drawerStartY : first.startY
    }

    public var drawerSpanH: Double {
        guard let first = items.first, let last = items.last else { return 0 }
        if isSharedMajorCluster {
            let subSpan = (last.startY + last.spanH) - first.startY
            return max(first.drawerSpanH, subSpan)
        }
        return first.spanH
    }
}

public struct LiveRailSculptorStripView: View {
    public let edge: MountEdge
    public let store: PurahWorkspaceStore
    public let totalHeight: CGFloat

    @State private var hoveredStackTargetPodId: String? = nil
    @State private var draggingPodId: String? = nil
    @State private var dragInitialCenterY: Double? = nil
    @State private var hoverMergeTask: Task<Void, Never>? = nil
    @State private var didAutoMergeDuringDrag: Bool = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(edge: MountEdge, store: PurahWorkspaceStore, totalHeight: CGFloat) {
        self.edge = edge
        self.store = store
        self.totalHeight = totalHeight
    }

    private func buildClusters(from layoutItems: [ResolvedPodLayoutItem]) -> [SculptRailCluster] {
        var clusters: [SculptRailCluster] = []
        var currentGroup: String? = nil
        var currentItems: [ResolvedPodLayoutItem] = []

        func flushCurrent() {
            guard !currentItems.isEmpty else { return }
            if let gid = currentGroup, currentItems.count >= 2 {
                clusters.append(SculptRailCluster(id: "cluster_\(gid)", groupId: gid, items: currentItems))
            } else {
                for item in currentItems {
                    clusters.append(SculptRailCluster(id: item.id, groupId: nil, items: [item]))
                }
            }
            currentItems.removeAll()
            currentGroup = nil
        }

        for item in layoutItems {
            if let gid = item.majorGroupId {
                if currentGroup == gid {
                    currentItems.append(item)
                } else {
                    flushCurrent()
                    currentGroup = gid
                    currentItems = [item]
                }
            } else {
                flushCurrent()
                clusters.append(SculptRailCluster(id: item.id, groupId: nil, items: [item]))
            }
        }
        flushCurrent()
        return clusters
    }

    private func detectStackTargetPodId(
        draggedItem: ResolvedPodLayoutItem,
        currentCenterY: Double,
        allItems: [ResolvedPodLayoutItem]
    ) -> String? {
        let draggedGroupId = draggedItem.majorGroupId
        for otherItem in allItems where otherItem.pod.id != draggedItem.pod.id {
            let otherGroupId = otherItem.majorGroupId
            if let g1 = draggedGroupId, let g2 = otherGroupId, g1 == g2 {
                continue
            }
            let rawTopY = otherItem.drawerStartY
            let rawSpan = otherItem.drawerSpanH
            let rawBottomY = rawTopY + rawSpan
            let inset = rawSpan * 0.12
            let topY = rawTopY + inset
            let bottomY = rawBottomY - inset
            if bottomY > topY && currentCenterY >= topY && currentCenterY <= bottomY {
                return otherItem.pod.id
            }
        }
        return nil
    }

    private func scheduleHoverMerge(draggedPodId: String, targetPodId: String?) {
        hoverMergeTask?.cancel()
        hoverMergeTask = nil
        hoveredStackTargetPodId = targetPodId

        guard let targetId = targetPodId else { return }
        store.triggerControlHaptic(.levelChange)

        hoverMergeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            guard draggingPodId == draggedPodId,
                  hoveredStackTargetPodId == targetId,
                  !didAutoMergeDuringDrag else { return }
            didAutoMergeDuringDrag = true
            hoveredStackTargetPodId = nil
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                store.addPodToMajorGroup(podId: draggedPodId, targetPodId: targetId)
                store.triggerControlHaptic(.levelChange)
            }
        }
    }

    private func handlePodDragChanged(
        item: ResolvedPodLayoutItem,
        translationY: CGFloat,
        allItems: [ResolvedPodLayoutItem]
    ) {
        if draggingPodId != item.pod.id {
            draggingPodId = item.pod.id
            dragInitialCenterY = item.startY + (item.spanH * 0.5)
            didAutoMergeDuringDrag = false
        }
        guard !didAutoMergeDuringDrag else { return }

        // Check if cursor crossed across the screen to the opposite rail
        let screenLoc = NSEvent.mouseLocation
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let isOnOppositeRail = (edge == .left && screenLoc.x >= screenFrame.maxX - 215)
            || (edge == .right && screenLoc.x <= screenFrame.minX + 215)
        if isOnOppositeRail {
            if hoveredStackTargetPodId != nil {
                scheduleHoverMerge(draggedPodId: item.pod.id, targetPodId: nil)
            }
            store.updateExternalPodDrag(podId: item.pod.id, screenPoint: screenLoc, screenFrame: screenFrame)
            return
        } else if store.externalDraggedPodId == item.pod.id {
            store.externalDraggedPodId = nil
            store.externalDragScreenLocation = nil
            store.externalDragTargetEdge = nil
            store.externalDragTargetPodId = nil
        }

        let baseCenter = dragInitialCenterY ?? (item.startY + item.spanH * 0.5)
        let currentCenterY = baseCenter + Double(translationY)
        let matchedTarget = detectStackTargetPodId(
            draggedItem: item,
            currentCenterY: currentCenterY,
            allItems: allItems
        )
        if matchedTarget != hoveredStackTargetPodId {
            scheduleHoverMerge(draggedPodId: item.pod.id, targetPodId: matchedTarget)
        }
    }

    private func handlePodDragEnded(
        item: ResolvedPodLayoutItem,
        translationY: CGFloat,
        baseStart: Double,
        safeHeight: Double,
        allItems: [ResolvedPodLayoutItem],
        isSubPodInCluster: Bool
    ) {
        hoverMergeTask?.cancel()
        hoverMergeTask = nil

        let wasAutoMerged = didAutoMergeDuringDrag
        let currentTargetId = hoveredStackTargetPodId
        let initialCenter = dragInitialCenterY ?? (item.startY + item.spanH * 0.5)

        hoveredStackTargetPodId = nil
        draggingPodId = nil
        dragInitialCenterY = nil
        didAutoMergeDuringDrag = false

        guard !wasAutoMerged else { return }

        // 1. Cross-rail drop onto opposite rail or opposite rail's stack
        if store.externalDraggedPodId == item.pod.id,
           let extEdge = store.externalDragTargetEdge,
           extEdge != edge {
            let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                store.commitExternalPodDrag(podId: item.pod.id, screenFrame: screenFrame)
            }
            return
        }
        if store.externalDraggedPodId == item.pod.id {
            store.externalDraggedPodId = nil
            store.externalDragScreenLocation = nil
            store.externalDragTargetEdge = nil
            store.externalDragTargetPodId = nil
        }

        // 2. Release-to-Merge onto hovered target pod / Major Stack
        if let targetId = currentTargetId {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                store.addPodToMajorGroup(podId: item.pod.id, targetPodId: targetId)
                store.triggerControlHaptic(.levelChange)
            }
            return
        }

        // 3. Released in empty space or past a neighbor's boundary -> reorder or reposition
        let finalCenterY = initialCenter + Double(translationY)
        if isSubPodInCluster {
            if translationY < -14 && store.canMovePod(id: item.pod.id, direction: .up) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.movePodInOrder(id: item.pod.id, direction: .up)
                    store.triggerControlHaptic(.alignment)
                }
            } else if translationY > 14 && store.canMovePod(id: item.pod.id, direction: .down) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.movePodInOrder(id: item.pod.id, direction: .down)
                    store.triggerControlHaptic(.alignment)
                }
            }
            return
        }

        if let myIdx = allItems.firstIndex(where: { $0.pod.id == item.pod.id }) {
            if translationY < -14 {
                let crossedAbove = allItems[0..<myIdx].filter { ($0.startY + $0.spanH * 0.5) > finalCenterY }.count
                if crossedAbove > 0 {
                    for _ in 0..<crossedAbove {
                        store.movePodInOrder(id: item.pod.id, direction: .up)
                    }
                    store.triggerControlHaptic(.alignment)
                }
            } else if translationY > 14 {
                let crossedBelow = allItems[(myIdx + 1)..<allItems.count].filter { ($0.startY + $0.spanH * 0.5) < finalCenterY }.count
                if crossedBelow > 0 {
                    for _ in 0..<crossedBelow {
                        store.movePodInOrder(id: item.pod.id, direction: .down)
                    }
                    store.triggerControlHaptic(.alignment)
                }
            }
        }

        let newStart = min(max(baseStart + (Double(translationY) / safeHeight), 0.02), max(0.96 - item.pod.range.length, 0.02))
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            store.updatePodRange(
                id: item.pod.id,
                newRange: NormalizedRange(start: newStart, length: item.pod.range.length)
            )
        }
    }

    public var body: some View {
        let safeHeight = max(Double(totalHeight), 400.0)
        let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: safeHeight)
        let clusters = buildClusters(from: layoutItems)
        let pages = store.paginatedPods(for: edge, totalHeight: safeHeight)
        let pageCount = max(pages.count, 1)
        let currentPage = min(max(store.currentRailPage(for: edge), 0), pageCount - 1)
        let isExternalDropEdge = (store.externalDragTargetEdge == edge)

        ZStack(alignment: .top) {
            // Frosted glass sculpting strip background
            UnevenRoundedRectangle(
                topLeadingRadius: edge == .right ? 12 : 0,
                bottomLeadingRadius: edge == .right ? 12 : 0,
                bottomTrailingRadius: edge == .left ? 12 : 0,
                topTrailingRadius: edge == .left ? 12 : 0,
                style: .continuous
            )
            .fill(Color.black.opacity(0.42))
            .background(.ultraThinMaterial)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: edge == .right ? 12 : 0,
                    bottomLeadingRadius: edge == .right ? 12 : 0,
                    bottomTrailingRadius: edge == .left ? 12 : 0,
                    topTrailingRadius: edge == .left ? 12 : 0,
                    style: .continuous
                )
                .stroke(
                    isExternalDropEdge ? Color.orange : palette.primaryAccent.opacity(0.45),
                    lineWidth: isExternalDropEdge ? 2.2 : 1.2
                )
            )
            .frame(width: 210, height: totalHeight)

            // Section A: Prominent Multi-Page Deck Header
            pageDeckHeader(pages: pages, currentPage: currentPage)
                .frame(width: 200, height: 58)
                .offset(y: 8)
                .zIndex(250)

            // Section B: 1:1 Physical Sculpting Capsules & Unified Shared Major Pod Outer Boxes
            if layoutItems.isEmpty {
                emptyRailPlaceholder
                    .frame(width: 196, height: 140)
                    .offset(y: max((totalHeight - 140) * 0.5, 80))
            } else {
                ForEach(clusters) { cluster in
                    if cluster.isSharedMajorCluster, let groupId = cluster.groupId {
                        let isClusterHighlighted = cluster.items.contains {
                            $0.pod.id == hoveredStackTargetPodId || $0.pod.id == store.externalDragTargetPodId
                        }
                        let isDraggingMember = cluster.items.contains { $0.pod.id == draggingPodId }
                        LiveSculptMajorClusterBoxView(
                            cluster: cluster,
                            groupId: groupId,
                            edge: edge,
                            totalHeight: totalHeight,
                            store: store,
                            isStackTargetHighlighted: isClusterHighlighted,
                            hasActiveStackMergeTarget: hoveredStackTargetPodId != nil || store.externalDraggedPodId != nil,
                            onCancelParentDragState: {
                                hoverMergeTask?.cancel()
                                hoverMergeTask = nil
                                hoveredStackTargetPodId = nil
                                draggingPodId = nil
                                dragInitialCenterY = nil
                                didAutoMergeDuringDrag = false
                            },
                            onSubPodDragChanged: { subItem, translationY in
                                handlePodDragChanged(
                                    item: subItem,
                                    translationY: translationY,
                                    allItems: layoutItems
                                )
                            },
                            onSubPodDragEnded: { subItem, translationY in
                                handlePodDragEnded(
                                    item: subItem,
                                    translationY: translationY,
                                    baseStart: subItem.pod.range.start,
                                    safeHeight: safeHeight,
                                    allItems: layoutItems,
                                    isSubPodInCluster: true
                                )
                            }
                        )
                        .frame(width: 202, height: max(CGFloat(cluster.drawerSpanH), 84))
                        .offset(y: CGFloat(cluster.drawerStartY))
                        .zIndex(isDraggingMember ? 200 : (isClusterHighlighted ? 120 : 10))
                    } else if let item = cluster.items.first {
                        let isHighlighted = (hoveredStackTargetPodId == item.pod.id || store.externalDragTargetPodId == item.pod.id)
                        let isDraggingThis = (draggingPodId == item.pod.id)
                        LiveSculptPodCapsuleView(
                            item: item,
                            edge: edge,
                            pageCount: pageCount,
                            totalHeight: totalHeight,
                            store: store,
                            isStackTargetHighlighted: isHighlighted,
                            isDraggingThis: isDraggingThis,
                            onDragMoveChanged: { translationY, _ in
                                handlePodDragChanged(
                                    item: item,
                                    translationY: translationY,
                                    allItems: layoutItems
                                )
                            },
                            onDragMoveEnded: { translationY, baseStart in
                                handlePodDragEnded(
                                    item: item,
                                    translationY: translationY,
                                    baseStart: baseStart,
                                    safeHeight: safeHeight,
                                    allItems: layoutItems,
                                    isSubPodInCluster: false
                                )
                            }
                        )
                        .frame(width: 198, height: max(CGFloat(item.spanH), 22))
                        .offset(y: CGFloat(item.startY))
                        .zIndex(isDraggingThis ? 200 : (isHighlighted ? 120 : 10))
                    }
                }
            }
        }
        .frame(width: 210, height: totalHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .left ? .topLeading : .topTrailing)
    }

    @ViewBuilder
    private func pageDeckHeader(pages: [[SlotPod]], currentPage: Int) -> some View {
        let totalPages = max(pages.count, 1)
        let canSplitNewPage = currentPage < pages.count && pages[currentPage].count > 1

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("📑 Paged Spaces · \(pages.count) Page(s)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(palette.primaryAccent)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(0..<totalPages, id: \.self) { pIdx in
                        let isSelected = (pIdx == currentPage)
                        let pagePods = pIdx < pages.count ? pages[pIdx] : []
                        Button {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                store.setRailPage(pIdx, for: edge)
                                store.triggerControlHaptic(.alignment)
                            }
                        } label: {
                            HStack(spacing: 3.5) {
                                Text("P\(pIdx + 1) (\(pagePods.count))")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(isSelected ? .black : .white)

                                HStack(spacing: 2) {
                                    ForEach(pagePods.prefix(4)) { p in
                                        Circle()
                                            .fill(isSelected ? Color.black.opacity(0.75) : palette.podColor(for: p.id, store: store))
                                            .frame(width: 4, height: 4)
                                    }
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .fill(isSelected ? palette.primaryAccent : Color.white.opacity(0.12))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(palette.primaryAccent.opacity(isSelected ? 1.0 : 0.4), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.tactile)
                    }

                    Button {
                        guard currentPage < pages.count,
                              pages[currentPage].count > 1,
                              let lastPod = pages[currentPage].last else { return }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            store.setPodPage(id: lastPod.id, pageIndex: pages.count)
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        Text("+ Page")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(canSplitNewPage ? palette.primaryAccent : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .fill(palette.primaryAccent.opacity(canSplitNewPage ? 0.16 : 0.06))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(palette.primaryAccent.opacity(canSplitNewPage ? 0.55 : 0.2), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.tactile)
                    .disabled(!canSplitNewPage)
                    .help("Move the bottom pod on this page to a new page")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(palette.primaryAccent.opacity(0.65), lineWidth: 1.0)
                )
        )
    }

    private var emptyRailPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.rectangle.on.folder")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(palette.primaryAccent.opacity(0.8))

            Text("Empty \(edge == .left ? "Left" : "Right") Rail · Click +L / +R in the top dock to mount plugins")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                        .foregroundColor(palette.primaryAccent.opacity(0.45))
                )
        )
    }
}

public struct LiveSculptMajorClusterBoxView: View {
    public let cluster: SculptRailCluster
    public let groupId: String
    public let edge: MountEdge
    public let totalHeight: CGFloat
    public let store: PurahWorkspaceStore
    public let isStackTargetHighlighted: Bool
    public let hasActiveStackMergeTarget: Bool
    public let onCancelParentDragState: () -> Void
    public let onSubPodDragChanged: (ResolvedPodLayoutItem, CGFloat) -> Void
    public let onSubPodDragEnded: (ResolvedPodLayoutItem, CGFloat) -> Void

    @State private var resizeInitialRatio: Double? = nil
    @State private var lastResizeHapticStep: Int = 0
    @State private var isResizeHovered: Bool = false
    @State private var activeDraggingSubId: String? = nil
    @State private var activeSubDragOffset: CGSize = .zero
    @State private var isSubPodPulledOutside: Bool = false
    @State private var detachHoverTask: Task<Void, Never>? = nil
    @State private var didAutoDetachDuringDrag: Bool = false
    @State private var stackMoveInitialStart: Double? = nil
    @State private var lastStackMoveHapticStep: Int = 0
    @State private var activeResizingSubId: String? = nil
    @State private var subResizeInitialLength: Double? = nil
    @State private var lastSubResizeHapticStep: Int = 0
    @State private var hoveredSubResizeId: String? = nil
    @State private var isPulseOn: Bool = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        cluster: SculptRailCluster,
        groupId: String,
        edge: MountEdge,
        totalHeight: CGFloat,
        store: PurahWorkspaceStore,
        isStackTargetHighlighted: Bool = false,
        hasActiveStackMergeTarget: Bool = false,
        onCancelParentDragState: @escaping () -> Void = {},
        onSubPodDragChanged: @escaping (ResolvedPodLayoutItem, CGFloat) -> Void = { _, _ in },
        onSubPodDragEnded: @escaping (ResolvedPodLayoutItem, CGFloat) -> Void = { _, _ in }
    ) {
        self.cluster = cluster
        self.groupId = groupId
        self.edge = edge
        self.totalHeight = totalHeight
        self.store = store
        self.isStackTargetHighlighted = isStackTargetHighlighted
        self.hasActiveStackMergeTarget = hasActiveStackMergeTarget
        self.onCancelParentDragState = onCancelParentDragState
        self.onSubPodDragChanged = onSubPodDragChanged
        self.onSubPodDragEnded = onSubPodDragEnded
    }

    private func computeDetachTargetY(
        subItem: ResolvedPodLayoutItem,
        translation: CGSize,
        safeTotalH: Double
    ) -> Double {
        let currentSubCenterY = subItem.startY + (subItem.spanH * 0.5) + Double(translation.height)
        let isPulledVerticallyOut = (currentSubCenterY < cluster.drawerStartY - 14.0)
            || (currentSubCenterY > cluster.drawerStartY + cluster.drawerSpanH + 14.0)
        if isPulledVerticallyOut {
            return currentSubCenterY
        }
        let placeBelow = cluster.drawerStartY + cluster.drawerSpanH + 40.0 + (subItem.spanH * 0.5)
        if placeBelow + (subItem.spanH * 0.5) < safeTotalH - 20.0 {
            return placeBelow
        }
        return max(cluster.drawerStartY - 40.0 - (subItem.spanH * 0.5), 40.0)
    }

    public var body: some View {
        let safeTotalH = max(Double(totalHeight), 400.0)
        let boxH = max(CGFloat(cluster.drawerSpanH), 84.0)
        let headerH: CGFloat = 22.0
        let gripH: CGFloat = 12.0
        let innerSpacing: CGFloat = 3.0
        let count = max(cluster.items.count, 1)
        let innerAvailableH = max(boxH - headerH - gripH - 6.0, CGFloat(count) * 20.0)
        let totalSubSpan = max(cluster.items.reduce(0.0) { $0 + max($1.spanH, 18.0) }, 1.0)
        let totalInnerGaps = CGFloat(max(count - 1, 0)) * innerSpacing
        let netSliceBudget = max(innerAvailableH - totalInnerGaps, CGFloat(count) * 18.0)

        ZStack {
            VStack(alignment: .leading, spacing: 2) {
                // Top Header Bar: Shared Stack summary (draggable vertically) + [Unstack All]
                HStack(spacing: 4) {
                    Text("📦 Stack (\(cluster.pods.count)) · \(Int(cluster.drawerSpanH))pt")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            store.unstackMajorGroup(groupId: groupId, on: edge)
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        Text("Unstack All")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.20))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.tactile)
                    .help("Unstack all pods in this Shared Major Pod")
                }
                .padding(.horizontal, 7)
                .frame(height: headerH)
                .background(Color.orange.opacity(0.14))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .global)
                        .onChanged { value in
                            if stackMoveInitialStart == nil {
                                stackMoveInitialStart = cluster.drawerStartY / safeTotalH
                                lastStackMoveHapticStep = 0
                            }
                            let deltaY = Double(value.translation.height)
                            let step = Int(deltaY / 24.0)
                            if step != lastStackMoveHapticStep {
                                lastStackMoveHapticStep = step
                                store.triggerControlHaptic(.alignment)
                            }
                            let baseStart = stackMoveInitialStart ?? (cluster.drawerStartY / safeTotalH)
                            let newStartRatio = baseStart + (deltaY / safeTotalH)
                            store.moveMajorGroup(groupId: groupId, on: edge, newStartRatio: newStartRatio)
                        }
                        .onEnded { _ in
                            stackMoveInitialStart = nil
                            lastStackMoveHapticStep = 0
                        }
                )
                .help("Drag vertically to move this entire Shared Stack along the rail")

                // Stacked Sub-Pod Slices
                VStack(spacing: innerSpacing) {
                    ForEach(cluster.items) { subItem in
                        let pod = subItem.pod
                        let podColor = palette.podColor(for: pod.id, store: store)
                        let sliceRatio = CGFloat(max(subItem.spanH, 18.0) / totalSubSpan)
                        let sliceH = max(netSliceBudget * sliceRatio, 20.0)
                        let isDraggingSub = (activeDraggingSubId == pod.id)
                        let isSubResizeHovered = (hoveredSubResizeId == pod.id)

                        ZStack {
                            VStack(alignment: .leading, spacing: 0) {
                                // Upper draggable area of sub-pod slice
                                VStack(alignment: .leading, spacing: 3) {
                                    // Row 1: Header Row — Full Width for Plugin Name
                                    HStack(spacing: 5) {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(podColor)
                                            .frame(width: 3, height: 12)

                                        Image(systemName: pod.systemIcon)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(podColor)

                                        Text(pod.name)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .lineLimit(1)

                                        Spacer(minLength: 2)

                                        Text("\(Int(subItem.spanH))pt")
                                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                            .foregroundColor(podColor)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1.5)
                                            .background(Capsule().fill(podColor.opacity(0.18)))

                                        // Unmount button [✕]
                                        Button {
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                                store.splitPodFromMajorGroup(id: pod.id)
                                                store.togglePodEnabled(id: pod.id)
                                                store.triggerControlHaptic(.alignment)
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.red.opacity(0.9))
                                        }
                                        .buttonStyle(.tactile)
                                        .help("Unmount \(pod.name) from rail")
                                    }

                                    // Row 2: Action Toolbar Row — shown when sliceH >= 46
                                    if sliceH >= 46 {
                                        HStack(spacing: 4) {
                                            // Move Up [↑]
                                            Button {
                                                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                                    store.movePodInOrder(id: pod.id, direction: .up)
                                                    store.triggerControlHaptic(.alignment)
                                                }
                                            } label: {
                                                Text("↑")
                                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.white)
                                                    .frame(width: 18, height: 17)
                                                    .background(Color.white.opacity(0.14))
                                                    .cornerRadius(4)
                                            }
                                            .buttonStyle(.tactile)
                                            .disabled(!store.canMovePod(id: pod.id, direction: .up))
                                            .help("Move up in stack")

                                            // Move Down [↓]
                                            Button {
                                                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                                    store.movePodInOrder(id: pod.id, direction: .down)
                                                    store.triggerControlHaptic(.alignment)
                                                }
                                            } label: {
                                                Text("↓")
                                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.white)
                                                    .frame(width: 18, height: 17)
                                                    .background(Color.white.opacity(0.14))
                                                    .cornerRadius(4)
                                            }
                                            .buttonStyle(.tactile)
                                            .disabled(!store.canMovePod(id: pod.id, direction: .down))
                                            .help("Move down in stack")

                                            // Pop Out / Split from Stack [✂️ Split]
                                            Button {
                                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                                    store.splitPodFromMajorGroup(id: pod.id)
                                                    store.triggerControlHaptic(.alignment)
                                                }
                                            } label: {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "scissors")
                                                        .font(.system(size: 8, weight: .bold))
                                                    Text("Split")
                                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                                }
                                                .foregroundColor(.orange)
                                                .padding(.horizontal, 5)
                                                .frame(height: 17)
                                                .background(Color.orange.opacity(0.22))
                                                .cornerRadius(4)
                                            }
                                            .buttonStyle(.tactile)
                                            .help("Pop \(pod.name) out of this Shared Stack")

                                            Spacer(minLength: 0)

                                            // Throw to Opposite Rail [⇄]
                                            Button {
                                                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                                    store.splitPodFromMajorGroup(id: pod.id)
                                                    store.movePod(id: pod.id, to: edge == .left ? .right : .left)
                                                    store.triggerControlHaptic(.alignment)
                                                }
                                            } label: {
                                                Text("⇄")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(palette.warningAccent)
                                                    .frame(width: 19, height: 17)
                                                    .background(palette.warningAccent.opacity(0.18))
                                                    .cornerRadius(4)
                                            }
                                            .buttonStyle(.tactile)
                                            .help(edge == .left ? "Throw to Right Rail" : "Throw to Left Rail")
                                        }
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.top, sliceH >= 48 ? 5 : 2)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                        .onChanged { value in
                                            if activeDraggingSubId != pod.id {
                                                activeDraggingSubId = pod.id
                                                didAutoDetachDuringDrag = false
                                                isSubPodPulledOutside = false
                                            }
                                            guard !didAutoDetachDuringDrag else { return }

                                            activeSubDragOffset = value.translation
                                            onSubPodDragChanged(subItem, value.translation.height)

                                            let currentSubCenterY = subItem.startY + (subItem.spanH * 0.5) + Double(value.translation.height)
                                            let isPulledVerticallyOut = (currentSubCenterY < cluster.drawerStartY - 14.0)
                                                || (currentSubCenterY > cluster.drawerStartY + cluster.drawerSpanH + 14.0)
                                            let isPulledHorizontallyOut = abs(value.translation.width) > 36.0
                                            let pulledOut = isPulledVerticallyOut || isPulledHorizontallyOut

                                            if pulledOut && !isSubPodPulledOutside {
                                                isSubPodPulledOutside = true
                                                store.triggerControlHaptic(.alignment)
                                                detachHoverTask?.cancel()
                                                detachHoverTask = Task { @MainActor in
                                                    try? await Task.sleep(nanoseconds: 400_000_000)
                                                    guard !Task.isCancelled else { return }
                                                    guard activeDraggingSubId == pod.id,
                                                          isSubPodPulledOutside,
                                                          !didAutoDetachDuringDrag,
                                                          !hasActiveStackMergeTarget else { return }
                                                    let latestOffset = activeSubDragOffset
                                                    let targetY = computeDetachTargetY(
                                                        subItem: subItem,
                                                        translation: latestOffset,
                                                        safeTotalH: safeTotalH
                                                    )
                                                    didAutoDetachDuringDrag = true
                                                    isSubPodPulledOutside = false
                                                    activeDraggingSubId = nil
                                                    activeSubDragOffset = .zero
                                                    onCancelParentDragState()
                                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                                                        store.detachPodFromMajorGroup(
                                                            id: pod.id,
                                                            targetCenterY: targetY,
                                                            totalHeight: safeTotalH
                                                        )
                                                        store.triggerControlHaptic(.levelChange)
                                                    }
                                                }
                                            } else if !pulledOut && isSubPodPulledOutside {
                                                detachHoverTask?.cancel()
                                                detachHoverTask = nil
                                                isSubPodPulledOutside = false
                                            }
                                        }
                                        .onEnded { value in
                                            detachHoverTask?.cancel()
                                            detachHoverTask = nil

                                            let wasAutoDetached = didAutoDetachDuringDrag
                                            let wasPulledOut = isSubPodPulledOutside

                                            activeDraggingSubId = nil
                                            activeSubDragOffset = .zero
                                            isSubPodPulledOutside = false
                                            didAutoDetachDuringDrag = false

                                            guard !wasAutoDetached else { return }

                                            let currentSubCenterY = subItem.startY + (subItem.spanH * 0.5) + Double(value.translation.height)
                                            let isPulledVerticallyOut = (currentSubCenterY < cluster.drawerStartY - 14.0)
                                                || (currentSubCenterY > cluster.drawerStartY + cluster.drawerSpanH + 14.0)
                                            let isPulledHorizontallyOut = abs(value.translation.width) > 36.0
                                            let pulledOut = wasPulledOut || isPulledVerticallyOut || isPulledHorizontallyOut

                                            if pulledOut && !hasActiveStackMergeTarget {
                                                let targetY = computeDetachTargetY(
                                                    subItem: subItem,
                                                    translation: value.translation,
                                                    safeTotalH: safeTotalH
                                                )
                                                onCancelParentDragState()
                                                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                                                    store.detachPodFromMajorGroup(
                                                        id: pod.id,
                                                        targetCenterY: targetY,
                                                        totalHeight: safeTotalH
                                                    )
                                                    store.triggerControlHaptic(.levelChange)
                                                }
                                            } else {
                                                onSubPodDragEnded(subItem, value.translation.height)
                                            }
                                        }
                                )

                                // Sub-Pod Resize Handle (`── ══ ──`, 8pt tall)
                                ZStack {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(height: 8)

                                    Text("── ══ ──")
                                        .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(isSubResizeHovered ? .white : podColor.opacity(0.85))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 8)
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if hovering {
                                        hoveredSubResizeId = pod.id
                                    } else if hoveredSubResizeId == pod.id {
                                        hoveredSubResizeId = nil
                                    }
                                }
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                        .onChanged { value in
                                            if subResizeInitialLength == nil || activeResizingSubId != pod.id {
                                                activeResizingSubId = pod.id
                                                subResizeInitialLength = max(pod.range.length, 0.03)
                                                lastSubResizeHapticStep = 0
                                            }
                                            let deltaY = Double(value.translation.height)
                                            let step = Int(deltaY / 16.0)
                                            if step != lastSubResizeHapticStep {
                                                lastSubResizeHapticStep = step
                                                store.triggerControlHaptic(.alignment)
                                            }
                                            let baseLen = subResizeInitialLength ?? max(pod.range.length, 0.03)
                                            let clusterTotalRatio = max(cluster.items.reduce(0.0) { $0 + max($1.pod.range.length, 0.025) }, 0.05)
                                            let clusterRenderedSubRatio = max(cluster.items.reduce(0.0) { $0 + $1.spanH } / safeTotalH, 0.05)
                                            let ratioPerScreenUnit = clusterTotalRatio / clusterRenderedSubRatio
                                            let targetRatio = max(baseLen + (deltaY / safeTotalH) * ratioPerScreenUnit, 0.03)
                                            store.resizeSubPodInMajorGroup(
                                                podId: pod.id,
                                                on: edge,
                                                newSubSpanRatio: targetRatio
                                            )
                                        }
                                        .onEnded { _ in
                                            activeResizingSubId = nil
                                            subResizeInitialLength = nil
                                            lastSubResizeHapticStep = 0
                                        }
                                )
                                .help("Drag vertically to resize \(pod.name) inside this Shared Stack")
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .frame(height: sliceH, alignment: .topLeading)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(podColor.opacity(isDraggingSub && isSubPodPulledOutside ? 0.36 : 0.18))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(
                                        isDraggingSub && isSubPodPulledOutside ? palette.primaryAccent : podColor.opacity(0.55),
                                        lineWidth: isDraggingSub && isSubPodPulledOutside ? 1.8 : 0.9
                                    )
                            )

                            if isDraggingSub && isSubPodPulledOutside {
                                Text("💧 Hold or Release to Detach")
                                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(palette.primaryAccent))
                                    .shadow(color: Color.black.opacity(0.45), radius: 4)
                            }
                        }
                        .scaleEffect(isDraggingSub ? (isSubPodPulledOutside ? 1.05 : 1.02) : 1.0)
                        .offset(
                            x: isDraggingSub ? activeSubDragOffset.width : 0,
                            y: isDraggingSub ? activeSubDragOffset.height : 0
                        )
                        .zIndex(isDraggingSub ? 50 : 1)
                    }
                }
                .padding(.horizontal, 5)

                Spacer(minLength: 0)

                // Unified Bottom Resize Grip Bar (`══════`)
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: gripH)

                    Text("══════")
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundColor(isResizeHovered ? .white : .orange)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isResizeHovered = hovering
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if resizeInitialRatio == nil {
                                resizeInitialRatio = Double(cluster.drawerSpanH) / safeTotalH
                                lastResizeHapticStep = 0
                            }
                            let deltaY = Double(value.translation.height)
                            let step = Int(deltaY / 20.0)
                            if step != lastResizeHapticStep {
                                lastResizeHapticStep = step
                                store.triggerControlHaptic(.alignment)
                            }
                            let baseRatio = resizeInitialRatio ?? (Double(cluster.drawerSpanH) / safeTotalH)
                            let newTotalRatio = baseRatio + (deltaY / safeTotalH)
                            store.resizeMajorGroup(
                                groupId: groupId,
                                on: edge,
                                newTotalSpanRatio: newTotalRatio
                            )
                        }
                        .onEnded { _ in
                            resizeInitialRatio = nil
                            lastResizeHapticStep = 0
                        }
                )
                .help("Drag vertically to resize the entire Shared Major Pod")
            }
            .frame(width: 202, height: boxH, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        Color.orange.opacity(isStackTargetHighlighted ? (isPulseOn ? 1.0 : 0.65) : 1.0),
                        lineWidth: isStackTargetHighlighted ? (isPulseOn ? 3.2 : 2.4) : 2.0
                    )
            )
            .shadow(
                color: isStackTargetHighlighted ? Color.orange.opacity(isPulseOn ? 0.85 : 0.45) : Color.orange.opacity(0.25),
                radius: isStackTargetHighlighted ? 11 : 4
            )

            if isStackTargetHighlighted {
                Text("📦 Release or Hold to Stack")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange))
                    .shadow(color: Color.black.opacity(0.45), radius: 5)
            }
        }
        .onChange(of: isStackTargetHighlighted) { _, highlighted in
            if highlighted {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    isPulseOn = true
                }
            } else {
                isPulseOn = false
            }
        }
    }
}

public struct LiveSculptPodCapsuleView: View {
    public let item: ResolvedPodLayoutItem
    public let edge: MountEdge
    public let pageCount: Int
    public let totalHeight: CGFloat
    public let store: PurahWorkspaceStore
    public let isStackTargetHighlighted: Bool
    public let isDraggingThis: Bool
    public let onDragMoveChanged: (CGFloat, Double) -> Void
    public let onDragMoveEnded: (CGFloat, Double) -> Void

    @State private var moveInitialStart: Double? = nil
    @State private var lastMoveHapticStep: Int = 0
    @State private var dragVisualOffsetY: CGFloat = 0.0
    @State private var resizeInitialLength: Double? = nil
    @State private var resizeInitialStart: Double? = nil
    @State private var lastResizeHapticStep: Int = 0
    @State private var isResizeHovered: Bool = false
    @State private var isPulseOn: Bool = false

    private var pod: SlotPod {
        item.pod
    }

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: pod.id, store: store)
    }

    public init(
        item: ResolvedPodLayoutItem,
        edge: MountEdge,
        pageCount: Int,
        totalHeight: CGFloat,
        store: PurahWorkspaceStore,
        isStackTargetHighlighted: Bool = false,
        isDraggingThis: Bool = false,
        onDragMoveChanged: @escaping (CGFloat, Double) -> Void = { _, _ in },
        onDragMoveEnded: @escaping (CGFloat, Double) -> Void = { _, _ in }
    ) {
        self.item = item
        self.edge = edge
        self.pageCount = pageCount
        self.totalHeight = totalHeight
        self.store = store
        self.isStackTargetHighlighted = isStackTargetHighlighted
        self.isDraggingThis = isDraggingThis
        self.onDragMoveChanged = onDragMoveChanged
        self.onDragMoveEnded = onDragMoveEnded
    }

    public var body: some View {
        let spanH = max(CGFloat(item.spanH), 22.0)
        let safeTotalH = max(Double(totalHeight), 400.0)
        let isSharedStacked = (pod.majorGroupId != nil && store.isInSharedMajorPod(podId: pod.id))
        let activelyDragging = isDraggingThis || moveInitialStart != nil

        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // Entire upper body is draggable for moving & stacking (excludes bottom 12pt resize grip bar)
                VStack(alignment: .leading, spacing: 0) {
                    // Row 1: Header & Drag-to-Move / Drag-to-Stack Body
                    HStack(spacing: 5) {
                        Image(systemName: pod.systemIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(podColor)

                        Text(pod.name)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        Text("\(Int(item.spanH))pt")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(podColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule()
                                    .fill(podColor.opacity(0.18))
                            )

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                store.togglePodEnabled(id: pod.id)
                                store.triggerControlHaptic(.alignment)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.red.opacity(0.9))
                        }
                        .buttonStyle(.tactile)
                        .help("Unmount \(pod.name) from rail")
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, spanH >= 42 ? 6 : 3)
                    .padding(.bottom, 2)

                    // Row 2: Compact Action Controls (shown when item.spanH >= 42)
                    if spanH >= 42 {
                        HStack(spacing: 4) {
                            // Move Up
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    store.movePodInOrder(id: pod.id, direction: .up)
                                    store.triggerControlHaptic(.alignment)
                                }
                            } label: {
                                Text("↑")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(width: 18, height: 17)
                                    .background(Color.white.opacity(0.14))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.tactile)
                            .disabled(!store.canMovePod(id: pod.id, direction: .up))
                            .help("Move up")

                            // Move Down
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    store.movePodInOrder(id: pod.id, direction: .down)
                                    store.triggerControlHaptic(.alignment)
                                }
                            } label: {
                                Text("↓")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(width: 18, height: 17)
                                    .background(Color.white.opacity(0.14))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.tactile)
                            .disabled(!store.canMovePod(id: pod.id, direction: .down))
                            .help("Move down")

                            // Snap to Predecessor if gap exists
                            if store.hasGapAbove(id: pod.id) {
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        store.snapPod(id: pod.id, to: .predecessor)
                                        store.triggerControlHaptic(.alignment)
                                    }
                                } label: {
                                    Text("🧲")
                                        .font(.system(size: 8.5))
                                        .frame(width: 19, height: 17)
                                        .background(palette.primaryAccent.opacity(0.22))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.tactile)
                                .help("Snap to pod above")
                            }

                            // Fill Rail
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    store.fillRail(podId: pod.id)
                                    store.triggerControlHaptic(.alignment)
                                }
                            } label: {
                                Text("↕")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(podColor)
                                    .frame(width: 18, height: 17)
                                    .background(podColor.opacity(0.18))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.tactile)
                            .help("Expand to fill available rail space")

                            // Page Assignment Menu
                            let maxPage = max(pageCount, pod.pageIndex + 1)
                            Menu {
                                ForEach(0..<maxPage, id: \.self) { pIdx in
                                    Button("Page \(pIdx + 1)\(pod.pageIndex == pIdx ? " ✓" : "")") {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            store.setPodPage(id: pod.id, pageIndex: pIdx)
                                            store.triggerControlHaptic(.alignment)
                                        }
                                    }
                                }
                                Divider()
                                Button("+ New Page (P\(maxPage + 1))") {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        store.setPodPage(id: pod.id, pageIndex: maxPage)
                                        store.triggerControlHaptic(.alignment)
                                    }
                                }
                            } label: {
                                Text("P\(pod.pageIndex + 1) ▾")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(palette.primaryAccent)
                                    .padding(.horizontal, 4)
                                    .frame(height: 17)
                                    .background(palette.primaryAccent.opacity(0.18))
                                    .cornerRadius(4)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Move pod to another page")

                            // Split / Stack buttons
                            if pod.majorGroupId != nil {
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        store.splitPodFromMajorGroup(id: pod.id)
                                        store.triggerControlHaptic(.alignment)
                                    }
                                } label: {
                                    Text("✂️ Split")
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 4)
                                        .frame(height: 17)
                                        .background(Color.orange.opacity(0.20))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.tactile)
                                .help("Split from Shared Major Pod")
                            }

                            if store.canMergePodWithNext(id: pod.id) {
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        store.mergePodWithNext(id: pod.id)
                                        store.triggerControlHaptic(.alignment)
                                    }
                                } label: {
                                    Text("🔗 Stack")
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .foregroundColor(palette.primaryAccent)
                                        .padding(.horizontal, 4)
                                        .frame(height: 17)
                                        .background(palette.primaryAccent.opacity(0.18))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.tactile)
                                .help("Stack with pod below into a Shared Major Pod")
                            }

                            Spacer(minLength: 0)

                            // Throw to Opposite Rail
                            Button {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                    store.movePod(id: pod.id, to: edge == .left ? .right : .left)
                                    store.triggerControlHaptic(.alignment)
                                }
                            } label: {
                                Text("⇄")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(palette.warningAccent)
                                    .frame(width: 19, height: 17)
                                    .background(palette.warningAccent.opacity(0.18))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.tactile)
                            .help(edge == .left ? "Throw to Right Rail" : "Throw to Left Rail")
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged { value in
                            if moveInitialStart == nil {
                                moveInitialStart = item.startY / safeTotalH
                                lastMoveHapticStep = 0
                            }
                            dragVisualOffsetY = value.translation.height
                            let deltaY = Double(value.translation.height)
                            let step = Int(deltaY / 24.0)
                            if step != lastMoveHapticStep {
                                lastMoveHapticStep = step
                                store.triggerControlHaptic(.alignment)
                            }
                            let baseStart = moveInitialStart ?? (item.startY / safeTotalH)
                            onDragMoveChanged(value.translation.height, baseStart)
                        }
                        .onEnded { value in
                            let baseStart = moveInitialStart ?? (item.startY / safeTotalH)
                            dragVisualOffsetY = 0.0
                            moveInitialStart = nil
                            lastMoveHapticStep = 0
                            onDragMoveEnded(value.translation.height, baseStart)
                        }
                )

                // Bottom Resize Grip Bar (12pt tall, global coordinate space to prevent local feedback loop)
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 12)

                    Capsule()
                        .fill(isResizeHovered ? Color.white : podColor.opacity(0.85))
                        .frame(width: isResizeHovered ? 44 : 32, height: 3.5)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 12)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isResizeHovered = hovering
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if resizeInitialLength == nil {
                                resizeInitialLength = Double(item.spanH) / safeTotalH
                                resizeInitialStart = item.startY / safeTotalH
                                lastResizeHapticStep = 0
                            }
                            let deltaY = Double(value.translation.height)
                            let step = Int(deltaY / 20.0)
                            if step != lastResizeHapticStep {
                                lastResizeHapticStep = step
                                store.triggerControlHaptic(.alignment)
                            }
                            let baseLength = resizeInitialLength ?? (Double(item.spanH) / safeTotalH)
                            let baseStart = resizeInitialStart ?? pod.range.start
                            let minAllowedRatio = max(48.0 / safeTotalH, 0.05)
                            let rawLength = baseLength + (deltaY / safeTotalH)
                            let maxLegalLength = max(0.98 - baseStart, minAllowedRatio)
                            let clampedLength = min(max(rawLength, minAllowedRatio), maxLegalLength)
                            store.updatePodRange(
                                id: pod.id,
                                newRange: NormalizedRange(start: baseStart, length: clampedLength)
                            )
                        }
                        .onEnded { _ in
                            resizeInitialLength = nil
                            resizeInitialStart = nil
                            lastResizeHapticStep = 0
                        }
                )
                .help("Drag vertically to resize height at 1:1 scale")
            }
            .frame(width: 198, height: spanH, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(podColor.opacity(0.22))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        isStackTargetHighlighted
                            ? Color.orange.opacity(isPulseOn ? 1.0 : 0.65)
                            : (isSharedStacked ? Color.orange.opacity(0.9) : podColor.opacity(0.85)),
                        lineWidth: isStackTargetHighlighted ? (isPulseOn ? 3.0 : 2.3) : 1.5
                    )
            )
            .shadow(
                color: isStackTargetHighlighted ? Color.orange.opacity(isPulseOn ? 0.85 : 0.45) : .clear,
                radius: isStackTargetHighlighted ? 10 : 0
            )
            .clipped()

            if isStackTargetHighlighted {
                Text("📦 Release or Hold to Stack")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.orange))
                    .shadow(color: Color.black.opacity(0.45), radius: 5)
            }
        }
        .scaleEffect(activelyDragging ? 1.03 : 1.0)
        .offset(y: activelyDragging ? dragVisualOffsetY : 0)
        .onChange(of: isStackTargetHighlighted) { _, highlighted in
            if highlighted {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    isPulseOn = true
                }
            } else {
                isPulseOn = false
            }
        }
    }
}
