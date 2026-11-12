import SwiftUI
import PurahCore

// MARK: - Domain

public enum VitalsColumnDomain: Equatable, Sendable {
    case percentage
    case log(lower: Double, upper: Double)

    /// Normalized 0…1 height for a bucket mean.
    public func height(for value: Double) -> CGFloat {
        guard value.isFinite, value > 0 else { return 0 }
        switch self {
        case .percentage:
            return CGFloat(min(max(value, 0), 1))
        case .log(let lower, let upper):
            guard lower > 0, upper > lower else { return 0 }
            let clamped = max(value, lower)
            let position = log10(clamped / lower) / log10(upper / lower)
            return CGFloat(min(max(position, 0), 1))
        }
    }
}

// MARK: - Layout

struct VitalsColumnBar: Identifiable {
    let index: Int
    let rect: CGRect
    let mean: Double

    var id: Int { index }
}

enum VitalsColumnStripLayout {
    static func bars(
        buckets: [VitalsBucket],
        domain: VitalsColumnDomain,
        size: CGSize
    ) -> [VitalsColumnBar] {
        guard !buckets.isEmpty, size.width > 0, size.height > 0 else { return [] }
        let geometry = cellGeometry(count: buckets.count, width: size.width)

        return buckets.enumerated().compactMap { index, bucket in
            guard bucket.mean > 0.000_001 else { return nil }
            let height = max(domain.height(for: bucket.mean) * size.height, 1.5)
            let x = CGFloat(index) * (geometry.cell + geometry.gap)
            return VitalsColumnBar(
                index: index,
                rect: CGRect(x: x, y: size.height - height, width: geometry.cell, height: height),
                mean: bucket.mean
            )
        }
    }

    static func index(at x: CGFloat, count: Int, width: CGFloat) -> Int? {
        guard count > 0, width > 0 else { return nil }
        let geometry = cellGeometry(count: count, width: width)
        let index = Int(floor(max(x, 0) / (geometry.cell + geometry.gap)))
        return min(max(index, 0), count - 1)
    }

    static func centerX(index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let geometry = cellGeometry(count: count, width: width)
        return CGFloat(index) * (geometry.cell + geometry.gap) + geometry.cell / 2
    }

    private static func cellGeometry(
        count: Int,
        width: CGFloat
    ) -> (cell: CGFloat, gap: CGFloat) {
        let count = CGFloat(max(count, 1))
        let stride = width / count
        // A sub-point gap can be covered entirely by the antialiased edges of
        // two neighbouring bars at 2x, which reads as a random double-width
        // column. One point of separation stays visible at every scale; the
        // cap keeps a very narrow strip from inverting into overlap.
        let gap = min(1.5, max(1.0, stride * 0.2), stride * 0.5)
        let cell = max(stride - gap, 0.5)
        return (cell, gap)
    }
}

// MARK: - Strip

