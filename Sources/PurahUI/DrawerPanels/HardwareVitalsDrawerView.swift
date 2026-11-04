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

struct ProcessBarWidths: Equatable, Sendable {
    let first: Double
    let second: Double

    var total: Double { first + second }

    static let zero = ProcessBarWidths(first: 0, second: 0)
}

enum ProcessBarSplitter {
    static func width(
        value: Double,
        scale: Double,
        trackWidth: Double,
        minimumNonZeroWidth: Double = 2
    ) -> Double {
        let value = finiteNonNegative(value)
        let trackWidth = finiteNonNegative(trackWidth)
        let scale = finiteNonNegative(scale)
        guard value > 0, trackWidth > 0, scale > 0 else { return 0 }

        let proportional = trackWidth * min(value / scale, 1)
        let minimum = min(finiteNonNegative(minimumNonZeroWidth), trackWidth)
        return min(trackWidth, max(proportional, minimum))
    }

    static func widths(
        first: Double,
        second: Double,
        scale: Double,
        trackWidth: Double,
        minimumNonZeroWidth: Double = 2
    ) -> ProcessBarWidths {
        let first = finiteNonNegative(first)
        let second = finiteNonNegative(second)
        let totalValue = first + second
        let trackWidth = finiteNonNegative(trackWidth)
        let scale = finiteNonNegative(scale)
        guard totalValue > 0, trackWidth > 0, scale > 0 else { return .zero }

        let minimum = min(finiteNonNegative(minimumNonZeroWidth), trackWidth)
        let nonzeroCount = (first > 0 ? 1.0 : 0.0) + (second > 0 ? 1.0 : 0.0)
        let proportional = trackWidth * min(totalValue / scale, 1)
        let totalWidth = min(
            trackWidth,
            max(proportional, minimum * nonzeroCount)
        )

        guard first > 0, second > 0 else {
            return first > 0
                ? ProcessBarWidths(first: totalWidth, second: 0)
                : ProcessBarWidths(first: 0, second: totalWidth)
        }

        let effectiveMinimum = min(minimum, totalWidth / 2)
        let distributable = max(totalWidth - effectiveMinimum * 2, 0)
        let firstWidth = effectiveMinimum + distributable * (first / totalValue)
        let secondWidth = totalWidth - firstWidth
        return ProcessBarWidths(first: firstWidth, second: secondWidth)
    }

    private static func finiteNonNegative(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 0
    }
}

private enum ProcessMetricThresholds {
    static let cpuWarningPercent = 20.0
    static let cpuDangerPercent = 50.0
    static let memoryWarningPercent = 5.0
    static let memoryDangerPercent = 10.0
    static let networkWarningBytesPerSecond = 5.0 * 1_048_576.0
    static let networkDangerBytesPerSecond = 20.0 * 1_048_576.0
    static let diskWarningBytesPerSecond = 10.0 * 1_048_576.0
    static let diskDangerBytesPerSecond = 50.0 * 1_048_576.0
    static let powerWarningWatts = 1.0
    static let powerDangerWatts = 5.0
}

