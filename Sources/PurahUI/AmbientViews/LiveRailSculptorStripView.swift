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

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(edge: MountEdge, store: PurahWorkspaceStore, totalHeight: CGFloat) {
        self.edge = edge
        self.store = store
        self.totalHeight = totalHeight
    }

    private func buildClusters(from layoutItems: [ResolvedPodLayoutItem], strategy: RailOverflowStrategy) -> [SculptRailCluster] {
        guard strategy == .decomposedMajorPod else {
            return layoutItems.map { SculptRailCluster(id: $0.id, groupId: nil, items: [$0]) }
        }
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
        allItems: [ResolvedPodLayoutItem],
        edgeStrategy: RailOverflowStrategy
    ) -> String? {
        let draggedGroupId = (edgeStrategy == .decomposedMajorPod) ? draggedItem.majorGroupId : nil
        for otherItem in allItems where otherItem.pod.id != draggedItem.pod.id {
            let otherGroupId = (edgeStrategy == .decomposedMajorPod) ? otherItem.majorGroupId : nil
            if let g1 = draggedGroupId, let g2 = otherGroupId, g1 == g2 {
                continue
            }
            let topY = (edgeStrategy == .decomposedMajorPod ? otherItem.drawerStartY : otherItem.startY) + 8.0
            let bottomY = (edgeStrategy == .decomposedMajorPod ? (otherItem.drawerStartY + otherItem.drawerSpanH) : (otherItem.startY + otherItem.spanH)) - 8.0
            if bottomY > topY && currentCenterY >= topY && currentCenterY <= bottomY {
                return otherItem.pod.id
            }
        }
        return nil
    }

    public var body: some View {
        let safeHeight = max(Double(totalHeight), 400.0)
        let edgeStrategy = store.overflowStrategy(for: edge)
        let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: safeHeight)
        let clusters = buildClusters(from: layoutItems, strategy: edgeStrategy)
        let pages = (edgeStrategy == .pagedSpaces)
            ? store.paginatedPods(for: edge, totalHeight: safeHeight)
            : []
        let pageCount = max(pages.count, 1)
        let currentPage = min(max(store.currentRailPage(for: edge), 0), pageCount - 1)

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
                .stroke(palette.primaryAccent.opacity(0.45), lineWidth: 1.2)
            )
            .frame(width: 210, height: totalHeight)

            // Section A: Prominent Multi-Page Deck Header (when in Paged Spaces mode)
            if edgeStrategy == .pagedSpaces {
                pageDeckHeader(pages: pages, currentPage: currentPage)
                    .frame(width: 200, height: 58)
                    .offset(y: 8)
                    .zIndex(250)
            }

            // Section B: 1:1 Physical Sculpting Capsules & Unified Shared Major Pod Outer Boxes
            if layoutItems.isEmpty {
                emptyRailPlaceholder
                    .frame(width: 196, height: 140)
                    .offset(y: max((totalHeight - 140) * 0.5, 80))
            } else {
                ForEach(clusters) { cluster in
                    if cluster.isSharedMajorCluster, let groupId = cluster.groupId {
                        let isClusterHighlighted = cluster.items.contains { $0.pod.id == hoveredStackTargetPodId }
                        let isDraggingMember = cluster.items.contains { $0.pod.id == draggingPodId }
                        LiveSculptMajorClusterBoxView(
                            cluster: cluster,
                            groupId: groupId,
                            edge: edge,
                            totalHeight: totalHeight,
                            store: store,
                            isStackTargetHighlighted: isClusterHighlighted,
                            onSubPodDragChanged: { subItem, translationY in
                                if draggingPodId != subItem.pod.id {
                                    draggingPodId = subItem.pod.id
                                }
                                let currentCenterY = subItem.startY + (subItem.spanH * 0.5) + Double(translationY)
                                let matchedTarget = detectStackTargetPodId(
                                    draggedItem: subItem,
                                    currentCenterY: currentCenterY,
                                    allItems: layoutItems,
                                    edgeStrategy: edgeStrategy
                                )
                                if matchedTarget != hoveredStackTargetPodId {
                                    hoveredStackTargetPodId = matchedTarget
                                    if matchedTarget != nil {
                                        store.triggerControlHaptic(.levelChange)
                                    }
                                }
                            },
                            onSubPodDragEnded: { subItem, translationY in
                                if let targetId = hoveredStackTargetPodId {
                                    if store.overflowStrategy(for: edge) != .decomposedMajorPod {
                                        store.setOverflowStrategy(.decomposedMajorPod, for: edge)
                                    }
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                        store.addPodToMajorGroup(podId: subItem.pod.id, targetPodId: targetId)
                                        store.triggerControlHaptic(.levelChange)
                                    }
                                } else if abs(translationY) > 14 {
                                    if translationY < -14 && store.canMovePod(id: subItem.pod.id, direction: .up) {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            store.movePodInOrder(id: subItem.pod.id, direction: .up)
                                            store.triggerControlHaptic(.alignment)
                                        }
                                    } else if translationY > 14 && store.canMovePod(id: subItem.pod.id, direction: .down) {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            store.movePodInOrder(id: subItem.pod.id, direction: .down)
                                            store.triggerControlHaptic(.alignment)
                                        }
                                    }
                                }
                                hoveredStackTargetPodId = nil
                                draggingPodId = nil
                            }
                        )
                        .frame(width: 202, height: max(CGFloat(cluster.drawerSpanH), 84))
                        .offset(y: CGFloat(cluster.drawerStartY))
                        .zIndex(isDraggingMember ? 200 : (isClusterHighlighted ? 120 : 10))
                    } else if let item = cluster.items.first {
                        let isHighlighted = (hoveredStackTargetPodId == item.pod.id)
                        let isDraggingThis = (draggingPodId == item.pod.id)
                        LiveSculptPodCapsuleView(
                            item: item,
                            edge: edge,
                            edgeStrategy: edgeStrategy,
                            pageCount: pageCount,
                            totalHeight: totalHeight,
                            store: store,
                            isStackTargetHighlighted: isHighlighted,
                            onDragMoveChanged: { translationY, baseStart in
                                if draggingPodId != item.pod.id {
                                    draggingPodId = item.pod.id
                                }
                                let currentCenterY = item.startY + (item.spanH * 0.5) + Double(translationY)
                                let matchedTarget = detectStackTargetPodId(
                                    draggedItem: item,
                                    currentCenterY: currentCenterY,
                                    allItems: layoutItems,
                                    edgeStrategy: edgeStrategy
                                )
                                if matchedTarget != hoveredStackTargetPodId {
                                    hoveredStackTargetPodId = matchedTarget
                                    if matchedTarget != nil {
                                        store.triggerControlHaptic(.levelChange)
                                    }
                                }
                                if matchedTarget == nil {
                                    let newStart = min(max(baseStart + (Double(translationY) / safeHeight), 0.02), max(0.96 - item.pod.range.length, 0.02))
                                    store.updatePodRange(
                                        id: item.pod.id,
                                        newRange: NormalizedRange(start: newStart, length: item.pod.range.length)
                                    )
                                }
                            },
                            onDragMoveEnded: { translationY, baseStart in
                                if let targetId = hoveredStackTargetPodId {
                                    if store.overflowStrategy(for: edge) != .decomposedMajorPod {
                                        store.setOverflowStrategy(.decomposedMajorPod, for: edge)
                                    }
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                        store.addPodToMajorGroup(podId: item.pod.id, targetPodId: targetId)
                                        store.triggerControlHaptic(.levelChange)
                                    }
                                } else {
                                    let newStart = min(max(baseStart + (Double(translationY) / safeHeight), 0.02), max(0.96 - item.pod.range.length, 0.02))
                                    store.updatePodRange(
                                        id: item.pod.id,
                                        newRange: NormalizedRange(start: newStart, length: item.pod.range.length)
                                    )
                                }
                                hoveredStackTargetPodId = nil
                                draggingPodId = nil
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
    public let onSubPodDragChanged: (ResolvedPodLayoutItem, CGFloat) -> Void
    public let onSubPodDragEnded: (ResolvedPodLayoutItem, CGFloat) -> Void

    @State private var resizeInitialRatio: Double? = nil
    @State private var lastResizeHapticStep: Int = 0
    @State private var isResizeHovered: Bool = false
    @State private var activeDraggingSubId: String? = nil
    @State private var activeSubDragOffsetY: CGFloat = 0.0

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
        onSubPodDragChanged: @escaping (ResolvedPodLayoutItem, CGFloat) -> Void = { _, _ in },
        onSubPodDragEnded: @escaping (ResolvedPodLayoutItem, CGFloat) -> Void = { _, _ in }
    ) {
        self.cluster = cluster
        self.groupId = groupId
        self.edge = edge
        self.totalHeight = totalHeight
        self.store = store
        self.isStackTargetHighlighted = isStackTargetHighlighted
        self.onSubPodDragChanged = onSubPodDragChanged
        self.onSubPodDragEnded = onSubPodDragEnded
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
                // Top Header Bar: Shared Stack summary + [Unstack All]
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

                // Stacked Sub-Pod Slices
                VStack(spacing: innerSpacing) {
                    ForEach(cluster.items) { subItem in
                        let pod = subItem.pod
                        let podColor = palette.podColor(for: pod.id, store: store)
                        let sliceRatio = CGFloat(max(subItem.spanH, 18.0) / totalSubSpan)
                        let sliceH = max(netSliceBudget * sliceRatio, 20.0)
                        let isDraggingSub = (activeDraggingSubId == pod.id)

                        VStack(alignment: .leading, spacing: 4) {
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

                            // Row 2: Action Toolbar Row — shown when sliceH >= 42
                            if sliceH >= 42 {
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
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, sliceH >= 48 ? 6 : 3)
                        .frame(height: sliceH, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(podColor.opacity(0.18))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(podColor.opacity(0.55), lineWidth: 0.9)
                        )
                        .contentShape(Rectangle())
                        .offset(y: isDraggingSub ? activeSubDragOffsetY : 0)
                        .zIndex(isDraggingSub ? 50 : 1)
                        .gesture(
                            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                .onChanged { value in
                                    activeDraggingSubId = pod.id
                                    activeSubDragOffsetY = value.translation.height
                                    onSubPodDragChanged(subItem, value.translation.height)
                                }
                                .onEnded { value in
                                    activeDraggingSubId = nil
                                    activeSubDragOffsetY = 0.0
                                    onSubPodDragEnded(subItem, value.translation.height)
                                }
                        )
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
                .gesture(
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
                        isStackTargetHighlighted ? palette.primaryAccent : Color.orange,
                        lineWidth: isStackTargetHighlighted ? 2.6 : 2.0
                    )
            )
            .shadow(
                color: isStackTargetHighlighted ? palette.primaryAccent.opacity(0.65) : Color.orange.opacity(0.25),
                radius: isStackTargetHighlighted ? 10 : 4
            )
            .clipped()

            if isStackTargetHighlighted {
                Text("📦 Release to Stack")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange))
                    .shadow(color: Color.black.opacity(0.45), radius: 5)
            }
        }
    }
}

