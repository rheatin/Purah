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
        let isDynamicAccordion = store.isBreathingActive(for: edge)
        let maxAllowedItems = isDynamicAccordion
            ? max(policy.maxRailItems, 1)
            : max(min(Int((totalHeight + spacing) / (minChipH + spacing)), policy.maxRailItems), 1)

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
                        id: PurahPluginSubItem.moreItemsID(forPod: pod.id),
                        title: "+\(remaining) More",
                        systemIcon: "ellipsis",
                        badge: "\(remaining)",
                        state: .normal
                    ))
                }
                return result
            }
        }()

        let effectiveMinChipH: CGFloat = isDynamicAccordion ? 6.0 : minChipH

        let barW = max(context.railWidth, CGFloat(store.railBarWidth))

        // Merged overview state: when the smart-fold "+N" chip is hovered-open
        // or pinned, the item list folds down to just that chip and its slot
        // grows to the pod's full height — same ForEach identity, so chips
        // fading out, the bar stretching, and the drawer sliding in all run as
        // ONE animation transaction instead of a two-stage swap.
        let mergedChip = PurahPluginSubItem.mergedOverviewChip(
            in: items,
            activeDrawerItemId: store.activeDrawerItemId,
            isItemPinned: { store.isItemPinned(id: $0) }
        )
        let displayItems: [PurahPluginSubItem] = mergedChip.map { [$0] } ?? items
        // "+N" exclusion set = everything the rail displayed before merging;
        // merging collapses chips visually but they stay excluded.
        let railChipIDs = Set(items.map(\.id))
        let isMerged = mergedChip != nil
        let slotCount = max(displayItems.count, 1)
        let slotSpacing = spacing * CGFloat(slotCount - 1)
        let slotH: CGFloat = isMerged
            ? totalHeight
            : min(max((totalHeight - slotSpacing) / CGFloat(slotCount), effectiveMinChipH), maxChipH)
        let displaySpanH = CGFloat(displayItems.count) * slotH + slotSpacing

        Group {
            if displayItems.isEmpty {
                plugin.makeRailBarView(context: context)
                    .frame(width: barW, height: totalHeight)
            } else {
                VStack(alignment: edge == .left ? .leading : .trailing, spacing: spacing) {
                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { idx, subItem in
                        let isPinned = store.isItemPinned(id: subItem.id)
                        let isActive = (subItem.id == store.activeDrawerItemId || isPinned)
                        let state: ItemDrawerState = isActive ? .expandedDrawer : .dockedFlush
                        // The chip is drawn from a clear shape with no text, so
                        // VoiceOver had nothing to read and nothing to activate.
                        let activate: () -> Void = {
                            let subContext = makeSubItemContext(for: subItem, itemH: slotH, isActive: state == .expandedDrawer, isPinned: isPinned, visibleIDs: railChipIDs)
                            plugin.onRailBarTap(subItemId: subItem.id, context: subContext)
                        }

                        // Coordinate alignment: an expanded card is chip height
                        // plus the host header, and is kept on screen at both
                        // edges. Same numbers as the hit box in the store.
                        let cardH = PurahSteppedCardMetrics.cardHeight(slotHeight: slotH, minChipHeight: minChipH)
                        let effectiveChipH = isActive ? cardH : slotH
                        let itemTop = startY + CGFloat(idx) * (slotH + spacing)
                        let shift = isActive
                            ? PurahSteppedCardMetrics.verticalShift(itemTop: itemTop, cardHeight: cardH, screenHeight: screenHeight)
                            : 0.0

                        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
                            subItemChip(subItem: subItem, state: state, isPinned: isPinned, itemH: effectiveChipH, visibleIDs: railChipIDs)
                                .id(subItem.id)
                                .offset(y: -shift)
                                // Zero Ghosting: chips are physical bezel
                                // extensions, so a smart-folded chip tucks
                                // back into the edge rather than fading out.
                                .transition(.asymmetric(
                                    insertion: .move(edge: edge == .right ? Edge.trailing : Edge.leading),
                                    removal: .move(edge: edge == .right ? Edge.trailing : Edge.leading)
                                ))

                            // Scope rail tap gestures strictly to the rail bar indicator shape (not the entire ZStack containing expanded card)
                            RoundedRectangle(cornerRadius: min(barW / 2, 4))
                                .fill(Color.clear)
                                .frame(width: barW, height: slotH)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: activate)
                                // A slot is a button.
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text(subItem.title))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { activate() }
                        }
                        .frame(height: slotH, alignment: .top)
                        .zIndex(isActive ? 100 : Double(10 - idx))
                    }
                }
                .frame(height: displaySpanH, alignment: .top)
            }
        }
        .animation(PurahMotionPolicy.railReflow, value: totalHeight)
        .animation(PurahMotionPolicy.railReflow, value: store.activeDrawerItemId)
        .modifier(PurahDropIngestionModifier(types: plugin.supportedDropTypes) { providers in
            plugin.onDrop(providers: providers, context: context)
        })
    }

    private func makeSubItemContext(for subItem: PurahPluginSubItem, itemH: CGFloat, isActive: Bool, isPinned: Bool, visibleIDs: Set<String> = []) -> PurahPluginContext {
        PurahPluginContext(
            pod: pod,
            edge: edge,
            railWidth: CGFloat(store.railBarWidth),
            slotHeight: itemH,
            drawerWidth: store.effectiveDrawerWidth(for: subItem.title, baseWidth: 280.0, podId: pod.id),
            isExpanded: isActive,
            isPinned: isPinned,
            accentColor: subItem.tintColorHex.flatMap { Color(hex: $0) } ?? context.accentColor,
            palette: palette,
            storage: context.storage,
            store: store,
            visibleSubItemIds: visibleIDs,
            requestExpand: {
                store.activateDrawer(podId: pod.id, itemId: subItem.id)
            },
            requestDismiss: {
                withAnimation(PurahMotionPolicy.drawerExit) {
                    if store.activeDrawerItemId == subItem.id {
                        store.activeDrawerItemId = nil
                    }
                }
            },
            togglePin: {
                withAnimation(PurahMotionPolicy.pin) {
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
        itemH: CGFloat,
        visibleIDs: Set<String>
    ) -> some View {
        let subContext = makeSubItemContext(for: subItem, itemH: itemH, isActive: state == .expandedDrawer, isPinned: isPinned, visibleIDs: visibleIDs)
        if state == .expandedDrawer, PurahPluginSubItem.isMoreItemsID(subItem.id),
           let content = plugin.makeOverviewDrawerContent(context: subContext) {
            // Zero Ghosting: the overview is a drawer-grade solid card, so it
            // must slide back into the bezel at full opacity — an opacity fade
            // makes it read as a translucent ghost floating over user content.
            overviewShell(subItem: subItem, context: subContext, content: content, height: itemH)
                .transition(.asymmetric(
                    insertion: .move(edge: edge == .right ? Edge.trailing : Edge.leading),
                    removal: .move(edge: edge == .right ? Edge.trailing : Edge.leading)
                ))
        } else if let hosted = hostedSteppedChip(
            subItem: subItem,
            state: state,
            isPinned: isPinned,
            itemH: itemH,
            visibleIDs: visibleIDs
        ) {
            hosted
        } else if let customDrawer = plugin.makeSteppedDrawerView(subItemId: subItem.id, context: subContext) {
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

    // MARK: - Host-owned stepped card

    /// A plugin that returns body content gets the standard card: rail bar,
    /// background, header with settings/pin, on-screen clamp, entrance/exit
    /// motion. It keeps the plugin out of height and chrome maths.
    private func hostedSteppedChip(
        subItem: PurahPluginSubItem,
        state: ItemDrawerState,
        isPinned: Bool,
        itemH: CGFloat,
        visibleIDs: Set<String>
    ) -> AnyView? {
        let isExpanded = (state == .expandedDrawer)
        let minChipH = plugin.decomposedPolicy(store: store).minChipHeight
        let cardH = PurahSteppedCardMetrics.cardHeight(slotHeight: itemH, minChipHeight: minChipH)
        let bodyH = PurahSteppedCardMetrics.bodyHeight(cardHeight: cardH)
        let contentContext = makeSubItemContext(
            for: subItem,
            itemH: bodyH,
            isActive: isExpanded,
            isPinned: isPinned,
            visibleIDs: visibleIDs
        )
        guard let content = plugin.makeSteppedDrawerContent(subItemId: subItem.id, context: contentContext) else {
            return nil
        }
        // A minimum-size chip is its row and nothing else. The plugin declares
        // the body height it can actually render at, so a graph is not squeezed
        // into a sliver under the row.
        let minBodyH = max(8.0, plugin.steppedDrawerMinimumBodyHeight(subItemId: subItem.id))
        let showsBody = bodyH >= minBodyH
        // Row accessories size themselves against the card, not the body.
        let rowContext = makeSubItemContext(
            for: subItem,
            itemH: cardH,
            isActive: isExpanded,
            isPinned: isPinned,
            visibleIDs: visibleIDs
        )

        let tintColor: Color = subItem.tintColorHex.flatMap { Color(hex: $0) } ?? context.accentColor
        return AnyView(
            ZStack(alignment: edge == .right ? .trailing : .leading) {
                subItemIndicatorBar(subItem: subItem, itemH: itemH, tintColor: tintColor)
                    .transaction { t in
                        if !store.isBreathingActive(for: edge) {
                            t.animation = nil
                        }
                    }

                if isExpanded {
                    hostedSteppedCard(
                        subItem: subItem,
                        isPinned: isPinned,
                        cardH: cardH,
                        tintColor: tintColor,
                        accessory: plugin.makeSteppedRowAccessory(subItemId: subItem.id, context: rowContext),
                        content: showsBody ? content : nil
                    )
                    .transition(.move(edge: edge == .right ? .trailing : .leading))
                }
            }
            .frame(height: itemH)
            .animation(isExpanded ? PurahMotionPolicy.drawerEntrance : PurahMotionPolicy.drawerExit, value: isExpanded)
        )
    }

    private func hostedSteppedCard(
        subItem: PurahPluginSubItem,
        isPinned: Bool,
        cardH: CGFloat,
        tintColor: Color,
        accessory: AnyView?,
        content: AnyView?
    ) -> some View {
        let effectiveW = store.effectiveDrawerWidth(for: subItem.title, baseWidth: 280.0, podId: pod.id)
        let rowH = PurahSteppedCardMetrics.rowHeight(cardHeight: cardH)

        return VStack(alignment: .leading, spacing: PurahSteppedCardMetrics.rowGap) {
            HStack(alignment: .center, spacing: 8) {
                steppedRow(
                    subItem: subItem,
                    scale: PurahSteppedCardMetrics.rowScale(cardHeight: cardH),
                    rowH: rowH,
                    tintColor: tintColor
                )

                // The row hugs its content so an accessory (a battery chart)
                // can take the width the text does not need.
                Spacer(minLength: 8)

                // The trailing column belongs to the host: a plugin action sits
                // to its left, never inside it, so it cannot collide with gear/pin.
                if let accessory {
                    accessory
                }

                PurahDrawerHeaderTools(
                    onSettings: { store.openPluginSettings(id: pod.id) },
                    settingsHelp: String(format: "help.openSettingsNamed".localized, plugin.manifest.displayName),
                    isPinned: isPinned,
                    tintColor: tintColor,
                    onTogglePin: {
                        withAnimation(PurahMotionPolicy.pin) {
                            store.togglePinItem(id: subItem.id)
                        }
                    }
                )
            }
            .frame(height: rowH)

            if let content {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, edge == .left ? 12 : 18)
        .padding(.trailing, edge == .left ? 18 : 12)
        .padding(.vertical, PurahSteppedCardMetrics.verticalPadding)
        .frame(width: effectiveW, height: cardH, alignment: edge == .left ? .leading : .trailing)
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
                withAnimation(PurahMotionPolicy.pin) {
                    store.togglePinItem(id: subItem.id)
                }
            } label: {
                Label(isPinned ? "Unpin Item" : "Pin Item", systemImage: isPinned ? "pin.slash" : "pin")
            }
        }
    }

    /// The chip's single row. A chip has no header — this row *is* the card, and
    /// every dimension in it scales with the card so a 40pt chip and a 120pt
    /// chip read as the same row rather than a small one with a dead band.
    private func steppedRow(
        subItem: PurahPluginSubItem,
        scale: CGFloat,
        rowH: CGFloat,
        tintColor: Color
    ) -> some View {
        let iconSize = min(26.0 * scale, rowH)

        return HStack(spacing: 6 * scale) {
            RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                .fill(tintColor.opacity(0.18))
                .frame(width: iconSize, height: iconSize)
                .overlay(
                    Image(systemName: subItem.systemIcon)
                        .font(.system(size: 14 * scale, weight: .semibold))
                        .foregroundColor(tintColor)
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4 * scale) {
                    Text(subItem.title)
                        .font(.system(size: 13 * scale, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    if let badge = subItem.badge {
                        Text(badge)
                            .font(.system(size: 8.5 * scale, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 4 * scale)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(tintColor.opacity(0.2)))
                            .foregroundColor(tintColor)
                    }
                }

                // The live second line: a calendar's time and place, a note's
                // path. It rides here because the shortest chip has no body.
                if let subtitle = subItem.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(palette.fontMono)
                        .font(.system(size: 11 * scale))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)
        }
        .frame(height: rowH)
        .layoutPriority(1)
    }

    /// Shared "+N" overview shell: rail bar across the merged slot plus the
    /// drawer-grade solid card. Plugins contribute content only; every
    /// overview therefore looks and animates identically.
    private func overviewShell(
        subItem: PurahPluginSubItem,
        context subContext: PurahPluginContext,
        content: AnyView,
        height: CGFloat
    ) -> some View {
        let barW = max(context.railWidth, CGFloat(store.railBarWidth))
        let drawerW = store.effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id)
        let tintColor = subContext.accentColor
        let isPinned = store.isItemPinned(id: subItem.id)
        // Fixed compact row: the overview exists to show as many entries as
        // possible, so extra height belongs to the list, never to the header.
        let rowH = PurahSteppedCardMetrics.baseRowHeight

        return ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            RoundedRectangle(cornerRadius: min(barW / 2, 4))
                .fill(tintColor.opacity(0.85))
                .frame(width: barW, height: height)

            // The +N card gets the same host row as every chip: icon, title,
            // badge and the gear/pin column. Plugins supply the list only.
            VStack(alignment: .leading, spacing: PurahSteppedCardMetrics.rowGap) {
                HStack(alignment: .center, spacing: 8) {
                    steppedRow(subItem: subItem, scale: 1.0, rowH: rowH, tintColor: tintColor)
                    Spacer(minLength: 8)
                    PurahDrawerHeaderTools(
                        onSettings: { store.openPluginSettings(id: pod.id) },
                        settingsHelp: String(format: "help.openSettingsNamed".localized, plugin.manifest.displayName),
                        isPinned: isPinned,
                        tintColor: tintColor,
                        onTogglePin: {
                            withAnimation(PurahMotionPolicy.pin) {
                                store.togglePinItem(id: subItem.id)
                            }
                        }
                    )
                }
                .frame(height: rowH)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.leading, edge == .left ? 12.0 : 18.0)
            .padding(.trailing, edge == .left ? 18.0 : 12.0)
            .padding(.vertical, 10)
            .frame(width: drawerW, height: height, alignment: .topLeading)
            .liquidDrawerBackground(
                shape: PurahDrawerShape.composite(edge: edge),
                accentColor: tintColor
            )
        }
        .frame(height: height, alignment: .top)
    }

    @ViewBuilder
    private func genericSubItemChip(
        subItem: PurahPluginSubItem,
        state: ItemDrawerState,
        isPinned: Bool,
        itemH: CGFloat
    ) -> some View {
        let tintColor: Color = subItem.tintColorHex.flatMap { Color(hex: $0) } ?? context.accentColor
        let isExpanded = (state == .expandedDrawer)
        let minChipH = plugin.decomposedPolicy(store: store).minChipHeight
        let cardH = isExpanded ? max(itemH, minChipH) : max(itemH, 6.0)

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            subItemIndicatorBar(subItem: subItem, itemH: cardH, tintColor: tintColor)
                .transaction { t in
                    if !store.isBreathingActive(for: edge) {
                        t.animation = nil
                    }
                }

            if isExpanded {
                genericSubItemDrawerCard(subItem: subItem, isPinned: isPinned, cardH: cardH, tintColor: tintColor)
                    .transition(.move(edge: edge == .right ? .trailing : .leading))
            }
        }
        .frame(height: cardH)
        .animation(isExpanded ? PurahMotionPolicy.drawerEntrance : PurahMotionPolicy.drawerExit, value: isExpanded)
    }

    @ViewBuilder
    private func subItemIndicatorBar(subItem: PurahPluginSubItem, itemH: CGFloat, tintColor: Color) -> some View {
        let barW = CGFloat(store.railBarWidth)
        let fill = subItem.gaugeStyle == .solid ? subItem.gaugeRatio : nil

        ZStack(alignment: .bottom) {
            PurahSegmentGaugeBarView(
                segments: fill.map {
                    [PurahGaugeSegment(id: subItem.id, ratio: $0, color: tintColor)]
                } ?? [],
                barWidth: barW,
                height: itemH,
                trackColor: baseFillColor(for: subItem.state, tintColor: tintColor)
            )
            // The chip's glow follows its activity state, not the metric level,
            // so it stays on the bar rather than on the filled channel.
            .modifier(OptionalGlow(color: tintColor, enabled: subItem.state == .alerting || subItem.state == .ongoing))

            if subItem.state == .running {
                Circle()
                    .fill(Color.white)
                    .frame(width: min(max(barW - 2, 3), 5), height: min(max(barW - 2, 3), 5))
                    .padding(.bottom, itemH / 2 - 2.5)
            }
        }
        .frame(width: barW, height: itemH)
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
        let effectiveW = store.effectiveDrawerWidth(for: subItem.title, baseWidth: 280.0, podId: pod.id)

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

            PurahDrawerHeaderTools(
                onSettings: { store.openPluginSettings(id: pod.id) },
                settingsHelp: String(format: "help.openSettingsNamed".localized, plugin.manifest.displayName),
                isPinned: isPinned,
                tintColor: tintColor,
                onTogglePin: {
                    withAnimation(PurahMotionPolicy.pin) {
                        store.togglePinItem(id: subItem.id)
                    }
                }
            )
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
                withAnimation(PurahMotionPolicy.pin) {
                    store.togglePinItem(id: subItem.id)
                }
            } label: {
                Label(isPinned ? "Unpin Item" : "Pin Item", systemImage: isPinned ? "pin.slash" : "pin")
            }
        }
    }

    private var drawerShape: UnevenRoundedRectangle {
        PurahDrawerShape.stepped(edge: edge)
    }
}