struct VitalsColumnStrip: View {
    let buckets: [VitalsBucket]
    let domain: VitalsColumnDomain
    let tint: Color
    /// Optional per-bucket colour source. A supplied colour wins over the
    /// metric's alert logic; nil keeps every existing caller unchanged.
    var bucketColors: [Color]? = nil
    let metric: VitalsMetricType
    let thresholds: VitalsColorThresholds
    @Binding var hoveredIndex: Int?
    var showsHover = true
    var onCycle: (() -> Void)?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let bars = VitalsColumnStripLayout.bars(
                buckets: buckets,
                domain: domain,
                size: size
            )
            ZStack(alignment: .topLeading) {
                ForEach(bars) { bar in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(color(for: bar.mean, index: bar.index))
                        .frame(width: bar.rect.width, height: bar.rect.height)
                        .position(x: bar.rect.midX, y: bar.rect.midY)
                }

                if showsHover,
                   let index = hoveredIndex,
                   buckets.indices.contains(index) {
                    let x = VitalsColumnStripLayout.centerX(
                        index: index,
                        count: buckets.count,
                        width: size.width
                    )
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 0.6, height: size.height)
                        .position(x: x, y: size.height / 2)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 3, height: 3)
                        .position(
                            x: x,
                            y: size.height - max(
                                domain.height(for: buckets[index].mean) * size.height,
                                1.5
                            )
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onCycle?()
            }
            .onContinuousHover { phase in
                guard showsHover else { return }
                switch phase {
                case .active(let location):
                    hoveredIndex = VitalsColumnStripLayout.index(
                        at: location.x,
                        count: buckets.count,
                        width: size.width
                    )
                case .ended:
                    hoveredIndex = nil
                }
            }
        }
    }

    func color(for mean: Double, index: Int) -> Color {
        if let bucketColors, bucketColors.indices.contains(index) {
            return bucketColors[index]
        }
        switch metric {
        case .cpu:
            return alertColor(mean, warning: thresholds.cpuWarning, danger: thresholds.cpuDanger)
        case .gpu:
            return alertColor(mean, warning: thresholds.gpuWarning, danger: thresholds.gpuDanger)
        case .ram:
            return alertColor(mean, warning: thresholds.ramWarning, danger: thresholds.ramDanger)
        case .network:
            // Throughput histories are bytes per second; the threshold is
            // megabytes.
            let megabytes = mean / 1_048_576.0
            return alertColor(
                megabytes,
                warning: thresholds.networkWarningMB,
                danger: thresholds.networkDangerMB
            )
        case .power, .disk:
            return tint
        }
    }

    private func alertColor(_ value: Double, warning: Double, danger: Double) -> Color {
        if value > danger { return VitalsColorResolver.dangerRed }
        if value > warning { return VitalsColorResolver.warningYellow }
        return tint
    }
}

// MARK: - Band Formatting

@MainActor
enum VitalsColumnFormatting {
    private static let preciseFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func time(_ date: Date, scope: VitalsTimeScope) -> String {
        let precise = scope == .realTime30s || scope == .minutes5
        return (precise ? preciseFormatter : shortFormatter).string(from: date)
    }

    static func minuteTime(_ date: Date) -> String {
        shortFormatter.string(from: date)
    }

    /// The detail line while a column is hovered: the bucket's time plus the
    /// band's range, passed in so the view never parses its own detail string.
    static func hoverDetail(
        for bucket: VitalsBucket,
        scope: VitalsTimeScope,
        rangeLabel: String
    ) -> String {
        "\(time(bucket.start, scope: scope)) · \(rangeLabel)"
    }

    /// The Power tab's ribbon readout: the cell's wall-clock span followed by
    /// the localized state it recorded.
    static func batteryRibbonReadout(cell: VitalsStateCell) -> String {
        let span = "\(minuteTime(cell.start)) – \(minuteTime(cell.end))"
        guard let label = batteryStateLabel(cell.state) else { return span }
        return "\(span) · \(label)"
    }

    static func batteryRibbonReadout(
        cells: [VitalsStateCell],
        index: Int
    ) -> String? {
        guard cells.indices.contains(index) else { return nil }
        return batteryRibbonReadout(cell: cells[index])
    }

