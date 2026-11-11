// Sources/PurahUI/DrawerPanels/HardwareVitalsDrawerView.swift
import SwiftUI
import PurahCore

// MARK: - Dashboard Tab Selection
public enum VitalsDashboardTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case compute
    case io
    case power
    case processes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .compute: return "Compute"
        case .io: return "Net/Disk"
        case .power: return "Power"
        case .processes: return "Procs"
        }
    }

    public var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .compute: return "cpu"
        case .io: return "network"
        case .power: return "bolt.batteryblock.fill"
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

/// Pure width maths for the per-core heat grid, so the P/E weighting is
/// resolved once and can be tested without a window.
struct VitalsCoreGridMetrics: Equatable, Sendable {
    static let groupGap: CGFloat = 12
    static let intraGroupSpacing: CGFloat = 3
    static let performanceWeight: CGFloat = 1.5

    let performanceWidth: CGFloat
    let efficiencyWidth: CGFloat

    static func resolve(
        availableWidth: CGFloat,
        performanceCount: Int,
        efficiencyCount: Int
    ) -> VitalsCoreGridMetrics? {
        let performance = max(performanceCount, 0)
        let efficiency = max(efficiencyCount, 0)
        let cores = performance + efficiency
        guard cores > 0 else { return nil }

        let available = max(availableWidth, 0)
        let isSplit = performance > 0 && efficiency > 0
        let gap = isSplit ? groupGap : 0
        // One gap between neighbours in the brief's single-row model; the
        // rendered two-group HStack simply leaves a little extra slack.
        let gaps = CGFloat(max(cores - 1, 0)) * intraGroupSpacing
        let weights = CGFloat(performance) * performanceWeight + CGFloat(efficiency)
        let unit = max((available - gap - gaps) / max(weights, 0.0001), 0)

        if isSplit {
            return VitalsCoreGridMetrics(
                performanceWidth: unit * performanceWeight,
                efficiencyWidth: unit
            )
        }

        // No P/E claim: every core in the one group gets the same width.
        return VitalsCoreGridMetrics(
            performanceWidth: performance > 0 ? unit : 0,
            efficiencyWidth: efficiency > 0 ? unit : 0
        )
    }
}

/// One shared vertical scale for a band's rows, so download and upload (or
/// read and write) are drawn against the same ceiling instead of each row
/// normalising to its own maximum.
struct VitalsThroughputDomain: Equatable, Sendable {
    /// A quiet link must look quiet: no band ever draws below 1 MB/s.
    static let floorCeiling: Double = 1_048_576

    let ceiling: Double

    static func ceiling(for maximumBytesPerSecond: Double) -> Double {
        guard maximumBytesPerSecond.isFinite, maximumBytesPerSecond > floorCeiling else {
            return floorCeiling
        }
        var scale = pow(10.0, floor(log10(maximumBytesPerSecond)) - 2)
        while scale > 0 {
            for multiplier in [1.0, 2.0, 5.0] {
                let candidate = multiplier * scale
                if candidate >= maximumBytesPerSecond {
                    return max(candidate, floorCeiling)
                }
            }
            scale *= 10
        }
        return floorCeiling
    }

    init(maximumBytesPerSecond: Double) {
        self.ceiling = Self.ceiling(for: maximumBytesPerSecond)
    }
}

/// The three directional series that share a metric (`.network` is download,
/// `.disk` is capacity), used by the test seam that renders each row with its
/// own curve.
enum VitalsThroughputSeries: Hashable, Sendable {
    case networkUp
    case diskRead
    case diskWrite
}

private struct VitalsOverviewHover: Equatable {
    let metric: VitalsMetricType
    let index: Int
    let buckets: [VitalsBucket]
    let bucketColors: [Color]?
}

// MARK: - Composite Full Drawer View
public struct HardwareVitalsDrawerView: View {
    public let state: VitalsPluginState
    public let store: PurahWorkspaceStore
    private let service: HardwareVitalsService
    /// Test seam: the overview render tests need deterministic curves, while
    /// the cells' live readings still come from the probe-injected service.
    private let historyOverride: [VitalsMetricType: [VitalsHistoryPoint]]?
    /// Test seam for the rows that share `.network` or `.disk` with another
    /// direction.
    private let throughputOverride: [VitalsThroughputSeries: [VitalsHistoryPoint]]?
    /// Test seam for the Power tab's ribbon readout, which otherwise needs a
    /// pointer.
    private let batteryHoverPreview: Int?
    /// Test seam for the ribbon's wall-clock cells.
    private let renderNow: Date?
    /// Test seam for the state points behind the ribbon and the battery cell.
    private let batteryStateOverride: [VitalsHistoryPoint]?
    /// Test seam for a hovered column in the Compute bands.
    private let columnHoverPreviews: [VitalsMetricType: Int]
    @State private var overviewHover: VitalsOverviewHover?
    @State private var hoveredBatteryCell: Int?

    private var vitals: HardwareVitalsService {
        service
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
        self.service = .shared
        self.historyOverride = nil
        self.throughputOverride = nil
        self.batteryHoverPreview = nil
        self.renderNow = nil
        self.batteryStateOverride = nil
        self.columnHoverPreviews = [:]
    }

    /// Test seam: a drawer reads one service instance, so a probe-injected
    /// service (for example a desktop with no battery) can be rendered without
    /// touching the app-wide singleton.
    init(
        state: VitalsPluginState,
        store: PurahWorkspaceStore,
        service: HardwareVitalsService
    ) {
        self.state = state
        self.store = store
        self.service = service
        self.historyOverride = nil
        self.throughputOverride = nil
        self.batteryHoverPreview = nil
        self.renderNow = nil
        self.batteryStateOverride = nil
        self.columnHoverPreviews = [:]
    }

    /// Test seam for render harnesses that need a fixed curve (for example a
    /// constant GPU series) without faking the whole service.
    init(
        state: VitalsPluginState,
        store: PurahWorkspaceStore,
        service: HardwareVitalsService,
        historyOverride: [VitalsMetricType: [VitalsHistoryPoint]],
        throughputOverride: [VitalsThroughputSeries: [VitalsHistoryPoint]] = [:],
        batteryHoverPreview: Int? = nil,
        renderNow: Date? = nil,
        batteryStateOverride: [VitalsHistoryPoint]? = nil,
        columnHoverPreviews: [VitalsMetricType: Int] = [:]
    ) {
        self.state = state
        self.store = store
        self.service = service
        self.historyOverride = historyOverride
        self.throughputOverride = throughputOverride.isEmpty ? nil : throughputOverride
        self.batteryHoverPreview = batteryHoverPreview
        self.renderNow = renderNow
        self.batteryStateOverride = batteryStateOverride
        self.columnHoverPreviews = columnHoverPreviews
    }

    private func columnBuckets(
        _ metric: VitalsMetricType,
        scope: VitalsTimeScope,
        maximumColumns: Int = 60
    ) -> [VitalsBucket] {
        if let points = historyOverride?[metric] {
            return VitalsHistoryBuffer.columns(
                fast: points,
                scope: scope,
                fastResolution: vitals.samplingInterval,
                maximumColumns: maximumColumns
            )
        }
        return vitals.columns(
            for: metric,
            scope: scope,
            maximumColumns: maximumColumns
        )
    }

    private func columnBuckets(
        _ series: VitalsThroughputSeries,
        scope: VitalsTimeScope
    ) -> [VitalsBucket] {
        if let points = throughputOverride?[series] {
            return VitalsHistoryBuffer.columns(
                fast: points,
                scope: scope,
                fastResolution: vitals.samplingInterval
            )
        }
        switch series {
        case .networkUp:
            return vitals.networkUpColumns(scope: scope)
        case .diskRead:
            return vitals.diskReadColumns(scope: scope)
        case .diskWrite:
            return vitals.diskWriteColumns(scope: scope)
        }
    }

    private func availableSpan(_ metric: VitalsMetricType) -> TimeInterval {
        if let points = historyOverride?[metric],
           let oldest = points.map(\.timestamp).min() {
            return max(Date().timeIntervalSince(oldest), 0)
        }
        return vitals.availableSpan(for: metric)
    }

    private func rangeFooter(_ metric: VitalsMetricType, scope: VitalsTimeScope) -> String {
        VitalsColumnFormatting.rangeFooter(
            scope: scope,
            available: availableSpan(metric)
        )
    }

    private func detailWithRange(
        _ detail: String,
        metric: VitalsMetricType,
        scope: VitalsTimeScope
    ) -> String {
        let range = VitalsColumnFormatting.duration(scope.durationSeconds)
        return detail.isEmpty ? range : "\(detail) · \(range)"
    }

