import SwiftUI
import AppKit
import PurahCore
import UniformTypeIdentifiers

public struct HardwareVitalsPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "vitals",
        displayName: "Hardware Vitals",
        systemIcon: "waveform.path.ecg",
        author: "Project Purah",
        version: "0.1.0",
        description: "Real-time hardware performance, memory, and power monitoring",
        defaultEdge: .left,
        preferredZone: .glance,
        ergonomicWeight: 35.0,
        minLengthRatio: 0.22,
        defaultColorHex: "#00E5A3",
        permissions: [.machTelemetry]
    )

    public let state: VitalsPluginState

    public init(state: VitalsPluginState = VitalsPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(VitalsRailBarPluginView(context: context, state: state))
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(HardwareVitalsDrawerView(state: state, store: context.store))
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            Text("CPU \(Int(state.metrics.cpuUsage * 100))%")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(context.accentColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(context.accentColor.opacity(0.16))
                .cornerRadius(3)
        )
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(VitalsPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.composite, .stepped] }

    public var decomposedPolicy: PurahDecomposedPolicy {
        PurahDecomposedPolicy(
            maxRailItems: state.enabledMetrics.count,
            minChipHeight: 56.0,
            maxChipHeight: 185.0,
            spacing: 2.5,
            overflowStrategy: .truncate
        )
    }

    public func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        decomposedPolicy
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        let isDecomp = state.isDecomposed || store._isVitalsDecomposed
        if isDecomp {
            return decomposedPolicy.calculateMinimumHeight(activeCount: state.enabledMetrics.count)
        }
        return 300.0
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        let metrics = !store._vitalsEnabledMetrics.isEmpty ? store._vitalsEnabledMetrics : state.enabledMetrics
        return metrics.contains { store.isItemPinned(id: "vitals-\($0.rawValue)") }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("vitals-")
    }

    public var isDecomposed: Bool {
        state.isDecomposed
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        state.isDecomposed || store._isVitalsDecomposed
    }

    public var subItemCount: Int {
        state.isDecomposed ? state.enabledMetrics.count : 0
    }

    public var subItemTitles: [String] {
        state.isDecomposed ? state.enabledMetrics.map(\.displayName) : []
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        let isDecomp = state.isDecomposed || store._isVitalsDecomposed
        guard isDecomp else { return 0 }
        let metrics = !store._vitalsEnabledMetrics.isEmpty ? store._vitalsEnabledMetrics : state.enabledMetrics
        return metrics.count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isVitalsDecomposed
        guard isDecomp else { return nil }
        let metrics = !store._vitalsEnabledMetrics.isEmpty ? store._vitalsEnabledMetrics : state.enabledMetrics
        guard metrics.indices.contains(index) else { return nil }
        return "vitals-\(metrics[index].rawValue)"
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isVitalsDecomposed
        guard isDecomp else { return nil }
        let metrics = !store._vitalsEnabledMetrics.isEmpty ? store._vitalsEnabledMetrics : state.enabledMetrics
        guard metrics.indices.contains(index) else { return nil }
        return metrics[index].displayName
    }

    public func dynamicBarColor(context: PurahPluginContext) -> Color? {
        VitalsColorResolver.overallVitalsColor(
            vitals: state.metrics,
            thresholds: state.thresholds,
            palette: context.palette
        )
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let metrics = state.metrics
        return state.enabledMetrics.map { metric in
            let ratio: Double = {
                switch metric {
                case .cpu: return metrics.cpuUsage
                case .gpu: return metrics.gpuUsage
                case .ram: return metrics.memoryUsage
                case .power: return Double(metrics.batteryLevel) / 100.0
                case .network: return min((metrics.networkDownSpeed + metrics.networkUpSpeed) / 10_485_760.0, 1.0)
                case .disk:
                    return metrics.diskTotalGB > 0 ? (metrics.diskTotalGB - metrics.diskFreeGB) / metrics.diskTotalGB : 0.5
                }
            }()
            let color = VitalsColorResolver.color(for: metric, vitals: metrics, thresholds: state.thresholds, palette: context.palette)
            let isAlerting = (metric == .cpu && metrics.cpuUsage > state.thresholds.cpuDanger) ||
                             (metric == .ram && metrics.memoryUsage > state.thresholds.ramDanger)
            return PurahPluginSubItem(
                id: "vitals-\(metric.rawValue)",
                title: metric.displayName,
                systemIcon: metric.systemIcon,
                state: isAlerting ? .alerting : .normal,
                gaugeRatio: ratio,
                gaugeStyle: .solid,
                tintColorHex: color.toHex(),
                isPinned: context.isItemPinned("vitals-\(metric.rawValue)")
            )
        }
    }

    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        let metricKey = subItemId.replacingOccurrences(of: "vitals-", with: "")
        guard let metric = VitalsMetricType(rawValue: metricKey) else { return nil }
        let isPinned = context.isItemPinned(subItemId)
        let state: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush
        return AnyView(
            VitalsItemDrawerView(
                metric: metric,
                edge: context.edge,
                state: state,
                isPinned: isPinned,
                height: context.slotHeight,
                store: context.store,
                onTogglePin: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        context.togglePin(subItemId)
                    }
                }
            )
        )
    }
}

