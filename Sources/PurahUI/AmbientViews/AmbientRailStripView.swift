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
            let edgeStrategy = store.overflowStrategy(for: edge)
            let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: Double(totalHeight))
            let pages = (edgeStrategy == .pagedSpaces)
                ? store.paginatedPods(for: edge, totalHeight: Double(totalHeight))
                : []
            let pageCount = pages.count
            let currentPage = min(max(store.currentRailPage(for: edge), 0), max(pageCount - 1, 0))

            ZStack(alignment: edge == .left ? .topLeading : .topTrailing) {
                // Top & Bottom Hover Portals for Paged Spaces when multiple pages exist (avoiding 20pt macOS Hot Corners)
                if edgeStrategy == .pagedSpaces && pageCount > 1 {
                    RailPagePortalView(
                        edge: edge,
                        direction: .previous,
                        currentPage: currentPage,
                        pageCount: pageCount,
                        barWidth: barW,
                        accentColor: palette.primaryAccent
                    ) {
                        store.dismissActiveDrawer()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            store.cycleRailPage(for: edge, delta: -1)
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                    .offset(y: 36.0)
                    .zIndex(200)

                    RailPagePortalView(
                        edge: edge,
                        direction: .next,
                        currentPage: currentPage,
                        pageCount: pageCount,
                        barWidth: barW,
                        accentColor: palette.primaryAccent
                    ) {
                        store.dismissActiveDrawer()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            store.cycleRailPage(for: edge, delta: 1)
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                    .offset(y: max(totalHeight - 64.0, 72.0))
                    .zIndex(200)
                }

                // Active slot pods mounted with strict non-overlapping physical positions
                ForEach(layoutItems) { item in
                    let pod = item.pod
                    let spanH = CGFloat(item.spanH)
                    let startY = CGFloat(item.startY)
                    let drawerStartY = CGFloat(item.drawerStartY)
                    let drawerSpanH = CGFloat(item.drawerSpanH)
                    let isSharedMajorSubBar = (edgeStrategy == .decomposedMajorPod && abs(drawerSpanH - spanH) > 1.0)
                    let shouldShowDrawer = store.shouldRenderDrawer(for: item, in: layoutItems)
                    let isThisPodActive = shouldShowDrawer || (store.hoveredPodId == pod.id || store.activePod?.id == pod.id || store.isItemPinned(id: pod.id) || store.capabilityProvider(for: pod.id)?.hasPinnedChild(store: store) == true)
                    let activeBarW: CGFloat = (edgeStrategy == .dynamicAccordion && isThisPodActive) ? (barW + 2.5) : barW

                    let isPinned = store.isItemPinned(id: pod.id)
                    let isActive = shouldShowDrawer
                    let context = makeContext(for: pod, totalHeight: spanH, isActive: isActive, isPinned: isPinned, railWidth: activeBarW)

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
                                    shouldShowDrawer: shouldShowDrawer,
                                    railWidth: activeBarW,
                                    isThisPodActive: isThisPodActive
                                )
                            }
                        } else {
                            genericRailBar(pod: pod, totalHeight: spanH, railWidth: activeBarW, isThisPodActive: isThisPodActive)
                        }
                    }
                    .frame(width: geo.size.width, height: spanH, alignment: edge == .left ? .topLeading : .topTrailing)
                    .opacity(edgeStrategy == .dynamicAccordion && store.activePod != nil && !isThisPodActive ? 0.65 : 1.0)
                    .offset(y: startY)
                    .zIndex(shouldShowDrawer ? 120 : (isThisPodActive ? 100 : 1))
                    .animation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08), value: spanH)
                    .animation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08), value: startY)
                    .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isThisPodActive)
                }
            }
            .frame(width: geo.size.width, height: totalHeight, alignment: edge == .left ? .topLeading : .topTrailing)
            .animation(
                .spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08),
                value: layoutItems.map { "\($0.id)_\(Int($0.startY))_\(Int($0.spanH))" }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .left ? .leading : .trailing)
        .ignoresSafeArea()
    }

    private func makeContext(for pod: SlotPod, totalHeight: CGFloat, isActive: Bool, isPinned: Bool, railWidth: CGFloat) -> PurahPluginContext {
        let color = palette.podColor(for: pod.id, store: store)
        let slotH = max(totalHeight, 36.0)

        return PurahPluginContext(
            pod: pod,
            edge: edge,
            railWidth: railWidth,
            slotHeight: slotH,
            drawerWidth: store.effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id),
            isExpanded: isActive,
            isPinned: isPinned,
            accentColor: color,
            palette: palette,
            store: store,
            requestExpand: {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
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
                    if store.hoveredPodId == pod.id {
                        store.hoveredPodId = nil
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
        shouldShowDrawer: Bool,
        railWidth: CGFloat,
        isThisPodActive: Bool
    ) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = shouldShowDrawer
        let barSlotH = max(barHeight, 22.0)
        let drawerSlotH = max(drawerHeight, 36.0)
        let color = plugin.dynamicBarColor(context: PurahPluginContext(
            pod: pod, edge: edge, railWidth: railWidth, slotHeight: barSlotH,
            drawerWidth: store.effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id), isExpanded: isActive,
            isPinned: isPinned, accentColor: palette.podColor(for: pod.id, store: store),
            palette: palette, store: store, requestExpand: {}, requestDismiss: {}, togglePin: {}
        )) ?? palette.podColor(for: pod.id, store: store)

        let barContext = PurahPluginContext(
            pod: pod,
            edge: edge,
            railWidth: railWidth,
            slotHeight: barSlotH,
            drawerWidth: store.effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id),
            isExpanded: isActive,
            isPinned: isPinned,
            accentColor: color,
            palette: palette,
            store: store,
            requestExpand: {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
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
                    if store.hoveredPodId == pod.id {
                        store.hoveredPodId = nil
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
            railWidth: railWidth,
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
                .frame(width: railWidth, height: barSlotH)
                .shadow(color: isThisPodActive ? color.opacity(0.6) : .clear, radius: isThisPodActive ? 6 : 0)
                .contentShape(Rectangle())
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
    private func genericRailBar(pod: SlotPod, totalHeight: CGFloat, railWidth: CGFloat, isThisPodActive: Bool) -> some View {
        let color = palette.podColor(for: pod.id, store: store)
        RoundedRectangle(cornerRadius: 3.5)
            .fill(color.opacity(0.5))
            .frame(width: railWidth, height: totalHeight)
            .shadow(color: isThisPodActive ? color.opacity(0.6) : .clear, radius: isThisPodActive ? 6 : 0)
    }

    private func pinButton(id: String, isPinned: Bool, color: Color) -> some View {
        PurahPinButton(isPinned: isPinned, tintColor: color) {
            store.togglePinItem(id: id)
        }
    }
}

public enum RailPagePortalDirection: Sendable {
    case previous
    case next
}

public struct RailPagePortalView: View {
    public let edge: MountEdge
    public let direction: RailPagePortalDirection
    public let currentPage: Int
    public let pageCount: Int
    public let barWidth: CGFloat
    public let accentColor: Color
    public let onTrigger: () -> Void

    @State private var isHovered: Bool = false

    public init(
        edge: MountEdge,
        direction: RailPagePortalDirection,
        currentPage: Int,
        pageCount: Int,
        barWidth: CGFloat = 8.0,
        accentColor: Color,
        onTrigger: @escaping () -> Void
    ) {
        self.edge = edge
        self.direction = direction
        self.currentPage = currentPage
        self.pageCount = pageCount
        self.barWidth = barWidth
        self.accentColor = accentColor
        self.onTrigger = onTrigger
    }

    private var portalWidth: CGFloat {
        max(barWidth + 6.0, 14.0)
    }

    private var portalShape: UnevenRoundedRectangle {
        if edge == .right {
            return UnevenRoundedRectangle(
                topLeadingRadius: 7,
                bottomLeadingRadius: 7,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 7,
                topTrailingRadius: 7,
                style: .continuous
            )
        }
    }

    public var body: some View {
        Button {
            onTrigger()
        } label: {
            VStack(spacing: 2.5) {
                if direction == .previous {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 7.5, weight: .black))
                        .foregroundColor(isHovered ? .white : accentColor)
                }

                VStack(spacing: 2) {
                    ForEach(0..<min(pageCount, 4), id: \.self) { idx in
                        Circle()
                            .fill(idx == currentPage ? accentColor : accentColor.opacity(0.28))
                            .frame(width: 3, height: 3)
                            .shadow(color: idx == currentPage ? accentColor.opacity(0.85) : .clear, radius: 2)
                    }
                }

                if direction == .next {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 7.5, weight: .black))
                        .foregroundColor(isHovered ? .white : accentColor)
                }
            }
            .frame(width: portalWidth, height: 28.0)
            .background(
                portalShape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        portalShape
                            .fill(accentColor.opacity(isHovered ? 0.28 : 0.12))
                    )
                    .overlay(
                        portalShape
                            .strokeBorder(accentColor.opacity(isHovered ? 0.9 : 0.45), lineWidth: isHovered ? 1.2 : 0.8)
                    )
            )
            .shadow(color: accentColor.opacity(isHovered ? 0.75 : 0.25), radius: isHovered ? 6 : 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