    private func cycleScope(_ metric: VitalsMetricType) {
        let all = VitalsTimeScope.allCases
        let current = state.scope(for: metric)
        guard let index = all.firstIndex(of: current) else { return }
        state.setScope(all[(index + 1) % all.count], for: metric)
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
    }

    /// The ribbon records one state per ten-minute bucket, so its availability
    /// is counted in whole cells rather than seconds.
    private var batteryStatePointsForDisplay: [VitalsHistoryPoint] {
        batteryStateOverride ?? vitals.batteryStatePoints
    }

    private func batteryStateCellsForDisplay(
        range: TimeInterval,
        now: Date
    ) -> [VitalsStateCell] {
        if let batteryStateOverride {
            return VitalsStateHistory(points: batteryStateOverride).cells(
                range: range,
                now: now,
                currentState: nil
            )
        }
        return vitals.batteryStateCells(range: range, now: now)
    }

    private func batteryStateAvailableSpan(now: Date = Date()) -> TimeInterval {
        let interval = VitalsStateHistory.interval
        guard let oldest = batteryStatePointsForDisplay.first?.timestamp else {
            return vitals.metrics.batteryIsPresent ? interval : 0
        }
        let currentStart = Date(
            timeIntervalSince1970: floor(now.timeIntervalSince1970 / interval) * interval
        )
        let oldestStart = Date(
            timeIntervalSince1970: floor(oldest.timeIntervalSince1970 / interval) * interval
        )
        let count = max(
            Int((currentStart.timeIntervalSince(oldestStart) / interval).rounded()) + 1,
            1
        )
        return Double(count) * interval
    }

    private func batteryRibbonCells(
        scope: VitalsTimeScope,
        now: Date = Date()
    ) -> [VitalsStateCell] {
        let interval = VitalsStateHistory.interval
        let availableCount = max(
            Int((batteryStateAvailableSpan(now: now) / interval).rounded()),
            1
        )
        let selectedCount = max(
            Int((scope.durationSeconds / interval).rounded()),
            1
        )
        let count = min(selectedCount, availableCount)
        return batteryStateCellsForDisplay(
            range: Double(count) * interval,
            now: now
        )
    }

