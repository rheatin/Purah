// Sources/PurahUI/AmbientViews/SteppedRailContainerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct SteppedRailContainerView: View {
    public let plugin: any PurahPodPlugin
    public let pod: SlotPod
    public let context: PurahPluginContext
    public let totalHeight: CGFloat
    public let edge: MountEdge
    public let store: PurahWorkspaceStore
    public let startY: CGFloat
    public let screenHeight: CGFloat

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        plugin: any PurahPodPlugin,
        pod: SlotPod,
        context: PurahPluginContext,
        totalHeight: CGFloat,
        edge: MountEdge? = nil,
        store: PurahWorkspaceStore? = nil,
        startY: CGFloat = 0.0,
        screenHeight: CGFloat = 900.0
    ) {
        self.plugin = plugin
        self.pod = pod
        self.context = context
        self.totalHeight = totalHeight
        self.edge = edge ?? context.edge
        self.store = store ?? context.store
        self.startY = startY
        self.screenHeight = screenHeight
    }

    public var body: some View {
        let policy = plugin.decomposedPolicy(store: store)
        let allItems = plugin.steppedItems(context: context)
        let minChipH: CGFloat = policy.minChipHeight
        let maxChipH: CGFloat = policy.maxChipHeight
        let spacing: CGFloat = policy.spacing
        let maxAllowedItems = max(min(Int((totalHeight + spacing) / (minChipH + spacing)), policy.maxRailItems), 1)

        let items: [PurahPluginSubItem] = {
            guard allItems.count > maxAllowedItems else { return allItems }
            switch policy.overflowStrategy {
            case .truncate, .compactScale:
                return Array(allItems.prefix(maxAllowedItems))
            case .smartFold:
                if allItems.last?.id.contains("more_") == true {
                    return Array(allItems.prefix(maxAllowedItems))
                }
                let visibleCount = max(maxAllowedItems - 1, 1)
                var result = Array(allItems.prefix(visibleCount))
                let remaining = allItems.count - visibleCount
                if remaining > 0 {
                    result.append(PurahPluginSubItem(
                        id: "\(pod.id)_more_items",
                        title: "+\(remaining) More",
                        systemIcon: "ellipsis",
                        badge: "\(remaining)",
                        state: .normal
                    ))
                }
                return result
            }
        }()

        let count = max(items.count, 1)
        let totalSpacing = spacing * CGFloat(count - 1)
        let itemH = min(max((totalHeight - totalSpacing) / CGFloat(count), minChipH), maxChipH)
        let actualSpanH = CGFloat(items.count) * itemH + spacing * CGFloat(max(items.count - 1, 0))

        let barW = max(context.railWidth, CGFloat(store.railBarWidth))

        Group {
            if items.isEmpty {
                plugin.makeRailBarView(context: context)
                    .frame(width: barW, height: totalHeight)
            } else {
                VStack(alignment: edge == .left ? .leading : .trailing, spacing: spacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, subItem in
                        let isPinned = store.isItemPinned(id: subItem.id)
                        let isActive = (subItem.id == store.activeDrawerItemId || isPinned)
                        let state: ItemDrawerState = isActive ? .expandedDrawer : .dockedFlush

                        // Coordinate alignment: Shift expanded drawer card upward if it overflows screen bottom
                        let cardH = max(itemH, 44.0)
                        let itemTop = startY + CGFloat(idx) * (itemH + spacing)
                        let itemBottom = itemTop + cardH
                        let maxAllowedY = screenHeight - 12.0
                        let shift = isActive ? max(itemBottom - maxAllowedY, 0.0) : 0.0

                        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
                            subItemChip(subItem: subItem, state: state, isPinned: isPinned, itemH: itemH)
                                .id(subItem.id)
                                .offset(y: -shift)

                            // Scope rail tap gestures strictly to the rail bar indicator shape (not the entire ZStack containing expanded card)
                            RoundedRectangle(cornerRadius: min(barW / 2, 4))
                                .fill(Color.clear)
                                .frame(width: barW, height: itemH)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if store.dismissAlertOnHover && subItem.state == .alerting {
                                        store.acknowledgeAlert(id: subItem.id)
                                    }
                                    let subContext = makeSubItemContext(for: subItem, itemH: itemH, isActive: state == .expandedDrawer, isPinned: isPinned)
                                    plugin.onRailBarTap(subItemId: subItem.id, context: subContext)
                                }
                        }
                        .frame(height: itemH, alignment: .top)
                        .zIndex(isActive ? 100 : Double(10 - idx))
                    }
                }
                .frame(height: actualSpanH, alignment: .top)
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08), value: totalHeight)
        .modifier(PurahDropIngestionModifier(types: plugin.supportedDropTypes) { providers in
            plugin.onDrop(providers: providers, context: context)
        })
    }

    private func makeSubItemContext(for subItem: PurahPluginSubItem, itemH: CGFloat, isActive: Bool, isPinned: Bool) -> PurahPluginContext {
        PurahPluginContext(
            pod: pod,
            edge: edge,
            railWidth: CGFloat(store.railBarWidth),
            slotHeight: itemH,
            drawerWidth: store.effectiveDrawerWidth(for: subItem.title, baseWidth: 280.0),
            isExpanded: isActive,
            isPinned: isPinned,
            accentColor: subItem.tintColorHex.flatMap { Color(hex: $0) } ?? context.accentColor,
            palette: palette,
            storage: context.storage,
            store: store,
            requestExpand: {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                    store.activateDrawer(podId: pod.id, itemId: subItem.id)
                }
            },
            requestDismiss: {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                    if store.activeDrawerItemId == subItem.id {
                        store.activeDrawerItemId = nil
                    }
                }
            },
            togglePin: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                    store.togglePinItem(id: subItem.id)
                }
            },
            showToast: context.showToast,
            showWarning: context.showWarning,
            performHaptic: context.performHaptic,
            isSoundEnabled: context.isSoundEnabled,
            isHapticsEnabled: context.isHapticsEnabled,
            isDrawerPopHapticEnabled: context.isDrawerPopHapticEnabled,
            isControlHapticEnabled: context.isControlHapticEnabled,
            notificationSound: context.notificationSound,
            playSound: context.playSound
        )
    }

    @ViewBuilder
    private func subItemChip(
        subItem: PurahPluginSubItem,
        state: ItemDrawerState,
        isPinned: Bool,
        itemH: CGFloat
    ) -> some View {
        let subContext = makeSubItemContext(for: subItem, itemH: itemH, isActive: state == .expandedDrawer, isPinned: isPinned)
        if let customDrawer = plugin.makeSteppedDrawerView(subItemId: subItem.id, context: subContext) {
            customDrawer
        } else {
            genericSubItemChip(
                subItem: subItem,
                state: state,
                isPinned: isPinned,
                itemH: itemH
            )
        }
    }

    @ViewBuilder
    private func genericSubItemChip(
        subItem: PurahPluginSubItem,
        state: ItemDrawerState,
        isPinned: Bool,
        itemH: CGFloat
    ) -> some View {
        let tintColor: Color = subItem.tintColorHex.flatMap { Color(hex: $0) } ?? context.accentColor
        let cardH = max(itemH, 32.0)
        let drawerW = store.effectiveDrawerWidth(for: subItem.title, baseWidth: 280.0)
        let isExpanded = (state == .expandedDrawer)

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            subItemIndicatorBar(subItem: subItem, itemH: cardH, tintColor: tintColor)

            genericSubItemDrawerCard(subItem: subItem, isPinned: isPinned, cardH: cardH, tintColor: tintColor)
                .offset(x: isExpanded ? 0 : (edge == .right ? (drawerW + 50) : -(drawerW + 50)))
                .opacity(isExpanded ? 1.0 : 0.0)
                .allowsHitTesting(isExpanded)
        }
        .frame(height: cardH)
        .animation(state == .expandedDrawer ? .spring(response: 0.30, dampingFraction: 0.80) : .spring(response: 0.18, dampingFraction: 0.92), value: state)
    }

    @ViewBuilder
    private func subItemIndicatorBar(subItem: PurahPluginSubItem, itemH: CGFloat, tintColor: Color) -> some View {
        let barW = CGFloat(store.railBarWidth)
        let radius = min(barW / 2, 4)

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: radius)
                .fill(baseFillColor(for: subItem.state, tintColor: tintColor))
                .frame(width: barW, height: itemH)

            if subItem.gaugeStyle == .solid, let ratio = subItem.gaugeRatio {
                RoundedRectangle(cornerRadius: radius)
                    .fill(tintColor)
                    .frame(width: barW, height: max(itemH * CGFloat(min(max(ratio, 0.0), 1.0)), 4.0))
            }

            if subItem.state == .running {
                Circle()
                    .fill(Color.white)
                    .frame(width: min(max(barW - 2, 3), 5), height: min(max(barW - 2, 3), 5))
                    .padding(.bottom, itemH / 2 - 2.5)
            }
        }
        .frame(width: barW, height: itemH)
        .modifier(OptionalGlow(color: tintColor, enabled: subItem.state == .alerting || subItem.state == .ongoing))
    }

    private func baseFillColor(for state: RailItemActivityState, tintColor: Color) -> Color {
        switch state {
        case .normal:
            return tintColor.opacity(0.85)
        case .ongoing:
            return tintColor.opacity(0.95)
        case .alerting:
            return tintColor
        case .inactive:
            return tintColor.opacity(0.35)
        case .running:
            return tintColor.opacity(0.9)
        }
    }

    @ViewBuilder
    private func genericSubItemDrawerCard(
        subItem: PurahPluginSubItem,
        isPinned: Bool,
        cardH: CGFloat,
        tintColor: Color
    ) -> some View {
        let effectiveW = store.effectiveDrawerWidth(for: subItem.title, baseWidth: 280.0)

        HStack(spacing: 8) {
            Image(systemName: subItem.systemIcon)
                .foregroundColor(tintColor)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(subItem.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .lineLimit(1)

                    if let badge = subItem.badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(tintColor.opacity(0.2)))
                            .foregroundColor(tintColor)
                    }
                }

                if let subtitle = subItem.subtitle {
                    Text(subtitle)
                        .font(palette.fontMono)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            PurahPinButton(isPinned: isPinned, tintColor: tintColor) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                    store.togglePinItem(id: subItem.id)
                }
            }
        }
        .padding(.leading, edge == .left ? 10 : 20)
        .padding(.trailing, edge == .left ? 20 : 10)
        .padding(.vertical, 4)
        .frame(width: effectiveW, height: cardH)
        .liquidDrawerBackground(shape: drawerShape, accentColor: tintColor)
        .contextMenu {
            let subCtx = makeSubItemContext(for: subItem, itemH: cardH, isActive: true, isPinned: isPinned)
            ForEach(plugin.contextMenuActions(subItemId: subItem.id, context: subCtx)) { menuAction in
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
            if !plugin.contextMenuActions(subItemId: subItem.id, context: subCtx).isEmpty {
                Divider()
            }
            Button {
                store.openPluginSettings(id: pod.id)
            } label: {
                Label("Configure \(plugin.manifest.displayName)...", systemImage: "gearshape")
            }
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                    store.togglePinItem(id: subItem.id)
                }
            } label: {
                Label(isPinned ? "Unpin Item" : "Pin Item", systemImage: isPinned ? "pin.slash" : "pin")
            }
        }
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            return UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 8,
                topTrailingRadius: 8,
                style: .continuous
            )
        }
    }
}
