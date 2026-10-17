// Sources/PurahUI/DrawerPanels/HardwareVitalsDrawerView.swift
import SwiftUI
import PurahCore

public struct HardwareVitalsDrawerView: View {
    public let state: VitalsPluginState
    public let store: PurahWorkspaceStore
    @State private var isPulsing: Bool = false

    private var vitals: HardwareVitalsService {
        HardwareVitalsService.shared
    }
    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }
    private var effectiveThresholds: VitalsColorThresholds {
        state.thresholds
    }

    public init(state: VitalsPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "vitals") as? HardwareVitalsPlugin)?.state ?? VitalsPluginState()
        self.init(state: pluginState, store: store)
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }

    public var body: some View {
        let metrics = vitals.metrics
        let cpuColor = VitalsColorResolver.color(for: .cpu, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        let gpuColor = VitalsColorResolver.color(for: .gpu, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        let ramColor = VitalsColorResolver.color(for: .ram, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        let diskColor = VitalsColorResolver.color(for: .disk, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        let powerColor = VitalsColorResolver.color(for: .power, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        let netColor = VitalsColorResolver.color(for: .network, vitals: metrics, thresholds: effectiveThresholds, palette: palette)

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                // MARK: - Row 1: Dual Compute Cores (CPU & GPU)
                HStack(spacing: 6) {
                    // CPU Card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("CPU")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            Text("\(Int(metrics.cpuUsage * 100))%")
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(cpuColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(cpuColor)
                                    .frame(width: max(geo.size.width * CGFloat(metrics.cpuUsage), 3))
                            }
                        }
                        .frame(height: 4.5)

                        Text("\(ProcessInfo.processInfo.activeProcessorCount) Cores • \(thermalStatusLabel(cpuUsage: metrics.cpuUsage))")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(6.5)
                    .background(Color.primary.opacity(0.035))
                    .cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))

                    // GPU Card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("GPU")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            Text("\(Int(metrics.gpuUsage * 100))%")
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(gpuColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(gpuColor)
                                    .frame(width: max(geo.size.width * CGFloat(metrics.gpuUsage), 3))
                            }
                        }
                        .frame(height: 4.5)

                        Text(metrics.gpuUsage > 0.70 ? "High Metal Render Load" : "Metal Engine Active")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(6.5)
                    .background(Color.primary.opacity(0.035))
                    .cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))
                }

                // MARK: - Row 2: Memory & Storage (RAM & Disk)
                HStack(spacing: 6) {
                    // Memory Card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("RAM")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            Text("\(Int(metrics.memoryUsage * 100))%")
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(ramColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(ramColor)
                                    .frame(width: max(geo.size.width * CGFloat(metrics.memoryUsage), 3))
                            }
                        }
                        .frame(height: 4.5)

                        Text("\(String(format: "%.1f", metrics.memoryUsedGB)) / \(String(format: "%.0f", metrics.memoryTotalGB)) GB • \(memoryPressureLabel(usage: metrics.memoryUsage))")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(6.5)
                    .background(Color.primary.opacity(0.035))
                    .cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))

                    // Disk Card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Disk")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            Text("\(Int(metrics.diskFreeGB))G")
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(diskColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        let usedDiskRatio = metrics.diskTotalGB > 0 ? max(min((metrics.diskTotalGB - metrics.diskFreeGB) / metrics.diskTotalGB, 1.0), 0.0) : 0.5
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(diskColor)
                                    .frame(width: max(geo.size.width * CGFloat(usedDiskRatio), 3))
                            }
                        }
                        .frame(height: 4.5)

                        Text("\(Int(metrics.diskFreeGB))GB free / \(Int(metrics.diskTotalGB))GB")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(6.5)
                    .background(Color.primary.opacity(0.035))
                    .cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))
                }

                // MARK: - Row 3: Network Throughput & Power Dynamics
                HStack(spacing: 6) {
                    // Network Card
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Network")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            Circle()
                                .fill(netColor)
                                .frame(width: 4.5, height: 4.5)
                        }
                        HStack(spacing: 6) {
                            HStack(spacing: 2) {
                                Text("↓")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(netColor)
                                Text(formatSpeed(metrics.networkDownSpeed))
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            Spacer()
                            HStack(spacing: 2) {
                                Text("↑")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text(formatSpeed(metrics.networkUpSpeed))
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                    }
                    .padding(6.5)
                    .background(Color.primary.opacity(0.035))
                    .cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))

                    // Battery / Power Card
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Label("Power", systemImage: batteryIcon(level: metrics.batteryLevel, isCharging: metrics.isCharging))
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(powerColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer()
                            Text("\(metrics.batteryLevel)%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(powerColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        Text(metrics.isCharging ? "Charging (\(metrics.powerSource))" : metrics.powerSource)
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(6.5)
                    .background(Color.primary.opacity(0.035))
                    .cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))
                }

                // MARK: - Row 4: Status Heartbeat & Refresh
                HStack {
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(cpuColor.opacity(0.25))
                                .frame(width: 11, height: 11)
                                .scaleEffect(isPulsing ? 1.4 : 0.8)
                                .opacity(isPulsing ? 0.25 : 0.8)
                            Circle()
                                .fill(cpuColor)
                                .frame(width: 5, height: 5)
                        }
                        Text(metrics.cpuUsage > 0.85 ? "Heavy Compute Load" : "System Running Optimally")
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Spacer()

                    Button {
                        Task {
                            await vitals.refreshMetricsAsync(includeProcesses: true)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 8.5))
                            Text("Refresh")
                                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 3)

                // MARK: - Row 5: Top Processes
                VStack(alignment: .leading, spacing: 5) {
                    Text("Top Processes")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    VStack(spacing: 4) {
                        ForEach(metrics.topProcesses) { proc in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(proc.cpuPercent > 50 ? palette.dangerAccent : (proc.cpuPercent > 20 ? VitalsColorResolver.warningYellow : cpuColor))
                                    .frame(width: 4.5, height: 4.5)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(proc.name)
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)

                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.primary.opacity(0.06))
                                            Capsule()
                                                .fill(proc.cpuPercent > 50 ? palette.dangerAccent : cpuColor)
                                                .frame(width: max(g.size.width * CGFloat(min(proc.cpuPercent / 100.0, 1.0)), 2))
                                        }
                                    }
                                    .frame(height: 2.5)
                                }

                                Spacer()

                                Text("CPU \(String(format: "%.1f", proc.cpuPercent))% • MEM \(String(format: "%.1f", proc.memoryPercent))%")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)

                                Button {
                                    vitals.killProcess(pid: proc.id)
                                } label: {
                                    Text("Kill")
                                        .font(.system(size: 8, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(palette.dangerAccent.opacity(0.12))
                                        .foregroundColor(palette.dangerAccent)
                                        .cornerRadius(3.5)
                                }
                                .buttonStyle(.tactile)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(5.5)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            state.mount(store: store)
            vitals.startMonitoring()
            Task {
                await vitals.refreshMetricsAsync(includeProcesses: true)
                state.refreshMetrics(includeProcesses: true)
            }
        }
    }

    private func thermalStatusLabel(cpuUsage: Double) -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return cpuUsage > 0.75 ? "High Load" : "Nominal"
        case .fair:
            return "Warm"
        case .serious:
            return "Hot"
        case .critical:
            return "Throttling"
        @unknown default:
            return "Nominal"
        }
    }

    private func memoryPressureLabel(usage: Double) -> String {
        if usage >= effectiveThresholds.ramDanger {
            return "High Pressure"
        } else if usage >= effectiveThresholds.ramWarning {
            return "Elevated"
        } else {
            return "Normal"
        }
    }

    private func batteryIcon(level: Int, isCharging: Bool) -> String {
        if isCharging { return "battery.100.bolt" }
        switch level {
        case 0..<20: return "battery.0"
        case 20..<50: return "battery.25"
        case 50..<75: return "battery.50"
        case 75..<95: return "battery.75"
        default: return "battery.100"
        }
    }
}

