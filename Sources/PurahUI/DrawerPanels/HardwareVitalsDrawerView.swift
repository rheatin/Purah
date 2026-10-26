// Sources/PurahUI/DrawerPanels/HardwareVitalsDrawerView.swift
import SwiftUI
import PurahCore

// MARK: - Dashboard Tab Selection
public enum VitalsDashboardTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case compute
    case io
    case processes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .compute: return "CPU/RAM"
        case .io: return "Net/Disk"
        case .processes: return "Procs"
        }
    }

    public var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .compute: return "cpu"
        case .io: return "network"
        case .processes: return "list.bullet.rectangle"
        }
    }
}

// MARK: - Composite Full Drawer View
public struct HardwareVitalsDrawerView: View {
    public let state: VitalsPluginState
    public let store: PurahWorkspaceStore

    @State private var selectedTab: VitalsDashboardTab = .overview
    @State private var sortProcessesByCPU: Bool = true
    @State private var isPulsing: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        if bytesPerSec >= 1_048_576.0 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else if bytesPerSec >= 1024.0 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
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

    private func thermalColor(for label: String) -> Color {
        switch label.lowercased() {
        case "nominal": return palette.primaryAccent
        case "fair": return VitalsColorResolver.warningYellow
        case "serious": return Color(hex: "#FF9F0A")
        case "critical": return palette.dangerAccent
        default: return palette.primaryAccent
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

        PurahAdaptiveTierDrawer(
            tiers: [
                PurahAdaptiveTier(id: "compact", minHeight: 0),
                PurahAdaptiveTier(id: "standard", minHeight: 108),
                PurahAdaptiveTier(id: "immersive", minHeight: 235)
            ]
        ) { tier, h in
            AnyView(
                tierContent(
                    tierId: tier.id,
                    height: h,
                    metrics: metrics,
                    cpuColor: cpuColor,
                    gpuColor: gpuColor,
                    ramColor: ramColor,
                    diskColor: diskColor,
                    powerColor: powerColor,
                    netColor: netColor
                )
            )
        }
        .onAppear {
            vitals.isDrawerVisible = true
            if PurahMotionPolicy.allowsAmbientAnimation(reduceMotion: reduceMotion) {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
            state.mount(store: store)
            vitals.startMonitoring()
            Task {
                await vitals.refreshMetricsAsync(includeProcesses: true)
                state.refreshMetrics(includeProcesses: true)
            }
        }
        .onDisappear {
            vitals.isDrawerVisible = false
        }
    }

    // MARK: - Tier Routing
    /// The tier id decides the presentation; `height` is passed through so
    /// content inside a tier can still refine itself (the overview appends its
    /// deep-telemetry strip only when there is room).
    @ViewBuilder
    private func tierContent(
        tierId: String,
        height: CGFloat,
        metrics: HardwareVitalsInfo,
        cpuColor: Color,
        gpuColor: Color,
        ramColor: Color,
        diskColor: Color,
        powerColor: Color,
        netColor: Color
    ) -> some View {
        switch tierId {
        case "compact":
            ultraCompactDashboard(
                metrics: metrics,
                cpuColor: cpuColor,
                gpuColor: gpuColor,
                ramColor: ramColor,
                powerColor: powerColor,
                netColor: netColor
            )
        case "immersive":
            tabbedDashboard(
                metrics: metrics,
                height: height,
                showsDeepTelemetry: true,
                cpuColor: cpuColor,
                gpuColor: gpuColor,
                ramColor: ramColor,
                diskColor: diskColor,
                powerColor: powerColor,
                netColor: netColor
            )
        default:
            tabbedDashboard(
                metrics: metrics,
                height: height,
                showsDeepTelemetry: false,
                cpuColor: cpuColor,
                gpuColor: gpuColor,
                ramColor: ramColor,
                diskColor: diskColor,
                powerColor: powerColor,
                netColor: netColor
            )
        }
    }

    @ViewBuilder
    private func tabbedDashboard(
        metrics: HardwareVitalsInfo,
        height: CGFloat,
        showsDeepTelemetry: Bool,
        cpuColor: Color,
        gpuColor: Color,
        ramColor: Color,
        diskColor: Color,
        powerColor: Color,
        netColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            topNavigationBar(metrics: metrics, cpuColor: cpuColor)
                .frame(height: 24)

            PurahScrollableBody {
                VStack(alignment: .leading, spacing: 6) {
                    switch selectedTab {
                    case .overview:
                        overviewTabContent(
                            metrics: metrics,
                            showsDeepTelemetry: showsDeepTelemetry,
                            cpuColor: cpuColor,
                            gpuColor: gpuColor,
                            ramColor: ramColor,
                            diskColor: diskColor,
                            powerColor: powerColor,
                            netColor: netColor
                        )
                    case .compute:
                        computeTabContent(
                            metrics: metrics,
                            cpuColor: cpuColor,
                            gpuColor: gpuColor,
                            ramColor: ramColor
                        )
                    case .io:
                        ioTabContent(
                            metrics: metrics,
                            diskColor: diskColor,
                            netColor: netColor,
                            powerColor: powerColor
                        )
                    case .processes:
                        processesTabContent(
                            metrics: metrics,
                            cpuColor: cpuColor
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Tier 1: Ultra-Compact Dashboard (< 108pt)
    @ViewBuilder
    private func ultraCompactDashboard(
        metrics: HardwareVitalsInfo,
        cpuColor: Color,
        gpuColor: Color,
        ramColor: Color,
        powerColor: Color,
        netColor: Color
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                miniStatusPill(
                    title: "CPU",
                    icon: "cpu",
                    value: "\(Int(metrics.cpuUsage * 100))%",
                    ratio: metrics.cpuUsage,
                    color: cpuColor,
                    detail: "Ld \(String(format: "%.1f", metrics.loadAverage1m))"
                )
                miniStatusPill(
                    title: "GPU",
                    icon: "display",
                    value: "\(Int(metrics.gpuUsage * 100))%",
                    ratio: metrics.gpuUsage,
                    color: gpuColor,
                    detail: metrics.thermalStateLabel
                )
            }
            HStack(spacing: 4) {
                miniStatusPill(
                    title: "RAM",
                    icon: "memorychip",
                    value: "\(Int(metrics.memoryUsage * 100))%",
                    ratio: metrics.memoryUsage,
                    color: ramColor,
                    detail: "\(String(format: "%.1f", metrics.memoryUsedGB))G"
                )
                miniStatusPill(
                    title: "NET/BAT",
                    icon: batteryIcon(level: metrics.batteryLevel, isCharging: metrics.isCharging),
                    value: "\(metrics.batteryLevel)%",
                    ratio: Double(metrics.batteryLevel) / 100.0,
                    color: powerColor,
                    detail: formatSpeed(metrics.networkDownSpeed)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func miniStatusPill(
        title: String,
        icon: String,
        value: String,
        ratio: Double,
        color: Color,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 7.5))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * CGFloat(min(max(ratio, 0.0), 1.0)), 2))
                }
            }
            .frame(height: 3)

            Text(detail)
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3.5)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(5.5)
        .overlay(RoundedRectangle(cornerRadius: 5.5).stroke(palette.borderColor.opacity(0.18), lineWidth: 0.6))
    }

    // MARK: - Top Navigation Bar (24pt)
    @ViewBuilder
    private func topNavigationBar(metrics: HardwareVitalsInfo, cpuColor: Color) -> some View {
        HStack(spacing: 4) {
            // Segmented pill tabs
            HStack(spacing: 2) {
                ForEach(VitalsDashboardTab.allCases) { tab in
                    Button {
                        withAnimation(PurahMotionPolicy.micro) {
                            selectedTab = tab
                        }
                        if tab == .processes {
                            Task {
                                await vitals.refreshMetricsAsync(includeProcesses: true)
                            }
                        }
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 8.5, weight: selectedTab == tab ? .bold : .medium, design: .rounded))
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 2.5)
                            .background(selectedTab == tab ? palette.primaryAccent.opacity(0.18) : Color.clear)
                            .foregroundColor(selectedTab == tab ? palette.primaryAccent : .secondary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Pulsing thermal status indicator
            HStack(spacing: 3) {
                Circle()
                    .fill(thermalColor(for: metrics.thermalStateLabel))
                    .frame(width: 4.5, height: 4.5)
                    .scaleEffect(isPulsing ? 1.25 : 0.85)
                    .opacity(isPulsing ? 0.95 : 0.6)
                Text(metrics.thermalStateLabel)
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(3.5)

            // Compact refresh button
            Button {
                Task {
                    await vitals.refreshMetricsAsync(includeProcesses: true)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .padding(3.5)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(3.5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 1)
    }

    // MARK: - Tab: Overview
    @ViewBuilder
    private func overviewTabContent(
        metrics: HardwareVitalsInfo,
        showsDeepTelemetry: Bool,
        cpuColor: Color,
        gpuColor: Color,
        ramColor: Color,
        diskColor: Color,
        powerColor: Color,
        netColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 2x2 Grid of rich cards
            HStack(spacing: 6) {
                // 1. CPU Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("CPU")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(metrics.cpuUsage * 100))%")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundColor(cpuColor)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(cpuColor).frame(width: max(geo.size.width * CGFloat(metrics.cpuUsage), 3))
                        }
                    }
                    .frame(height: 4)

                    Text("Usr \(Int(metrics.cpuUserUsage * 100))% · Sys \(Int(metrics.cpuSystemUsage * 100))% · Load \(String(format: "%.1f", metrics.loadAverage1m))")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(6)
                .background(Color.primary.opacity(0.035))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))

                // 2. GPU Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("GPU")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(metrics.gpuUsage * 100))%")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundColor(gpuColor)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(gpuColor).frame(width: max(geo.size.width * CGFloat(metrics.gpuUsage), 3))
                        }
                    }
                    .frame(height: 4)

                    Text("\(metrics.chipModelName) · \(metrics.thermalStateLabel)")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(6)
                .background(Color.primary.opacity(0.035))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))
            }

