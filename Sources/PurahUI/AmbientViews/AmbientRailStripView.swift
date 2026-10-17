// Sources/PurahUI/AmbientViews/AmbientRailStripView.swift
import SwiftUI
import AppKit
import PurahCore

public struct AmbientRailStripView: View {
    public let edge: MountEdge
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var barW: CGFloat {
        CGFloat(store.railBarWidth)
    }

    public init(edge: MountEdge, store: PurahWorkspaceStore) {
        self.edge = edge
        self.store = store
    }

    public var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: Double(totalHeight))
            let pages = (store.railOverflowStrategy == .pagedSpaces)
                ? store.paginatedPods(for: edge, totalHeight: Double(totalHeight))
                : []
            let pageCount = pages.count
            let currentPage = min(max(store.currentRailPage(for: edge), 0), max(pageCount - 1, 0))

            ZStack(alignment: edge == .left ? .topLeading : .topTrailing) {
                // Page Pill Indicator for Paged Spaces when multiple pages exist
                if store.railOverflowStrategy == .pagedSpaces && pageCount > 1 {
                    RailPageIndicatorView(
                        edge: edge,
                        currentPage: currentPage,
                        pageCount: pageCount,
                        accentColor: palette.primaryAccent
                    ) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) {
                            store.cycleRailPage(for: edge, delta: 1)
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                    .offset(x: edge == .left ? 2 : -2, y: 10)
                    .zIndex(200)
                }

                // Shared Major Pod group brackets when in Decomposed Major Pod mode
                if store.railOverflowStrategy == .decomposedMajorPod {
                    ForEach(majorGroupClusters(from: layoutItems), id: \.groupId) { cluster in
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(palette.primaryAccent.opacity(0.45), lineWidth: 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(palette.primaryAccent.opacity(0.08))
                            )
                            .frame(width: barW + 3, height: CGFloat(cluster.spanH))
                            .offset(y: CGFloat(cluster.startY))
                            .allowsHitTesting(false)
                            .zIndex(0)
                    }
                }

                // Active slot pods mounted with strict non-overlapping physical positions
                ForEach(layoutItems) { item in
                    let pod = item.pod
                    let spanH = CGFloat(item.spanH)
                    let startY = CGFloat(item.startY)
                    let drawerStartY = CGFloat(item.drawerStartY)
                    let drawerSpanH = CGFloat(item.drawerSpanH)
                    let isSharedMajorSubBar = (store.railOverflowStrategy == .decomposedMajorPod && abs(drawerSpanH - spanH) > 1.0)
                    let shouldShowDrawer = store.shouldRenderDrawer(for: item, in: layoutItems)
                    let isThisPodActive = shouldShowDrawer || (store.activePod?.id == pod.id || store.isItemPinned(id: pod.id) || store.capabilityProvider(for: pod.id)?.hasPinnedChild(store: store) == true)

                    let isPinned = store.isItemPinned(id: pod.id)
                    let isActive = shouldShowDrawer
                    let context = makeContext(for: pod, totalHeight: spanH, isActive: isActive, isPinned: isPinned)

                    VStack(alignment: edge == .left ? .leading : .trailing, spacing: 0) {
                        if let plugin = PluginRegistry.shared.plugin(for: pod.id) {
                            if !isSharedMajorSubBar && plugin.supportedDrawerModes.contains(.stepped) && store.isPodDecomposed(pod.id) {
                                SteppedRailContainerView(
                                    plugin: plugin,
                                    pod: pod,
                                    context: context,
                                    totalHeight: spanH,
                                    edge: edge,
                                    store: store,
                                    startY: startY,
                                    screenHeight: totalHeight
                                )
                            } else {
                                renderPluginPod(
                                    plugin: plugin,
                                    pod: pod,
                                    barHeight: spanH,
                                    drawerHeight: drawerSpanH,
                                    drawerOffsetY: drawerStartY - startY,
                                    shouldShowDrawer: shouldShowDrawer
                                )
                            }
                        } else {
                            genericRailBar(pod: pod, totalHeight: spanH)
                        }
                    }
                    .frame(width: geo.size.width, height: spanH, alignment: edge == .left ? .topLeading : .topTrailing)
                    .offset(y: startY)
                    .zIndex(shouldShowDrawer ? 120 : (isThisPodActive ? 100 : 1))
                }
            }
            .frame(width: geo.size.width, height: totalHeight, alignment: edge == .left ? .topLeading : .topTrailing)
            .animation(
                .spring(response: 0.32, dampingFraction: 0.82),
                value: layoutItems.map { "\($0.id)_\(Int($0.startY))_\(Int($0.spanH))" }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .left ? .leading : .trailing)
        .ignoresSafeArea()
    }

    private struct MajorGroupCluster {
        let groupId: String
        let startY: Double
        let spanH: Double
    }

    private func majorGroupClusters(from items: [ResolvedPodLayoutItem]) -> [MajorGroupCluster] {
        var clusters: [MajorGroupCluster] = []
        var seen: Set<String> = []
        for item in items {
            guard let gid = item.majorGroupId, !seen.contains(gid) else { continue }
            let members = items.filter { $0.majorGroupId == gid }
            guard members.count > 1 else { continue }
            seen.insert(gid)
            clusters.append(MajorGroupCluster(groupId: gid, startY: item.drawerStartY, spanH: item.drawerSpanH))
        }
        return clusters
    }

    private func makeContext(for pod: SlotPod, totalHeight: CGFloat, isActive: Bool, isPinned: Bool) -> PurahPluginContext {
        let color = palette.podColor(for: pod.id, store: store)
        let slotH = max(totalHeight, 36.0)

        return PurahPluginContext(
            pod: pod,
            edge: edge,
            railWidth: barW,
            slotHeight: slotH,
            drawerWidth: store.effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id),
            isExpanded: isActive,
            isPinned: isPinned,
            accentColor: color,
            palette: palette,
            store: store,
            requestExpand: {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                    store.activateDrawer(podId: pod.id)
                }
            },
            requestDismiss: {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                    if store.activeDrawerItemId == pod.id {
                        store.activeDrawerItemId = nil
                    }
                    if store.activeDrawerPodId == pod.id {
                        store.activeDrawerPodId = nil
                    }
                }
            },
            togglePin: {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                    store.togglePinItem(id: pod.id)
                }
            }
        )
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            // Right rail: 10px continuous radius on the left, 0px flush against right bezel
            return UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        } else {
            // Left rail: 10px continuous radius on the right, 0px flush against left bezel
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 10,
                topTrailingRadius: 10,
                style: .continuous
            )
        }
    }

    private var drawerTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    // MARK: - Plugin Pod Rendering
    @ViewBuilder
    private func renderPluginPod(
        plugin: any PurahPodPlugin,
        pod: SlotPod,
        barHeight: CGFloat,
        drawerHeight: CGFloat,
        drawerOffsetY: CGFloat,
        shouldShowDrawer: Bool
    ) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = shouldShowDrawer
        let barSlotH = max(barHeight, 22.0)
        let drawerSlotH = max(drawerHeight, 36.0)
        let color = plugin.dynamicBarColor(context: PurahPluginContext(
            pod: pod, edge: edge, railWidth: barW, slotHeight: barSlotH,
            drawerWidth: store.effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id), isExpanded: isActive,
            isPinned: isPinned, accentColor: palette.podColor(for: pod.id, store: store),
            palette: palette, store: store, requestExpand: {}, requestDismiss: {}, togglePin: {}
        )) ?? palette.podColor(for: pod.id, store: store)

        let barContext = PurahPluginContext(
            pod: pod,
            edge: edge,
            railWidth: barW,
            slotHeight: barSlotH,
            drawerWidth: store.effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id),
            isExpanded: isActive,
            isPinned: isPinned,
            accentColor: color,
            palette: palette,
            store: store,
            requestExpand: {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                    store.activateDrawer(podId: pod.id)
                }
            },
            requestDismiss: {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                    if store.activeDrawerItemId == pod.id {
                        store.activeDrawerItemId = nil
                    }
                    if store.activeDrawerPodId == pod.id {
                        store.activeDrawerPodId = nil
                    }
                    store.invalidateLayoutCache()
                }
            },
            togglePin: {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                    store.togglePinItem(id: pod.id)
                }
            }
        )

        let drawerContext = PurahPluginContext(
            pod: pod,
            edge: edge,
            railWidth: barW,
            slotHeight: drawerSlotH,
            drawerWidth: store.effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id),
            isExpanded: isActive,
            isPinned: isPinned,
            accentColor: color,
            palette: palette,
            store: store,
            requestExpand: barContext.requestExpand,
            requestDismiss: barContext.requestDismiss,
            togglePin: barContext.togglePin
        )

        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            plugin.makeRailBarView(context: barContext)
                .frame(width: barW, height: barSlotH)
                .contentShape(Rectangle())
                .transaction { $0.animation = nil }
                .onTapGesture {
                    plugin.onRailBarTap(subItemId: nil, context: barContext)
                }

            if isActive {
                pluginDrawerCard(plugin: plugin, pod: pod, context: drawerContext, totalHeight: drawerSlotH)
                    .offset(y: drawerOffsetY)
                    .transition(drawerTransition)
            }
        }
        .frame(height: barSlotH, alignment: .top)
        .modifier(PurahDropIngestionModifier(types: plugin.supportedDropTypes) { providers in
            plugin.onDrop(providers: providers, context: drawerContext)
        })
    }

    @ViewBuilder
    private func pluginDrawerCard(plugin: any PurahPodPlugin, pod: SlotPod, context: PurahPluginContext, totalHeight: CGFloat) -> some View {
        let color = context.accentColor
        let isPinned = context.isPinned
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: plugin.manifest.systemIcon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(plugin.manifest.displayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                if let accessory = plugin.makeHeaderAccessoryView(context: context) {
                    accessory
                }

                Spacer()

                if let trailing = plugin.makeHeaderTrailingView(context: context) {
                    trailing
                }

                Button {
                    store.openPluginSettings(id: pod.id)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.tactile)
                .help("Open \(plugin.manifest.displayName) Settings")

                pinButton(id: pod.id, isPinned: isPinned, color: color)
            }
            plugin.makeDrawerView(context: context)
        }
        .padding(8)
        .frame(
            width: store.effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id),
            height: totalHeight,
            alignment: edge == .left ? .topLeading : .topTrailing
        )
        .clipped()
        .liquidDrawerBackground(shape: drawerShape, accentColor: color)
        .contextMenu {
            ForEach(plugin.contextMenuActions(subItemId: nil, context: context)) { menuAction in
                Button(role: menuAction.isDestructive ? .destructive : nil) {
                    menuAction.action()
                } label: {
                    if let icon = menuAction.systemImage {
                        Label(menuAction.title, systemImage: icon)
                    } else {
                        Text(menuAction.title)
                    }
                }
            }
            if !plugin.contextMenuActions(subItemId: nil, context: context).isEmpty {
                Divider()
            }
            Button {
                store.openPluginSettings(id: pod.id)
            } label: {
                Label("Configure \(plugin.manifest.displayName)...", systemImage: "gearshape")
            }
            Button {
                store.togglePinItem(id: pod.id)
            } label: {
                Label(isPinned ? "Unpin Drawer" : "Pin Drawer", systemImage: isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Button(role: .destructive) {
                store.togglePodEnabled(id: pod.id)
            } label: {
                Label("Unmount from Rail", systemImage: "xmark.circle")
            }
        }
    }

    @ViewBuilder
    private func genericRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: pod.id, store: store)
        RoundedRectangle(cornerRadius: 3.5)
            .fill(color.opacity(0.5))
            .frame(width: barW, height: totalHeight)
            .transaction { $0.animation = nil }
    }

    private func pinButton(id: String, isPinned: Bool, color: Color) -> some View {
        PurahPinButton(isPinned: isPinned, tintColor: color) {
            store.togglePinItem(id: id)
        }
    }
}

public struct RailPageIndicatorView: View {
    public let edge: MountEdge
    public let currentPage: Int
    public let pageCount: Int
    public let accentColor: Color
    public let onCyclePage: () -> Void

    public init(
        edge: MountEdge,
        currentPage: Int,
        pageCount: Int,
        accentColor: Color,
        onCyclePage: @escaping () -> Void
    ) {
        self.edge = edge
        self.currentPage = currentPage
        self.pageCount = pageCount
        self.accentColor = accentColor
        self.onCyclePage = onCyclePage
    }

    public var body: some View {
        Button {
            onCyclePage()
        } label: {
            HStack(spacing: 3) {
                ForEach(0..<pageCount, id: \.self) { idx in
                    Circle()
                        .fill(idx == currentPage ? accentColor : Color.secondary.opacity(0.45))
                        .frame(width: idx == currentPage ? 4.5 : 3.5, height: idx == currentPage ? 4.5 : 3.5)
                }
                Text("\(currentPage + 1)/\(pageCount)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(accentColor.opacity(0.5), lineWidth: 1)
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.tactile)
        .help("Switch Rail Page (\(currentPage + 1)/\(pageCount))")
    }
}