    private static func batteryStateLabel(_ state: Int?) -> String? {
        switch state {
        case 1: return "vitals.power.charging".localized
        case 2: return "vitals.power.fullyCharged".localized
        case 0: return "vitals.power.onBattery".localized
        default: return nil
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let formatters = durationFormatters()
        let formatter = seconds >= 3600 ? formatters.long : formatters.short
        return formatter.string(from: max(seconds, 0)) ?? ""
    }

    /// Building a `DateComponentsFormatter`, a calendar and a locale apiece on
    /// every redraw was measurable: the drawer asks for a range label about
    /// nine times per frame. Cache both shapes and rebuild only when the app
    /// language changes, like the `DateFormatter`s above.
    private static var cachedDurationFormatters: (
        language: String,
        short: DateComponentsFormatter,
        long: DateComponentsFormatter
    )?

    private static func durationFormatters() -> (
        short: DateComponentsFormatter,
        long: DateComponentsFormatter
    ) {
        let language = LocalizationManager.shared.resolvedLanguage.rawValue
        if let cached = cachedDurationFormatters, cached.language == language {
            return (cached.short, cached.long)
        }
        let short = makeDurationFormatter(units: [.minute, .second], language: language)
        let long = makeDurationFormatter(units: [.hour, .minute], language: language)
        cachedDurationFormatters = (language, short, long)
        return (short, long)
    }

    private static func makeDurationFormatter(
        units: NSCalendar.Unit,
        language: String
    ) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = units
        // The app has its own language switch; the formatter must follow it
        // rather than the host locale, or a Chinese UI would print "1 hr".
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: language)
        formatter.calendar = calendar
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }

    static func rangeFooter(
        scope: VitalsTimeScope,
        available: TimeInterval
    ) -> String {
        guard scope != .realTime30s else { return "" }
        let label = duration(scope.durationSeconds)
        guard available >= 1, available + 1 < scope.durationSeconds else { return label }
        let availableLabel = String(
            format: "vitals.range.available".localized,
            duration(available)
        )
        return "\(label) · \(availableLabel)"
    }
}

// MARK: - Single-metric band

struct VitalsMetricColumnBand: View {
    let metric: VitalsMetricType
    let title: String
    let detail: String
    /// The range label the detail already carries, supplied separately so the
    /// hovered detail can rebuild the same suffix without parsing `detail`.
    let rangeLabel: String
    let liveValue: String
    let tint: Color
    /// Columns carry the metric's identity hue; `tint` is the band's status
    /// colour (it may already be an alarm hue). A bucket that crosses a
    /// threshold still replaces this with the alert colour for that bucket.
    var columnTint: Color? = nil
    let buckets: [VitalsBucket]
    let domain: VitalsColumnDomain
    let scope: VitalsTimeScope
    let thresholds: VitalsColorThresholds
    let nowLabel: String
    let liveFooter: String?
    let rangeFooter: String
    let valueFormatter: (Double) -> String
    let plotMinHeight: CGFloat
    let plotMaxHeight: CGFloat?
    let extra: AnyView?
    let onCycle: () -> Void
    var collapsesWhenEmpty = false
    var showsFooter = true
    /// Render/test seam: opens the readout on one bucket without a mouse.
    var previewHoveredIndex: Int? = nil

    private struct HoverSnapshot {
        let buckets: [VitalsBucket]
        let domain: VitalsColumnDomain
    }

    @State private var hoveredIndex: Int?
    @State private var hoverSnapshot: HoverSnapshot?

    private var effectiveHoveredIndex: Int? {
        hoveredIndex ?? previewHoveredIndex
    }

    private var displayedBuckets: [VitalsBucket] {
        hoverSnapshot?.buckets ?? buckets
    }

    private var displayedDomain: VitalsColumnDomain {
        hoverSnapshot?.domain ?? domain
    }

    private var hoveredBucket: VitalsBucket? {
        guard let index = effectiveHoveredIndex,
              displayedBuckets.indices.contains(index) else { return nil }
        return displayedBuckets[index]
    }

    private var headerDetail: String {
        guard let bucket = hoveredBucket else { return detail }
        return VitalsColumnFormatting.hoverDetail(
            for: bucket,
            scope: scope,
            rangeLabel: rangeLabel
        )
    }