// MARK: - Focused Decomposed Vitals Drawer View
public struct VitalsFocusedDrawerView: View {
    public let metric: VitalsMetricType
    public let availableHeight: CGFloat
    public let trailingHeader: AnyView?
    public let state: VitalsPluginState
    public let store: PurahWorkspaceStore

    @State private var timeScope: VitalsTimeScope = .realTime30s

    private var palette: ThemePalette { ThemeManager.shared.palette }
    private var vitals: HardwareVitalsService { HardwareVitalsService.shared }
    private var effectiveThresholds: VitalsColorThresholds { state.thresholds }

    private var scopePicker: some View {
        HStack(spacing: 2) {
            ForEach(VitalsTimeScope.allCases) { sc in
                Button {
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.80)) {
                        timeScope = sc
                    }
                } label: {
                    Text(sc.displayName)
                        .font(.system(size: 7.5, weight: timeScope == sc ? .bold : .medium, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(timeScope == sc ? Color.primary.opacity(0.12) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .foregroundColor(timeScope == sc ? .primary : .secondary)
            }
        }
    }

    public init(
        metric: VitalsMetricType,
        availableHeight: CGFloat = 48.0,
        trailingHeader: AnyView? = nil,
        state: VitalsPluginState,
        store: PurahWorkspaceStore = PurahWorkspaceStore()
    ) {
        self.metric = metric
        self.availableHeight = availableHeight
        self.trailingHeader = trailingHeader
        self.state = state
        self.store = store
    }

    public init(
        metric: VitalsMetricType,
        availableHeight: CGFloat = 48.0,
        trailingHeader: AnyView? = nil,
        store: PurahWorkspaceStore
    ) {
        let pluginState = (PluginRegistry.shared.plugin(for: "vitals") as? HardwareVitalsPlugin)?.state ?? VitalsPluginState()
        self.init(metric: metric, availableHeight: availableHeight, trailingHeader: trailingHeader, state: pluginState, store: store)
    }

    public init(metric: VitalsMetricType, availableHeight: CGFloat = 48.0, state: VitalsPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.init(metric: metric, availableHeight: availableHeight, trailingHeader: nil, state: state, store: store)
    }

    public init(metric: VitalsMetricType, availableHeight: CGFloat = 48.0, store: PurahWorkspaceStore) {
        self.init(metric: metric, availableHeight: availableHeight, trailingHeader: nil, store: store)
    }

    public init(metric: VitalsMetricType, state: VitalsPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.init(metric: metric, availableHeight: 48.0, trailingHeader: nil, state: state, store: store)
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let metrics = vitals.metrics

            VStack(alignment: .leading, spacing: 4) {
                switch metric {
                case .cpu:
                    cpuFocusedView(metrics: metrics)
                case .gpu:
                    gpuFocusedView(metrics: metrics)
                case .ram:
                    ramFocusedView(metrics: metrics)
                case .power:
                    powerFocusedView(metrics: metrics)
                case .network:
                    networkFocusedView(metrics: metrics)
                case .disk:
                    diskFocusedView(metrics: metrics)
                }
            }
        }
        .onAppear {
            vitals.startMonitoring()
            Task {
                await vitals.refreshMetricsAsync(includeProcesses: true)
            }
        }
    }

    @ViewBuilder
    private func cpuFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let color = VitalsColorResolver.color(for: .cpu, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label("CPU Activity", systemImage: "cpu")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Text("\(Int(metrics.cpuUsage * 100))%")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(color)
                if let trailingHeader {
                    trailingHeader
                }
            }

            if availableHeight >= 50.0 {
                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .cpu, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: min(max(availableHeight - 40, 24), 100),
                    scope: timeScope
                )
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(color)
                            .frame(width: max(geo.size.width * CGFloat(metrics.cpuUsage), 4))
                    }
                }
                .frame(height: 4)
            }

            HStack {
                if let top = metrics.topProcesses.first {
                    Text("Top: \(top.name) (\(String(format: "%.0f", top.cpuPercent))%)")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Button("Kill") {
                        vitals.killProcess(pid: top.id)
                    }
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(palette.dangerAccent.opacity(0.18))
                    .foregroundColor(palette.dangerAccent)
                    .cornerRadius(3)
                    .buttonStyle(.tactile)
                } else {
                    Text("Background tasks normal")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                Spacer()
                scopePicker
            }
        }
    }

    @ViewBuilder
    private func gpuFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let color = VitalsColorResolver.color(for: .gpu, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        let gpuRatio = max(min(metrics.gpuUsage, 1.0), 0.0)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label("GPU Activity", systemImage: "display")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Text("\(Int(gpuRatio * 100))%")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(color)
                if let trailingHeader {
                    trailingHeader
                }
            }

            if availableHeight >= 50.0 {
                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .gpu, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: min(max(availableHeight - 40, 24), 100),
                    scope: timeScope
                )
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(color)
                            .frame(width: max(geo.size.width * CGFloat(gpuRatio), 4))
                    }
                }
                .frame(height: 4)
            }

            HStack {
                Text(gpuRatio > 0.10 ? "Metal / Apple Silicon GPU" : "Low Power / Idle Engine")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                scopePicker
            }
        }
    }

    @ViewBuilder
    private func ramFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let color = VitalsColorResolver.color(for: .ram, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label("Memory (RAM)", systemImage: "memorychip")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Text("\(Int(metrics.memoryUsage * 100))%")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(color)
                if let trailingHeader {
                    trailingHeader
                }
            }

            if availableHeight >= 50.0 {
                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .ram, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: min(max(availableHeight - 40, 24), 100),
                    scope: timeScope
                )
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(color)
                            .frame(width: max(geo.size.width * CGFloat(metrics.memoryUsage), 4))
                    }
                }
                .frame(height: 4)
            }

            HStack {
                Text("\(String(format: "%.1f", metrics.memoryUsedGB)) / \(String(format: "%.0f", metrics.memoryTotalGB)) GB")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                scopePicker
            }
        }
    }

    @ViewBuilder
    private func powerFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let color = VitalsColorResolver.color(for: .power, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label("Battery & Power", systemImage: "bolt.batteryblock.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Text("\(metrics.batteryLevel)%")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(color)
                if let trailingHeader {
                    trailingHeader
                }
            }

            if availableHeight >= 50.0 {
                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .power, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: min(max(availableHeight - 40, 24), 100),
                    scope: timeScope
                )
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(color)
                            .frame(width: max(geo.size.width * CGFloat(Double(metrics.batteryLevel) / 100.0), 4))
                    }
                }
                .frame(height: 4)
            }

            HStack {
                Text(metrics.isCharging ? "Charging (\(metrics.powerSource))" : metrics.powerSource)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                scopePicker
            }
        }
    }

    @ViewBuilder
    private func networkFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let downColor = Color(hex: "#00F5D4")
        let upColor = Color(hex: "#0A84FF")
        let totalSpeed = metrics.networkDownSpeed + metrics.networkUpSpeed
        let totalMB = totalSpeed / 1_048_576.0
        let dangerMB = max(effectiveThresholds.networkDangerMB, 1.0)
        let networkRatio = min(totalMB / dangerMB, 1.0)
        
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label("Network I/O", systemImage: "network")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                        Text(formatSpeed(bytesPerSec: metrics.networkDownSpeed))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    }
                    .foregroundColor(downColor)

                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8, weight: .bold))
                        Text(formatSpeed(bytesPerSec: metrics.networkUpSpeed))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    }
                    .foregroundColor(upColor)
                }

                if let trailingHeader {
                    trailingHeader
                }
            }

            if availableHeight >= 50.0 {
                VitalsDualTimeSeriesGraphView(
                    downPoints: vitals.history(for: .network, scope: timeScope),
                    upPoints: vitals.networkUpHistory(scope: timeScope),
                    downColor: downColor,
                    upColor: upColor,
                    palette: palette,
                    height: min(max(availableHeight - 40, 24), 100),
                    scope: timeScope
                )
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(downColor)
                            .frame(width: max(geo.size.width * CGFloat(networkRatio), 4))
                    }
                }
                .frame(height: 4)
            }

            HStack {
                HStack(spacing: 3) {
                    Circle().fill(downColor).frame(width: 4, height: 4)
                    Text("↓ In: \(formatSpeed(bytesPerSec: metrics.networkDownSpeed))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 3) {
                    Circle().fill(upColor).frame(width: 4, height: 4)
                    Text("↑ Out: \(formatSpeed(bytesPerSec: metrics.networkUpSpeed))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                scopePicker
            }
        }
    }

    private func formatSpeed(bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576.0 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else if bytesPerSec >= 1024.0 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }

    @ViewBuilder
    private func diskFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let color = VitalsColorResolver.color(for: .disk, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        let usedRatio = metrics.diskTotalGB > 0 ? max(min((metrics.diskTotalGB - metrics.diskFreeGB) / metrics.diskTotalGB, 1.0), 0.0) : 0.5

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label("Disk Storage", systemImage: "internaldrive")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Text("\(Int(metrics.diskFreeGB))GB Free")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(color)
                if let trailingHeader {
                    trailingHeader
                }
            }

            if availableHeight >= 50.0 {
                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .disk, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: min(max(availableHeight - 40, 24), 100),
                    scope: timeScope
                )
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(color)
                            .frame(width: max(geo.size.width * CGFloat(usedRatio), 4))
                    }
                }
                .frame(height: 4)
            }

            HStack {
                Text("\(Int(metrics.diskTotalGB - metrics.diskFreeGB)) / \(Int(metrics.diskTotalGB)) GB")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                scopePicker
            }
        }
    }
}