            HStack(spacing: 6) {
                // 3. RAM Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("RAM")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(metrics.memoryUsage * 100))%")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundColor(ramColor)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(ramColor).frame(width: max(geo.size.width * CGFloat(metrics.memoryUsage), 3))
                        }
                    }
                    .frame(height: 4)

                    let swapStr = metrics.memorySwapUsedMB >= 1024 ? String(format: "%.1fG", metrics.memorySwapUsedMB / 1024.0) : "\(Int(metrics.memorySwapUsedMB))M"
                    Text("Wired \(String(format: "%.1f", metrics.memoryWiredGB))G · Compr \(String(format: "%.1f", metrics.memoryCompressedGB))G · Swp \(swapStr)")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(6)
                .background(Color.primary.opacity(0.035))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))

                // 4. Battery Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Battery")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(metrics.batteryLevel)%")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundColor(powerColor)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(powerColor).frame(width: max(geo.size.width * CGFloat(min(max(CGFloat(metrics.batteryLevel) / 100.0, 0.0), 1.0)), 3))
                        }
                    }
                    .frame(height: 4)

                    Text("Health \(metrics.batteryHealthPercent)% · \(metrics.batteryCycleCount) cyc · \(metrics.isCharging ? "Charging" : metrics.powerSource)")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(6)
                .background(Color.primary.opacity(0.035))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))
            }

            // Dedicated Full-Width Network Card
            VStack(alignment: .leading, spacing: 4) {
                // Top Row
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(netColor)
                    Text("Network")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)

                    Text("\(metrics.networkInterfaceName) · \(metrics.localIPAddress)")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(3.5)

                    Spacer()

                    HStack(spacing: 4) {
                        Text("↓ \(formatSpeed(metrics.networkDownSpeed))")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(netColor)
                        Text("↑ \(formatSpeed(metrics.networkUpSpeed))")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#0A84FF"))
                    }
                }

                // Bottom Row: Activity bar + session totals on the right
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        let netRatio = min((metrics.networkDownSpeed + metrics.networkUpSpeed) / 10_485_760.0, 1.0)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(netColor).frame(width: max(geo.size.width * CGFloat(netRatio), 3))
                        }
                    }
                    .frame(height: 4)

                    Text("Total: ↓ \(String(format: "%.1f", metrics.networkTotalReceivedGB)) GB · ↑ \(String(format: "%.1f", metrics.networkTotalSentGB)) GB")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(6)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))

            // Deep telemetry strip + top processes belong to the immersive
            // tier only; the standard tier keeps the 2x2 grid plus I/O.
            if showsDeepTelemetry {
                // CPU/RAM Breakdown Strip
                VStack(alignment: .leading, spacing: 4) {
                    Text("vitals.deepCompute".localized)
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        breakdownPill(label: "User", value: "\(Int(metrics.cpuUserUsage * 100))%", color: cpuColor)
                        breakdownPill(label: "System", value: "\(Int(metrics.cpuSystemUsage * 100))%", color: VitalsColorResolver.warningYellow)
                        breakdownPill(label: "App RAM", value: "\(String(format: "%.1f", metrics.memoryAppGB))G", color: ramColor)
                        breakdownPill(label: "Wired", value: "\(String(format: "%.1f", metrics.memoryWiredGB))G", color: .secondary)
                        breakdownPill(label: "Swap", value: "\(Int(metrics.memorySwapUsedMB))M", color: .secondary)
                    }
                }
                .padding(6)
                .background(Color.primary.opacity(0.025))
                .cornerRadius(6.5)

                // Top 3 Processes Strip
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("vitals.topProcesses".localized)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            withAnimation { selectedTab = .processes }
                            Task {
                                await vitals.refreshMetricsAsync(includeProcesses: true)
                            }
                        } label: {
                            Text("vitals.viewAll".localized)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(palette.primaryAccent)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(metrics.topProcesses.prefix(3)) { proc in
                        HStack(spacing: 6) {
                            Text(proc.name)
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Spacer()
                            Text("CPU \(String(format: "%.1f", proc.cpuPercent))% · \(String(format: "%.0f", proc.memoryMB))MB")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary)
                            Button("Kill") {
                                vitals.killProcess(pid: proc.id)
                            }
                            .font(.system(size: 7.5, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(palette.dangerAccent.opacity(0.12))
                            .foregroundColor(palette.dangerAccent)
                            .cornerRadius(3)
                            .buttonStyle(.tactile)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(5)
                    }
                }
            }
        }
    }

    // MARK: - Tab: Compute (CPU & RAM Deep Cards)
    @ViewBuilder
    private func computeTabContent(
        metrics: HardwareVitalsInfo,
        cpuColor: Color,
        gpuColor: Color,
        ramColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // CPU Deep Card
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(cpuColor)
                    Text(metrics.chipModelName)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    Spacer()
                    Text(String(format: "vitals.cores".localized, metrics.performanceCoreCount, metrics.efficiencyCoreCount))
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(3.5)
                }

                // 3-Segment Color Bar: User / System / Idle
                GeometryReader { geo in
                    let w = geo.size.width
                    let uW = w * CGFloat(min(max(metrics.cpuUserUsage, 0.0), 1.0))
                    let sW = w * CGFloat(min(max(metrics.cpuSystemUsage, 0.0), 1.0))
                    let iW = max(w - uW - sW, 0)
                    HStack(spacing: 1.5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(cpuColor)
                            .frame(width: max(uW, 2))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(VitalsColorResolver.warningYellow)
                            .frame(width: max(sW, 2))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: max(iW, 2))
                    }
                }
                .frame(height: 5)

                HStack(spacing: 8) {
                    legendItem(title: "User", value: "\(Int(metrics.cpuUserUsage * 100))%", color: cpuColor)
                    legendItem(title: "System", value: "\(Int(metrics.cpuSystemUsage * 100))%", color: VitalsColorResolver.warningYellow)
                    legendItem(title: "Idle", value: "\(Int(metrics.cpuIdleUsage * 100))%", color: .secondary)
                }

                // Load Average & Thermal Status
                HStack(spacing: 4) {
                    breakdownPill(label: "Load 1m", value: String(format: "%.2f", metrics.loadAverage1m), color: .secondary)
                    breakdownPill(label: "5m", value: String(format: "%.2f", metrics.loadAverage5m), color: .secondary)
                    breakdownPill(label: "15m", value: String(format: "%.2f", metrics.loadAverage15m), color: .secondary)
                    breakdownPill(label: "Thermal", value: metrics.thermalStateLabel, color: thermalColor(for: metrics.thermalStateLabel))
                }
            }
            .padding(7)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(7.5)
            .overlay(RoundedRectangle(cornerRadius: 7.5).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))

            // RAM Deep Card
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "memorychip")
                        .foregroundColor(ramColor)
                    Text("vitals.memoryArchitecture".localized)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    Spacer()
                    Text(String(format: "vitals.pressure".localized, metrics.memoryPressureLevel))
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(metrics.memoryPressureLevel == "Normal" ? palette.primaryAccent : palette.dangerAccent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(3.5)
                }

                HStack {
                    Text("\(String(format: "%.1f", metrics.memoryUsedGB)) GB Used / \(String(format: "%.1f", metrics.memoryTotalGB)) GB Physical")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(metrics.memoryUsage * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(ramColor)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(ramColor).frame(width: max(geo.size.width * CGFloat(metrics.memoryUsage), 3))
                    }
                }
                .frame(height: 5)

                // 4-Pill Breakdown
                HStack(spacing: 4) {
                    breakdownPill(label: "App Memory", value: "\(String(format: "%.1f", metrics.memoryAppGB)) GB", color: ramColor)
                    breakdownPill(label: "Wired", value: "\(String(format: "%.1f", metrics.memoryWiredGB)) GB", color: .secondary)
                    breakdownPill(label: "Compressed", value: "\(String(format: "%.1f", metrics.memoryCompressedGB)) GB", color: .secondary)
                    breakdownPill(label: "Swap Used", value: "\(Int(metrics.memorySwapUsedMB)) MB", color: .secondary)
                }
            }
            .padding(7)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(7.5)
            .overlay(RoundedRectangle(cornerRadius: 7.5).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))
        }
    }

    // MARK: - Tab: Net/Disk Deep Cards
    @ViewBuilder
    private func ioTabContent(
        metrics: HardwareVitalsInfo,
        diskColor: Color,
        netColor: Color,
        powerColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Network Deep Card
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(netColor)
                    Text(String(format: "vitals.networkInterface".localized, metrics.networkInterfaceName))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    Spacer()
                    Text(metrics.localIPAddress)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(3.5)
                }

                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Text("↓")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(netColor)
                        Text(formatSpeed(metrics.networkDownSpeed))
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    }
                    HStack(spacing: 3) {
                        Text("↑")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "#0A84FF"))
                        Text(formatSpeed(metrics.networkUpSpeed))
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    }
                    Spacer()
                }

                HStack(spacing: 4) {
                    breakdownPill(label: "Total In", value: "\(String(format: "%.2f", metrics.networkTotalReceivedGB)) GB", color: netColor)
                    breakdownPill(label: "Total Out", value: "\(String(format: "%.2f", metrics.networkTotalSentGB)) GB", color: Color(hex: "#0A84FF"))
                }
            }
            .padding(7)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(7.5)
            .overlay(RoundedRectangle(cornerRadius: 7.5).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))

            // Storage & Battery Deep Card
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundColor(diskColor)
                    Text("vitals.diskPower".localized)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    Spacer()
                    Text(String(format: "vitals.diskFreeGB".localized, Int(metrics.diskFreeGB)))
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(diskColor)
                }

                HStack(spacing: 4) {
                    breakdownPill(label: "Disk Read", value: formatSpeed(metrics.diskReadBytesPerSec), color: .secondary)
                    breakdownPill(label: "Disk Write", value: formatSpeed(metrics.diskWriteBytesPerSec), color: .secondary)
                }

                Divider().opacity(0.3)

                HStack(spacing: 4) {
                    breakdownPill(label: "Battery", value: "\(metrics.batteryLevel)% · \(metrics.powerSource)", color: powerColor)
                    breakdownPill(label: "Health", value: "\(metrics.batteryHealthPercent)%", color: .secondary)
                    breakdownPill(label: "Cycles", value: "\(metrics.batteryCycleCount)", color: .secondary)
                    breakdownPill(label: "Temp", value: "\(String(format: "%.1f", metrics.batteryTemperatureCelsius))°C", color: .secondary)
                }
            }
            .padding(7)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(7.5)
            .overlay(RoundedRectangle(cornerRadius: 7.5).stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6))
        }
    }

    // MARK: - Tab: Processes
    @ViewBuilder
    private func processesTabContent(
        metrics: HardwareVitalsInfo,
        cpuColor: Color
    ) -> some View {
        let sorted = sortProcessesByCPU ?
            metrics.topProcesses.sorted(by: { $0.cpuPercent > $1.cpuPercent }) :
            metrics.topProcesses.sorted(by: { $0.memoryPercent > $1.memoryPercent })

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(String(format: "vitals.processInspector".localized, sorted.count))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                Spacer()
                HStack(spacing: 2) {
                    Button {
                        sortProcessesByCPU = true
                    } label: {
                        Text("CPU")
                            .font(.system(size: 7.5, weight: sortProcessesByCPU ? .bold : .medium, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(sortProcessesByCPU ? palette.primaryAccent.opacity(0.18) : Color.clear)
                            .foregroundColor(sortProcessesByCPU ? palette.primaryAccent : .secondary)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)

                    Button {
                        sortProcessesByCPU = false
                    } label: {
                        Text("MEM")
                            .font(.system(size: 7.5, weight: !sortProcessesByCPU ? .bold : .medium, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(!sortProcessesByCPU ? palette.primaryAccent.opacity(0.18) : Color.clear)
                            .foregroundColor(!sortProcessesByCPU ? palette.primaryAccent : .secondary)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(sorted) { proc in
                HStack(spacing: 6) {
                    Circle()
                        .fill(proc.cpuPercent > 50 ? palette.dangerAccent : (proc.cpuPercent > 20 ? VitalsColorResolver.warningYellow : cpuColor))
                        .frame(width: 4.5, height: 4.5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(proc.name)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .lineLimit(1)

                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.06))
                                Capsule()
                                    .fill(proc.cpuPercent > 50 ? palette.dangerAccent : cpuColor)
                                    .frame(width: max(g.size.width * CGFloat(min(proc.cpuPercent / 100.0, 1.0)), 2))
                            }
                        }
                        .frame(height: 2.5)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("CPU \(String(format: "%.1f", proc.cpuPercent))%")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                        Text("\(String(format: "%.0f", proc.memoryMB)) MB")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Button {
                        vitals.killProcess(pid: proc.id)
                    } label: {
                        Text("vitals.kill".localized)
                            .font(.system(size: 7.5, weight: .semibold))
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(palette.dangerAccent.opacity(0.12))
                            .foregroundColor(palette.dangerAccent)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.tactile)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.025))
                .cornerRadius(5.5)
            }
        }
        .onAppear {
            Task {
                await vitals.refreshMetricsAsync(includeProcesses: true)
            }
        }
    }

    // MARK: - Reusable UI Helpers
    @ViewBuilder
    private func breakdownPill(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 6.5, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 2.5)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(4)
    }

    @ViewBuilder
    private func legendItem(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text("\(title): \(value)")
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Stepped Focused Vitals Drawer View
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
                    withAnimation(PurahMotionPolicy.confirm) {
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

            VStack(alignment: .leading, spacing: 2) {
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

    private func formatSpeed(bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576.0 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else if bytesPerSec >= 1024.0 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }

    // MARK: - CPU Focused View
    @ViewBuilder
    private func cpuFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let color = VitalsColorResolver.color(for: .cpu, vitals: metrics, thresholds: effectiveThresholds, palette: palette)

        if availableHeight < 42.0 {
            // Tier A: Ultra-compact (< 42pt) -> 2 crisp lines
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Label("CPU", systemImage: "cpu")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("Ld \(String(format: "%.1f", metrics.loadAverage1m))")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(2.5)
                    Spacer(minLength: 6)
                    Text("\(Int(metrics.cpuUsage * 100))%")
                        .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(metrics.cpuUsage), 3))
                        }
                    }
                    .frame(height: 3.5)

                    Text(String(format: "vitals.cpuUsrSys".localized, Int(metrics.cpuUserUsage * 100), Int(metrics.cpuSystemUsage * 100)))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if availableHeight < 105.0 {
            // Tier B (42 <= availableHeight < 105)
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("CPU", systemImage: "cpu")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text("\(Int(metrics.cpuUsage * 100))%")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                // Row 2: Graph
                let graphH: CGFloat = max(availableHeight - 32.0, 14.0)

                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .cpu, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3: Footer + scopePicker
                HStack(spacing: 4) {
                    if let top = metrics.topProcesses.first {
                        Text("Top: \(top.name) (\(String(format: "%.0f", top.cpuPercent))%) · Ld \(String(format: "%.1f", metrics.loadAverage1m))")
                            .font(.system(size: 7.5, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Button("Kill") {
                            vitals.killProcess(pid: top.id)
                        }
                        .font(.system(size: 7, weight: .bold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 0.5)
                        .background(palette.dangerAccent.opacity(0.18))
                        .foregroundColor(palette.dangerAccent)
                        .cornerRadius(2.5)
                        .buttonStyle(.tactile)
                    } else {
                        Text("Usr \(Int(metrics.cpuUserUsage * 100))% · Sys \(Int(metrics.cpuSystemUsage * 100))% · Ld \(String(format: "%.1f", metrics.loadAverage1m))")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else {
            // Tier C (availableHeight >= 105.0)
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("CPU", systemImage: "cpu")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text("\(Int(metrics.cpuUsage * 100))%")
                        .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 16)

                // Row 2: Graph
                let graphH: CGFloat = max(min(availableHeight - 64.0, 90.0), 36.0)

                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .cpu, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3: 4-Pill Telemetry Strip
                HStack(spacing: 3) {
                    miniPill(title: "Usr", value: "\(Int(metrics.cpuUserUsage * 100))%", color: color)
                    miniPill(title: "Sys", value: "\(Int(metrics.cpuSystemUsage * 100))%", color: VitalsColorResolver.warningYellow)
                    miniPill(title: "Load 1m", value: String(format: "%.1f", metrics.loadAverage1m), color: .secondary)
                    miniPill(title: "Thermal", value: metrics.thermalStateLabel, color: .secondary)
                }
                .frame(height: 22)

                // Row 4: Footer + scopePicker
                HStack(spacing: 4) {
                    if let top = metrics.topProcesses.first {
                        Text("Top: \(top.name) (\(String(format: "%.0f", top.cpuPercent))%) · Ld \(String(format: "%.1f", metrics.loadAverage1m))")
                            .font(.system(size: 7.5, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Button("Kill") {
                            vitals.killProcess(pid: top.id)
                        }
                        .font(.system(size: 7.5, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(palette.dangerAccent.opacity(0.18))
                        .foregroundColor(palette.dangerAccent)
                        .cornerRadius(3)
                        .buttonStyle(.tactile)
                    } else {
                        Text("Usr \(Int(metrics.cpuUserUsage * 100))% · Sys \(Int(metrics.cpuSystemUsage * 100))% · Ld \(String(format: "%.1f", metrics.loadAverage1m))")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    scopePicker
                }
                .frame(height: 14)
            }
        }
    }

    // MARK: - GPU Focused View
    @ViewBuilder
    private func gpuFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let color = VitalsColorResolver.color(for: .gpu, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        let gpuRatio = max(min(metrics.gpuUsage, 1.0), 0.0)

        if availableHeight < 42.0 {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Label("GPU", systemImage: "display")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(metrics.chipModelName)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(Int(gpuRatio * 100))%")
                        .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(gpuRatio), 3))
                        }
                    }
                    .frame(height: 3.5)

                    Text(metrics.thermalStateLabel)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if availableHeight < 105.0 {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("GPU", systemImage: "display")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text("\(Int(gpuRatio * 100))%")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                // Row 2: Graph
                let graphH: CGFloat = max(availableHeight - 32.0, 14.0)

                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .gpu, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3: Footer + scopePicker
                HStack {
                    Text(gpuRatio > 0.10 ? "\(metrics.chipModelName) · Metal Active" : "\(metrics.chipModelName) · Low Power")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("GPU", systemImage: "display")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text("\(Int(gpuRatio * 100))%")
                        .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 16)

                // Row 2: Graph
                let graphH: CGFloat = max(min(availableHeight - 64.0, 90.0), 36.0)

                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .gpu, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3 (Tier C only): 4-Pill Telemetry Strip
                HStack(spacing: 3) {
                    miniPill(title: "Chip", value: metrics.chipModelName, color: color)
                    miniPill(title: "Load", value: "\(Int(gpuRatio * 100))%", color: color)
                    miniPill(title: "Metal", value: gpuRatio > 0.6 ? "High" : "Normal", color: .secondary)
                    miniPill(title: "Thermal", value: metrics.thermalStateLabel, color: .secondary)
                }
                .frame(height: 22)

                // Row 4: Footer + scopePicker
                HStack {
                    Text(gpuRatio > 0.10 ? "\(metrics.chipModelName) · Metal Active" : "\(metrics.chipModelName) · Low Power")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 14)
            }
        }
    }

    // MARK: - RAM Focused View
    @ViewBuilder
    private func ramFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let color = VitalsColorResolver.color(for: .ram, vitals: metrics, thresholds: effectiveThresholds, palette: palette)

        if availableHeight < 42.0 {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Label("Memory", systemImage: "memorychip")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(String(format: "vitals.swap".localized, Int(metrics.memorySwapUsedMB)))
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(2.5)
                    Spacer(minLength: 6)
                    Text("\(Int(metrics.memoryUsage * 100))%")
                        .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(metrics.memoryUsage), 3))
                        }
                    }
                    .frame(height: 3.5)

                    Text("\(String(format: "%.1f", metrics.memoryUsedGB))G / \(String(format: "%.0f", metrics.memoryTotalGB))G")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if availableHeight < 105.0 {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("Memory", systemImage: "memorychip")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text("\(Int(metrics.memoryUsage * 100))% (\(String(format: "%.1f", metrics.memoryUsedGB))G)")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                // Row 2: Graph
                let graphH: CGFloat = max(availableHeight - 32.0, 14.0)

                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .ram, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3: Footer + scopePicker
                HStack {
                    Text("App \(String(format: "%.1f", metrics.memoryAppGB))G · Wired \(String(format: "%.1f", metrics.memoryWiredGB))G · Compr \(String(format: "%.1f", metrics.memoryCompressedGB))G · Swap \(Int(metrics.memorySwapUsedMB))M")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("Memory", systemImage: "memorychip")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text("\(Int(metrics.memoryUsage * 100))% (\(String(format: "%.1f", metrics.memoryUsedGB))G)")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 16)

                // Row 2: Graph
                let graphH: CGFloat = max(min(availableHeight - 64.0, 90.0), 36.0)

                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .ram, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3 (Tier C only): 4-Pill Telemetry Strip
                HStack(spacing: 3) {
                    miniPill(title: "App", value: "\(String(format: "%.1f", metrics.memoryAppGB))G", color: color)
                    miniPill(title: "Wired", value: "\(String(format: "%.1f", metrics.memoryWiredGB))G", color: .secondary)
                    miniPill(title: "Compr", value: "\(String(format: "%.1f", metrics.memoryCompressedGB))G", color: .secondary)
                    miniPill(title: "Swap", value: "\(Int(metrics.memorySwapUsedMB))M", color: .secondary)
                }
                .frame(height: 22)

                // Row 4: Footer + scopePicker
                HStack {
                    Text("App \(String(format: "%.1f", metrics.memoryAppGB))G · Wired \(String(format: "%.1f", metrics.memoryWiredGB))G · Compr \(String(format: "%.1f", metrics.memoryCompressedGB))G · Swap \(Int(metrics.memorySwapUsedMB))M")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 14)
            }
        }
    }

    // MARK: - Power Focused View
    @ViewBuilder
    private func powerFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let color = VitalsColorResolver.color(for: .power, vitals: metrics, thresholds: effectiveThresholds, palette: palette)

        if availableHeight < 42.0 {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Label("Battery", systemImage: "bolt.batteryblock.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(String(format: "vitals.batteryHealth".localized, metrics.batteryHealthPercent))
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(2.5)
                    Spacer(minLength: 6)
                    Text("\(metrics.batteryLevel)%")
                        .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(Double(metrics.batteryLevel) / 100.0), 3))
                        }
                    }
                    .frame(height: 3.5)

                    Text(metrics.isCharging ? "Charging" : metrics.powerSource)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if availableHeight < 105.0 {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("Battery", systemImage: "bolt.batteryblock.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text("\(metrics.batteryLevel)%")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                // Row 2: Graph
                let graphH: CGFloat = max(availableHeight - 32.0, 14.0)

                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .power, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3: Footer + scopePicker
                HStack {
                    Text("Hlt \(metrics.batteryHealthPercent)% · Cycles \(metrics.batteryCycleCount) · \(String(format: "%.0f", metrics.batteryTemperatureCelsius))°C · \(metrics.isCharging ? "Charging" : metrics.powerSource)")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("Battery", systemImage: "bolt.batteryblock.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text("\(metrics.batteryLevel)%")
                        .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 16)

                // Row 2: Graph
                let graphH: CGFloat = max(min(availableHeight - 64.0, 90.0), 36.0)

                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .power, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3 (Tier C only): 4-Pill Telemetry Strip
                HStack(spacing: 3) {
                    miniPill(title: "Health", value: "\(metrics.batteryHealthPercent)%", color: color)
                    miniPill(title: "Cycles", value: "\(metrics.batteryCycleCount)", color: .secondary)
                    miniPill(title: "Temp", value: "\(String(format: "%.0f", metrics.batteryTemperatureCelsius))°C", color: .secondary)
                    miniPill(title: "Source", value: metrics.powerSource, color: .secondary)
                }
                .frame(height: 22)

                // Row 4: Footer + scopePicker
                HStack {
                    Text("Hlt \(metrics.batteryHealthPercent)% · Cycles \(metrics.batteryCycleCount) · \(String(format: "%.0f", metrics.batteryTemperatureCelsius))°C · \(metrics.isCharging ? "Charging" : metrics.powerSource)")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 14)
            }
        }
    }

    // MARK: - Network Focused View
    @ViewBuilder
    private func networkFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let downColor = Color(hex: "#00F5D4")
        let upColor = Color(hex: "#0A84FF")

        if availableHeight < 42.0 {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Label("Network", systemImage: "network")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    HStack(spacing: 3) {
                        Text("↓\(formatSpeed(bytesPerSec: metrics.networkDownSpeed))")
                            .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                            .foregroundColor(downColor)
                        Text("↑\(formatSpeed(bytesPerSec: metrics.networkUpSpeed))")
                            .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                            .foregroundColor(upColor)
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                HStack(spacing: 4) {
                    GeometryReader { geo in
                        let netRatio = min((metrics.networkDownSpeed + metrics.networkUpSpeed) / 10_485_760.0, 1.0)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(downColor).frame(width: max(geo.size.width * CGFloat(netRatio), 3))
                        }
                    }
                    .frame(height: 3.5)

                    Text("\(metrics.networkInterfaceName) · \(metrics.localIPAddress)")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if availableHeight < 105.0 {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("Network", systemImage: "network")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        Text("↓ \(formatSpeed(bytesPerSec: metrics.networkDownSpeed))")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(downColor)
                        Text("↑ \(formatSpeed(bytesPerSec: metrics.networkUpSpeed))")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(upColor)
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                // Row 2: Graph
                let graphH: CGFloat = max(availableHeight - 32.0, 14.0)

                VitalsDualTimeSeriesGraphView(
                    downPoints: vitals.history(for: .network, scope: timeScope),
                    upPoints: vitals.networkUpHistory(scope: timeScope),
                    downColor: downColor,
                    upColor: upColor,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3: Footer + scopePicker
                HStack {
                    Text("\(metrics.networkInterfaceName) · \(metrics.localIPAddress) · Σ↓ \(String(format: "%.1f", metrics.networkTotalReceivedGB))G ↑ \(String(format: "%.1f", metrics.networkTotalSentGB))G")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("Network", systemImage: "network")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        Text("↓ \(formatSpeed(bytesPerSec: metrics.networkDownSpeed))")
                            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                            .foregroundColor(downColor)
                        Text("↑ \(formatSpeed(bytesPerSec: metrics.networkUpSpeed))")
                            .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                            .foregroundColor(upColor)
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 16)

                // Row 2: Graph
                let graphH: CGFloat = max(min(availableHeight - 64.0, 90.0), 36.0)

                VitalsDualTimeSeriesGraphView(
                    downPoints: vitals.history(for: .network, scope: timeScope),
                    upPoints: vitals.networkUpHistory(scope: timeScope),
                    downColor: downColor,
                    upColor: upColor,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3 (Tier C only): 4-Pill Telemetry Strip
                HStack(spacing: 3) {
                    miniPill(title: "Dev", value: metrics.networkInterfaceName, color: downColor)
                    miniPill(title: "IP", value: metrics.localIPAddress, color: .secondary)
                    miniPill(title: "Total In", value: "\(String(format: "%.1f", metrics.networkTotalReceivedGB))G", color: downColor)
                    miniPill(title: "Total Out", value: "\(String(format: "%.1f", metrics.networkTotalSentGB))G", color: upColor)
                }
                .frame(height: 22)

                // Row 4: Footer + scopePicker
                HStack {
                    Text("\(metrics.networkInterfaceName) · \(metrics.localIPAddress) · Σ↓ \(String(format: "%.1f", metrics.networkTotalReceivedGB))G ↑ \(String(format: "%.1f", metrics.networkTotalSentGB))G")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 14)
            }
        }
    }

    // MARK: - Disk Focused View
    @ViewBuilder
    private func diskFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let color = VitalsColorResolver.color(for: .disk, vitals: metrics, thresholds: effectiveThresholds, palette: palette)
        let usedRatio = metrics.diskTotalGB > 0 ? max(min((metrics.diskTotalGB - metrics.diskFreeGB) / metrics.diskTotalGB, 1.0), 0.0) : 0.5

        if availableHeight < 42.0 {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Label("Disk", systemImage: "internaldrive")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text(String(format: "vitals.diskFreeG".localized, Int(metrics.diskFreeGB)))
                        .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(usedRatio), 3))
                        }
                    }
                    .frame(height: 3.5)

                    Text("R: \(formatSpeed(bytesPerSec: metrics.diskReadBytesPerSec)) · W: \(formatSpeed(bytesPerSec: metrics.diskWriteBytesPerSec))")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if availableHeight < 105.0 {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("Disk", systemImage: "internaldrive")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text(String(format: "vitals.diskFreeG".localized, Int(metrics.diskFreeGB)))
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 15)

                // Row 2: Graph
                let graphH: CGFloat = max(availableHeight - 32.0, 14.0)

                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .disk, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3: Footer + scopePicker
                HStack {
                    Text(String(format: "vitals.diskUsedTotal".localized, Int(metrics.diskTotalGB - metrics.diskFreeGB), Int(metrics.diskTotalGB), formatSpeed(bytesPerSec: metrics.diskReadBytesPerSec), formatSpeed(bytesPerSec: metrics.diskWriteBytesPerSec)))
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Header
                HStack(spacing: 6) {
                    Label("Disk", systemImage: "internaldrive")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text(String(format: "vitals.diskFreeG".localized, Int(metrics.diskFreeGB)))
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: 16)

                // Row 2: Graph
                let graphH: CGFloat = max(min(availableHeight - 64.0, 90.0), 36.0)

                VitalsTimeSeriesGraphView(
                    points: vitals.history(for: .disk, scope: timeScope),
                    color: color,
                    palette: palette,
                    height: graphH,
                    scope: timeScope
                )

                // Row 3 (Tier C only): 4-Pill Telemetry Strip
                HStack(spacing: 3) {
                    miniPill(title: "Used", value: "\(Int(metrics.diskTotalGB - metrics.diskFreeGB))G", color: color)
                    miniPill(title: "Free", value: "\(Int(metrics.diskFreeGB))G", color: .secondary)
                    miniPill(title: "Read", value: formatSpeed(bytesPerSec: metrics.diskReadBytesPerSec), color: .secondary)
                    miniPill(title: "Write", value: formatSpeed(bytesPerSec: metrics.diskWriteBytesPerSec), color: .secondary)
                }
                .frame(height: 22)

                // Row 4: Footer + scopePicker
                HStack {
                    Text(String(format: "vitals.diskUsedTotal".localized, Int(metrics.diskTotalGB - metrics.diskFreeGB), Int(metrics.diskTotalGB), formatSpeed(bytesPerSec: metrics.diskReadBytesPerSec), formatSpeed(bytesPerSec: metrics.diskWriteBytesPerSec)))
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 14)
            }
        }
    }

    @ViewBuilder
    private func miniPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 6.5, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3.5)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(3.5)
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
        let showMarkings = height >= 46.0
        let canvasH = showMarkings ? max(height - 12.0, 10.0) : height

        VStack(spacing: showMarkings ? 2 : 0) {
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
            .frame(height: canvasH)

            if showMarkings {
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
                .frame(height: 10)
            }
        }
        .frame(height: height)
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
        let showMarkings = height >= 46.0
        let canvasH = showMarkings ? max(height - 12.0, 10.0) : height

        VStack(spacing: showMarkings ? 2 : 0) {
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
            .frame(height: canvasH)

            if showMarkings {
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
                .frame(height: 10)
            }
        }
        .frame(height: height)
    }
}