    private func snapshotHoverIfNeeded() {
        guard effectiveHoveredIndex != nil, hoverSnapshot == nil else { return }
        hoverSnapshot = HoverSnapshot(buckets: buckets, domain: domain)
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: collapsesWhenEmpty && displayedBuckets.isEmpty ? 0 : 5
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.primary.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if !headerDetail.isEmpty {
                    Text(headerDetail)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                Text(hoveredBucket.map { valueFormatter($0.mean) } ?? liveValue)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    // The reading is the fact; the subtitle gives way first.
                    // At the 300pt stepped width this keeps `136 / 245 GB`
                    // whole and squeezes the detail instead of the number.
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
            }

            if !displayedBuckets.isEmpty || !collapsesWhenEmpty {
                VitalsColumnStrip(
                    buckets: displayedBuckets,
                    domain: displayedDomain,
                    tint: columnTint ?? tint,
                    metric: metric,
                    thresholds: thresholds,
                    hoveredIndex: Binding(
                        get: { effectiveHoveredIndex },
                        set: { newValue in
                            if newValue != nil, hoveredIndex == nil {
                                hoverSnapshot = HoverSnapshot(buckets: buckets, domain: domain)
                            }
                            hoveredIndex = newValue
                            if newValue == nil {
                                hoverSnapshot = nil
                            }
                        }
                    ),
                    onCycle: {
                        // A range change happens under the cursor, so the
                        // frozen snapshot would hide the window it just
                        // switched to. Release the hover first.
                        hoverSnapshot = nil
                        hoveredIndex = nil
                        onCycle()
                    }
                )
                .frame(minHeight: plotMinHeight, maxHeight: plotMaxHeight ?? .infinity)
            }

            if let extra {
                extra
            }

            if showsFooter {
                footer
            }
        }
        .onAppear { snapshotHoverIfNeeded() }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Text(nowLabel)
                .foregroundColor(.secondary)
            if let liveFooter, !liveFooter.isEmpty {
                Text("·")
                    .foregroundColor(.secondary.opacity(0.5))
                Text(liveFooter)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if !rangeFooter.isEmpty {
                Text(rangeFooter)
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .font(.system(size: 7.5, design: .monospaced))
    }
}

// MARK: - Focused single-metric band (expanded chip card)

/// The three strings a focused band prints. The header carries the metric's
/// real magnitude; the footer keeps the time context and the range. A fact is
/// printed once: when the footer would repeat the header's reading, it is
/// dropped instead of being said twice.
struct VitalsFocusedBandCopy: Equatable, Sendable {
    let reading: String
    let footerLeading: String
    let footerTrailing: String

    static func make(
        metric: VitalsMetricType,
        metrics: HardwareVitalsInfo,
        nowLabel: String,
        rangeFooter: String
    ) -> VitalsFocusedBandCopy {
        let reading = reading(for: metric, metrics: metrics)
        let live = liveFact(for: metric, metrics: metrics)
        let leading = live.map { $0 == reading ? nowLabel : "\(nowLabel) · \($0)" } ?? nowLabel
        return VitalsFocusedBandCopy(
            reading: reading,
            footerLeading: leading,
            footerTrailing: rangeFooter
        )
    }

    /// The number the drawer is for: the ratio is already the chip's value and
    /// the row-fill bar, so CPU/GPU keep the percentage (there is no other
    /// magnitude) while the gauge metrics print the quantity behind it.
    static func reading(for metric: VitalsMetricType, metrics: HardwareVitalsInfo) -> String {
        switch metric {
        case .cpu:
            return "\(Int(metrics.cpuUsage * 100))%"
        case .gpu:
            return "\(Int(metrics.gpuUsage * 100))%"
        case .ram:
            return String(format: "%.1f / %.0f GB", metrics.memoryUsedGB, metrics.memoryTotalGB)
        case .power:
            return String(format: "%.1f W", systemWatts(metrics))
        case .network:
            return formatRate(metrics.networkDownSpeed + metrics.networkUpSpeed)
        case .disk:
            let used = max(metrics.diskTotalGB - metrics.diskFreeGB, 0)
            return String(format: "%.0f / %.0f GB", used, metrics.diskTotalGB)
        }
    }

    /// What the footer adds beside the time label. RAM and disk answer with
    /// the same used/total string as the header, so the equality rule above
    /// removes it; GPU's memory total is a second fact and stays.
    static func liveFact(for metric: VitalsMetricType, metrics: HardwareVitalsInfo) -> String? {
        switch metric {
        case .gpu:
            return String(format: "%.0f M", metrics.gpuMemoryInUseMB)
        case .ram:
            return String(format: "%.1f / %.0f GB", metrics.memoryUsedGB, metrics.memoryTotalGB)
        case .disk:
            let used = max(metrics.diskTotalGB - metrics.diskFreeGB, 0)
            return String(format: "%.0f / %.0f GB", used, metrics.diskTotalGB)
        case .cpu, .power, .network:
            return nil
        }
    }