public struct LiveSculptPodCapsuleView: View {
    public let item: ResolvedPodLayoutItem
    public let edge: MountEdge
    public let edgeStrategy: RailOverflowStrategy
    public let pageCount: Int
    public let totalHeight: CGFloat
    public let store: PurahWorkspaceStore
    public let isStackTargetHighlighted: Bool
    public let onDragMoveChanged: (CGFloat, Double) -> Void
    public let onDragMoveEnded: (CGFloat, Double) -> Void

    @State private var moveInitialStart: Double? = nil
    @State private var lastMoveHapticStep: Int = 0
    @State private var dragVisualOffsetY: CGFloat = 0.0
    @State private var resizeInitialLength: Double? = nil
    @State private var resizeInitialStart: Double? = nil
    @State private var lastResizeHapticStep: Int = 0
    @State private var isResizeHovered: Bool = false

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
        edgeStrategy: RailOverflowStrategy,
        pageCount: Int,
        totalHeight: CGFloat,
        store: PurahWorkspaceStore,
        isStackTargetHighlighted: Bool = false,
        onDragMoveChanged: @escaping (CGFloat, Double) -> Void = { _, _ in },
        onDragMoveEnded: @escaping (CGFloat, Double) -> Void = { _, _ in }
    ) {
        self.item = item
        self.edge = edge
        self.edgeStrategy = edgeStrategy
        self.pageCount = pageCount
        self.totalHeight = totalHeight
        self.store = store
        self.isStackTargetHighlighted = isStackTargetHighlighted
        self.onDragMoveChanged = onDragMoveChanged
        self.onDragMoveEnded = onDragMoveEnded
    }

    public var body: some View {
        let spanH = max(CGFloat(item.spanH), 22.0)
        let safeTotalH = max(Double(totalHeight), 400.0)
        let isSharedStacked = (edgeStrategy == .decomposedMajorPod && pod.majorGroupId != nil)

        ZStack {
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

                        // Paged Spaces: Page Assignment Menu
                        if edgeStrategy == .pagedSpaces {
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
                        }

                        // Decomposed Major Pod: Split / Stack buttons
                        if edgeStrategy == .decomposedMajorPod {
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

                // Bottom Resize Grip Bar (10pt tall, global coordinate space to prevent local feedback loop)
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 10)

                    Capsule()
                        .fill(isResizeHovered ? Color.white : podColor.opacity(0.85))
                        .frame(width: isResizeHovered ? 44 : 32, height: 3.5)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isResizeHovered = hovering
                }
                .gesture(
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
                            ? Color.orange
                            : (isSharedStacked ? Color.orange.opacity(0.9) : podColor.opacity(0.85)),
                        lineWidth: isStackTargetHighlighted ? 2.5 : 1.5
                    )
            )
            .shadow(
                color: isStackTargetHighlighted ? Color.orange.opacity(0.65) : .clear,
                radius: isStackTargetHighlighted ? 8 : 0
            )
            .clipped()

            if isStackTargetHighlighted {
                Text("📦 Release to Stack")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.orange))
                    .shadow(color: Color.black.opacity(0.45), radius: 5)
            }
        }
        .offset(y: isStackTargetHighlighted ? 0 : (moveInitialStart != nil ? dragVisualOffsetY * 0.15 : 0))
    }
}
