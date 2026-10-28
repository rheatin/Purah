// Sources/PurahUI/Settings/VisualLayoutSimulatorView.swift
import SwiftUI
import UniformTypeIdentifiers
import PurahCore

public struct VisualLayoutSimulatorView: View {
    public let store: PurahWorkspaceStore

    /// The name being typed for a new profile. Held here rather than in the
    /// store because an abandoned draft is not configuration.
    @State private var newProfileName: String = ""
    /// The profile whose name is being edited, if any.
    @State private var renamingProfileId: UUID?

    private var theme: ThemeManager {
        ThemeManager.shared
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        let palette = theme.palette

        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                // Top Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.2.square")
                                .foregroundColor(palette.primaryAccent)
                                .font(.title2)
                            Text("simulator.title".localized)
                                .font(.title3.weight(.bold))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)
                        }
                        Text("simulator.subtitle".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        store.triggerControlHaptic(.levelChange)
                        store.setLiveRailEditingMode(true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "viewfinder.rectangular")
                            Text("sculptor.enterButton".localized)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(palette.primaryAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(palette.primaryAccent.opacity(0.14))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(palette.primaryAccent.opacity(0.65), lineWidth: 1.2)
                        )
                    }
                    .buttonStyle(.tactile)

                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.autoLayoutAll()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("simulator.magicButton".localized)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(palette.style == .native ? Color.white : Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(palette.primaryAccent)
                        .cornerRadius(8)
                        .modifier(OptionalGlow(color: palette.primaryAccent, enabled: palette.useGlow))
                    }
                    .buttonStyle(.tactile)
                }
                .padding(.horizontal, 4)

                // 1. Context Profiles (whole-layout presets)
                contextProfilesCard

                // The miniature screen simulator that used to sit here is gone.
                // Editing belongs to the live rail sculptor (⌃⌥E), which is
                // 1:1 with the real bezel; a scaled-down copy underneath could
                // only approximate the same drags while adding a second set of
                // mount / transfer / page controls that this tab already owns.

                // 2. High-Density Rail Overflow Mode Card
                overflowStrategyCard

                // 3. Rail Module Assembly Card
                moduleAssemblyCard

                // 4. Rail & Drawer Geometry Card
                settingsCard(title: "layout.geometry.title".localized, icon: "ruler.fill") {
                    VStack(spacing: 16) {
                        // Rail bar width
                        PurahThemedSliderRow(
                            title: "layout.geometry.railWidth.title".localized,
                            subtitle: "Physical trigger bezel thickness (4px ~ 16px)",
                            value: Binding(
                                get: { store.railBarWidth },
                                set: {
                                    store.railBarWidth = $0
                                    store.savePersistentState()
                                    store.onWindowsRebuildNeeded?()
                                }
                            ),
                            range: 4.0...16.0,
                            step: 1.0,
                            valueBadgeText: "\(Int(store.railBarWidth)) px"
                        )

                        Divider()
                            .background(palette.borderColor.opacity(0.3))

                        // Drawer extrusion width mode
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("layout.geometry.drawerWidth.title".localized)
                                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                                    Text("simulator.widthMode".localized)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                PurahThemedSegmentedPicker(
                                    options: DrawerWidthMode.allCases,
                                    selection: Binding(
                                        get: { store.drawerWidthMode },
                                        set: {
                                            store.drawerWidthMode = $0
                                            store.savePersistentState()
                                        }
                                    ),
                                    titleForOption: { $0.localizedDisplayName }
                                )
                                .frame(width: 170)
                            }

                            if store.drawerWidthMode == .fixed {
                                PurahThemedSliderRow(
                                    title: "layout.geometry.fixedLength.title".localized,
                                    value: Binding(
                                        get: { store.fixedDrawerWidth },
                                        set: {
                                            store.fixedDrawerWidth = $0
                                            store.savePersistentState()
                                        }
                                    ),
                                    range: 220.0...330.0,
                                    step: 5.0,
                                    valueBadgeText: "\(Int(store.fixedDrawerWidth)) px"
                                )
                            } else {
                                Text("layout.geometry.adaptiveSubtitle".localized)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Frontmost-App Profile Switching sits last: it is a
                // once-in-a-while mapping, and the rail simulator above is what
                // the Layout tab is opened for. Keeping it up top pushed the
                // thing people actually came to see below the fold.
                appProfileSwitchCard(store: store, palette: palette)
                    .padding(.top, 8)
            }
            .padding(24)
            .frame(width: 680)
        }
        .frame(minHeight: 560)
    }

    // MARK: - Unified Elastic & Multi-Page Card
    private var overflowStrategyCard: some View {
        let palette = theme.palette
        let realLeftH = max(Double(store.availableScreenHeight(for: .left)), 600.0)
        let realRightH = max(Double(store.availableScreenHeight(for: .right)), 600.0)
        let leftPages = store.paginatedPods(for: .left, totalHeight: realLeftH)
        let rightPages = store.paginatedPods(for: .right, totalHeight: realRightH)
        let leftPageCount = max(leftPages.count, 1)
        let rightPageCount = max(rightPages.count, 1)
        let curLeftPage = min(max(store.currentRailPage(for: .left), 0), leftPageCount - 1)
        let curRightPage = min(max(store.currentRailPage(for: .right), 0), rightPageCount - 1)

        return settingsCard(title: "overflow.card.title".localized, icon: "rectangle.expand.vertical") {
            VStack(alignment: .leading, spacing: 14) {
                // Toggle 1: Dynamic Breathing
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: store.isDynamicBreathingEnabled ? "lungs.fill" : "lungs")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(store.isDynamicBreathingEnabled ? palette.primaryAccent : .secondary)
                        .frame(width: 24, height: 24)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(store.isDynamicBreathingEnabled ? palette.primaryAccent.opacity(0.16) : Color.primary.opacity(0.06))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("overflow.breathing.toggleTitle".localized)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)

                        Text("overflow.breathing.toggleSubtitle".localized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { store.isDynamicBreathingEnabled },
                        set: { store.setDynamicBreathingEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .purahRowAccessibility("overflow.breathing.toggleTitle".localized, detail: "overflow.breathing.toggleSubtitle".localized)
                }

                // Multi-Page Navigation when pages > 1
                if leftPageCount > 1 || rightPageCount > 1 {
                    Divider()

                    HStack(spacing: 12) {
                        if leftPageCount > 1 {
                            Button {
                                withAnimation(PurahMotionPolicy.drawerEntrance) {
                                    store.cycleRailPage(for: .left, delta: 1)
                                    store.triggerControlHaptic(.alignment)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.left.to.line")
                                        .font(.caption2)
                                    Text("\("overflow.paged.leftRail".localized): \(curLeftPage + 1)/\(leftPageCount)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    Image(systemName: "chevron.right.circle.fill")
                                        .font(.caption2)
                                }
                                .foregroundColor(palette.primaryAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(palette.primaryAccent.opacity(0.12))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.tactile)
                        }

                        Spacer()

                        if rightPageCount > 1 {
                            Button {
                                withAnimation(PurahMotionPolicy.drawerEntrance) {
                                    store.cycleRailPage(for: .right, delta: 1)
                                    store.triggerControlHaptic(.alignment)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.right.to.line")
                                        .font(.caption2)
                                    Text("\("overflow.paged.rightRail".localized): \(curRightPage + 1)/\(rightPageCount)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    Image(systemName: "chevron.right.circle.fill")
                                        .font(.caption2)
                                }
                                .foregroundColor(palette.primaryAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(palette.primaryAccent.opacity(0.12))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.tactile)
                        }
                    }
                }

                // Shared Major Pod / Stack manager section (always visible)
                sharedMajorPodToolbar
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Compact Shared Major Pod Toolbar
    private var sharedMajorPodToolbar: some View {
        let palette = theme.palette

        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: "square.stack.3d.down.right.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.orange)

            Text("overflow.majorPod.editorSubtitle".localized)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.autoStackMajorPods(for: .left)
                    store.autoStackMajorPods(for: .right)
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("overflow.majorPod.autoStack".localized)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.16))
                .foregroundColor(.orange)
                .cornerRadius(6)
            }
            .buttonStyle(.tactile)

            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.resetMajorGroups(for: .left)
                    store.resetMajorGroups(for: .right)
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .bold))
                    Text("overflow.majorPod.resetIndependent".localized)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.08))
                .foregroundColor(palette.style == .native ? Color.primary : .white)
                .cornerRadius(6)
            }
            .buttonStyle(.tactile)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1.0)
        )
    }

    private func majorPodClusters(for edge: MountEdge) -> [[SlotPod]] {
        store.majorPodClusters(for: edge)
    }

    // MARK: - Rail Module Assembly Card
    private var moduleAssemblyCard: some View {
        let palette = theme.palette
        let leftMountedPods = store.pods.filter { $0.isEnabled && $0.edge == .left }.sorted { $0.range.start < $1.range.start }
        let rightMountedPods = store.pods.filter { $0.isEnabled && $0.edge == .right }.sorted { $0.range.start < $1.range.start }
        let mountedCount = leftMountedPods.count + rightMountedPods.count
        let unmountedPods = store.pods.filter { !$0.isEnabled }

        return settingsCard(title: "layout.moduleAssembly.title".localized, icon: "square.grid.2x2.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("layout.moduleAssembly.subtitle".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "simulator.mountedCount".localized, mountedCount, store.pods.count))
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundColor(palette.primaryAccent)
                }

                // 1. Mounted Pods Split by Left Rail & Right Rail
                HStack(alignment: .top, spacing: 12) {
                    railAssemblyColumn(
                        edge: .left,
                        title: "Left Rail",
                        pods: leftMountedPods
                    )
                    railAssemblyColumn(
                        edge: .right,
                        title: "Right Rail",
                        pods: rightMountedPods
                    )
                }

                // 2. Unmounted Pods Tray (if any exist)
                if !unmountedPods.isEmpty {
                    Divider()
                        .background(palette.borderColor.opacity(0.35))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(format: "simulator.availableToMount".localized, unmountedPods.count))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                            ForEach(unmountedPods) { pod in
                                Button {
                                    withAnimation(PurahMotionPolicy.surface) {
                                        store.togglePodEnabled(id: pod.id)
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.green)

                                        Image(systemName: pod.systemIcon)
                                            .font(.caption2)
                                            .foregroundColor(palette.podColor(for: pod.id, store: store).opacity(0.8))

                                        Text(pod.name)
                                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.primary.opacity(0.03))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
                                    )
                                }
                                .buttonStyle(.tactile)
                                .help(String(format: "help.mountToRail".localized, pod.name))
                                .accessibilityLabel(String(format: "help.mountToRail".localized, pod.name))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func railAssemblyColumn(
        edge: MountEdge,
        title: String,
        pods: [SlotPod]
    ) -> some View {
        let palette = theme.palette
        let maxExistingPage = max(pods.map(\.pageIndex).max() ?? 0, 1)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: edge == .left ? "arrow.left.to.line" : "arrow.right.to.line")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(palette.primaryAccent)
                Text(title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)
                Spacer()
                Text("\(pods.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 2)

            let clusters = majorPodClusters(for: edge)
            ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                if cluster.count >= 2 {
                    let clusterIds = Set(cluster.map(\.id))
                    let availableToStack = pods.filter { !clusterIds.contains($0.id) }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.orange)
                            Text(String(format: "simulator.sharedMajorSlot".localized, cluster.count))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        ForEach(cluster) { pod in
                            assemblyPodRow(
                                pod: pod,
                                railPods: pods,
                                maxExistingPage: maxExistingPage,
                                isStackedInCluster: true
                            )
                        }

                        if !availableToStack.isEmpty {
                            Menu {
                                ForEach(availableToStack) { candidate in
                                    Button("Stack \(candidate.name) here") {
                                        withAnimation(PurahMotionPolicy.surface) {
                                            store.addPodToMajorGroup(podId: candidate.id, targetPodId: cluster[0].id)
                                            store.triggerControlHaptic(.alignment)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 8.5, weight: .semibold))
                                    Text("overflow.majorPod.addPlugin".localized)
                                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                        .lineLimit(1)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.12))
                                .foregroundColor(.orange)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.orange.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.top, 2)
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.55), lineWidth: 1.2)
                    )
                } else if let pod = cluster.first {
                    assemblyPodRow(
                        pod: pod,
                        railPods: pods,
                        maxExistingPage: maxExistingPage,
                        isStackedInCluster: false
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func assemblyPodRow(
        pod: SlotPod,
        railPods: [SlotPod],
        maxExistingPage: Int,
        isStackedInCluster: Bool
    ) -> some View {
        let palette = theme.palette
        let otherPods = railPods.filter { $0.id != pod.id }

        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Module Identity & Unmount
            HStack(spacing: 6) {
                if isStackedInCluster {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.orange)
                        .frame(width: 3, height: 14)
                }

                Image(systemName: pod.systemIcon)
                    .font(.system(size: 12))
                    .foregroundColor(palette.podColor(for: pod.id, store: store))

                Text(pod.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 4)

                // Unmount button
                Button {
                    withAnimation(PurahMotionPolicy.surface) {
                        store.togglePodEnabled(id: pod.id)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.red.opacity(0.85))
                }
                .buttonStyle(.tactile)
                .help(String(format: "help.unmountFromRail".localized, pod.name))
                .accessibilityLabel(String(format: "help.unmountFromRail".localized, pod.name))
            }

            // Row 2: Tactile Action Pill Bar
            HStack(spacing: 6) {
                // Page Pill Menu
                Menu {
                    ForEach(0...max(maxExistingPage, 2), id: \.self) { pageIdx in
                        Button("Page \(pageIdx + 1)\(pod.pageIndex == pageIdx ? " ✓" : "")") {
                            withAnimation(PurahMotionPolicy.surface) {
                                store.setPodPage(id: pod.id, pageIndex: pageIdx)
                            }
                        }
                    }
                    Divider()
                    Button("+ New Page (P\(maxExistingPage + 2))") {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.setPodPage(id: pod.id, pageIndex: maxExistingPage + 1)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 8.5))
                        Text(String(format: "simulator.page".localized, pod.pageIndex + 1))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(palette.primaryAccent.opacity(0.12))
                    .foregroundColor(palette.primaryAccent)
                    .cornerRadius(5)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
                .help(String(format: "help.assignPage".localized, pod.name))
                .accessibilityLabel(String(format: "help.assignPage".localized, pod.name))

                // Stack / Unstack Pill
                if isStackedInCluster {
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.splitPodFromMajorGroup(id: pod.id)
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "scissors")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("overflow.majorPod.unstack".localized)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.18))
                        .foregroundColor(.orange)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.tactile)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(String(format: "help.unstackNamed".localized, pod.name))
                    .accessibilityLabel(String(format: "help.unstackNamed".localized, pod.name))
                } else if !otherPods.isEmpty {
                    Menu {
                        ForEach(otherPods) { otherPod in
                            Button("Stack with \(otherPod.name)") {
                                withAnimation(PurahMotionPolicy.surface) {
                                    store.addPodToMajorGroup(podId: otherPod.id, targetPodId: pod.id)
                                    store.triggerControlHaptic(.alignment)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("simulator.stackWith".localized)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14))
                        .foregroundColor(.orange)
                        .cornerRadius(5)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(String(format: "help.stackWithModule".localized, pod.name))
                    .accessibilityLabel(String(format: "help.stackWithModule".localized, pod.name))
                }

                Spacer(minLength: 2)

                // Reorder: Move Up
                if store.canMovePod(id: pod.id, direction: .up) {
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.movePodInOrder(id: pod.id, direction: .up)
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .frame(width: 20, height: 20)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.tactile)
                    .help(String(format: "help.moveUpNamed".localized, pod.name))
                    .accessibilityLabel(String(format: "help.moveUpNamed".localized, pod.name))
                }

                // Reorder: Move Down
                if store.canMovePod(id: pod.id, direction: .down) {
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.movePodInOrder(id: pod.id, direction: .down)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .frame(width: 20, height: 20)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.tactile)
                    .help(String(format: "help.moveDownNamed".localized, pod.name))
                    .accessibilityLabel(String(format: "help.moveDownNamed".localized, pod.name))
                }

                // Transfer Edge (Switch Rail Button)
                Button {
                    withAnimation(PurahMotionPolicy.surface) {
                        store.movePod(id: pod.id, to: pod.edge == .left ? .right : .left)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: pod.edge == .left ? "arrow.right" : "arrow.left")
                            .font(.system(size: 8, weight: .bold))
                        Text(pod.edge == .left ? "To Right" : "To Left")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(palette.primaryAccent.opacity(0.15))
                    .foregroundColor(palette.primaryAccent)
                    .cornerRadius(5)
                }
                .buttonStyle(.tactile)
                .fixedSize(horizontal: true, vertical: false)
                .help(String(format: "help.moveOtherRail".localized, pod.name, pod.edge == .left ? "Right" : "Left"))
                .accessibilityLabel(String(format: "help.moveOtherRail".localized, pod.name, pod.edge == .left ? "Right" : "Left"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isStackedInCluster ? Color.orange.opacity(0.4) : palette.primaryAccent.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func settingsCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        let palette = theme.palette
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.primaryAccent)
                Text(title)
                    .font(.headline)
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)
            }

            content()
        }
        .padding(16)
        // Fill the column rather than sizing to content; see the identical
        // note in InteractionSettingsView.settingsCard.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.borderColor.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Context Profiles

    /// Named whole-layout snapshots.
    ///
    /// Placed at the top of the Layout tab because it acts on the entire
    /// arrangement rather than on one control, and a person reaching for it is
    /// usually about to rearrange everything.
    @ViewBuilder
    private var contextProfilesCard: some View {
        let palette = theme.palette
        let profiles = store.contextProfiles

        settingsCard(title: "profile.card.title".localized, icon: "square.stack.3d.up.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("profile.card.subtitle".localized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if profiles.profiles.isEmpty {
                    Text("profile.empty".localized)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 8) {
                        ForEach(profiles.profiles) { profile in
                            profileRow(profile: profile, isActive: profiles.activeProfileId == profile.id, palette: palette)
                        }
                    }
                }

                Divider()
                    .background(palette.borderColor.opacity(0.2))

                HStack(spacing: 8) {
                    TextField("profile.newPlaceholder".localized, text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .frame(maxWidth: 200)

                    Button {
                        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.saveProfile(named: name.isEmpty
                                          ? "profile.defaultName".localized
                                          : name)
                        newProfileName = ""
                        store.triggerControlHaptic(.alignment)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 10.5))
                            Text("profile.saveCurrent".localized)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(palette.borderColor.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.tactile)
                    .accessibilityLabel("profile.saveCurrent".localized)

                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func profileRow(profile: ContextProfile, isActive: Bool, palette: ThemePalette) -> some View {
        let isRenaming = renamingProfileId == profile.id
        // Two different questions, deliberately answered separately:
        // `isActive` is "this is the profile you last saved or applied", and
        // `matchesLayout` is "the rail right now looks exactly like this".
        // Only the second one makes Apply a no-op, and it is the only one that
        // should ever look like a completed state.
        let matchesLayout = store.layoutMatches(profile: profile)
        HStack(spacing: 8) {
            Image(systemName: matchesLayout ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundColor(matchesLayout ? palette.primaryAccent : palette.borderColor.opacity(0.5))

            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    // Commit on Return; the store rejects empty and duplicate
                    // names, so a bad entry leaves the old name in place rather
                    // than producing an unnamed profile.
                    TextField("profile.namePlaceholder".localized, text: Binding(
                        get: { profile.name },
                        set: { store.renameProfile(id: profile.id, to: $0) }
                    ), onCommit: { renamingProfileId = nil })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: 180)
                } else {
                    HStack(spacing: 5) {
                        Text(profile.name)
                            .font(.system(size: 11.5, weight: matchesLayout ? .semibold : .medium, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .lineLimit(1)
                        if matchesLayout {
                            Text("profile.current".localized)
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(palette.primaryAccent)
                        } else if isActive {
                            // Applied earlier, edited since. Worth saying,
                            // because the row would otherwise look identical
                            // to one that still matches.
                            Text("profile.modified".localized)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Text(profile.summary)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isRenaming {
                Button("profile.done".localized) { renamingProfileId = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(palette.primaryAccent)
            } else {
                // Apply stays enabled even on the active profile. The active
                // mark only says which profile was last saved or applied — the
                // user may have rearranged the rail since, and that is exactly
                // when they reach for Apply. Greying it out here made a saved
                // profile impossible to restore.
                Button("profile.apply".localized) {
                    store.applyProfile(id: profile.id)
                    store.triggerControlHaptic(.alignment)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(palette.primaryAccent)

                Button("profile.update".localized) {
                    store.updateProfile(id: profile.id)
                    store.triggerControlHaptic(.alignment)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

                Button {
                    renamingProfileId = profile.id
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("profile.rename".localized)

                Button {
                    store.deleteProfile(id: profile.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("profile.delete".localized)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(matchesLayout ? 0.05 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    matchesLayout ? palette.primaryAccent.opacity(0.4) : palette.borderColor.opacity(0.2),
                    lineWidth: matchesLayout ? 1.2 : 0.8
                )
        )
    }

    // MARK: - Frontmost-app profile switching

    /// The whitelist half of the feature: which app gets which profile, and
    /// what everything else falls back to.
    ///
    /// The unit is the profile, so there is nothing to configure per app beyond
    /// picking one — the arrangement itself was already described by the
    /// profiles card directly above.
    @ViewBuilder
    private func appProfileSwitchCard(store: PurahWorkspaceStore, palette: ThemePalette) -> some View {
        settingsCard(title: "layout.appProfile.card".localized, icon: "macwindow.on.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { store.isAppProfileSwitchingEnabled },
                    set: { newValue in
                        store.isAppProfileSwitchingEnabled = newValue
                        store.savePersistentState()
                        if newValue {
                            AppProfileSwitchService.shared.applyRememberedAppResolution()
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("layout.appProfile.toggle".localized)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                        Text("layout.appProfile.description".localized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if store.isAppProfileSwitchingEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        defaultProfileRow(store: store, palette: palette)
                        appWhitelistList(store: store, palette: palette)
                        HStack {
                            addAppMenu(store: store, palette: palette)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func defaultProfileRow(store: PurahWorkspaceStore, palette: ThemePalette) -> some View {
        let profiles = store.contextProfiles.profiles
        let current = store.contextProfiles.defaultProfileId
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("layout.appProfile.default".localized)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                    Text("layout.appProfile.default.subtitle".localized)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // The themed picker, not a stock `Picker(.menu)`: a native
                // popup renders as the one grey NSPopUpButton on a page of
                // themed controls, which reads as a bug rather than a choice.
                PurahThemedMenuPicker(
                    options: [UUID?.none] + profiles.map { Optional($0.id) },
                    selection: Binding<UUID?>(
                        get: { current },
                        set: { store.setDefaultProfile(id: $0) }
                    ),
                    titleForOption: { id in
                        guard let id, let profile = profiles.first(where: { $0.id == id }) else {
                            return "layout.appProfile.default.unset".localized
                        }
                        return profile.name
                    }
                )
                .disabled(profiles.isEmpty)
            }

            if current == nil || store.contextProfiles.defaultProfile == nil {
                // Without a fallback, every app off the list would leave the
                // last layout in place and the feature would look broken.
                Text("layout.appProfile.default.required".localized)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Every app with a profile, one row each.
    ///
    /// Flat rather than grouped by profile even though the model is
    /// profile → apps: a row is one decision ("what does *this* app get"), and
    /// the number of rows is the number of apps instead of profiles plus apps.
    @ViewBuilder
    private func appWhitelistList(store: PurahWorkspaceStore, palette: ThemePalette) -> some View {
        let bundleIds = orderedWhitelistedApps(store: store)
        if bundleIds.isEmpty {
            Text("layout.appProfile.empty".localized)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // One boxed row per app, the same row treatment the profiles card
            // above uses: two row idioms inside one settings window is exactly
            // the kind of drift this pass is meant to remove.
            VStack(spacing: 6) {
                ForEach(bundleIds, id: \.self) { bundleId in
                    appWhitelistRow(bundleId: bundleId, store: store, palette: palette)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                        )
                }
            }
        }
    }

    /// Whitelisted bundle ids in the order a person reads them: by app name.
    ///
    /// An app that is no longer installed still sorts by its bundle id, so a
    /// rule for a deleted app stays visible and removable instead of silently
    /// disappearing.
    private func orderedWhitelistedApps(store: PurahWorkspaceStore) -> [String] {
        store.contextProfiles.triggers
            .compactMap { $0.key.appBundleId }
            .sorted { lhs, rhs in
                AppIdentity.displayName(forBundleId: lhs)
                    .localizedStandardCompare(AppIdentity.displayName(forBundleId: rhs)) == .orderedAscending
            }
    }

    @ViewBuilder
    private func appWhitelistRow(bundleId: String, store: PurahWorkspaceStore, palette: ThemePalette) -> some View {
        let profiles = store.contextProfiles.profiles
        let assigned = store.contextProfiles.profileId(forApp: bundleId)
        let displayName = AppIdentity.displayName(forBundleId: bundleId)
        let isInstalled = AppIdentity.runningApp(forBundleId: bundleId) != nil
            || AppIdentity.icon(forBundleId: bundleId) != nil

        HStack(spacing: 8) {
            if let icon = AppIdentity.icon(forBundleId: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                // Same type as the profile rows above: 11.5 semibold name over a
                // 9pt monospaced identifier.
                Text(displayName)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(bundleId)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !isInstalled {
                        Text("layout.appProfile.notInstalled".localized)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // The picker *is* the relationship: an app maps to one profile, and
            // changing it here is how the mapping moves.
            if let selectionId = assigned ?? profiles.first?.id {
                PurahThemedMenuPicker(
                    options: profiles.map(\.id),
                    selection: Binding<UUID>(
                        get: { selectionId },
                        set: { newValue in
                            store.assignApp(bundleId: bundleId, to: newValue)
                            AppProfileSwitchService.shared.applyRememberedAppResolution()
                        }
                    ),
                    titleForOption: { id in
                        profiles.first { $0.id == id }?.name ?? "—"
                    }
                )
            }

            Button {
                store.removeAppTrigger(bundleId: bundleId)
                AppProfileSwitchService.shared.applyRememberedAppResolution()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("layout.appProfile.remove".localized)
            .accessibilityLabel("layout.appProfile.remove".localized)
        }
    }

    /// Adds an app to a profile, from the apps that are running or from disk.
    ///
    /// Running apps alone would make it impossible to configure an app before
    /// opening it — which is exactly when you think of doing so.
    @ViewBuilder
    private func addAppMenu(store: PurahWorkspaceStore, palette: ThemePalette) -> some View {
        let profiles = store.contextProfiles.profiles
        let listed = Set(orderedWhitelistedApps(store: store))
        let running = AppIdentity.runningAppCandidates()
        if !profiles.isEmpty {
            Menu {
                ForEach(running) { candidate in
                    Menu(candidate.name) {
                        ForEach(profiles) { profile in
                            Button(profile.name) {
                                addApp(candidate.bundleId, to: profile.id, store: store)
                            }
                        }
                    }
                    .disabled(listed.contains(candidate.bundleId))
                }
                if !running.isEmpty {
                    Divider()
                }
                Button("layout.appProfile.chooseInstalled".localized) {
                    chooseAppFromDisk(store: store)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10.5))
                    Text("layout.appProfile.add".localized)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(palette.borderColor.opacity(0.25), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .accessibilityLabel("layout.appProfile.add".localized)
        }
    }

    private func addApp(_ bundleId: String, to profileId: UUID, store: PurahWorkspaceStore) {
        store.assignApp(bundleId: bundleId, to: profileId)
        AppProfileSwitchService.shared.applyRememberedAppResolution()
    }

    /// Picks any installed `.app`, whether or not it is running.
    private func chooseAppFromDisk(store: PurahWorkspaceStore) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "layout.appProfile.chooseInstalled.prompt".localized
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleId = Bundle(url: url)?.bundleIdentifier else { return }

        let profiles = store.contextProfiles.profiles
        // A brand-new app has no mapping yet; put it on the default profile,
        // which is the one it would have landed on anyway.
        let target = store.contextProfiles.defaultProfileId ?? profiles.first?.id
        guard let target else { return }
        addApp(bundleId, to: target, store: store)
    }
}