// MARK: - Composite Full Drawer View
public struct HardwareVitalsDrawerView: View {
    public let state: VitalsPluginState
    public let store: PurahWorkspaceStore

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
            state.mount(store: store)
            vitals.startMonitoring()
            state.refreshMetrics(includeProcesses: false)
        }
        .onDisappear {
            vitals.isDrawerVisible = false
            vitals.setProcessesTabVisible(false)
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
            // The four dashboard tabs live in the card header now, so the
            // body starts with content.
            PurahScrollableBody {
                VStack(alignment: .leading, spacing: 6) {
                    switch state.dashboardTab {
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
                            cpuColor: cpuColor,
                            ramColor: ramColor,
                            netColor: netColor,
                            diskColor: diskColor,
                            powerColor: powerColor
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
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
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
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3.5)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.borderColor.opacity(0.16), lineWidth: 0.6))
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
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor.opacity(0.16), lineWidth: 0.6))

                // 2. GPU Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("GPU")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(metrics.gpuUsage * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor.opacity(0.16), lineWidth: 0.6))
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
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor.opacity(0.16), lineWidth: 0.6))

                // 4. Battery Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Battery")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(metrics.batteryLevel)%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor.opacity(0.16), lineWidth: 0.6))
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
                        .cornerRadius(4)

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
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor.opacity(0.16), lineWidth: 0.6))

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
                .cornerRadius(8)

                // Top 3 Processes Strip
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("vitals.topProcesses".localized)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            withAnimation { state.dashboardTab = .processes }
                        } label: {
                            Text("vitals.viewAll".localized)
                                .font(.system(size: 8.5, weight: .medium))
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
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundColor(.secondary)
                            if proc.id != 1 {
                                Button("Kill") {
                                    vitals.killProcess(pid: proc.id)
                                }
                                .font(.system(size: 7.5, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(palette.dangerAccent.opacity(0.12))
                                .foregroundColor(palette.dangerAccent)
                                .cornerRadius(4)
                                .buttonStyle(.tactile)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(6)
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
                        .cornerRadius(4)
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
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor.opacity(0.16), lineWidth: 0.6))

            // RAM Deep Card
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "memorychip")
                        .foregroundColor(ramColor)
                    Text("vitals.memoryArchitecture".localized)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    Spacer()
                    Text(String(format: "vitals.pressure".localized, metrics.memoryPressureLevel))
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(metrics.memoryPressureLevel == "Normal" ? palette.primaryAccent : palette.dangerAccent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                }

                HStack {
                    Text("\(String(format: "%.1f", metrics.memoryUsedGB)) GB Used / \(String(format: "%.1f", metrics.memoryTotalGB)) GB Physical")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(metrics.memoryUsage * 100))%")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
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
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor.opacity(0.16), lineWidth: 0.6))
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
                        .cornerRadius(4)
                }

                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Text("↓")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(netColor)
                        Text(formatSpeed(metrics.networkDownSpeed))
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    }
                    HStack(spacing: 3) {
                        Text("↑")
                            .font(.system(size: 9.5, weight: .bold))
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
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor.opacity(0.16), lineWidth: 0.6))

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
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor.opacity(0.16), lineWidth: 0.6))
        }
    }

    // MARK: - Tab: Processes
    @ViewBuilder
    private func processesTabContent(
        metrics: HardwareVitalsInfo,
        cpuColor: Color,
        ramColor: Color,
        netColor: Color,
        diskColor: Color,
        powerColor: Color
    ) -> some View {
        let metric = state.processSortMetric
        let visibleRows = ProcessInspectorRanking.ranked(
            metrics.topProcesses,
            by: metric,
            limit: 12
        )

        // The bar is a relative ranking inside the visible list; the number
        // carries the absolute truth. A zero value stays a zero-width bar.
        let largest = visibleRows.map { metric.value(for: $0) }.max() ?? 0
        let scale = max(largest, 0.000_001)

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(String(format: "vitals.processInspector".localized, metrics.topProcesses.count))
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(ProcessSortMetric.allCases) { candidate in
                        Button {
                            state.setProcessSortMetric(candidate)
                        } label: {
                            Text(candidate.title)
                                .font(.system(
                                    size: 7.5,
                                    weight: metric == candidate ? .bold : .medium,
                                    design: .monospaced
                                ))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(metric == candidate ? palette.primaryAccent.opacity(0.18) : Color.clear)
                                .foregroundColor(metric == candidate ? palette.primaryAccent : .secondary)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            ForEach(visibleRows) { proc in
                let alarmColor = processAlarmColor(proc, metric: metric)
                let statusColor = alarmColor ?? processBaseColor(
                    metric: metric,
                    cpuColor: cpuColor,
                    ramColor: ramColor,
                    netColor: netColor,
                    diskColor: diskColor,
                    powerColor: powerColor
                )
                let split = processBarSplit(for: proc, metric: metric)
                let splitColors = processBarSplitColors(
                    metric: metric,
                    netColor: netColor,
                    diskColor: diskColor
                )
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 4.5, height: 4.5)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(proc.name)
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Text("pid \(proc.id)")
                                .font(.system(size: 7.5, design: .monospaced))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.06))
                                if let split, let splitColors, alarmColor == nil {
                                    let widths = ProcessBarSplitter.widths(
                                        first: split.first,
                                        second: split.second,
                                        scale: scale,
                                        trackWidth: g.size.width
                                    )
                                    HStack(spacing: 0) {
                                        Rectangle()
                                            .fill(splitColors.0)
                                            .frame(
                                                width: CGFloat(widths.first),
                                                height: g.size.height
                                            )
                                        Rectangle()
                                            .fill(splitColors.1)
                                            .frame(
                                                width: CGFloat(widths.second),
                                                height: g.size.height
                                            )
                                    }
                                    .frame(width: CGFloat(widths.total), height: g.size.height, alignment: .leading)
                                    .clipShape(Capsule())
                                } else {
                                    let width = ProcessBarSplitter.width(
                                        value: metric.value(for: proc),
                                        scale: scale,
                                        trackWidth: g.size.width
                                    )
                                    Capsule()
                                        .fill(statusColor)
                                        .frame(width: CGFloat(width))
                                }
                            }
                        }
                        .frame(height: 2.5)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(primaryProcessValue(for: proc, metric: metric))
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(secondaryProcessValue(for: proc, metric: metric))
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    if proc.id != 1 {
                        Button {
                            vitals.killProcess(pid: proc.id)
                        } label: {
                            Text("vitals.kill".localized)
                                .font(.system(size: 7.5, weight: .semibold))
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1.5)
                                .background(palette.dangerAccent.opacity(0.12))
                                .foregroundColor(palette.dangerAccent)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.tactile)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.025))
                .cornerRadius(6)
            }
        }
        .onAppear {
            vitals.setProcessesTabVisible(true)
        }
        .onDisappear {
            vitals.setProcessesTabVisible(false)
        }
    }

    private func processAlarmColor(
        _ process: ProcessInfoItem,
        metric: ProcessSortMetric
    ) -> Color? {
        switch metric {
        case .cpu:
            if process.cpuPercent > ProcessMetricThresholds.cpuDangerPercent {
                return palette.dangerAccent
            }
            if process.cpuPercent > ProcessMetricThresholds.cpuWarningPercent {
                return VitalsColorResolver.warningYellow
            }
        case .memory:
            if process.memoryPercent > ProcessMetricThresholds.memoryDangerPercent {
                return palette.dangerAccent
            }
            if process.memoryPercent > ProcessMetricThresholds.memoryWarningPercent {
                return VitalsColorResolver.warningYellow
            }
        case .network:
            let total = process.networkDownBytesPerSecond + process.networkUpBytesPerSecond
            if total > ProcessMetricThresholds.networkDangerBytesPerSecond {
                return palette.dangerAccent
            }
            if total > ProcessMetricThresholds.networkWarningBytesPerSecond {
                return VitalsColorResolver.warningYellow
            }
        case .disk:
            let total = process.diskReadBytesPerSecond + process.diskWriteBytesPerSecond
            if total > ProcessMetricThresholds.diskDangerBytesPerSecond {
                return palette.dangerAccent
            }
            if total > ProcessMetricThresholds.diskWarningBytesPerSecond {
                return VitalsColorResolver.warningYellow
            }
        case .power:
            if process.energyWatts > ProcessMetricThresholds.powerDangerWatts {
                return palette.dangerAccent
            }
            if process.energyWatts > ProcessMetricThresholds.powerWarningWatts {
                return VitalsColorResolver.warningYellow
            }
        }
        return nil
    }

    private func processBaseColor(
        metric: ProcessSortMetric,
        cpuColor: Color,
        ramColor: Color,
        netColor: Color,
        diskColor: Color,
        powerColor: Color
    ) -> Color {
        switch metric {
        case .cpu:
            return cpuColor
        case .memory:
            return ramColor
        case .network:
            return netColor
        case .disk:
            return diskColor
        case .power:
            return powerColor
        }
    }

    private func processBarSplit(
        for process: ProcessInfoItem,
        metric: ProcessSortMetric
    ) -> (first: Double, second: Double)? {
        switch metric {
        case .network:
            return (
                process.networkDownBytesPerSecond,
                process.networkUpBytesPerSecond
            )
        case .disk:
            return (
                process.diskReadBytesPerSecond,
                process.diskWriteBytesPerSecond
            )
        case .cpu, .memory, .power:
            return nil
        }
    }

    private func processBarSplitColors(
        metric: ProcessSortMetric,
        netColor: Color,
        diskColor: Color
    ) -> (Color, Color)? {
        switch metric {
        case .network:
            return (netColor, Color(hex: "#0A84FF"))
        case .disk:
            return (diskColor, Color(hex: "#FF9F0A"))
        case .cpu, .memory, .power:
            return nil
        }
    }

    private func primaryProcessValue(for process: ProcessInfoItem, metric: ProcessSortMetric) -> String {
        switch metric {
        case .cpu:
            return "CPU \(String(format: "%.1f", process.cpuPercent))%"
        case .memory:
            return "\(formatProcessMemory(process.memoryMB)) · \(Int(process.memoryPercent.rounded()))%"
        case .network:
            if process.networkUpBytesPerSecond > process.networkDownBytesPerSecond {
                return "↑ \(formatProcessSpeed(process.networkUpBytesPerSecond))"
            }
            return "↓ \(formatProcessSpeed(process.networkDownBytesPerSecond))"
        case .disk:
            if process.diskWriteBytesPerSecond > process.diskReadBytesPerSecond {
                return "W \(formatProcessSpeed(process.diskWriteBytesPerSecond))"
            }
            return "R \(formatProcessSpeed(process.diskReadBytesPerSecond))"
        case .power:
            return String(format: "%.2f W", process.energyWatts)
        }
    }

    private func secondaryProcessValue(for process: ProcessInfoItem, metric: ProcessSortMetric) -> String {
        switch metric {
        case .cpu:
            return formatProcessMemory(process.memoryMB)
        case .memory:
            return "CPU \(String(format: "%.1f", process.cpuPercent))%"
        case .network:
            let other = process.networkUpBytesPerSecond > process.networkDownBytesPerSecond
                ? "↓ \(formatProcessSpeed(process.networkDownBytesPerSecond))"
                : "↑ \(formatProcessSpeed(process.networkUpBytesPerSecond))"
            return "\(other) · \(formatProcessMemory(process.memoryMB))"
        case .disk:
            let other = process.diskWriteBytesPerSecond > process.diskReadBytesPerSecond
                ? "R \(formatProcessSpeed(process.diskReadBytesPerSecond))"
                : "W \(formatProcessSpeed(process.diskWriteBytesPerSecond))"
            return "\(other) · CPU \(String(format: "%.1f", process.cpuPercent))%"
        case .power:
            return "CPU \(String(format: "%.1f", process.cpuPercent))%"
        }
    }

    private func formatProcessMemory(_ megabytes: Double) -> String {
        if megabytes >= 1_024 {
            return String(format: "%.1f GB", megabytes / 1_024)
        }
        return String(format: "%.0f MB", megabytes)
    }

    private func formatProcessSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1fM/s", bytesPerSecond / 1_048_576)
        }
        if bytesPerSecond >= 1_024 {
            return String(format: "%.0fK/s", bytesPerSecond / 1_024)
        }
        return String(format: "%.0fB/s", bytesPerSecond)
    }

    // MARK: - Reusable UI Helpers
    @ViewBuilder
    private func breakdownPill(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7.5, design: .monospaced))
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
    public let showsHeader: Bool
    public let state: VitalsPluginState
    public let store: PurahWorkspaceStore

    @State private var timeScope: VitalsTimeScope = .realTime30s

    private var palette: ThemePalette { ThemeManager.shared.palette }
    private var vitals: HardwareVitalsService { HardwareVitalsService.shared }
    private var effectiveThresholds: VitalsColorThresholds { state.thresholds }

    /// A header-less body (host-owned stepped card) still chooses the tier it
    /// would have drawn with its 15pt header row, then uses that room for the
    /// graph instead of leaving a blank strip.
    private var layoutHeight: CGFloat { availableHeight }

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
                        .cornerRadius(4)
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
        showsHeader: Bool = true,
        state: VitalsPluginState,
        store: PurahWorkspaceStore = PurahWorkspaceStore()
    ) {
        self.metric = metric
        self.availableHeight = availableHeight
        self.trailingHeader = trailingHeader
        self.showsHeader = showsHeader
        self.state = state
        self.store = store
    }

    public init(
        metric: VitalsMetricType,
        availableHeight: CGFloat = 48.0,
        trailingHeader: AnyView? = nil,
        showsHeader: Bool = true,
        store: PurahWorkspaceStore
    ) {
        let pluginState = (PluginRegistry.shared.plugin(for: "vitals") as? HardwareVitalsPlugin)?.state ?? VitalsPluginState()
        self.init(metric: metric, availableHeight: availableHeight, trailingHeader: trailingHeader, showsHeader: showsHeader, state: pluginState, store: store)
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
            vitals.refreshMetrics(includeProcesses: false)
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

        if layoutHeight < 42.0 {
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
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(metrics.cpuUsage), 3))
                        }
                    }
                    .frame(height: 3.5)

                    Text(String(format: "vitals.cpuUsrSys".localized, Int(metrics.cpuUserUsage * 100), Int(metrics.cpuSystemUsage * 100)))
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if layoutHeight < 105.0 {
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
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(layoutHeight - (showsHeader ? 32.0 : 17.0), 14.0)

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
                        if top.id != 1 {
                            Button("Kill") {
                                vitals.killProcess(pid: top.id)
                            }
                            .font(.system(size: 7.5, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 0.5)
                            .background(palette.dangerAccent.opacity(0.18))
                            .foregroundColor(palette.dangerAccent)
                            .cornerRadius(2.5)
                            .buttonStyle(.tactile)
                        }
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
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: showsHeader ? 16 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(min(layoutHeight - 64.0, 90.0), 36.0)

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
                        if top.id != 1 {
                            Button("Kill") {
                                vitals.killProcess(pid: top.id)
                            }
                            .font(.system(size: 7.5, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(palette.dangerAccent.opacity(0.18))
                            .foregroundColor(palette.dangerAccent)
                            .cornerRadius(4)
                            .buttonStyle(.tactile)
                        }
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

        if layoutHeight < 42.0 {
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
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(gpuRatio), 3))
                        }
                    }
                    .frame(height: 3.5)

                    Text(metrics.thermalStateLabel)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if layoutHeight < 105.0 {
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
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(layoutHeight - (showsHeader ? 32.0 : 17.0), 14.0)

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
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: showsHeader ? 16 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(min(layoutHeight - 64.0, 90.0), 36.0)

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

        if layoutHeight < 42.0 {
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
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(metrics.memoryUsage), 3))
                        }
                    }
                    .frame(height: 3.5)

                    Text("\(String(format: "%.1f", metrics.memoryUsedGB))G / \(String(format: "%.0f", metrics.memoryTotalGB))G")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if layoutHeight < 105.0 {
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
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(layoutHeight - (showsHeader ? 32.0 : 17.0), 14.0)

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
                .frame(height: showsHeader ? 16 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(min(layoutHeight - 64.0, 90.0), 36.0)

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

        if layoutHeight < 42.0 {
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
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(Double(metrics.batteryLevel) / 100.0), 3))
                        }
                    }
                    .frame(height: 3.5)

                    Text(metrics.isCharging ? "Charging" : metrics.powerSource)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if layoutHeight < 105.0 {
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
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(layoutHeight - (showsHeader ? 32.0 : 17.0), 14.0)

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
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: showsHeader ? 16 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(min(layoutHeight - 64.0, 90.0), 36.0)

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

        if layoutHeight < 42.0 {
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
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

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
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if layoutHeight < 105.0 {
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
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(layoutHeight - (showsHeader ? 32.0 : 17.0), 14.0)

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
                .frame(height: showsHeader ? 16 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(min(layoutHeight - 64.0, 90.0), 36.0)

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

        if layoutHeight < 42.0 {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Label("Disk", systemImage: "internaldrive")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    Text(String(format: "vitals.diskFreeG".localized, Int(metrics.diskFreeGB)))
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let trailingHeader { trailingHeader }
                }
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(usedRatio), 3))
                        }
                    }
                    .frame(height: 3.5)

                    Text("R: \(formatSpeed(bytesPerSec: metrics.diskReadBytesPerSec)) · W: \(formatSpeed(bytesPerSec: metrics.diskWriteBytesPerSec))")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    scopePicker
                }
                .frame(height: 13)
            }
        } else if layoutHeight < 105.0 {
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
                .frame(height: showsHeader ? 15 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(layoutHeight - (showsHeader ? 32.0 : 17.0), 14.0)

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
                .frame(height: showsHeader ? 16 : 0.0)
                .opacity(showsHeader ? 1.0 : 0.0)

                // Row 2: Graph
                let graphH: CGFloat = max(min(layoutHeight - 64.0, 90.0), 36.0)

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
                .font(.system(size: 7.5, design: .monospaced))
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
        .cornerRadius(4)
    }
}