    private static func systemWatts(_ metrics: HardwareVitalsInfo) -> Double {
        if metrics.powerSystemWatts > 0 { return metrics.powerSystemWatts }
        if metrics.powerSource == "AC Power" { return 0 }
        return max(-metrics.batteryChargeWatts, 0)
    }

    private static func formatRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576.0 {
            return String(format: "%.1fM/s", bytesPerSecond / 1_048_576.0)
        }
        if bytesPerSecond >= 1024.0 {
            return String(format: "%.0fK/s", bytesPerSecond / 1024.0)
        }
        return String(format: "%.0fB/s", bytesPerSecond)
    }
}

/// The composite drawer's band, focused on one metric. The stepped chip card
/// used to own a second chart implementation; this keeps one presentation so a
/// chip and the drawer tell the same story.
struct VitalsFocusedColumnBand: View {
    let metric: VitalsMetricType
    let availableHeight: CGFloat
    let state: VitalsPluginState

    private var vitals: HardwareVitalsService { HardwareVitalsService.shared }
    private var metrics: HardwareVitalsInfo { vitals.metrics }
    private var thresholds: VitalsColorThresholds { state.thresholds }
    private var scope: VitalsTimeScope { state.scope(for: metric) }

    var body: some View {
        let copy = VitalsFocusedBandCopy.make(
            metric: metric,
            metrics: metrics,
            nowLabel: "vitals.range.now".localized,
            rangeFooter: VitalsColumnFormatting.rangeFooter(
                scope: scope,
                available: vitals.availableSpan(for: metric)
            )
        )
        VitalsMetricColumnBand(
            metric: metric,
            title: title,
            detail: detailWithRange,
            rangeLabel: VitalsColumnFormatting.duration(scope.durationSeconds),
            liveValue: copy.reading,
            tint: VitalsColorResolver.color(
                for: metric,
                vitals: metrics,
                thresholds: thresholds
            ),
            columnTint: VitalsColorResolver.identityColor(for: metric),
            buckets: buckets,
            domain: domain,
            scope: scope,
            thresholds: thresholds,
            nowLabel: copy.footerLeading,
            liveFooter: nil,
            rangeFooter: copy.footerTrailing,
            valueFormatter: valueFormatter,
            plotMinHeight: max(min(24, availableHeight - 38), 12),
            plotMaxHeight: nil,
            extra: nil,
            onCycle: { cycleScope() },
            collapsesWhenEmpty: true
        )
    }

    private var title: String {
        switch metric {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ram: return "RAM"
        case .power: return "POWER"
        case .network: return "NETWORK"
        case .disk: return "DISK"
        }
    }

    private var detail: String {
        switch metric {
        case .cpu:
            let cores = metrics.performanceCoreCount + metrics.efficiencyCoreCount
            guard cores > 0 else { return metrics.chipModelName }
            return String(
                format: "vitals.compute.cpuDetail".localized,
                metrics.chipModelName,
                metrics.performanceCoreCount,
                metrics.efficiencyCoreCount
            )
        case .gpu:
            return metrics.gpuCoreCount > 0
                ? String(format: "vitals.compute.gpuDetail".localized, metrics.chipModelName, metrics.gpuCoreCount)
                : metrics.chipModelName
        case .ram:
            return String(format: "vitals.compute.ramDetail".localized, compactGB(metrics.memoryTotalGB))
        case .power:
            return metrics.powerSource
        case .network:
            return "↓ \(rate(metrics.networkDownSpeed)) · ↑ \(rate(metrics.networkUpSpeed))"
        case .disk:
            return String(format: "vitals.disk.bootDisk".localized, compactGB(metrics.diskTotalGB))
        }
    }

    private var detailWithRange: String {
        let range = VitalsColumnFormatting.duration(scope.durationSeconds)
        return detail.isEmpty ? range : "\(detail) · \(range)"
    }