// MARK: - Real-Time Time-Series Historical Graph (X-Axis: Time, Y-Axis: Value)
public struct VitalsTimeSeriesGraphView: View {
    public let points: [VitalsHistoryPoint]
    public let color: Color
    public let palette: ThemePalette
    public let height: CGFloat
    public let scope: VitalsTimeScope

    public init(
        points: [VitalsHistoryPoint],
        color: Color,
        palette: ThemePalette,
        height: CGFloat = 46.0,
        scope: VitalsTimeScope = .realTime30s
    ) {
        self.points = points
        self.color = color
        self.palette = palette
        self.height = height
        self.scope = scope
    }

    private func computePlotPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let now = Date()
        let windowSec = scope.durationSeconds

        let recent = points.filter { now.timeIntervalSince($0.timestamp) <= windowSec }
        let currentVal = points.last?.value ?? 0.0

        var result: [CGPoint] = recent.map { pt in
            let age = min(max(now.timeIntervalSince(pt.timestamp), 0.0), windowSec)
            let x = width * CGFloat(1.0 - (age / windowSec))
            let y = height - (height * CGFloat(max(min(pt.value, 1.0), 0.0)))
            return CGPoint(x: x, y: y)
        }

        if result.isEmpty {
            let y = height - (height * CGFloat(max(min(currentVal, 1.0), 0.0)))
            result = [CGPoint(x: 0, y: y), CGPoint(x: width, y: y)]
        } else if result.count == 1, let only = result.first {
            result.insert(CGPoint(x: 0, y: only.y), at: 0)
        } else if let first = result.first, first.x > 0 {
            result.insert(CGPoint(x: 0, y: first.y), at: 0)
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let plotPoints = computePlotPoints(width: w, height: h)

                ZStack {
                    // Grid background lines at 25%, 50%, 75%
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h * 0.25))
                        path.addLine(to: CGPoint(x: w, y: h * 0.25))
                        path.move(to: CGPoint(x: 0, y: h * 0.50))
                        path.addLine(to: CGPoint(x: w, y: h * 0.50))
                        path.move(to: CGPoint(x: 0, y: h * 0.75))
                        path.addLine(to: CGPoint(x: w, y: h * 0.75))
                    }
                    .stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

                    if !plotPoints.isEmpty {
                        // Area fill under curve
                        Path { path in
                            if let first = plotPoints.first {
                                path.move(to: CGPoint(x: first.x, y: h))
                                for pt in plotPoints {
                                    path.addLine(to: pt)
                                }
                                if let last = plotPoints.last {
                                    path.addLine(to: CGPoint(x: last.x, y: h))
                                }
                                path.closeSubpath()
                            }
                        }
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.32), color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Top line
                        Path { path in
                            if let first = plotPoints.first {
                                path.move(to: first)
                                for pt in plotPoints.dropFirst() {
                                    path.addLine(to: pt)
                                }
                            }
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                        // Current point indicator
                        if let last = plotPoints.last {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 4, height: 4)
                                .overlay(Circle().stroke(color, lineWidth: 1.5))
                                .position(x: last.x, y: last.y)
                        }
                    }
                }
            }
            .frame(height: height)

            // X-axis time markings
            HStack {
                Text(scope.markings.left)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
                Text(scope.markings.middle)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                Spacer()
                Text(scope.markings.right)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }
}