// MARK: - Real-Time Time-Series Historical Graph (X-Axis: Time, Y-Axis: Value)
public struct VitalsTimeSeriesGraphView: View {
    public let points: [VitalsHistoryPoint]
    public let color: Color
    public let palette: ThemePalette
    public let height: CGFloat
    public let scope: VitalsTimeScope
    public let showsGrid: Bool

    public init(
        points: [VitalsHistoryPoint],
        color: Color,
        palette: ThemePalette,
        height: CGFloat = 46.0,
        scope: VitalsTimeScope = .realTime30s,
        showsGrid: Bool = true
    ) {
        self.points = points
        self.color = color
        self.palette = palette
        self.height = height
        self.scope = scope
        self.showsGrid = showsGrid
    }

    /// The visible points, mapped onto the window. The vertical domain follows
    /// the data instead of a fixed 0…1: a metric that moves between 58% and
    /// 62% drew a flat line before, and "no visible change" is the one thing a
    /// sparkline must never say about data that did change.
    private func computePlotPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let now = Date()
        let windowSec = scope.durationSeconds

        let recent = points.filter { now.timeIntervalSince($0.timestamp) <= windowSec }
        let currentVal = points.last?.value ?? 0.0
        let domain = valueDomain(recent)
        let span = max(domain.upperBound - domain.lowerBound, 0.0001)