    private var buckets: [VitalsBucket] {
        vitals.columns(for: metric, scope: scope)
    }

    private var domain: VitalsColumnDomain {
        switch metric {
        case .network:
            let maximum = buckets.map(\.mean).max() ?? 0
            return .log(lower: 1_024, upper: VitalsThroughputDomain.ceiling(for: maximum))
        case .cpu, .gpu, .ram, .power, .disk:
            return .percentage
        }
    }

    private var valueFormatter: (Double) -> String {
        switch metric {
        case .network:
            return { rate($0) }
        case .cpu, .gpu, .ram, .power, .disk:
            return { "\(Int(($0 * 100).rounded()))%" }
        }
    }

    private func compactGB(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        return tenths == tenths.rounded()
            ? String(format: "%.0f", tenths)
            : String(format: "%.1f", tenths)
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576.0 {
            return String(format: "%.1fM/s", bytesPerSecond / 1_048_576.0)
        }
        if bytesPerSecond >= 1024.0 {
            return String(format: "%.0fK/s", bytesPerSecond / 1024.0)
        }
        return String(format: "%.0fB/s", bytesPerSecond)
    }

    private func cycleScope() {
        let all = VitalsTimeScope.allCases
        guard let index = all.firstIndex(of: scope) else { return }
        state.setScope(all[(index + 1) % all.count], for: metric)
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
    }
}

// MARK: - Two-row throughput band

struct VitalsThroughputBandRow {
    let glyph: String
    let liveValue: String
    let tint: Color
    let buckets: [VitalsBucket]
    let total: String
}

struct VitalsThroughputBand: View {
    let metric: VitalsMetricType
    let title: String
    let detail: String
    let headerValue: String
    let tint: Color
    let rows: [VitalsThroughputBandRow]
    let domain: VitalsColumnDomain
    let scope: VitalsTimeScope
    let thresholds: VitalsColorThresholds
    let nowLabel: String
    let rangeFooter: String
    let valueFormatter: (Double) -> String
    let extra: AnyView?
    let onCycle: () -> Void
    /// Render/test seam: opens the readout on one row's bucket without a mouse.
    var previewHoveredRow: Int? = nil
    var previewHoveredIndex: Int? = nil

    private struct Hover: Equatable {
        let row: Int
        let index: Int
    }

    private struct HoverSnapshot {
        let rows: [VitalsThroughputBandRow]
        let domain: VitalsColumnDomain
    }

    @State private var hovered: Hover?
    @State private var hoverSnapshot: HoverSnapshot?

    private var effectiveHover: Hover? {
        hovered ?? previewHoveredRow.flatMap { row in
            previewHoveredIndex.map { Hover(row: row, index: $0) }
        }
    }

    private var displayedRows: [VitalsThroughputBandRow] {
        hoverSnapshot?.rows ?? rows
    }

    private var displayedDomain: VitalsColumnDomain {
        hoverSnapshot?.domain ?? domain
    }

    private var hoveredRow: VitalsThroughputBandRow? {
        guard let effectiveHover,
              displayedRows.indices.contains(effectiveHover.row) else { return nil }
        return displayedRows[effectiveHover.row]
    }

    private var hoveredBucket: VitalsBucket? {
        guard let effectiveHover,
              displayedRows.indices.contains(effectiveHover.row),
              displayedRows[effectiveHover.row].buckets.indices.contains(effectiveHover.index) else {
            return nil
        }
        return displayedRows[effectiveHover.row].buckets[effectiveHover.index]
    }

