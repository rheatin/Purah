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

            ZStack(alignment: edge == .left ? .topLeading : .topTrailing) {
                // Active slot pods mounted with strict non-overlapping physical positions
                ForEach(layoutItems) { item in
                    let pod = item.pod
                    let spanH = CGFloat(item.spanH)
                    let startY = CGFloat(item.startY)
                    let isThisPodActive = (store.activePod?.id == pod.id || store.isItemPinned(id: pod.id) || store.capabilityProvider(for: pod.id)?.hasPinnedChild(store: store) == true)

                    let isPinned = store.isItemPinned(id: pod.id)
                    let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
                    let context = makeContext(for: pod, totalHeight: spanH, isActive: isActive, isPinned: isPinned)

                    VStack(spacing: 0) {
                        if let plugin = PluginRegistry.shared.plugin(for: pod.id) {
                            if plugin.supportedDrawerModes.contains(.stepped) && store.isPodDecomposed(pod.id) {
                                SteppedRailContainerView(plugin: plugin, pod: pod, context: context, totalHeight: spanH, edge: edge, store: store)
                            } else {
                                renderPluginPod(plugin: plugin, pod: pod, totalHeight: spanH)
                            }
                        } else {
                            genericRailBar(pod: pod, totalHeight: spanH)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                    .frame(height: spanH, alignment: .top)
                    .offset(y: startY)
                    .zIndex(isThisPodActive ? 100 : 1)
                }
            }
            .frame(width: geo.size.width, height: totalHeight, alignment: edge == .left ? .topLeading : .topTrailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .left ? .leading : .trailing)
        .ignoresSafeArea()
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
                    store.activeDrawerItemId = pod.id
                    store.activeDrawerPodId = pod.id
                    store.hoveredPodId = pod.id
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
    private func renderPluginPod(plugin: any PurahPodPlugin, pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let color = plugin.dynamicBarColor(context: PurahPluginContext(
            pod: pod, edge: edge, railWidth: barW, slotHeight: max(totalHeight, 36.0),
            drawerWidth: store.effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id), isExpanded: isActive,
            isPinned: isPinned, accentColor: palette.podColor(for: pod.id, store: store),
            palette: palette, store: store, requestExpand: {}, requestDismiss: {}, togglePin: {}
        )) ?? palette.podColor(for: pod.id, store: store)
        let slotH = max(totalHeight, 36.0)

        let context = PurahPluginContext(
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
                    store.activeDrawerItemId = pod.id
                    store.activeDrawerPodId = pod.id
                    store.hoveredPodId = pod.id
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

        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            plugin.makeRailBarView(context: context)
                .frame(width: barW, height: slotH)
                .contentShape(Rectangle())
                .onHover { isHovered in
                    if isHovered {
                        guard store.activeDrawerPodId != nil || (store.edgeTriggerMode == .hoverDwell && store.edgeTriggerSensitivity == .agile) else { return }
                        context.requestExpand()
                    }
                }
                .onTapGesture {
                    plugin.onRailBarTap(subItemId: nil, context: context)
                }

            if isActive {
                pluginDrawerCard(plugin: plugin, pod: pod, context: context, totalHeight: slotH)
                    .transition(drawerTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: slotH, alignment: .top)
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: store.activeDrawerPodId)
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
                Spacer()

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
        .frame(width: store.effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id), height: totalHeight)
        .liquidDrawerBackground(shape: drawerShape, accentColor: color)
        .contextMenu {
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
    }

    private func pinButton(id: String, isPinned: Bool, color: Color) -> some View {
        PurahPinButton(isPinned: isPinned, tintColor: color) {
            store.togglePinItem(id: id)
        }
    }
}