// MARK: - Dual Time-Series Historical Graph (e.g. Download & Upload)
public struct VitalsDualTimeSeriesGraphView: View {
    public let downPoints: [VitalsHistoryPoint]
    public let upPoints: [VitalsHistoryPoint]
    public let downColor: Color
    public let upColor: Color
    public let palette: ThemePalette
    public let height: CGFloat
    public let scope: VitalsTimeScope

    public init(
        downPoints: [VitalsHistoryPoint],
        upPoints: [VitalsHistoryPoint],
        downColor: Color = Color(hex: "#00F5D4"),
        upColor: Color = Color(hex: "#0A84FF"),
        palette: ThemePalette,
        height: CGFloat = 46.0,
        scope: VitalsTimeScope = .realTime30s
    ) {
        self.downPoints = downPoints
        self.upPoints = upPoints
        self.downColor = downColor
        self.upColor = upColor
        self.palette = palette
        self.height = height
        self.scope = scope
    }

    private func computePlotPoints(for pts: [VitalsHistoryPoint], width: CGFloat, height: CGFloat) -> [CGPoint] {
        let now = Date()
        let windowSec = scope.durationSeconds

        let recent = pts.filter { now.timeIntervalSince($0.timestamp) <= windowSec }
        let currentVal = pts.last?.value ?? 0.0

        var result: [CGPoint] = recent.map { pt in
            let age = min(max(now.timeIntervalSince(pt.timestamp), 0.0), windowSec)
            let x = width * CGFloat(1.0 - (age / windowSec))
            let y = height - (height * CGFloat(max(min(pt.value, 1.0), 0.0)))
            return CGPoint(x: x, y: y)
        }

        if result.isEmpty {
            let y = height - (height * CGFloat(max(min(currentVal, 1.0), 0.0)))
            result = [CGPoint(x: 0, y: y), CGPoint(x: width, y: y)]
        } else if result.count == 1, let only = result.first {
            result.insert(CGPoint(x: 0, y: only.y), at: 0)
        } else if let first = result.first, first.x > 0 {
            result.insert(CGPoint(x: 0, y: first.y), at: 0)
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let downPlot = computePlotPoints(for: downPoints, width: w, height: h)
                let upPlot = computePlotPoints(for: upPoints, width: w, height: h)

                ZStack {
                    // Grid background lines at 25%, 50%, 75%
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h * 0.25))
                        path.addLine(to: CGPoint(x: w, y: h * 0.25))
                        path.move(to: CGPoint(x: 0, y: h * 0.50))
                        path.addLine(to: CGPoint(x: w, y: h * 0.50))
                        path.move(to: CGPoint(x: 0, y: h * 0.75))
                        path.addLine(to: CGPoint(x: w, y: h * 0.75))
                    }
                    .stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