    private func snapshotHoverIfNeeded() {
        guard effectiveHover != nil, hoverSnapshot == nil else { return }
        hoverSnapshot = HoverSnapshot(rows: rows, domain: domain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
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
                Text(headerText)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            ForEach(Array(displayedRows.enumerated()), id: \.offset) { index, row in
                ZStack(alignment: .center) {
                    VitalsColumnStrip(
                        buckets: row.buckets,
                        domain: displayedDomain,
                        tint: row.tint,
                        metric: metric,
                        thresholds: thresholds,
                        hoveredIndex: Binding(
                            get: { effectiveHover?.row == index ? effectiveHover?.index : nil },
                            set: { newValue in
                                if let newValue {
                                    if hovered == nil {
                                        hoverSnapshot = HoverSnapshot(rows: rows, domain: domain)
                                    }
                                    hovered = Hover(row: index, index: newValue)
                                } else if hovered?.row == index {
                                    hovered = nil
                                    hoverSnapshot = nil
                                }
                            }
                        ),
                        onCycle: {
                            // Same as the single-metric band: the click is
                            // under the cursor, so the snapshot has to go.
                            hoverSnapshot = nil
                            hovered = nil
                            onCycle()
                        }
                    )
                    .padding(.leading, 72)
                    .padding(.trailing, 68)

                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Text(row.glyph)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(row.tint)
                            Text(leadingValue(row: row, index: index))
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.primary.opacity(0.88))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(width: 66, alignment: .leading)

                        Spacer(minLength: 0)

                        Text(row.total)
                            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 62, alignment: .trailing)
                            .lineLimit(1)
                    }
                }
                .frame(maxHeight: .infinity)
                .frame(minHeight: 20)
                .padding(.top, 6)
                .padding(.bottom, 4)
            }

            if let extra {
                extra
            }

            footer
        }
        .onAppear { snapshotHoverIfNeeded() }
    }

    private var headerText: String {
        guard let bucket = hoveredBucket, let row = hoveredRow else { return headerValue }
        return "\(row.glyph) \(valueFormatter(bucket.mean))"
    }

    private func leadingValue(row: VitalsThroughputBandRow, index: Int) -> String {
        guard let effectiveHover,
              effectiveHover.row == index,
              row.buckets.indices.contains(effectiveHover.index) else {
            return row.liveValue
        }
        return valueFormatter(row.buckets[effectiveHover.index].mean)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Text(hoveredBucket.map { VitalsColumnFormatting.time($0.start, scope: scope) } ?? nowLabel)
                .foregroundColor(.secondary)
            Spacer(minLength: 2)
            if !rangeFooter.isEmpty {
                Text(rangeFooter)
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .font(.system(size: 7.5, design: .monospaced))
    }
}

// MARK: - Battery state ribbon

struct VitalsStateRibbon: View {
    let cells: [VitalsStateCell]
    var hoveredIndex: Binding<Int?>? = nil
    /// Render/test seam: highlights one cell without a pointer.
    var previewHoveredIndex: Int? = nil

    private var effectiveHoveredIndex: Int? {
        hoveredIndex?.wrappedValue ?? previewHoveredIndex
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                HStack(spacing: 2) {
                    ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                        Rectangle()
                            .fill(Self.color(for: cell.state))
                            .overlay {
                                if index == effectiveHoveredIndex {
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .stroke(Color.primary.opacity(0.85), lineWidth: 1)
                                }
                            }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard let hoveredIndex, !cells.isEmpty else { return }
                switch phase {
                case .active(let location):
                    let width = max(geo.size.width, 1)
                    let index = min(
                        max(Int(location.x / (width / CGFloat(cells.count))), 0),
                        cells.count - 1
                    )
                    hoveredIndex.wrappedValue = index
                case .ended:
                    hoveredIndex.wrappedValue = nil
                }
            }
        }
    }

    static func color(for state: Int?) -> Color {
        switch state {
        case 1: return VitalsColorResolver.powerIdentity
        case 2: return VitalsColorResolver.batteryFullIdentity
        case 0: return Color.primary.opacity(0.28)
        default: return .clear
        }
    }
}

struct VitalsStateRibbonLegend: View {
    var body: some View {
        HStack(spacing: 9) {
            item("vitals.power.charging".localized, state: 1)
            item("vitals.power.onBattery".localized, state: 0)
            item("vitals.power.fullyCharged".localized, state: 2)
            Spacer(minLength: 0)
        }
    }

    private func item(_ label: String, state: Int) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1)
                .fill(VitalsStateRibbon.color(for: state))
                .frame(width: 7, height: 4)
            Text(label)
                .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
