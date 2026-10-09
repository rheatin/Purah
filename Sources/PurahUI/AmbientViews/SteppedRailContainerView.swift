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

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        plugin: any PurahPodPlugin,
        pod: SlotPod,
        context: PurahPluginContext,
        totalHeight: CGFloat,
        edge: MountEdge? = nil,
        store: PurahWorkspaceStore? = nil
    ) {
        self.plugin = plugin
        self.pod = pod
        self.context = context
        self.totalHeight = totalHeight
        self.edge = edge ?? context.edge
        self.store = store ?? context.store
    }

    public var body: some View {
        let items = plugin.steppedItems(context: context)
        let count = max(items.count, 1)
        let spacing: CGFloat = 2.5
        let totalSpacing = spacing * CGFloat(count - 1)
        let availablePerItem = (totalHeight - totalSpacing) / CGFloat(count)
        let itemH = max(availablePerItem, 24.0)
        let totalSpanH = totalHeight

        Group {
            if items.isEmpty {
                plugin.makeRailBarView(context: context)
                    .frame(width: CGFloat(store.railBarWidth), height: totalHeight)
            } else {
                VStack(spacing: spacing) {
                    ForEach(items) { subItem in
                        let isPinned = store.isItemPinned(id: subItem.id)
                        let isActive = (subItem.id == store.activeDrawerItemId || isPinned)
                        let state: ItemDrawerState = isActive ? .expandedDrawer : .dockedFlush

                        ZStack(alignment: edge == .right ? .trailing : .leading) {
                            subItemChip(subItem: subItem, state: state, isPinned: isPinned, itemH: itemH)
                                .id(subItem.id)
                                .onHover { isHovered in
                                    if isHovered {
                                        if store.dismissAlertOnHover && subItem.state == .alerting {
                                            store.acknowledgeAlert(id: subItem.id)
                                        }
                                        guard store.activeDrawerPodId != nil || (store.edgeTriggerMode == .hoverDwell && store.edgeTriggerSensitivity == .agile) else { return }
                                        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                            store.activateDrawer(podId: pod.id, itemId: subItem.id)
                                        }
                                    }
                                }

                            // Scope rail tap gestures strictly to the rail bar indicator shape (not the entire ZStack containing expanded card)
                            RoundedRectangle(cornerRadius: min(CGFloat(store.railBarWidth) / 2, 4))
                                .fill(Color.clear)
                                .frame(width: CGFloat(store.railBarWidth), height: itemH)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    plugin.onRailBarTap(subItemId: subItem.id, context: context)
                                }
                        }
                        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                        .frame(height: itemH)
                    }
                }
                .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                .frame(height: totalSpanH)
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerPodId)
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
            performHaptic: context.performHaptic
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

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            subItemIndicatorBar(subItem: subItem, itemH: cardH, tintColor: tintColor)

            if state == .expandedDrawer {
                genericSubItemDrawerCard(subItem: subItem, isPinned: isPinned, cardH: cardH, tintColor: tintColor)
                    .transition(itemDrawerTransition)
            }
        }
        .frame(height: cardH)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: state)
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

    private var itemDrawerTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }
}