public struct VitalsRailBarPluginView: View {
    public let context: PurahPluginContext
    public let state: VitalsPluginState

    public init(context: PurahPluginContext, state: VitalsPluginState? = nil) {
        self.context = context
        self.state = state ?? (PluginRegistry.shared.plugin(for: "vitals") as? HardwareVitalsPlugin)?.state ?? VitalsPluginState()
    }

    public var body: some View {
        let cpu = state.metrics.cpuUsage
        let isPulsing = cpu > 0.85
        let radius = min(context.railWidth / 2, 4)

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: radius)
                .fill(context.accentColor.opacity(0.25))
                .frame(width: context.railWidth, height: context.slotHeight)

            RoundedRectangle(cornerRadius: radius)
                .fill(context.accentColor)
                .frame(width: context.railWidth, height: max(context.slotHeight * CGFloat(cpu), 4.0))
                .modifier(OptionalGlow(color: context.accentColor, enabled: isPulsing))
        }
        .frame(width: context.railWidth, height: context.slotHeight)
    }
}

// MARK: - Script Runway Plugin

public struct VitalsPluginSettingsView: View {
    public let state: VitalsPluginState
    public let store: PurahWorkspaceStore

    public init(state: VitalsPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "vitals") as? HardwareVitalsPlugin)?.state ?? VitalsPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        let vitals = state.metrics
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Decompose into Stepped Metric Rail Chips", isOn: Binding(
                get: { state.isDecomposed },
                set: {
                    state.isDecomposed = $0
                    state.save()
                    store._isVitalsDecomposed = $0
                    store.savePersistentState()
                }
            ))
            .font(.subheadline.weight(.semibold))

            Text("Splits hardware monitoring into individual rail chips (CPU, GPU, RAM, Power, Network, Disk) like Calendar and Todo.")
                .font(.caption)
                .foregroundColor(.secondary)

            if state.isDecomposed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Visible Sub-Metrics")
                        .font(.caption.weight(.bold))

                    ForEach(VitalsMetricType.allCases) { metric in
                        let isIncluded = state.enabledMetrics.contains(metric)
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                if isIncluded {
                                    if state.enabledMetrics.count > 1 {
                                        state.enabledMetrics.removeAll { $0 == metric }
                                    }
                                } else {
                                    state.enabledMetrics.append(metric)
                                }
                                state.save()
                                store._vitalsEnabledMetrics = state.enabledMetrics
                                store.savePersistentState()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isIncluded ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isIncluded ? .accentColor : .secondary)
                                Image(systemName: metric.systemIcon)
                                    .font(.caption)
                                    .frame(width: 16)
                                Text(metric.displayName)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }

            Divider()

            // Dynamic Usage Color Thresholds Customization Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Dynamic Usage Color Thresholds")
                        .font(.caption.weight(.bold))
                    Spacer()
                    Button("Reset Thresholds to Defaults") {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            state.resetThresholds()
                            store._vitalsThresholds = state.thresholds
                            store.savePersistentState()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                // Visual 3-color legend/preview bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Color Progression (CPU Baseline)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("0% → \(Int(state.thresholds.cpuWarning * 100))% → \(Int(state.thresholds.cpuDanger * 100))% → 100%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    GeometryReader { geo in
                        let totalWidth = geo.size.width
                        let warnRatio = max(min(CGFloat(state.thresholds.cpuWarning), 1.0), 0.0)
                        let dangerRatio = max(min(CGFloat(state.thresholds.cpuDanger), 1.0), warnRatio)
                        let wGreen = warnRatio * totalWidth
                        let wAmber = max((dangerRatio - warnRatio) * totalWidth, 0)
                        let wRed = max(totalWidth - wGreen - wAmber, 0)

                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(VitalsColorResolver.healthyGreen)
                                .frame(width: wGreen)
                            Rectangle()
                                .fill(VitalsColorResolver.warningYellow)
                                .frame(width: wAmber)
                            Rectangle()
                                .fill(VitalsColorResolver.dangerRed)
                                .frame(width: wRed)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .frame(height: 10)

                    HStack {
                        HStack(spacing: 4) {
                            Circle().fill(VitalsColorResolver.healthyGreen).frame(width: 8, height: 8)
                            Text("Green (< \(Int(state.thresholds.cpuWarning * 100))%)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(VitalsColorResolver.warningYellow).frame(width: 8, height: 8)
                            Text("Amber (\(Int(state.thresholds.cpuWarning * 100))% ~ \(Int(state.thresholds.cpuDanger * 100))%)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(VitalsColorResolver.dangerRed).frame(width: 8, height: 8)
                            Text("Red (> \(Int(state.thresholds.cpuDanger * 100))%)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(6)

                // Sliders
                VStack(spacing: 8) {
                    // CPU Warning % (10% ~ 90%) & Danger % (50% ~ 99%)
                    thresholdRow(
                        title: "CPU Load",
                        warningLabel: "\(Int(state.thresholds.cpuWarning * 100))%",
                        warningValue: percentageBinding(for: \.cpuWarning, cappedBy: \.cpuDanger, isWarning: true),
                        warningRange: 10...90,
                        dangerLabel: "\(Int(state.thresholds.cpuDanger * 100))%",
                        dangerValue: percentageBinding(for: \.cpuDanger, cappedBy: \.cpuWarning, isWarning: false),
                        dangerRange: 50...99
                    )

                    // GPU Warning % (10% ~ 90%) & Danger % (50% ~ 99%)
                    thresholdRow(
                        title: "GPU Activity",
                        warningLabel: "\(Int(state.thresholds.gpuWarning * 100))%",
                        warningValue: percentageBinding(for: \.gpuWarning, cappedBy: \.gpuDanger, isWarning: true),
                        warningRange: 10...90,
                        dangerLabel: "\(Int(state.thresholds.gpuDanger * 100))%",
                        dangerValue: percentageBinding(for: \.gpuDanger, cappedBy: \.gpuWarning, isWarning: false),
                        dangerRange: 50...99
                    )

                    // RAM Warning % (20% ~ 90%) & Danger % (60% ~ 99%)
                    thresholdRow(
                        title: "Memory (RAM)",
                        warningLabel: "\(Int(state.thresholds.ramWarning * 100))%",
                        warningValue: percentageBinding(for: \.ramWarning, cappedBy: \.ramDanger, isWarning: true),
                        warningRange: 20...90,
                        dangerLabel: "\(Int(state.thresholds.ramDanger * 100))%",
                        dangerValue: percentageBinding(for: \.ramDanger, cappedBy: \.ramWarning, isWarning: false),
                        dangerRange: 60...99
                    )

                    // Battery Low Warning % (5% ~ 50%)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Battery Low Warning")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(Int(state.thresholds.batteryLow * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(VitalsColorResolver.warningYellow)
                        }

                        HStack(spacing: 8) {
                            Text("Level")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { state.thresholds.batteryLow * 100.0 },
                                    set: {
                                        state.thresholds.batteryLow = $0 / 100.0
                                        state.save()
                                        store._vitalsThresholds.batteryLow = state.thresholds.batteryLow
                                        store.savePersistentState()
                                    }
                                ),
                                in: 5...50,
                                step: 1
                            )
                        }
                    }

                    // Network Warning MB/s (1 ~ 100 MB/s)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Network Throughput")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("Warn: \(Int(state.thresholds.networkWarningMB)) MB/s")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(VitalsColorResolver.warningYellow)
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("Danger: \(Int(state.thresholds.networkDangerMB)) MB/s")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(VitalsColorResolver.dangerRed)
                        }

                        HStack(spacing: 8) {
                            Text("Warn")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { state.thresholds.networkWarningMB },
                                    set: {
                                        state.thresholds.networkWarningMB = min($0, state.thresholds.networkDangerMB - 1.0)
                                        state.save()
                                        store._vitalsThresholds.networkWarningMB = state.thresholds.networkWarningMB
                                        store.savePersistentState()
                                    }
                                ),
                                in: 1...100,
                                step: 1
                            )

                            Text("Danger")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 42, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { state.thresholds.networkDangerMB },
                                    set: {
                                        state.thresholds.networkDangerMB = max($0, state.thresholds.networkWarningMB + 1.0)
                                        state.save()
                                        store._vitalsThresholds.networkDangerMB = state.thresholds.networkDangerMB
                                        store.savePersistentState()
                                    }
                                ),
                                in: 10...200,
                                step: 1
                            )
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }

            Divider()

            HStack(spacing: 12) {
                Text("CPU: \(Int(vitals.cpuUsage * 100))%")
                    .font(.caption.monospaced())
                Text("RAM: \(Int(vitals.memoryUsage * 100))%")
                    .font(.caption.monospaced())
                Text("Disk: \(Int(vitals.diskFreeGB))GB Free")
                    .font(.caption.monospaced())
                Spacer()
                Button("Refresh") {
                    state.refreshMetrics(includeProcesses: true)
                }
                .buttonStyle(.tactile)
                .font(.caption.weight(.medium))
                .foregroundColor(.accentColor)
            }
            .foregroundColor(.secondary)
        }
    }

    private func percentageBinding(
        for keyPath: WritableKeyPath<VitalsColorThresholds, Double>,
        cappedBy limitKeyPath: KeyPath<VitalsColorThresholds, Double>,
        isWarning: Bool
    ) -> Binding<Double> {
        Binding(
            get: { state.thresholds[keyPath: keyPath] * 100.0 },
            set: { newVal in
                let val = newVal / 100.0
                let limit = state.thresholds[keyPath: limitKeyPath]
                state.thresholds[keyPath: keyPath] = isWarning ? min(val, limit - 0.05) : max(val, limit + 0.05)
                state.save()
                store._vitalsThresholds[keyPath: keyPath] = state.thresholds[keyPath: keyPath]
                store.savePersistentState()
            }
        )
    }

    @ViewBuilder
    private func thresholdRow(
        title: String,
        warningLabel: String,
        warningValue: Binding<Double>,
        warningRange: ClosedRange<Double>,
        dangerLabel: String,
        dangerValue: Binding<Double>,
        dangerRange: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("Warn: \(warningLabel)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(VitalsColorResolver.warningYellow)
                Text("•")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Danger: \(dangerLabel)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(VitalsColorResolver.dangerRed)
            }

            HStack(spacing: 8) {
                Text("Warn")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .leading)
                Slider(value: warningValue, in: warningRange, step: 1)

                Text("Danger")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 42, alignment: .leading)
                Slider(value: dangerValue, in: dangerRange, step: 1)
            }
        }
    }
}

