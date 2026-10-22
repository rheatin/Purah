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
        let isDecomp = isDecomposed(store: store)
        if isDecomp {
            return decomposedPolicy.calculateMinimumHeight(activeCount: state.enabledMetrics.count)
        }
        return 300.0
    }

    public func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        max(minimumDrawerHeight(store: store), 260.0)
    }

    public var usesAdaptiveTelemetryColor: Bool { true }

    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        360.0
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
        state.isDecomposed && store._isVitalsDecomposed
    }

    public var subItemCount: Int {
        state.isDecomposed ? state.enabledMetrics.count : 0
    }

    public var subItemTitles: [String] {
        state.isDecomposed ? state.enabledMetrics.map(\.displayName) : []
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        let isDecomp = isDecomposed(store: store)
        guard isDecomp else { return 0 }
        let metrics = !store._vitalsEnabledMetrics.isEmpty ? store._vitalsEnabledMetrics : state.enabledMetrics
        return metrics.count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = isDecomposed(store: store)
        guard isDecomp else { return nil }
        let metrics = !store._vitalsEnabledMetrics.isEmpty ? store._vitalsEnabledMetrics : state.enabledMetrics
        guard metrics.indices.contains(index) else { return nil }
        return "vitals-\(metrics[index].rawValue)"
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = isDecomposed(store: store)
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

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

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
        VStack(alignment: .leading, spacing: 14) {
            // Card 1: Stepped Rail Chips & Active Metrics
            PurahPluginSettingsCard(
                title: "Stepped Rail Chips & Active Metrics",
                subtitle: "Configure individual hardware monitor chips on the rail bezel",
                icon: "waveform.path.ecg",
                iconColor: Color(hex: "#34C759")
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    // Switch sub-card for decomposition
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Decompose into Stepped Metric Rail Chips")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("Splits hardware monitoring into individual rail chips (CPU, GPU, RAM, Power, Network, Disk)")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { state.isDecomposed },
                            set: {
                                state.isDecomposed = $0
                                state.save()
                                store._isVitalsDecomposed = $0
                                store.invalidateLayoutCache()
                                store.savePersistentState()
                                store.onWindowsRebuildNeeded?()
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                    )

                    if state.isDecomposed {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Visible Sub-Metrics")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(state.enabledMetrics.count) Active")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(palette.primaryAccent)
                            }

                            let columns = [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)
                            ]

                            LazyVGrid(columns: columns, spacing: 8) {
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
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Image(systemName: metric.systemIcon)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(isIncluded ? palette.primaryAccent : .secondary)
                                                Spacer()
                                                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(isIncluded ? palette.primaryAccent : palette.borderColor.opacity(0.4))
                                            }

                                            Text(metric.displayName)
                                                .font(.system(size: 10, weight: isIncluded ? .bold : .medium, design: .rounded))
                                                .foregroundColor(isIncluded ? .primary : .secondary)
                                                .lineLimit(1)
                                        }
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(isIncluded ? palette.primaryAccent.opacity(0.12) : Color.primary.opacity(0.03))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .stroke(isIncluded ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isIncluded ? 1.4 : 0.8)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }

            // Card 2: Dynamic Telemetry Color Thresholds
            PurahPluginSettingsCard(
                title: "Dynamic Telemetry Color Thresholds",
                subtitle: "Real-time green / amber / red boundary calibration",
                icon: "slider.horizontal.3",
                iconColor: Color(hex: "#FF9F0A"),
                trailing: Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        state.resetThresholds()
                        store._vitalsThresholds = state.thresholds
                        store.savePersistentState()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Reset Defaults")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            ) {
                VStack(alignment: .leading, spacing: 12) {
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
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Circle().fill(VitalsColorResolver.warningYellow).frame(width: 8, height: 8)
                                Text("Amber (\(Int(state.thresholds.cpuWarning * 100))% ~ \(Int(state.thresholds.cpuDanger * 100))%)")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Circle().fill(VitalsColorResolver.dangerRed).frame(width: 8, height: 8)
                                Text("Red (> \(Int(state.thresholds.cpuDanger * 100))%)")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                    )

                    // Sliders in styled sub-cards
                    VStack(spacing: 8) {
                        thresholdRow(
                            title: "CPU Load",
                            warningLabel: "\(Int(state.thresholds.cpuWarning * 100))%",
                            warningValue: percentageBinding(for: \.cpuWarning, cappedBy: \.cpuDanger, isWarning: true),
                            warningRange: 10...90,
                            dangerLabel: "\(Int(state.thresholds.cpuDanger * 100))%",
                            dangerValue: percentageBinding(for: \.cpuDanger, cappedBy: \.cpuWarning, isWarning: false),
                            dangerRange: 50...99
                        )

                        thresholdRow(
                            title: "GPU Activity",
                            warningLabel: "\(Int(state.thresholds.gpuWarning * 100))%",
                            warningValue: percentageBinding(for: \.gpuWarning, cappedBy: \.gpuDanger, isWarning: true),
                            warningRange: 10...90,
                            dangerLabel: "\(Int(state.thresholds.gpuDanger * 100))%",
                            dangerValue: percentageBinding(for: \.gpuDanger, cappedBy: \.gpuWarning, isWarning: false),
                            dangerRange: 50...99
                        )

                        thresholdRow(
                            title: "Memory (RAM)",
                            warningLabel: "\(Int(state.thresholds.ramWarning * 100))%",
                            warningValue: percentageBinding(for: \.ramWarning, cappedBy: \.ramDanger, isWarning: true),
                            warningRange: 20...90,
                            dangerLabel: "\(Int(state.thresholds.ramDanger * 100))%",
                            dangerValue: percentageBinding(for: \.ramDanger, cappedBy: \.ramWarning, isWarning: false),
                            dangerRange: 60...99
                        )

                        // Battery Low Warning %
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Battery Low Warning")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                Spacer()
                                Text("\(Int(state.thresholds.batteryLow * 100))%")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                        .padding(9)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(palette.borderColor.opacity(0.15), lineWidth: 0.8)
                        )

                        // Network Warning MB/s
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Network Throughput")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                Spacer()
                                Text("Warn: \(Int(state.thresholds.networkWarningMB)) MB/s")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(VitalsColorResolver.warningYellow)
                                Text("•")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text("Danger: \(Int(state.thresholds.networkDangerMB)) MB/s")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                        .padding(9)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(palette.borderColor.opacity(0.15), lineWidth: 0.8)
                        )
                    }

                    // Live stats footer row
                    HStack(spacing: 10) {
                        Text("CPU: \(Int(vitals.cpuUsage * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        Text("RAM: \(Int(vitals.memoryUsage * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        Text("Disk: \(Int(vitals.diskFreeGB))GB Free")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        Spacer()
                        Button {
                            state.refreshMetrics(includeProcesses: true)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9))
                                Text("Refresh")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(palette.primaryAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(palette.primaryAccent.opacity(0.08))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(palette.primaryAccent.opacity(0.25), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }
            }
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

