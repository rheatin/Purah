// Sources/PurahUI/Settings/VisualLayoutSimulatorView.swift
import SwiftUI
import PurahCore

public struct VisualLayoutSimulatorView: View {
    public let store: PurahWorkspaceStore

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
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
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

                // Capacity Overload Warning Banner
                if store.capacityRatio(for: .left) > 1.0 || store.capacityRatio(for: .right) > 1.0 {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rail Capacity Overload Warning")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.orange)

                            if store.capacityRatio(for: .left) > 1.0 {
                                let req = Int(store.totalRequiredHeight(for: .left))
                                let avail = Int(store.availableScreenHeight(for: .left))
                                let pct = Int(store.capacityRatio(for: .left) * 100)
                                Text("• Left Rail requires \(req)pt (available: \(avail)pt · \(pct)% used). Bottom chips may be crowded. Consider reducing decomposed sub-items or assigning modules to the right rail.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if store.capacityRatio(for: .right) > 1.0 {
                                let req = Int(store.totalRequiredHeight(for: .right))
                                let avail = Int(store.availableScreenHeight(for: .right))
                                let pct = Int(store.capacityRatio(for: .right) * 100)
                                Text("• Right Rail requires \(req)pt (available: \(avail)pt · \(pct)% used). Bottom chips may be crowded. Consider reducing decomposed sub-items or assigning modules to the left rail.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )
                }

                // 1. Mini Screen Simulation (Top Primary Focus)
                ScreenSimulationCanvas(store: store)

                // 2. High-Density Rail Overflow Mode Card
                overflowStrategyCard

                // 3. Rail Module Assembly Card
                moduleAssemblyCard

                // 3. Presets Card
                settingsCard(title: "simulator.presets".localized, icon: "sparkle") {
                    HStack(spacing: 12) {
                        ForEach(PodPreset.allCases) { preset in
                            Button {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                    store.applyPreset(preset)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.defaultTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(store.currentPreset == preset ? palette.primaryAccent : (palette.style == .native ? Color.primary : .white))
                                        .lineLimit(1)
                                    Text(preset.defaultDescription)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: 75, alignment: .topLeading)
                                .background(store.currentPreset == preset ? palette.surfaceBackground : Color(nsColor: .controlBackgroundColor).opacity(0.4))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(store.currentPreset == preset ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.tactile)
                        }
                    }
                }

                // 3. Rail & Drawer Geometry Card
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
                                    Text("Fixed width or content-driven adaptive sizing")
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
                }

                // Toggle 2: Always Compact Breathing (when breathing is enabled)
                if store.isDynamicBreathingEnabled {
                    Divider()

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(store.isAlwaysCompactBreathing ? palette.primaryAccent : .secondary)
                            .frame(width: 24, height: 24)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(store.isAlwaysCompactBreathing ? palette.primaryAccent.opacity(0.16) : Color.primary.opacity(0.06))
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text("overflow.breathing.alwaysCompactTitle".localized)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)

                            Text("overflow.breathing.alwaysCompactSubtitle".localized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { store.isAlwaysCompactBreathing },
                            set: { store.setAlwaysCompactBreathing($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    .padding(.leading, 12)
                }

                // Multi-Page Navigation when pages > 1
                if leftPageCount > 1 || rightPageCount > 1 {
                    Divider()

                    HStack(spacing: 12) {
                        if leftPageCount > 1 {
                            Button {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
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
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
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
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                    Text("\(mountedCount) of \(store.pods.count) mounted")
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
                        Text("Available to Mount (\(unmountedPods.count))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                            ForEach(unmountedPods) { pod in
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                                .help("Mount \(pod.name) to rail")
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
                            Text("Shared Major Slot · \(cluster.count) Stacked")
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
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.togglePodEnabled(id: pod.id)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.red.opacity(0.85))
                }
                .buttonStyle(.tactile)
                .help("Unmount \(pod.name) from rail")
            }

            // Row 2: Tactile Action Pill Bar
            HStack(spacing: 6) {
                // Page Pill Menu
                Menu {
                    ForEach(0...max(maxExistingPage, 2), id: \.self) { pageIdx in
                        Button("Page \(pageIdx + 1)\(pod.pageIndex == pageIdx ? " ✓" : "")") {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                store.setPodPage(id: pod.id, pageIndex: pageIdx)
                            }
                        }
                    }
                    Divider()
                    Button("+ New Page (P\(maxExistingPage + 2))") {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            store.setPodPage(id: pod.id, pageIndex: maxExistingPage + 1)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 8.5))
                        Text("Page \(pod.pageIndex + 1)")
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
                .help("Assign \(pod.name) to a specific rail page")

                // Stack / Unstack Pill
                if isStackedInCluster {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                    .help("Unstack \(pod.name) from its Shared Major Pod")
                } else if !otherPods.isEmpty {
                    Menu {
                        ForEach(otherPods) { otherPod in
                            Button("Stack with \(otherPod.name)") {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    store.addPodToMajorGroup(podId: otherPod.id, targetPodId: pod.id)
                                    store.triggerControlHaptic(.alignment)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("Stack With")
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
                    .help("Stack \(pod.name) with another module on this rail")
                }

                Spacer(minLength: 2)

                // Reorder: Move Up
                if store.canMovePod(id: pod.id, direction: .up) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                    .help("Move \(pod.name) up")
                }

                // Reorder: Move Down
                if store.canMovePod(id: pod.id, direction: .down) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                    .help("Move \(pod.name) down")
                }

                // Transfer Edge (Switch Rail Button)
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                .help("Move \(pod.name) to \(pod.edge == .left ? "Right" : "Left") Rail")
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
        .background(palette.surfaceBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.borderColor.opacity(0.35), lineWidth: 1)
        )
    }
}