                    // 1. Downlink: Area gradient & line stroke
                    if !downPlot.isEmpty {
                        Path { path in
                            if let first = downPlot.first {
                                path.move(to: CGPoint(x: first.x, y: h))
                                for pt in downPlot { path.addLine(to: pt) }
                                if let last = downPlot.last { path.addLine(to: CGPoint(x: last.x, y: h)) }
                                path.closeSubpath()
                            }
                        }
                        .fill(
                            LinearGradient(
                                colors: [downColor.opacity(0.24), downColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        Path { path in
                            if let first = downPlot.first {
                                path.move(to: first)
                                for pt in downPlot.dropFirst() { path.addLine(to: pt) }
                            }
                        }
                        .stroke(downColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                        if let last = downPlot.last {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 4, height: 4)
                                .overlay(Circle().stroke(downColor, lineWidth: 1.5))
                                .position(x: last.x, y: last.y)
                        }
                    }

                    // 2. Uplink: Distinct dashed curve & line indicator
                    if !upPlot.isEmpty {
                        Path { path in
                            if let first = upPlot.first {
                                path.move(to: first)
                                for pt in upPlot.dropFirst() { path.addLine(to: pt) }
                            }
                        }
                        .stroke(upColor, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round, dash: [4, 2]))

                        if let last = upPlot.last {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 3.5, height: 3.5)
                                .overlay(Circle().stroke(upColor, lineWidth: 1.3))
                                .position(x: last.x, y: last.y)
                        }
                    }
                }
            }
            .frame(height: height)

            // X-axis time markings
            HStack {
                Text(scope.markings.left)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
                Text(scope.markings.middle)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                Spacer()
                Text(scope.markings.right)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }
}
