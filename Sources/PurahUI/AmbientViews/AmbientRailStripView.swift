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
            let pages = store.paginatedPods(for: edge, totalHeight: Double(totalHeight))
            let pageCount = pages.count
            let currentPage = min(max(store.currentRailPage(for: edge), 0), max(pageCount - 1, 0))

            if store.isLiveRailEditingMode && !store.isRehearsingBreathingInSculptor {
                LiveRailSculptorStripView(edge: edge, store: store, totalHeight: totalHeight)
            } else {
                ZStack(alignment: edge == .left ? .topLeading : .topTrailing) {
                // Top & Bottom Hover Portals when multiple pages exist (avoiding 20pt macOS Hot Corners)
                if pageCount > 1 {
                    let alertingPages = store.alertingPageIndices(for: edge, totalHeight: Double(totalHeight))
                    let offPageAlert = store.firstOffPageAlertingPod(for: edge, totalHeight: Double(totalHeight))
                    let offPageAlertColor = offPageAlert.map { palette.podColor(for: $0.pod.id, store: store) }
                    let isTopPortalAlerting = (store.alertStyle != .off) && (offPageAlert.map { $0.pageIndex < currentPage } ?? false)
                    let isBottomPortalAlerting = (store.alertStyle != .off) && (offPageAlert.map { $0.pageIndex > currentPage } ?? false)

                    RailPagePortalView(
                        edge: edge,
                        direction: .previous,
                        currentPage: currentPage,
                        pageCount: pageCount,
                        barWidth: barW,
                        accentColor: palette.primaryAccent,
                        isRevealed: store.isPagePortalRevealed(for: edge, isTop: true) || isTopPortalAlerting,
                        isAlerting: isTopPortalAlerting,
                        alertingPageIndices: alertingPages,
                        alertColor: offPageAlertColor,
                        alertStyle: store.alertStyle
                    ) {
                        store.dismissActiveDrawer()
                        withAnimation(PurahMotionPolicy.pageFlip) {
                            store.cycleRailPage(for: edge, delta: -1)
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                    .offset(y: 22.0)
                    .zIndex(200)

                    RailPagePortalView(
                        edge: edge,
                        direction: .next,
                        currentPage: currentPage,
                        pageCount: pageCount,
                        barWidth: barW,
                        accentColor: palette.primaryAccent,
                        isRevealed: store.isPagePortalRevealed(for: edge, isTop: false) || isBottomPortalAlerting,
                        isAlerting: isBottomPortalAlerting,
                        alertingPageIndices: alertingPages,
                        alertColor: offPageAlertColor,
                        alertStyle: store.alertStyle
                    ) {
                        store.dismissActiveDrawer()
                        withAnimation(PurahMotionPolicy.pageFlip) {
                            store.cycleRailPage(for: edge, delta: 1)
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                    .offset(y: max(totalHeight - 42.0, 52.0))
                    .zIndex(200)
                }

                let isBreathing = store.isBreathingActive(for: edge, totalHeight: Double(totalHeight))

                // Active slot pods mounted with strict non-overlapping physical positions
                ForEach(layoutItems) { item in
                    let pod = item.pod
                    let spanH = CGFloat(item.spanH)
                    let startY = CGFloat(item.startY)
                    let drawerStartY = CGFloat(item.drawerStartY)
                    let drawerSpanH = CGFloat(item.drawerSpanH)
                    let isSharedMajorSubBar = (item.majorGroupId != nil && abs(drawerSpanH - spanH) > 1.0)
                    let shouldShowDrawer = store.shouldRenderDrawer(for: item, in: layoutItems)
                    let isThisPodActive = shouldShowDrawer || (store.hoveredPodId == pod.id || store.activePod?.id == pod.id || store.isItemPinned(id: pod.id) || store.capabilityProvider(for: pod.id)?.hasPinnedChild(store: store) == true)
                    let activeBarW: CGFloat = (isBreathing && isThisPodActive) ? (barW + 2.5) : barW

                    let isPinned = store.isItemPinned(id: pod.id)
                    let isActive = shouldShowDrawer
                    let context = makeContext(for: pod, totalHeight: spanH, isActive: isActive, isPinned: isPinned, railWidth: activeBarW)

                    VStack(alignment: edge == .left ? .leading : .trailing, spacing: 0) {
                        if let plugin = PluginRegistry.shared.plugin(for: pod.id) {
                            if !isSharedMajorSubBar && plugin.supportedDrawerModes.contains(.stepped) && store.isPodDecomposed(pod.id) && !plugin.steppedItems(context: context).isEmpty {
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
                    .opacity(isBreathing && store.activePod != nil && !isThisPodActive ? 0.65 : 1.0)
                    .offset(y: startY)
                    .zIndex(shouldShowDrawer ? 120 : (isThisPodActive ? 100 : 1))
                    .animation(PurahMotionPolicy.railReflow, value: spanH)
                    .animation(PurahMotionPolicy.railReflow, value: startY)
                    .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isThisPodActive)
                }
            }
            .frame(width: geo.size.width, height: totalHeight, alignment: edge == .left ? .topLeading : .topTrailing)
            .animation(
                PurahMotionPolicy.railReflow,
                value: layoutItems.map { "\($0.id)_\(Int($0.startY))_\(Int($0.spanH))" }
            )
            }
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
                store.activateDrawer(podId: pod.id)
            },
            requestDismiss: {
                withAnimation(PurahMotionPolicy.drawerExit) {
                    if store.activeDrawerItemId == pod.id {
                        store.activeDrawerItemId = nil
                    }
                    if store.activeDrawerPodId == pod.id {
                        store.activeDrawerPodId = nil
                    }
                    if store.hoveredPodId == pod.id {
                        store.hoveredPodId = nil
                    }
                    store.onDismissPreviewPanel?()
                    store.activePreviewScreenFrame = nil
                    store.invalidateLayoutCache()
                }
            },
            togglePin: {
                withAnimation(PurahMotionPolicy.buttonPop) {
                    store.togglePinItem(id: pod.id)
                }
            }
        )
    }

    private var drawerShape: UnevenRoundedRectangle {
        PurahDrawerShape.composite(edge: edge)
    }

    private var drawerTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    // MARK: - Plugin Pod Alert Helpers
    private func isPluginPodAlerting(plugin: any PurahPodPlugin, pod: SlotPod, context: PurahPluginContext) -> Bool {
        if store.isPodAlerting(podId: pod.id) {
            return true
        }
        let items = plugin.steppedItems(context: context)
        if items.contains(where: { $0.state == .alerting && !store.isAlertAcknowledged(id: $0.id) }) {
            return true
        }
        return false
    }

    private func acknowledgePluginPodAlerts(plugin: any PurahPodPlugin, pod: SlotPod, context: PurahPluginContext) {
        store.acknowledgeAllAlerts(forPodId: pod.id)
        for sub in plugin.steppedItems(context: context) where sub.state == .alerting {
            context.acknowledgeAlert(sub.id)
        }
        plugin.acknowledgeAllAlerts(context: context)
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
                store.activateDrawer(podId: pod.id)
            },
            requestDismiss: {
                withAnimation(PurahMotionPolicy.drawerExit) {
                    if store.activeDrawerItemId == pod.id {
                        store.activeDrawerItemId = nil
                    }
                    if store.activeDrawerPodId == pod.id {
                        store.activeDrawerPodId = nil
                    }
                    if store.hoveredPodId == pod.id {
                        store.hoveredPodId = nil
                    }
                    store.onDismissPreviewPanel?()
                    store.activePreviewScreenFrame = nil
                    store.invalidateLayoutCache()
                }
            },
            togglePin: {
                withAnimation(PurahMotionPolicy.buttonPop) {
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

        let isPodAlerting = (store.alertStyle != .off) && isPluginPodAlerting(plugin: plugin, pod: pod, context: barContext)

        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            plugin.makeRailBarView(context: barContext)
                .frame(width: railWidth, height: barSlotH)
                .dynamicAttentionBeacon(
                    isAlerting: isPodAlerting,
                    edge: edge,
                    baseWidth: railWidth,
                    color: color,
                    alertStyle: store.alertStyle
                ) {
                    acknowledgePluginPodAlerts(plugin: plugin, pod: pod, context: barContext)
                }
                .shadow(color: isThisPodActive ? color.opacity(0.6) : .clear, radius: isThisPodActive ? 6 : 0)
                .contentShape(Rectangle())
                // The rail bar is an icon-only, gesture-driven target; without
                // an explicit element VoiceOver reads nothing and cannot
                // activate it.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(pod.name)
                .accessibilityValue(isThisPodActive ? "Expanded" : "Collapsed")
                .accessibilityHint("Open \(pod.name) drawer")
                .accessibilityAddTraits(isThisPodActive ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction {
                    plugin.onRailBarTap(subItemId: nil, context: barContext)
                }
                .onTapGesture {
                    plugin.onRailBarTap(subItemId: nil, context: barContext)
                }
                .modifier(PurahDropIngestionModifier(types: plugin.supportedDropTypes) { providers in
                    plugin.onDrop(providers: providers, context: drawerContext)
                })

            if isActive {
                pluginDrawerCard(plugin: plugin, pod: pod, context: drawerContext, totalHeight: drawerSlotH)
                    .offset(y: drawerOffsetY)
                    .transition(drawerTransition)
                    .onAppear {
                        acknowledgePluginPodAlerts(plugin: plugin, pod: pod, context: barContext)
                    }
            }
        }
        .frame(height: barSlotH, alignment: .top)
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
                    // A drawer header is one row. With a long accessory (a note
                    // filename) this used to wrap onto a second line and squeeze
                    // the card; the title keeps its room and the accessory
                    // truncates instead.
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                if let accessory = plugin.makeHeaderAccessoryView(context: context) {
                    accessory
                }

                Spacer(minLength: 4)

                // Every drawer's controls — whatever the plugin contributes,
                // then the host's own gear and pin — sit on one faint plate.
                // It reads as a single control surface instead of loose glyphs
                // floating at the card's edge.
                PurahHeaderGroup(showsSurface: true) {
                    if let trailing = plugin.makeHeaderTrailingView(context: context) {
                        trailing
                        PurahHeaderDivider()
                    }

                    PurahHeaderButton(
                        systemImage: "gearshape",
                        help: String(format: "help.openSettingsNamed".localized, plugin.manifest.displayName)
                    ) {
                        store.openPluginSettings(id: pod.id)
                    }

                    pinButton(id: pod.id, isPinned: isPinned, color: color)
                }
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
        PurahPinButton(isPinned: isPinned, tintColor: color, showsDisc: false) {
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
    public var isRevealed: Bool = false
    public var isAlerting: Bool = false
    public var alertingPageIndices: Set<Int> = []
    public var alertColor: Color? = nil
    public var alertStyle: PluginAlertStyle = .breathingBeacon
    public let onTrigger: () -> Void

    @State private var isHovered: Bool = false

    public init(
        edge: MountEdge,
        direction: RailPagePortalDirection,
        currentPage: Int,
        pageCount: Int,
        barWidth: CGFloat = 8.0,
        accentColor: Color,
        isRevealed: Bool = false,
        isAlerting: Bool = false,
        alertingPageIndices: Set<Int> = [],
        alertColor: Color? = nil,
        alertStyle: PluginAlertStyle = .breathingBeacon,
        onTrigger: @escaping () -> Void
    ) {
        self.edge = edge
        self.direction = direction
        self.currentPage = currentPage
        self.pageCount = pageCount
        self.barWidth = barWidth
        self.accentColor = accentColor
        self.isRevealed = isRevealed
        self.isAlerting = isAlerting
        self.alertingPageIndices = alertingPageIndices
        self.alertColor = alertColor
        self.alertStyle = alertStyle
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
        let visible = isRevealed || isHovered || isAlerting
        let effectiveColor = isAlerting ? (alertColor ?? accentColor) : accentColor
        Button {
            onTrigger()
        } label: {
            VStack(spacing: 1.5) {
                if direction == .previous {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 6.5, weight: .black))
                        .foregroundColor(isHovered ? .white : effectiveColor)
                }

                VStack(spacing: 1.5) {
                    ForEach(0..<min(pageCount, 4), id: \.self) { idx in
                        let isPageAlerting = alertingPageIndices.contains(idx)
                        let dotColor = isPageAlerting
                            ? (alertColor ?? .orange)
                            : (idx == currentPage ? effectiveColor : effectiveColor.opacity(0.28))
                        let dotSize: CGFloat = isPageAlerting ? 3.5 : 2.5
                        Circle()
                            .fill(dotColor)
                            .frame(width: dotSize, height: dotSize)
                            .shadow(
                                color: (isPageAlerting || idx == currentPage) ? dotColor.opacity(0.85) : .clear,
                                radius: isPageAlerting ? 3.5 : 2.0
                            )
                    }
                }

                if direction == .next {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 6.5, weight: .black))
                        .foregroundColor(isHovered ? .white : effectiveColor)
                }
            }
            .frame(width: portalWidth, height: 20.0)
            .background(
                portalShape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        portalShape
                            .fill(effectiveColor.opacity(isHovered ? 0.28 : (isAlerting ? 0.22 : 0.12)))
                    )
                    .overlay(
                        portalShape
                            .strokeBorder(effectiveColor.opacity(isHovered ? 0.9 : (isAlerting ? 0.85 : 0.45)), lineWidth: (isHovered || isAlerting) ? 1.2 : 0.8)
                    )
            )
            .dynamicAttentionBeacon(
                isAlerting: isAlerting,
                edge: edge,
                baseWidth: portalWidth,
                color: effectiveColor,
                alertStyle: alertStyle
            )
            .shadow(color: effectiveColor.opacity(isHovered ? 0.75 : (isAlerting ? 0.65 : 0.25)), radius: (isHovered || isAlerting) ? 6 : 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("help.switchRailPage".localized)
        .opacity(visible ? 1.0 : 0.0)
        .offset(x: visible ? 0 : (edge == .left ? -16 : 16))
        .animation(PurahMotionPolicy.micro, value: visible)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