    private func batteryRangeFooter(
        scope: VitalsTimeScope,
        now: Date = Date()
    ) -> String {
        VitalsColumnFormatting.rangeFooter(
            scope: scope,
            available: batteryStateAvailableSpan(now: now)
        )
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
            vitals.startMonitoring(interval: TimeInterval(state.samplingIntervalSeconds))
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
        // The tabs are sized by the body they actually get, not by the tier's
        // estimate: a card that is co-planar with its pod can be shorter than
        // the drawer content it was asked to draw. Measuring here is what
        // keeps "no band leaves a void" true at every pod height.
        GeometryReader { proxy in
            // The four dashboard tabs live in the card header now, so the
            // body starts with content.
            PurahScrollableBody {
                VStack(alignment: .leading, spacing: 6) {
                    switch state.dashboardTab {
                    case .overview:
                        overviewTabContent(
                            metrics: metrics,
                            availableHeight: proxy.size.height,
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
                            availableHeight: proxy.size.height,
                            cpuColor: cpuColor,
                            gpuColor: gpuColor,
                            ramColor: ramColor
                        )
                    case .io:
                        ioTabContent(
                            metrics: metrics,
                            availableHeight: proxy.size.height,
                            diskColor: diskColor,
                            netColor: netColor
                        )
                    case .power:
                        powerTabContent(
                            metrics: metrics,
                            availableHeight: proxy.size.height,
                            powerColor: powerColor
                        )
                    case .processes:
                        processesTabContent(
                            metrics: metrics,
                            availableHeight: proxy.size.height,
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
        availableHeight: CGFloat,
        showsDeepTelemetry: Bool,
        cpuColor: Color,
        gpuColor: Color,
        ramColor: Color,
        diskColor: Color,
        powerColor: Color,
        netColor: Color
    ) -> some View {
        overviewSheet(
            metrics: metrics,
            availableHeight: availableHeight,
            showsDeepTelemetry: showsDeepTelemetry,
            cpuColor: cpuColor,
            gpuColor: gpuColor,
            ramColor: ramColor,
            powerColor: powerColor,
            netColor: netColor
        )
    }

    // MARK: - Overview Sheet (variant E)

    /// One surface divided by hairlines: the drawer card is already a card,
    /// so the Overview draws no second card inside it.
    private func overviewSheet(
        metrics: HardwareVitalsInfo,
        availableHeight: CGFloat,
        showsDeepTelemetry: Bool,
        cpuColor: Color,
        gpuColor: Color,
        ramColor: Color,
        powerColor: Color,
        netColor: Color
    ) -> some View {
        // A tall drawer gives every band a share of the surplus; a short one
        // keeps the sheet at its natural height and lets the host scroll it,
        // so a 60pt body never squeezes the cells on top of each other.
        // Everything on this sheet — the tiles, the network band and the two
        // immersive rows — grows together. The tiles and the network carry
        // plots and stop at twice their natural height; the two immersive rows
        // are lists and take whatever is left, so the sheet ends exactly at
        // the card's bottom edge at every drawer height.
        var bands: [VitalsBandBudget.Band] = [
            .chart(natural: Self.overviewCellNaturalHeight),
            .chart(natural: Self.overviewCellNaturalHeight),
            .fixed(Self.overviewHairlineHeight),
            .chart(natural: Self.overviewNetworkNaturalHeight)
        ]
        if showsDeepTelemetry {
            // Without a process sample (the Procs tab has not been opened in
            // this session) the TOP band is one header line; it must not claim
            // the sheet's spare height for rows that will not be drawn.
            let topRows = min(metrics.topProcesses.count, 3)
            let topNatural = Self.overviewTopProcessesNaturalHeight
                - CGFloat(3 - topRows) * Self.overviewTopProcessRowHeight
            bands += [
                .fixed(Self.overviewHairlineHeight),
                .list(natural: Self.overviewDeepRowNaturalHeight),
                .fixed(Self.overviewHairlineHeight),
                topRows > 0
                    ? .list(natural: topNatural)
                    : .fixed(topNatural)
            ]
        }
        let sheetHeight = VitalsBandBudget.drawingHeight(
            available: availableHeight - 4,
            bands: bands
        )
        let heights = VitalsBandBudget.allocate(available: sheetHeight, bands: bands)
        let cpuBuckets = columnBuckets(.cpu, scope: .realTime30s, maximumColumns: 30)
        let gpuBuckets = columnBuckets(.gpu, scope: .realTime30s, maximumColumns: 30)
        let ramBuckets = columnBuckets(.ram, scope: .realTime30s, maximumColumns: 30)
        let batteryBuckets = columnBuckets(.power, scope: .hours12, maximumColumns: 30)
        let batteryStates = VitalsStateHistory.stateValues(
            for: batteryBuckets,
            points: batteryStatePointsForDisplay
        )
        let batteryColors = batteryStates.map {
            VitalsStateRibbon.color(for: $0 ?? 0)
        }

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                overviewCell(
                    title: "CPU",
                    value: "\(Int(metrics.cpuUsage * 100))%",
                    tint: cpuColor,
                    detail: "Usr \(Int(metrics.cpuUserUsage * 100))% · Sys \(Int(metrics.cpuSystemUsage * 100))% · Load \(String(format: "%.1f", metrics.loadAverage1m))",
                    hoverMetric: .cpu,
                    plot: AnyView(overviewColumnPlot(metric: .cpu, buckets: cpuBuckets)),
                    spokenLabel: String(
                        format: "vitals.a11y.metric".localized,
                        "CPU",
                        Int(metrics.cpuUsage * 100)
                    )
                )
                .overlay(alignment: .trailing) { overviewVerticalHairline }

                overviewCell(
                    title: "GPU",
                    value: "\(Int(metrics.gpuUsage * 100))%",
                    tint: gpuColor,
                    detail: "\(metrics.chipModelName) · \(metrics.thermalStateLabel)",
                    hoverMetric: .gpu,
                    plot: AnyView(overviewColumnPlot(metric: .gpu, buckets: gpuBuckets)),
                    spokenLabel: String(
                        format: "vitals.a11y.metric".localized,
                        "GPU",
                        Int(metrics.gpuUsage * 100)
                    )
                )
            }
            .frame(height: heights[0])

            overviewHairline
                .frame(height: heights[2])

            HStack(spacing: 0) {
                overviewCell(
                    title: "RAM",
                    value: "\(Int(metrics.memoryUsage * 100))%",
                    tint: ramColor,
                    detail: ramDetail(metrics),
                    hoverMetric: .ram,
                    plot: AnyView(overviewColumnPlot(metric: .ram, buckets: ramBuckets)),
                    spokenLabel: String(
                        format: "vitals.a11y.metric".localized,
                        "RAM",
                        Int(metrics.memoryUsage * 100)
                    )
                )
                .overlay(alignment: .trailing) { overviewVerticalHairline }

                overviewCell(
                    title: "BATTERY",
                    value: "\(metrics.batteryLevel)%",
                    tint: powerColor,
                    detail: "Health \(metrics.batteryHealthPercent)% · \(metrics.batteryCycleCount) cyc · \(metrics.isCharging ? "Charging" : metrics.powerSource)",
                    hoverMetric: .power,
                    plot: AnyView(
                        overviewColumnPlot(
                            metric: .power,
                            buckets: batteryBuckets,
                            bucketColors: batteryColors
                        )
                    ),
                    spokenLabel: String(
                        format: "vitals.a11y.metric".localized,
                        "BATTERY",
                        metrics.batteryLevel
                    )
                )
            }
            .frame(height: heights[1])

            overviewHairline

            overviewNetworkBand(metrics: metrics)
                .frame(height: heights[3])

            if showsDeepTelemetry {
                overviewHairline
                    .frame(height: heights[4])
                overviewDeepTelemetryRow(metrics: metrics)
                    .frame(height: heights[5])
                overviewHairline
                    .frame(height: heights[6])
                overviewTopProcessesRow(metrics: metrics)
                    .frame(height: heights[7], alignment: .topLeading)
            }
        }
        .padding(.horizontal, 2)
        .frame(height: sheetHeight, alignment: .top)
    }

    private static let overviewCellNaturalHeight: CGFloat = 62
    private static let overviewNetworkNaturalHeight: CGFloat = 54
    private static let overviewDeepRowNaturalHeight: CGFloat = 21
    private static let overviewTopProcessesNaturalHeight: CGFloat = 66
    private static let overviewTopProcessRowHeight: CGFloat = 14
    private static let overviewHairlineHeight: CGFloat = 0.6

    func overviewCell(
        title: String,
        value: String,
        tint: Color,
        detail: String,
        hoverMetric: VitalsMetricType? = nil,
        plot: AnyView,
        spokenLabel: String
    ) -> some View {
        let hoveredBucket: VitalsBucket? = {
            guard let hoverMetric,
                  let overviewHover,
                  overviewHover.metric == hoverMetric,
                  overviewHover.buckets.indices.contains(overviewHover.index) else {
                return nil
            }
            return overviewHover.buckets[overviewHover.index]
        }()
        let displayedValue = hoveredBucket.map {
            "\(Int(($0.mean * 100).rounded()))%"
        } ?? value
        let displayedDetail = hoveredBucket.map {
            "\(VitalsColumnFormatting.minuteTime($0.start)) · \(Int(($0.mean * 100).rounded()))%"
        } ?? detail

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(displayedValue)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            plot
            .frame(maxHeight: .infinity)
            .frame(minHeight: 20)

            Text(displayedDetail)
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    /// The Overview cell reads on a fixed 0…1 scale, so a 1% idle reading
    /// stays a 1% column instead of zooming its own noise across the plot.
    private func overviewColumnPlot(
        metric: VitalsMetricType,
        buckets: [VitalsBucket],
        bucketColors: [Color]? = nil
    ) -> some View {
        let displayedBuckets = overviewHover?.metric == metric
            ? overviewHover?.buckets ?? buckets
            : buckets
        let displayedColors = overviewHover?.metric == metric
            ? overviewHover?.bucketColors
            : bucketColors
        return VitalsColumnStrip(
            buckets: displayedBuckets,
            domain: .percentage,
            tint: VitalsColorResolver.identityColor(for: metric),
            bucketColors: displayedColors,
            metric: metric,
            thresholds: effectiveThresholds,
            hoveredIndex: Binding(
                get: {
                    guard let overviewHover, overviewHover.metric == metric else { return nil }
                    return overviewHover.index
                },
                set: { newValue in
                    if let newValue {
                        let snapshot = overviewHover?.metric == metric
                            ? overviewHover?.buckets ?? buckets
                            : buckets
                        let snapshotColors = overviewHover?.metric == metric
                            ? overviewHover?.bucketColors
                            : bucketColors
                        overviewHover = VitalsOverviewHover(
                            metric: metric,
                            index: newValue,
                            buckets: snapshot,
                            bucketColors: snapshotColors
                        )
                    } else if overviewHover?.metric == metric {
                        overviewHover = nil
                    }
                }
            )
        )
    }

    private func ramDetail(_ metrics: HardwareVitalsInfo) -> String {
        "\(compactGB(metrics.memoryUsedGB)) / \(compactGB(metrics.memoryTotalGB)) G · Wired \(compactGB(metrics.memoryWiredGB)) · Swp \(compactSwap(metrics.memorySwapUsedMB))"
    }

    /// Whole gigabytes lose their `.0`; the cell row has one line and the
    /// total already carries the unit, so the fractions only earn their space
    /// when they are real.
    private func compactGB(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        return tenths == tenths.rounded()
            ? String(format: "%.0f", tenths)
            : String(format: "%.1f", tenths)
    }

    private func compactSwap(_ megabytes: Double) -> String {
        if megabytes >= 1024 {
            return compactGB(megabytes / 1024) + "G"
        }
        if megabytes < 1 {
            return "0"
        }
        return "\(Int(megabytes))M"
    }

    /// A machine without swap has no total worth showing, so the footer drops
    /// the "/ total" half instead of claiming "0 / 0 GB".
    private func ramFooter(
        _ metrics: HardwareVitalsInfo,
        usedGB: Double,
        totalGB: Double
    ) -> String {
        if totalGB > 0 {
            return String(
                format: "vitals.compute.ramFooter".localized,
                compactGB(usedGB),
                compactGB(totalGB),
                localizedMemoryPressure(metrics.memoryPressureLevel)
            )
        }
        return String(
            format: "vitals.compute.ramFooterNoSwap".localized,
            compactGB(usedGB),
            localizedMemoryPressure(metrics.memoryPressureLevel)
        )
    }

    /// The storage pressure level is a stable English token; the footer shows
    /// the same state in the reader's language.
    private func localizedMemoryPressure(_ level: String) -> String {
        switch level.lowercased() {
        case "normal": return "vitals.pressureState.normal".localized
        case "warning": return "vitals.pressureState.warning".localized
        case "critical": return "vitals.pressureState.critical".localized
        default: return level
        }
    }

    /// `thermalStateLabel` is the service's stable English token; the legend
    /// renders the same state in the reader's language.
    private func localizedThermalState(_ label: String) -> String {
        switch label.lowercased() {
        case "nominal": return "vitals.thermal.nominal".localized
        case "fair": return "vitals.thermal.fair".localized
        case "serious": return "vitals.thermal.serious".localized
        case "critical": return "vitals.thermal.critical".localized
        default: return label
        }
    }

    private func overviewNetworkBand(
        metrics: HardwareVitalsInfo
    ) -> some View {
        let downBuckets = columnBuckets(.network, scope: .realTime30s)
        let upBuckets = columnBuckets(.networkUp, scope: .realTime30s)
        let domain = throughputDomain([downBuckets, upBuckets])
        let downTint = VitalsColorResolver.identityColor(for: .network)
        let upTint = Color(hex: "#0A84FF")

        return VStack(spacing: 5) {
            overviewNetworkRow(
                label: "NET ↓",
                speed: metrics.networkDownSpeed,
                tint: downTint,
                buckets: downBuckets,
                domain: domain,
                total: metrics.networkTotalReceivedGB,
                spokenLabel: String(
                    format: "vitals.a11y.networkDown".localized,
                    spokenSpeed(metrics.networkDownSpeed)
                )
            )
            overviewNetworkRow(
                label: "NET ↑",
                speed: metrics.networkUpSpeed,
                tint: upTint,
                buckets: upBuckets,
                domain: domain,
                total: metrics.networkTotalSentGB,
                spokenLabel: String(
                    format: "vitals.a11y.networkUp".localized,
                    spokenSpeed(metrics.networkUpSpeed)
                )
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxHeight: .infinity)
    }

    private func overviewNetworkRow(
        label: String,
        speed: Double,
        tint: Color,
        buckets: [VitalsBucket],
        domain: VitalsColumnDomain,
        total: Double,
        spokenLabel: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(formatSpeed(speed))
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundColor(tint)
                .lineLimit(1)
                .fixedSize()
            VitalsColumnStrip(
                buckets: buckets,
                domain: domain,
                tint: tint,
                metric: .network,
                thresholds: effectiveThresholds,
                hoveredIndex: .constant(nil),
                showsHover: false
            )
            .frame(maxWidth: .infinity)
            Text(String(format: "Σ %.1f G", total))
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 62, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private func spokenSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576.0 {
            return String(
                format: "vitals.a11y.megabytesPerSecond".localized,
                String(format: "%.1f", bytesPerSec / 1_048_576.0)
            )
        }
        if bytesPerSec >= 1024.0 {
            return String(
                format: "vitals.a11y.kilobytesPerSecond".localized,
                String(format: "%.0f", bytesPerSec / 1024.0)
            )
        }
        return String(
            format: "vitals.a11y.bytesPerSecond".localized,
            String(format: "%.0f", bytesPerSec)
        )
    }

    private func overviewDeepTelemetryRow(metrics: HardwareVitalsInfo) -> some View {
        return HStack(spacing: 8) {
            overviewBreakdownPair(label: "USER", value: "\(Int(metrics.cpuUserUsage * 100))%")
            Text("·").foregroundColor(.secondary)
            overviewBreakdownPair(label: "SYS", value: "\(Int(metrics.cpuSystemUsage * 100))%")
            Text("·").foregroundColor(.secondary)
            overviewBreakdownPair(label: "APP", value: "\(String(format: "%.1f", metrics.memoryAppGB))G")
            Text("·").foregroundColor(.secondary)
            overviewBreakdownPair(label: "WIRED", value: "\(String(format: "%.1f", metrics.memoryWiredGB))G")
            Text("·").foregroundColor(.secondary)
            overviewBreakdownPair(label: "SWAP", value: compactSwap(metrics.memorySwapUsedMB))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func overviewBreakdownPair(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func overviewTopProcessesRow(metrics: HardwareVitalsInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TOP")
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
            Spacer(minLength: 3)

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
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { state.dashboardTab = .processes }
                }
                Spacer(minLength: 3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var overviewHairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 0.6)
    }

    private var overviewVerticalHairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 0.6)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 2)
    }

    // MARK: - Shared Sheet Grammar

    private func vitalsBandHeader(
        title: String,
        detail: String = "",
        value: String = "",
        tint: Color,
        valueSize: CGFloat = 14
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color.primary.opacity(0.85))
                .lineLimit(1)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: valueSize, weight: .bold, design: .monospaced))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func vitalsRail(ratio: Double, tint: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(geo.size.width * CGFloat(min(max(ratio, 0), 1)), 4))
            }
        }
        // The level bar and the state ribbon below it share one band and must
        // stay the same thickness.
        .frame(height: 16)
    }

    private func vitalsLegend(_ items: [(String, String, Color)]) -> some View {
        HStack(spacing: 9) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 3) {
                    Circle()
                        .fill(item.2)
                        .frame(width: 4.5, height: 4.5)
                    Text(item.0)
                        .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(item.1)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.primary.opacity(0.8))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
        }
    }

    private func vitalsCompositionBar(
        segments: [(Double, Color)],
        height: CGFloat = 7
    ) -> some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.0 }, 0.0001)
            HStack(spacing: 1.5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.1)
                        .frame(width: max(geo.size.width * CGFloat(segment.0 / total) - 1.5, 2))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .frame(height: height)
    }

    private var vitalsHairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 0.6)
    }

    private func vitalsDetailCells(_ cells: [(String, String)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(alignment: .leading, spacing: 1) {
                    Text(cell.0)
                        .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(cell.1)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.primary.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Both rows of a band share one log domain: 1 KB/s at the bottom and a
    /// nice-number ceiling above the busiest bucket, never below 1 MB/s.
    private func throughputDomain(_ series: [[VitalsBucket]]) -> VitalsColumnDomain {
        let maximumBytes = series.flatMap { $0 }.map(\.mean).max() ?? 0
        let ceilingBytes = VitalsThroughputDomain.ceiling(for: max(maximumBytes, 0))
        return .log(lower: 1_024, upper: ceilingBytes)
    }

    // MARK: - Tab: Compute (CPU, GPU & RAM)
    @ViewBuilder
    private func computeTabContent(
        metrics: HardwareVitalsInfo,
        availableHeight: CGFloat,
        cpuColor: Color,
        gpuColor: Color,
        ramColor: Color
    ) -> some View {
        let cpuDetail: String = {
            let cores = metrics.performanceCoreCount + metrics.efficiencyCoreCount
            guard cores > 0 else { return metrics.chipModelName }
            return String(
                format: "vitals.compute.cpuDetail".localized,
                metrics.chipModelName,
                metrics.performanceCoreCount,
                metrics.efficiencyCoreCount
            )
        }()
        let gpuDetail = metrics.gpuCoreCount > 0
            ? String(format: "vitals.compute.gpuDetail".localized, metrics.chipModelName, metrics.gpuCoreCount)
            : metrics.chipModelName
        let gpuMemory = metrics.gpuMemoryInUseMB >= 1024
            ? String(format: "%.1f G", metrics.gpuMemoryInUseMB / 1024.0)
            : String(format: "%.0f M", metrics.gpuMemoryInUseMB)
        let swapUsedGB = metrics.memorySwapUsedMB / 1024.0
        let swapTotalGB = metrics.memorySwapTotalMB / 1024.0
        let cpuScope = state.scope(for: .cpu)
        let gpuScope = state.scope(for: .gpu)
        let ramScope = state.scope(for: .ram)
        // Three identical bands share one budget: the CPU's core grid makes
        // its natural band taller, but each band's share of the surplus is the
        // same, and a plot stops at twice its natural height.
        let bands: [VitalsBandBudget.Band] = [
            .chart(natural: Self.cpuBandNaturalHeight),
            .fixed(Self.computeHairlineHeight),
            .chart(natural: Self.gpuBandNaturalHeight),
            .fixed(Self.computeHairlineHeight),
            .chart(natural: Self.ramBandNaturalHeight)
        ]
        let drawingHeight = VitalsBandBudget.drawingHeight(
            available: availableHeight - 4,
            bands: bands
        )
        let bandHeights = VitalsBandBudget.allocate(available: drawingHeight, bands: bands)

        VStack(spacing: 0) {
            VitalsMetricColumnBand(
                metric: .cpu,
                title: "CPU",
                detail: detailWithRange(cpuDetail, metric: .cpu, scope: cpuScope),
                rangeLabel: VitalsColumnFormatting.duration(cpuScope.durationSeconds),
                liveValue: "\(Int(metrics.cpuUsage * 100))%",
                tint: cpuColor,
                columnTint: VitalsColorResolver.identityColor(for: .cpu),
                buckets: columnBuckets(.cpu, scope: cpuScope),
                domain: .percentage,
                scope: cpuScope,
                thresholds: effectiveThresholds,
                nowLabel: "vitals.range.now".localized,
                liveFooter: nil,
                rangeFooter: rangeFooter(.cpu, scope: cpuScope),
                valueFormatter: { "\(Int(($0 * 100).rounded()))%" },
                plotMinHeight: 20,
                plotMaxHeight: nil,
                extra: AnyView(
                    VStack(alignment: .leading, spacing: 5) {
                        vitalsCoreGrid(
                            usages: metrics.cpuCoreUsages,
                            performanceCount: metrics.performanceCoreCount,
                            efficiencyCount: metrics.efficiencyCoreCount,
                            tint: cpuColor
                        )
                        .padding(.top, 1)
                        vitalsLegend([
                            ("USR", "\(Int(metrics.cpuUserUsage * 100))", cpuColor),
                            ("SYS", "\(Int(metrics.cpuSystemUsage * 100))", VitalsColorResolver.warningYellow),
                            ("IDLE", "\(Int(metrics.cpuIdleUsage * 100))", Color.primary.opacity(0.35)),
                            ("LOAD", String(format: "%.2f", metrics.loadAverage1m), Color.primary.opacity(0.8)),
                            (
                                "vitals.compute.thermal".localized,
                                localizedThermalState(metrics.thermalStateLabel),
                                Color.primary.opacity(0.8)
                            )
                        ])
                    }
                ),
                onCycle: { cycleScope(.cpu) },
                collapsesWhenEmpty: true,
                showsFooter: false,
                previewHoveredIndex: columnHoverPreviews[.cpu]
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(height: bandHeights[0], alignment: .topLeading)

            vitalsHairline
                .frame(height: bandHeights[1])

            VitalsMetricColumnBand(
                metric: .gpu,
                title: "GPU",
                detail: detailWithRange(gpuDetail, metric: .gpu, scope: gpuScope),
                rangeLabel: VitalsColumnFormatting.duration(gpuScope.durationSeconds),
                liveValue: "\(Int(metrics.gpuUsage * 100))%",
                tint: gpuColor,
                columnTint: VitalsColorResolver.identityColor(for: .gpu),
                buckets: columnBuckets(.gpu, scope: gpuScope),
                domain: .percentage,
                scope: gpuScope,
                thresholds: effectiveThresholds,
                nowLabel: "vitals.range.now".localized,
                liveFooter: nil,
                rangeFooter: rangeFooter(.gpu, scope: gpuScope),
                valueFormatter: { "\(Int(($0 * 100).rounded()))%" },
                plotMinHeight: 30,
                plotMaxHeight: nil,
                extra: AnyView(
                    vitalsLegend([
                        ("RENDERER", "\(Int(metrics.gpuRendererUsage * 100))", gpuColor),
                        ("TILER", "\(Int(metrics.gpuTilerUsage * 100))", Color.primary.opacity(0.45)),
                        ("MEM", gpuMemory, Color.primary.opacity(0.8))
                    ])
                ),
                onCycle: { cycleScope(.gpu) },
                previewHoveredIndex: columnHoverPreviews[.gpu]
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(height: bandHeights[2], alignment: .topLeading)

            vitalsHairline
                .frame(height: bandHeights[3])

            VitalsMetricColumnBand(
                metric: .ram,
                title: "RAM",
                detail: detailWithRange(
                    String(
                        format: "vitals.compute.ramDetail".localized,
                        compactGB(metrics.memoryTotalGB)
                    ),
                    metric: .ram,
                    scope: ramScope
                ),
                rangeLabel: VitalsColumnFormatting.duration(ramScope.durationSeconds),
                liveValue: "\(Int(metrics.memoryUsage * 100))%",
                tint: ramColor,
                columnTint: VitalsColorResolver.identityColor(for: .ram),
                buckets: columnBuckets(.ram, scope: ramScope),
                domain: .percentage,
                scope: ramScope,
                thresholds: effectiveThresholds,
                nowLabel: "vitals.range.now".localized,
                liveFooter: ramFooter(metrics, usedGB: swapUsedGB, totalGB: swapTotalGB),
                rangeFooter: rangeFooter(.ram, scope: ramScope),
                valueFormatter: { "\(Int(($0 * 100).rounded()))%" },
                plotMinHeight: 32,
                plotMaxHeight: nil,
                extra: AnyView(
                    VStack(alignment: .leading, spacing: 5) {
                        vitalsCompositionBar(segments: [
                            (metrics.memoryActiveGB, ramColor.opacity(0.9)),
                            (metrics.memoryWiredGB, Color.primary.opacity(0.42)),
                            (metrics.memoryCompressedGB, VitalsColorResolver.warningYellow.opacity(0.85)),
                            (metrics.memoryCachedGB, Color.primary.opacity(0.20)),
                            (metrics.memoryFreeGB, Color.primary.opacity(0.08))
                        ])
                        vitalsLegend([
                            ("ACTIVE", compactGB(metrics.memoryActiveGB), ramColor),
                            ("WIRED", compactGB(metrics.memoryWiredGB), Color.primary.opacity(0.55)),
                            ("COMPR", compactGB(metrics.memoryCompressedGB), VitalsColorResolver.warningYellow),
                            ("CACHED", compactGB(metrics.memoryCachedGB), Color.primary.opacity(0.30)),
                            ("FREE", compactGB(metrics.memoryFreeGB), Color.primary.opacity(0.16))
                        ])
                    }
                ),
                onCycle: { cycleScope(.ram) },
                previewHoveredIndex: columnHoverPreviews[.ram]
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(height: bandHeights[4], alignment: .topLeading)
        }
        .padding(.horizontal, 2)
        .frame(height: drawingHeight, alignment: .top)
    }

    /// Natural heights of the three Compute bands at rest: header, plot and
    /// the band's own extra (the CPU core grid, the GPU/RAM legends) plus the
    /// 12pt of vertical padding. They are inputs to the budget, not floors.
    private static let cpuBandNaturalHeight: CGFloat = 142
    private static let gpuBandNaturalHeight: CGFloat = 89
    private static let ramBandNaturalHeight: CGFloat = 103
    private static let computeHairlineHeight: CGFloat = 0.6

    // MARK: - Per-Core Heat Grid

    @ViewBuilder
    private func vitalsCoreGrid(
        usages: [Double],
        performanceCount: Int,
        efficiencyCount: Int,
        tint: Color
    ) -> some View {
        let splitKnown = performanceCount > 0
            && efficiencyCount > 0
            && usages.count == performanceCount + efficiencyCount
        let performanceUsages = splitKnown
            ? Array(usages.prefix(performanceCount))
            : usages
        let efficiencyUsages = splitKnown
            ? Array(usages.dropFirst(performanceCount))
            : []

        GeometryReader { geo in
            if let layout = VitalsCoreGridMetrics.resolve(
                availableWidth: geo.size.width,
                performanceCount: performanceUsages.count,
                efficiencyCount: efficiencyUsages.count
            ) {
                HStack(alignment: .top, spacing: VitalsCoreGridMetrics.groupGap) {
                    vitalsCoreGroup(
                        usages: performanceUsages,
                        alpha: 0.95,
                        blockWidth: layout.performanceWidth,
                        startIndex: 1,
                        kind: splitKnown ? .performance : nil,
                        tint: tint
                    )
                    if !efficiencyUsages.isEmpty {
                        vitalsCoreGroup(
                            usages: efficiencyUsages,
                            alpha: 0.55,
                            blockWidth: layout.efficiencyWidth,
                            startIndex: performanceUsages.count + 1,
                            kind: .efficiency,
                            tint: tint
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 62)
    }

    private enum CoreKind {
        case performance
        case efficiency
    }

    @ViewBuilder
    private func vitalsCoreGroup(
        usages: [Double],
        alpha: Double,
        blockWidth: CGFloat,
        startIndex: Int,
        kind: CoreKind?,
        tint: Color
    ) -> some View {
        VStack(spacing: 2.5) {
            HStack(alignment: .bottom, spacing: VitalsCoreGridMetrics.intraGroupSpacing) {
                ForEach(Array(usages.enumerated()), id: \.offset) { offset, usage in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(Color.primary.opacity(0.055))
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(tint.opacity(alpha))
                            .frame(height: max(50 * CGFloat(min(max(usage, 0), 1)), 2))
                    }
                    .frame(width: blockWidth, height: 40)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(coreAccessibilityLabel(
                        index: startIndex + offset,
                        usage: usage,
                        kind: kind
                    ))
                }
            }
            .frame(height: 50)

            HStack(spacing: VitalsCoreGridMetrics.intraGroupSpacing) {
                ForEach(Array(usages.enumerated()), id: \.offset) { _, usage in
                    if blockWidth >= 11 {
                        Text("\(Int(usage * 100))")
                            .font(.system(
                                size: blockWidth >= 17 ? 6.5 : 6,
                                weight: .semibold,
                                design: .monospaced
                            ))
                            .foregroundColor(.secondary)
                            .frame(width: blockWidth)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Color.clear.frame(width: blockWidth, height: 8)
                    }
                }
            }
        }
    }

    private func coreAccessibilityLabel(index: Int, usage: Double, kind: CoreKind?) -> String {
        let percent = Int((min(max(usage, 0), 1) * 100).rounded())
        let key: String = switch kind {
        case .performance: "vitals.a11y.corePerformance"
        case .efficiency: "vitals.a11y.coreEfficiency"
        case nil: "vitals.a11y.core"
        }
        return String(format: key.localized, index, percent)
    }

    // MARK: - Tab: Net/Disk
    @ViewBuilder
    private func ioTabContent(
        metrics: HardwareVitalsInfo,
        availableHeight: CGFloat,
        diskColor: Color,
        netColor: Color
    ) -> some View {
        let upColor = Color(hex: "#0A84FF")
        let writeColor = Color.primary.opacity(0.5)
        let usedGB = max(metrics.diskTotalGB - metrics.diskFreeGB, 0)
        let usedRatio = metrics.diskTotalGB > 0 ? usedGB / metrics.diskTotalGB : 0
        let netScope = state.scope(for: .network)
        let diskScope = state.scope(for: .disk)
        let downBuckets = columnBuckets(.network, scope: netScope)
        let upBuckets = columnBuckets(.networkUp, scope: netScope)
        let readBuckets = columnBuckets(.diskRead, scope: diskScope)
        let writeBuckets = columnBuckets(.diskWrite, scope: diskScope)
        // Both rows in a band share one log domain, so a quiet upload is not
        // stretched to the height of a busy download.
        let netDomain = throughputDomain([downBuckets, upBuckets])
        let diskDomain = throughputDomain([readBuckets, writeBuckets])
        let rateFormatter: (Double) -> String = { formatSpeed($0) }
        // Both IO bands are charts and share one budget; each row inside them
        // already gives its strip the flexible half, so the extra height lands
        // on the plots rather than on the band's padding.
        let bands: [VitalsBandBudget.Band] = [
            .chart(natural: Self.networkBandNaturalHeight),
            .fixed(Self.ioHairlineHeight),
            .chart(natural: Self.diskBandNaturalHeight)
        ]
        let drawingHeight = VitalsBandBudget.drawingHeight(
            available: availableHeight - 4,
            bands: bands
        )
        let bandHeights = VitalsBandBudget.allocate(available: drawingHeight, bands: bands)

        VStack(spacing: 0) {
            VitalsThroughputBand(
                metric: .network,
                title: "NETWORK",
                detail: detailWithRange(
                    "\(metrics.networkInterfaceName) · \(metrics.localIPAddress)",
                    metric: .network,
                    scope: netScope
                ),
                headerValue: "",
                tint: netColor,
                rows: [
                    VitalsThroughputBandRow(
                        glyph: "↓",
                        liveValue: formatSpeed(metrics.networkDownSpeed),
                        tint: VitalsColorResolver.identityColor(for: .network),
                        buckets: downBuckets,
                        total: "Σ \(compactGB(metrics.networkTotalReceivedGB)) G"
                    ),
                    VitalsThroughputBandRow(
                        glyph: "↑",
                        liveValue: formatSpeed(metrics.networkUpSpeed),
                        tint: upColor,
                        buckets: upBuckets,
                        total: "Σ \(compactGB(metrics.networkTotalSentGB)) G"
                    )
                ],
                domain: netDomain,
                scope: netScope,
                thresholds: effectiveThresholds,
                nowLabel: "vitals.range.now".localized,
                rangeFooter: rangeFooter(.network, scope: netScope),
                valueFormatter: rateFormatter,
                extra: nil,
                onCycle: { cycleScope(.network) }
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(height: bandHeights[0], alignment: .topLeading)

            vitalsHairline
                .frame(height: bandHeights[1])

            VitalsThroughputBand(
                metric: .disk,
                title: "DISK",
                detail: detailWithRange(
                    String(
                        format: "vitals.disk.bootDisk".localized,
                        compactGB(metrics.diskTotalGB)
                    ),
                    metric: .disk,
                    scope: diskScope
                ),
                headerValue: "\(Int((usedRatio * 100).rounded()))%",
                tint: diskColor,
                rows: [
                    VitalsThroughputBandRow(
                        glyph: "R",
                        liveValue: formatSpeed(metrics.diskReadBytesPerSec),
                        tint: VitalsColorResolver.identityColor(for: .disk),
                        buckets: readBuckets,
                        total: "Σ \(compactGB(metrics.diskReadTotalGB)) G"
                    ),
                    VitalsThroughputBandRow(
                        glyph: "W",
                        liveValue: formatSpeed(metrics.diskWriteBytesPerSec),
                        tint: writeColor,
                        buckets: writeBuckets,
                        total: "Σ \(compactGB(metrics.diskWriteTotalGB)) G"
                    )
                ],
                domain: diskDomain,
                scope: diskScope,
                thresholds: effectiveThresholds,
                nowLabel: "vitals.range.now".localized,
                rangeFooter: rangeFooter(.disk, scope: diskScope),
                valueFormatter: rateFormatter,
                extra: AnyView(
                    VStack(alignment: .leading, spacing: 5) {
                        vitalsCompositionBar(segments: [
                            (usedGB, diskColor.opacity(0.75)),
                            (metrics.diskFreeGB, Color.primary.opacity(0.08))
                        ])
                        vitalsLegend([
                            ("USED", "\(compactGB(usedGB)) G", diskColor),
                            ("FREE", "\(compactGB(metrics.diskFreeGB)) G", Color.primary.opacity(0.8)),
                            ("TOTAL", "\(compactGB(metrics.diskTotalGB)) G", Color.primary.opacity(0.3))
                        ])
                    }
                ),
                onCycle: { cycleScope(.disk) }
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(height: bandHeights[2], alignment: .topLeading)
        }
        .padding(.horizontal, 2)
        .frame(height: drawingHeight, alignment: .top)
    }

    /// Natural heights of the two throughput bands: header, two rows at their
    /// 20pt minimum, the footer, and the disk's composition legend.
    private static let networkBandNaturalHeight: CGFloat = 110
    private static let diskBandNaturalHeight: CGFloat = 136
    private static let ioHairlineHeight: CGFloat = 0.6

    // MARK: - Tab: Power

    @ViewBuilder
    private func powerTabContent(
        metrics: HardwareVitalsInfo,
        availableHeight: CGFloat,
        powerColor: Color
    ) -> some View {
        Group {
            if metrics.batteryIsPresent {
                batterySheet(
                    metrics: metrics,
                    availableHeight: availableHeight,
                    powerColor: powerColor
                )
            } else {
                noBatterySheet(metrics: metrics, powerColor: powerColor)
            }
        }
        .padding(.horizontal, 2)
    }

    private func batterySheet(
        metrics: HardwareVitalsInfo,
        availableHeight: CGFloat,
        powerColor: Color
    ) -> some View {
        let state = batteryState(metrics)
        let capacity = capacityWh(metrics)
        let showsFlow = showsPowerFlow(metrics)
        // The battery bar and the flow band grow with the drawer; CAPACITY and
        // the health grid are pinned to the bottom. A fixed band keeps its
        // natural height (weight 0), so every spare point lands on the two
        // bands that can use it.
        var bands: [VitalsBandBudget.Band] = [
            .chart(natural: Self.batteryBandNaturalHeight)
        ]
        if showsFlow {
            bands.append(.fixed(Self.powerHairlineHeight))
            // The flow band is the tab's list: three columns and a caption can
            // use any height the battery chart cannot take, so it absorbs the
            // remainder instead of leaving it at the bottom of the card.
            bands.append(.list(natural: Self.powerFlowNaturalHeight))
        }
        if capacity != nil {
            bands.append(.fixed(Self.powerHairlineHeight))
            bands.append(.fixed(Self.capacityBandNaturalHeight))
        }
        bands.append(.fixed(Self.powerHairlineHeight))
        bands.append(.fixed(Self.powerDetailNaturalHeight))
        let drawingHeight = VitalsBandBudget.drawingHeight(
            available: availableHeight - 4,
            bands: bands
        )
        let heights = VitalsBandBudget.allocate(available: drawingHeight, bands: bands)
        var cursor = 0
        let batteryHeight = heights[cursor]
        cursor += 1
        var flowHeight: CGFloat = 0
        if showsFlow {
            cursor += 1
            flowHeight = heights[cursor]
            cursor += 1
        }
        var capacityHeight: CGFloat = 0
        if capacity != nil {
            cursor += 1
            capacityHeight = heights[cursor]
            cursor += 1
        }
        let detailHeight = heights[cursor + 1]

        return VStack(spacing: 0) {
            batteryBand(metrics: metrics, state: state, powerColor: powerColor)
                .frame(height: batteryHeight)

            if showsFlow {
                vitalsHairline
                powerFlowBand(
                    metrics: metrics,
                    powerColor: powerColor
                )
                .frame(height: flowHeight)
            }

            if let capacity {
                vitalsHairline
                capacityBand(
                    metrics: metrics,
                    maxWh: capacity.max,
                    designWh: capacity.design,
                    powerColor: powerColor
                )
                .frame(height: capacityHeight)
            }

            vitalsHairline

            vitalsDetailCells(powerDetailCells(metrics))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(height: detailHeight)
        }
        .frame(height: drawingHeight, alignment: .top)
    }

    private static let batteryBandNaturalHeight: CGFloat = 79
    private static let powerFlowNaturalHeight: CGFloat = 93
    private static let capacityBandNaturalHeight: CGFloat = 52
    private static let powerDetailNaturalHeight: CGFloat = 30
    private static let powerHairlineHeight: CGFloat = 0.6

    private func batteryBand(
        metrics: HardwareVitalsInfo,
        state: BatteryState,
        powerColor: Color
    ) -> some View {
        let scope = self.state.scope(for: .power)
        let now = renderNow ?? Date()
        let rangeLabel = batteryRangeFooter(scope: scope, now: now)
        let ribbonCells = batteryRibbonCells(scope: scope, now: now)
        let hoveredCellIndex = hoveredBatteryCell ?? batteryHoverPreview
        let footerText = VitalsColumnFormatting.batteryRibbonReadout(
            cells: ribbonCells,
            index: hoveredCellIndex ?? -1
        ) ?? batteryFooter(metrics, state: state)

        return VStack(alignment: .leading, spacing: 5) {
            vitalsBandHeader(
                title: "BATTERY",
                detail: detailWithRange(state.label, metric: .power, scope: scope),
                value: "\(metrics.batteryLevel)%",
                tint: powerColor
            )
            vitalsRail(
                ratio: Double(metrics.batteryLevel) / 100.0,
                tint: powerColor
            )
            VitalsStateRibbon(
                cells: ribbonCells,
                hoveredIndex: $hoveredBatteryCell,
                previewHoveredIndex: batteryHoverPreview
            )
                .frame(height: 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    cycleScope(.power)
                }
            VitalsStateRibbonLegend()
            HStack(spacing: 5) {
                Text(footerText)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if !rangeLabel.isEmpty {
                    Text(rangeLabel)
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .font(.system(size: 7.5, design: .monospaced))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func showsPowerFlow(_ metrics: HardwareVitalsInfo) -> Bool {
        metrics.powerSystemWatts > 0
            || metrics.powerAdapterWatts > 0
            || metrics.batteryChargeWatts != 0
    }

    private func powerFlowBand(
        metrics: HardwareVitalsInfo,
        powerColor: Color
    ) -> some View {
        let onAC = metrics.powerSource == "AC Power"
        let systemWatts: Double = {
            if metrics.powerSystemWatts > 0 { return metrics.powerSystemWatts }
            return onAC ? 0 : max(-metrics.batteryChargeWatts, 0)
        }()
        let batteryWatts = metrics.batteryChargeWatts
        let batteryBar = onAC ? max(batteryWatts, 0) : 0

        var segments: [(Double, Color)] = []
        if systemWatts > 0 {
            segments.append((systemWatts, powerColor.opacity(0.85)))
        }
        if batteryBar > 0 {
            segments.append((batteryBar, VitalsColorResolver.warningYellow.opacity(0.85)))
        }

        return VStack(alignment: .leading, spacing: 5) {
            vitalsBandHeader(
                title: "vitals.power.flowTitle".localized,
                detail: metrics.powerSource.uppercased(),
                value: systemWatts > 0 ? formatWatts(systemWatts) : "",
                tint: powerColor
            )
            if !segments.isEmpty {
                vitalsCompositionBar(segments: segments, height: 16)
            }
            HStack(alignment: .top, spacing: 10) {
                powerFlowColumn(
                    label: "vitals.power.adapter".localized,
                    value: metrics.powerAdapterWatts > 0
                        ? formatAdapterWatts(metrics.powerAdapterWatts)
                        : "—",
                    caption: "vitals.power.adapterCaption".localized,
                    tint: Color.primary.opacity(0.55)
                )
                powerFlowColumn(
                    label: "vitals.power.system".localized,
                    value: formatWatts(systemWatts),
                    caption: "vitals.power.systemCaption".localized,
                    tint: powerColor
                )
                powerFlowColumn(
                    label: "vitals.power.batteryLoad".localized,
                    value: formatSignedWatts(batteryWatts),
                    caption: "vitals.power.batteryCaption".localized,
                    tint: VitalsColorResolver.warningYellow
                )
            }
            .frame(maxHeight: .infinity, alignment: .center)
            Group {
                if onAC, systemWatts > 0 {
                    Text(String(
                        format: "vitals.power.input".localized,
                        String(format: "%.1f", systemWatts),
                        String(format: "%.2f", metrics.powerSystemVolts),
                        String(format: "%.3f", metrics.powerSystemAmps)
                    ))
                } else if !onAC {
                    Text(onBatteryFlowFooter(metrics))
                }
            }
            .font(.system(size: 7.5, design: .monospaced))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func powerFlowColumn(
        label: String,
        value: String,
        caption: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func onBatteryFlowFooter(_ metrics: HardwareVitalsInfo) -> String {
        var pieces = ["vitals.power.onBattery".localized]
        if metrics.batteryVoltageVolts > 0 {
            pieces.append(String(
                format: "vitals.power.volts".localized,
                String(format: "%.1f", metrics.batteryVoltageVolts)
            ))
            pieces.append(String(
                format: "%.2f A",
                abs(metrics.batteryChargeWatts) / metrics.batteryVoltageVolts
            ))
        }
        return pieces.joined(separator: " · ")
    }

    private func capacityWh(
        _ metrics: HardwareVitalsInfo
    ) -> (max: Double, design: Double)? {
        guard metrics.batteryVoltageVolts > 0 else { return nil }
        let maxWh = metrics.batteryMaxCapacityMAh / 1000.0 * metrics.batteryVoltageVolts
        let designWh = metrics.batteryDesignCapacityMAh / 1000.0 * metrics.batteryVoltageVolts
        guard maxWh > 0, designWh > 0 else { return nil }
        return (maxWh, designWh)
    }

    private func capacityBand(
        metrics: HardwareVitalsInfo,
        maxWh: Double,
        designWh: Double,
        powerColor: Color
    ) -> some View {
        let lostWh = max(designWh - maxWh, 0)
        var segments: [(Double, Color)] = [(maxWh, powerColor.opacity(0.85))]
        if lostWh > 0 {
            segments.append((lostWh, Color.primary.opacity(0.10)))
        }

        return VStack(alignment: .leading, spacing: 5) {
            vitalsBandHeader(
                title: "vitals.power.capacityTitle".localized,
                detail: String(
                    format: "vitals.power.design".localized,
                    formatWh(designWh)
                ),
                value: "\(formatWh(maxWh)) Wh",
                tint: powerColor
            )
            vitalsCompositionBar(segments: segments, height: 16)
            vitalsLegend([
                ("vitals.power.maxLabel".localized, "\(formatWh(maxWh)) Wh", powerColor),
                ("vitals.power.designLabel".localized, "\(formatWh(designWh)) Wh", Color.primary.opacity(0.35)),
                ("vitals.power.lostLabel".localized, "\(formatWh(lostWh)) Wh", Color.primary.opacity(0.2))
            ])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func powerDetailCells(_ metrics: HardwareVitalsInfo) -> [(String, String)] {
        [
            ("vitals.power.health".localized, "\(metrics.batteryHealthPercent)%"),
            ("vitals.power.cycles".localized, "\(metrics.batteryCycleCount)"),
            ("vitals.power.temp".localized, String(
                format: "%.0f °C",
                metrics.batteryTemperatureCelsius
            )),
            ("vitals.power.condition".localized, metrics.batteryCondition)
        ]
    }

    private func formatWatts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    /// A negotiated adapter rating is a round number, so 100 W earns no
    /// trailing zero; a rating that really carries a decimal keeps it.
    private func formatAdapterWatts(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        return tenths == tenths.rounded()
            ? String(format: "%.0f W", tenths)
            : String(format: "%.1f W", tenths)
    }

    private func formatSignedWatts(_ value: Double) -> String {
        return String(format: "%+.1f W", value)
    }

    private func formatWh(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func noBatterySheet(
        metrics: HardwareVitalsInfo,
        powerColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            vitalsBandHeader(
                title: "BATTERY",
                detail: "vitals.power.noBattery".localized,
                tint: powerColor
            )
            Text(String(
                format: "vitals.power.noBatteryDetail".localized,
                metrics.thermalStateLabel
            ))
            .font(.system(size: 7.5, design: .monospaced))
            .foregroundColor(.secondary)
            .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor
    private enum BatteryState {
        case charging
        case onBattery
        case fullyCharged

        var label: String {
            switch self {
            case .charging: "vitals.power.charging".localized
            case .onBattery: "vitals.power.onBattery".localized
            case .fullyCharged: "vitals.power.fullyCharged".localized
            }
        }
    }

    private func batteryState(_ metrics: HardwareVitalsInfo) -> BatteryState {
        if metrics.batteryLevel >= 100,
           !metrics.isCharging,
           metrics.powerSource == "AC Power" {
            return .fullyCharged
        }
        return metrics.isCharging ? .charging : .onBattery
    }

    private func batteryFooter(
        _ metrics: HardwareVitalsInfo,
        state: BatteryState
    ) -> String {
        var pieces: [String] = [metrics.powerSource.uppercased()]

        if state != .fullyCharged,
           let minutes = metrics.batteryTimeRemainingMinutes,
           minutes > 0 {
            let time = String(format: "%d:%02d", minutes / 60, minutes % 60)
            let key = state == .charging
                ? "vitals.power.timeToFull"
                : "vitals.power.timeLeft"
            pieces.append(String(format: key.localized, time))
        }

        if metrics.batteryVoltageVolts > 0 {
            pieces.append(String(
                format: "vitals.power.volts".localized,
                String(format: "%.1f", metrics.batteryVoltageVolts)
            ))
        }

        return pieces.joined(separator: " · ")
    }

    // MARK: - Tab: Processes
    @ViewBuilder
    private func processesTabContent(
        metrics: HardwareVitalsInfo,
        availableHeight: CGFloat,
        cpuColor: Color,
        ramColor: Color,
        netColor: Color,
        diskColor: Color,
        powerColor: Color
    ) -> some View {
        let metric = state.processSortMetric
        // The list is sized by the drawer, not the other way round: as many
        // rows as the height really holds, never fewer than twelve, and never
        // more processes than exist.
        let rowsThatFit = VitalsProcessListBudget.rowsThatFit(available: availableHeight)
        let rowCount = VitalsProcessListBudget.visibleRowCount(
            available: availableHeight,
            total: metrics.topProcesses.count
        )
        let visibleRows = ProcessInspectorRanking.ranked(
            metrics.topProcesses,
            by: metric,
            limit: rowCount
        )
        let needsScroll = visibleRows.count > rowsThatFit

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

            if needsScroll {
                PurahScrollableBody {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(visibleRows) { proc in
                            processRow(
                                proc,
                                metric: metric,
                                scale: scale,
                                cpuColor: cpuColor,
                                ramColor: ramColor,
                                netColor: netColor,
                                diskColor: diskColor,
                                powerColor: powerColor
                            )
                        }
                    }
                }
                .frame(height: CGFloat(rowsThatFit) * VitalsProcessListBudget.rowPitch)
            } else {
                ForEach(visibleRows) { proc in
                    processRow(
                        proc,
                        metric: metric,
                        scale: scale,
                        cpuColor: cpuColor,
                        ramColor: ramColor,
                        netColor: netColor,
                        diskColor: diskColor,
                        powerColor: powerColor
                    )
                }
            }
        }
        .onAppear {
            vitals.setProcessesTabVisible(true)
        }
        .onDisappear {
            vitals.setProcessesTabVisible(false)
        }
    }

    private func processRow(
        _ proc: ProcessInfoItem,
        metric: ProcessSortMetric,
        scale: Double,
        cpuColor: Color,
        ramColor: Color,
        netColor: Color,
        diskColor: Color,
        powerColor: Color
    ) -> some View {
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
        return HStack(spacing: 6) {
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
            vitals.startMonitoring(interval: TimeInterval(state.samplingIntervalSeconds))
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

    /// `VitalsDualTimeSeriesGraphView` still draws 0…1 points, so the focused
    /// views convert the raw bytes/second history here rather than changing
    /// the graph or normalising the stored data again.
    private func graphRatioPoints(_ points: [VitalsHistoryPoint]) -> [VitalsHistoryPoint] {
        points.map {
            VitalsHistoryPoint(
                timestamp: $0.timestamp,
                value: min($0.value / 10_485_760.0, 1.0)
            )
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
                    downPoints: graphRatioPoints(vitals.history(for: .network, scope: timeScope)),
                    upPoints: graphRatioPoints(vitals.networkUpHistory(scope: timeScope)),
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
                    downPoints: graphRatioPoints(vitals.history(for: .network, scope: timeScope)),
                    upPoints: graphRatioPoints(vitals.networkUpHistory(scope: timeScope)),
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
    public let showsMarkings: Bool
    public let showsAreaFill: Bool
    /// An explicit 0…upper view window. Throughput rows share one of these so
    /// the two rows in a band are comparable; percentage traces leave it nil
    /// and keep the data-following domain.
    public let domainUpperBound: Double?
    /// An all-zero series draws nothing at all — the row's own value is the
    /// reading, and a flat line across a quiet link is decorative ink.
    public let hidesZeroSeries: Bool
    /// Throughput plots use a shared logarithmic axis so an idle link and a
    /// busy one can share a row without the quiet one collapsing onto the
    /// baseline. Nil keeps the linear percentage behaviour.
    public let logLowerBound: Double?

    public init(
        points: [VitalsHistoryPoint],
        color: Color,
        palette: ThemePalette,
        height: CGFloat = 46.0,
        scope: VitalsTimeScope = .realTime30s,
        showsGrid: Bool = true,
        showsMarkings: Bool = true,
        showsAreaFill: Bool = true,
        domainUpperBound: Double? = nil,
        hidesZeroSeries: Bool = false,
        logLowerBound: Double? = nil
    ) {
        self.points = points
        self.color = color
        self.palette = palette
        self.height = height
        self.scope = scope
        self.showsGrid = showsGrid
        self.showsMarkings = showsMarkings
        self.showsAreaFill = showsAreaFill
        self.domainUpperBound = domainUpperBound
        self.hidesZeroSeries = hidesZeroSeries
        self.logLowerBound = logLowerBound
    }

    /// The visible points, mapped onto the window. The vertical domain follows
    /// the data instead of a fixed 0…1: a metric that moves between 58% and
    /// 62% drew a flat line before, and "no visible change" is the one thing a
    /// sparkline must never say about data that did change.
    private func visiblePoints() -> [VitalsHistoryPoint] {
        let now = Date()
        let windowSec = scope.durationSeconds
        return points.filter { now.timeIntervalSince($0.timestamp) <= windowSec }
    }

    /// A flat series is a line, never a filled block: the area only says
    /// something when there is both movement and more than a single sample.
    /// A whole two-point band of movement is enough to earn the fill; a
    /// one-point wobble (an idle GPU stepping 0↔1%) is still a line.
    private func areaFillIsMeaningful(for visible: [VitalsHistoryPoint]) -> Bool {
        // Area under a log axis has no meaning: the band would grow with the
        // distance between samples, not with the value.
        guard logLowerBound == nil else { return false }
        guard showsAreaFill, visible.count >= 2 else { return false }
        let values = visible.map(\.value)
        guard let low = values.min(), let high = values.max() else { return false }
        return high - low >= 0.02
    }

    private func computePlotPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let now = Date()
        let windowSec = scope.durationSeconds

        let recent = visiblePoints()
        let currentVal = points.last?.value ?? 0.0
        let domain: ClosedRange<CGFloat> = {
            if let upper = domainUpperBound, upper > 0 {
                return 0...CGFloat(upper)
            }
            return valueDomain(recent, fallback: currentVal)
        }()
        let span = max(domain.upperBound - domain.lowerBound, 0.0001)

        func yPosition(_ value: Double) -> CGFloat {
            if let lower = logLowerBound, lower > 0, domain.upperBound > CGFloat(lower) {
                let clamped = max(value, lower)
                let position = log10(clamped / lower) / log10(Double(domain.upperBound) / lower)
                return height * (1 - CGFloat(min(max(position, 0), 1)))
            }
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
    /// constant reading sits in the middle instead of filling the chart. The
    /// domain is a view window, not the metric's legal range, so 0% and 100%
    /// keep the same half-span around them instead of hugging an edge.
    private func valueDomain(
        _ recent: [VitalsHistoryPoint],
        fallback: Double
    ) -> ClosedRange<CGFloat> {
        let values = recent.isEmpty
            ? [CGFloat(min(max(fallback, 0.0), 1.0))]
            : recent.map { CGFloat(min(max($0.value, 0.0), 1.0)) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let minimumSpan: CGFloat = 0.05
        if high - low < minimumSpan {
            let mid = (low + high) / 2
            return (mid - minimumSpan / 2)...(mid + minimumSpan / 2)
        }
        let padding = (high - low) * 0.15
        return max(low - padding, 0)...min(high + padding, 1)
    }

    public var body: some View {
        let showMarkings = showsMarkings && height >= 34.0
        let canvasH = showMarkings ? max(height - 11.0, 10.0) : height

        VStack(spacing: showMarkings ? 2 : 0) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let visible = visiblePoints()
                let currentValue = points.last?.value ?? 0
                let drawsNothing = hidesZeroSeries
                    && abs(currentValue) < 0.000_001
                    && visible.allSatisfy { abs($0.value) < 0.000_001 }
                let plotPoints = drawsNothing ? [] : computePlotPoints(width: w, height: h)

                ZStack {
                    // A log row has no fill, so it needs an axis of its own or
                    // an idle plot reads as a blank rectangle.
                    if logLowerBound != nil {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: h - 0.5))
                            path.addLine(to: CGPoint(x: w, y: h - 0.5))
                        }
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.6)
                    }

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
                        if areaFillIsMeaningful(for: visible) {
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
                        }

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