        func yPosition(_ value: Double) -> CGFloat {
            let clamped = min(max(CGFloat(value), domain.lowerBound), domain.upperBound)
            return height - height * ((clamped - domain.lowerBound) / span)
        }

        var result: [CGPoint] = recent.map { pt in
            let age = min(max(now.timeIntervalSince(pt.timestamp), 0.0), windowSec)
            let x = width * CGFloat(1.0 - (age / windowSec))
            return CGPoint(x: x, y: yPosition(pt.value))
        }

        if result.isEmpty {
            let y = yPosition(currentVal)
            result = [CGPoint(x: 0, y: y), CGPoint(x: width, y: y)]
        } else if result.count == 1, let only = result.first {
            result.insert(CGPoint(x: 0, y: only.y), at: 0)
        } else if let first = result.first, first.x > 0 {
            result.insert(CGPoint(x: 0, y: first.y), at: 0)
        }
        return result
    }

    /// Padded min…max of the visible samples, with a floor on the span so a
    /// constant reading sits in the middle instead of filling the chart.
    private func valueDomain(_ recent: [VitalsHistoryPoint]) -> ClosedRange<CGFloat> {
        let values = recent.map { CGFloat(min(max($0.value, 0.0), 1.0)) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let minimumSpan: CGFloat = 0.05
        if high - low < minimumSpan {
            let mid = (low + high) / 2
            let lower = max(mid - minimumSpan / 2, 0)
            return lower...min(lower + minimumSpan, 1)
        }
        let padding = (high - low) * 0.15
        return max(low - padding, 0)...min(high + padding, 1)
    }

    public var body: some View {
        let showMarkings = height >= 34.0
        let canvasH = showMarkings ? max(height - 11.0, 10.0) : height

        VStack(spacing: showMarkings ? 2 : 0) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let plotPoints = computePlotPoints(width: w, height: h)

                ZStack {
                    // Grid background lines at 25%, 50%, 75%
                    if showsGrid {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: h * 0.25))
                            path.addLine(to: CGPoint(x: w, y: h * 0.25))
                            path.move(to: CGPoint(x: 0, y: h * 0.50))
                            path.addLine(to: CGPoint(x: w, y: h * 0.50))
                            path.move(to: CGPoint(x: 0, y: h * 0.75))
                            path.addLine(to: CGPoint(x: w, y: h * 0.75))
                        }
                        .stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                    }

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
                                colors: [color.opacity(0.5), color.opacity(0.06)],
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
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                    Text(scope.markings.middle)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                    Spacer()
                    Text(scope.markings.right)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(height: 10)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Row Sparkline (chip row, 28pt)

/// The mini chart that rides a hardware chip's row: the same area fill and
/// end dot as the drawer graph, no grid and no axis, with the time range in
/// the corner. It takes whatever width the row's text leaves, so it never
/// leaves a dead gap between the reading and the line.
public struct VitalsRowSparkline: View {
    public let metric: VitalsMetricType
    public let color: Color
    public let palette: ThemePalette
    public let height: CGFloat

    /// Tapping cycles the window, so a 24h trend is one click away from a chip
    /// that has no room for a scope picker.
    @State private var scope: VitalsTimeScope = .realTime30s

    public init(metric: VitalsMetricType, color: Color, palette: ThemePalette, height: CGFloat = 28.0) {
        self.metric = metric
        self.color = color
        self.palette = palette
        self.height = height
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            VitalsTimeSeriesGraphView(
                points: HardwareVitalsService.shared.history(for: metric, scope: scope),
                color: color,
                palette: palette,
                height: max(height - 9.0, 12.0),
                scope: scope,
                showsGrid: false
            )
            Text(scope.rawValue)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 60, maxWidth: .infinity, alignment: .trailing)
        .frame(height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            let all = VitalsTimeScope.allCases
            guard let index = all.firstIndex(of: scope) else { return }
            scope = all[(index + 1) % all.count]
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
        }
        .help("vitals.scope.cycleHint".localized)
        .accessibilityLabel("vitals.scope.cycleHint".localized)
        .accessibilityAddTraits(.isButton)
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

    /// Padded min…max of the visible samples, with a floor on the span so a
    /// constant reading sits in the middle instead of filling the chart.
    private func valueDomain(_ recent: [VitalsHistoryPoint]) -> ClosedRange<CGFloat> {
        let values = recent.map { CGFloat(min(max($0.value, 0.0), 1.0)) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let minimumSpan: CGFloat = 0.05
        if high - low < minimumSpan {
            let mid = (low + high) / 2
            let lower = max(mid - minimumSpan / 2, 0)
            return lower...min(lower + minimumSpan, 1)
        }
        let padding = (high - low) * 0.15
        return max(low - padding, 0)...min(high + padding, 1)
    }

    public var body: some View {
        let showMarkings = height >= 34.0
        let canvasH = showMarkings ? max(height - 11.0, 10.0) : height

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
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                    Text(scope.markings.middle)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                    Spacer()
                    Text(scope.markings.right)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(height: 10)
            }
        }
        .frame(height: height)
    }
}
