import Foundation

/// One column in a Vitals strip: a bucket's start/end and its mean.
public struct VitalsBucket: Identifiable, Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let mean: Double

    public var id: Date { start }

    public init(start: Date, end: Date, mean: Double) {
        self.start = start
        self.end = end
        self.mean = mean
    }
}

/// The in-progress aggregation for one tier, persisted so a relaunch does not
/// discard the newest slot. `sum` is the running total and `count` its samples.
public struct VitalsPendingBucket: Codable, Sendable, Equatable {
    public var start: Date
    public var sum: Double
    public var count: Int

    public init(start: Date, sum: Double, count: Int) {
        self.start = start
        self.sum = sum
        self.count = count
    }
}

/// The three persisted retention tiers for one telemetry series.
///
/// The fast tier holds raw samples, the minute tier holds one mean per minute
/// and the coarse tier one mean per twelve minutes. Every bucket is a mean,
/// never a maximum: the strip answers "what was it on average".
public struct VitalsTieredHistory: Codable, Sendable {
    public var fast: [VitalsHistoryPoint]
    public var minute: [VitalsHistoryPoint]
    public var coarse: [VitalsHistoryPoint]

    public init(
        fast: [VitalsHistoryPoint] = [],
        minute: [VitalsHistoryPoint] = [],
        coarse: [VitalsHistoryPoint] = []
    ) {
        self.fast = fast
        self.minute = minute
        self.coarse = coarse
    }
}

/// Runtime aggregation for one series.
///
/// A minute bucket is completed by the first fast sample at or after the next
/// minute boundary, and a coarse bucket by the first minute bucket at or after
/// the next twelve-minute boundary. The boundary sample that completes a
/// bucket opens the next one, so it is never counted twice.
public struct VitalsHistoryBuffer: Sendable {
    public static let fastCoverage: TimeInterval = 300
    public static let fastCapacity = 300
    public static let minuteCapacity = 60
    public static let coarseCapacity = 60

    public static let fastInterval: TimeInterval = 1
    public static let minuteInterval: TimeInterval = 60
    public static let coarseInterval: TimeInterval = 720

    public private(set) var tiers: VitalsTieredHistory
    public private(set) var maximumFastSamples: Int

    private struct Pending {
        var start: Date
        var sum: Double
        var count: Int

        var mean: Double { count > 0 ? sum / Double(count) : 0 }
    }

    private var pendingMinute: Pending?
    private var pendingCoarse: Pending?

    public init(
        tiers: VitalsTieredHistory = .init(),
        maximumFastSamples: Int = Self.fastCapacity,
        pendingMinute: VitalsPendingBucket? = nil,
        pendingCoarse: VitalsPendingBucket? = nil
    ) {
        self.tiers = tiers
        self.maximumFastSamples = max(maximumFastSamples, 1)
        if self.tiers.fast.count > self.maximumFastSamples {
            self.tiers.fast.removeFirst(self.tiers.fast.count - self.maximumFastSamples)
        }
        // A pending bucket older than the newest completed one would be
        // completed out of order and corrupt `source()`'s coverage check.
        if let pendingMinute,
           pendingMinute.count > 0,
           pendingMinute.start >= (self.tiers.minute.last?.timestamp ?? .distantPast) {
            self.pendingMinute = Pending(
                start: pendingMinute.start,
                sum: pendingMinute.sum,
                count: pendingMinute.count
            )
        }
        if let pendingCoarse,
           pendingCoarse.count > 0,
           pendingCoarse.start >= (self.tiers.coarse.last?.timestamp ?? .distantPast) {
            self.pendingCoarse = Pending(
                start: pendingCoarse.start,
                sum: pendingCoarse.sum,
                count: pendingCoarse.count
            )
        }
    }

    public var pendingMinuteBucket: VitalsPendingBucket? {
        pendingMinute.map { VitalsPendingBucket(start: $0.start, sum: $0.sum, count: $0.count) }
    }

    public var pendingCoarseBucket: VitalsPendingBucket? {
        pendingCoarse.map { VitalsPendingBucket(start: $0.start, sum: $0.sum, count: $0.count) }
    }

    public static func fastCapacity(forInterval interval: TimeInterval) -> Int {
        guard interval.isFinite, interval > 0 else { return fastCapacity }
        return max(Int((fastCoverage / interval).rounded()), 1)
    }

    public mutating func setFastCapacity(_ capacity: Int, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.fastCoverage)
        tiers.fast.removeAll { $0.timestamp < cutoff }
        maximumFastSamples = max(capacity, 1)
        if tiers.fast.count > maximumFastSamples {
            tiers.fast.removeFirst(tiers.fast.count - maximumFastSamples)
        }
    }

    /// The newest instant the buffer can describe. The fast tier is the only
    /// one that sees every sample, so it is the honest "up to now" edge; a
    /// minute/coarse bucket starts at its bucket boundary.
    public var newestTimestamp: Date? {
        tiers.fast.last?.timestamp ?? tiers.minute.last?.timestamp ?? tiers.coarse.last?.timestamp
    }

    public var oldestTimestamp: Date? {
        [tiers.fast.first, tiers.minute.first, tiers.coarse.first]
            .compactMap { $0?.timestamp }
            .min()
    }

    public mutating func append(_ point: VitalsHistoryPoint) {
        Self.appendCapped(&tiers.fast, point, capacity: maximumFastSamples)

        let minuteStart = Self.bucketStart(point.timestamp, interval: Self.minuteInterval)
        if let pending = pendingMinute, minuteStart > pending.start {
            let mean = pending.mean
            Self.appendCapped(
                &tiers.minute,
                VitalsHistoryPoint(timestamp: pending.start, value: mean),
                capacity: Self.minuteCapacity
            )
            rollCoarse(at: pending.start, mean: mean)
            pendingMinute = Pending(start: minuteStart, sum: point.value, count: 1)
        } else if pendingMinute != nil {
            pendingMinute?.sum += point.value
            pendingMinute?.count += 1
        } else {
            pendingMinute = Pending(start: minuteStart, sum: point.value, count: 1)
        }
    }

    private mutating func rollCoarse(at minuteStart: Date, mean: Double) {
        let coarseStart = Self.bucketStart(minuteStart, interval: Self.coarseInterval)
        if let pending = pendingCoarse, coarseStart > pending.start {
            Self.appendCapped(
                &tiers.coarse,
                VitalsHistoryPoint(timestamp: pending.start, value: pending.mean),
                capacity: Self.coarseCapacity
            )
            pendingCoarse = Pending(start: coarseStart, sum: mean, count: 1)
        } else if pendingCoarse != nil {
            pendingCoarse?.sum += mean
            pendingCoarse?.count += 1
        } else {
            pendingCoarse = Pending(start: coarseStart, sum: mean, count: 1)
        }
    }

    /// The source tier and native resolution used for a scope. A range the
    /// fast tier can cover is always drawn from raw samples; only once the
    /// span outgrows it do the aggregates take over.
    public static func source(
        tiers: VitalsTieredHistory,
        scope: VitalsTimeScope,
        now: Date = Date(),
        fastResolution: TimeInterval = fastInterval
    ) -> (points: [VitalsHistoryPoint], resolution: TimeInterval) {
        let coverage: (VitalsHistoryPoint?) -> TimeInterval = { point in
            guard let point else { return 0 }
            return max(now.timeIntervalSince(point.timestamp), 0)
        }
        let oldest = [
            tiers.fast.first?.timestamp,
            tiers.minute.first?.timestamp,
            tiers.coarse.first?.timestamp
        ].compactMap { $0 }.min()
        guard let oldest else { return ([], fastResolution) }
        let span = min(scope.durationSeconds, max(now.timeIntervalSince(oldest), 0))

        if coverage(tiers.fast.first) + 1 >= span, !tiers.fast.isEmpty {
            return (tiers.fast, fastResolution)
        }
        if coverage(tiers.minute.first) + 1 >= span, !tiers.minute.isEmpty {
            return (tiers.minute, minuteInterval)
        }
        if coverage(tiers.coarse.first) + 1 >= span, !tiers.coarse.isEmpty {
            return (tiers.coarse, coarseInterval)
        }
        // The span is longer than any complete tier: use the widest one that
        // exists rather than showing nothing.
        if !tiers.coarse.isEmpty { return (tiers.coarse, coarseInterval) }
        if !tiers.minute.isEmpty { return (tiers.minute, minuteInterval) }
        return (tiers.fast, fastResolution)
    }

    /// Builds the strip's buckets. The grid always ends at `now`; its span is
    /// `min(scope, available)` so an empty history grows wider buckets until
    /// the range is reached and then locks.
    public static func columns(
        tiers: VitalsTieredHistory,
        scope: VitalsTimeScope,
        now: Date = Date(),
        fastResolution: TimeInterval = fastInterval,
        maximumColumns: Int = 60
    ) -> [VitalsBucket] {
        let oldest = [
            tiers.fast.first?.timestamp,
            tiers.minute.first?.timestamp,
            tiers.coarse.first?.timestamp
        ].compactMap { $0 }.min()
        guard let oldest else { return [] }
        let available = max(now.timeIntervalSince(oldest), 0)
        let span = min(scope.durationSeconds, available)
        guard span > 0 else { return [] }

        let source = source(
            tiers: tiers,
            scope: scope,
            now: now,
            fastResolution: fastResolution
        )
        // A slot is one measurement period, never a slice narrower than the
        // source can fill. The cadence comes from the points themselves
        // because a series can sample slower than the configured interval
        // (GPU), and a strip that implies sixty samples where six exist is a
        // picket fence rather than a chart.
        let cadence = sampleCadence(source.points, fallback: source.resolution)
        let limit = max(maximumColumns, 1)
        // A slot is one sample period; the window is padded back to whole
        // periods so the newest slot always ends at `now`.
        let width = max(cadence, span / Double(limit))
        let count = max(min(Int((span / width).rounded(.up)), limit), 1)
        let gridStart = now.addingTimeInterval(-Double(count) * width)
        let grid = (0..<count).map { index in
            let start = gridStart.addingTimeInterval(Double(index) * width)
            let end = min(start.addingTimeInterval(width), now)
            return VitalsBucket(start: start, end: end, mean: 0)
        }
        let means = means(for: grid, points: source.points)
        return grid.enumerated().map { index, bucket in
            VitalsBucket(start: bucket.start, end: bucket.end, mean: means[index])
        }
    }

    /// The mean of `points` inside each bucket's time slot; a slot with no
    /// samples reads as 0.
    ///
    /// This is for a series that is sampled by someone else and has to land on
    /// a grid it did not build — the temperatures, which only exist while the
    /// drawer is open, borrow the chart's own buckets so their columns are the
    /// same width as the plot above them. Building a second grid for them
    /// would move the bars whenever the two series had different history.
    public static func means(
        for grid: [VitalsBucket],
        points: [VitalsHistoryPoint]
    ) -> [Double] {
        guard let first = grid.first else { return [] }
        let width: Double = grid.count > 1
            ? grid[1].start.timeIntervalSince(first.start)
            : first.end.timeIntervalSince(first.start)
        let span = width * Double(grid.count)
        guard span > 0 else { return [Double](repeating: 0, count: grid.count) }

        var sums = [Double](repeating: 0, count: grid.count)
        var counts = [Int](repeating: 0, count: grid.count)
        for point in points {
            let offset = point.timestamp.timeIntervalSince(first.start)
            guard offset >= -0.5, offset <= span + 0.5 else { continue }
            let index = min(max(Int(offset / width), 0), grid.count - 1)
            sums[index] += point.value
            counts[index] += 1
        }
        var rawMeans = grid.indices.map { index in
            counts[index] > 0 ? sums[index] / Double(counts[index]) : 0
        }

        // A timer that ticks at 1.02s against 1.00s buckets slips across a
        // bucket edge once per window: the sample before lands just left of
        // `start` and the next lands just right of `end`, leaving `counts == 0`
        // even though no sample period was missed. Bridge only when two
        // consecutive samples straddle the slot within normal single-period
        // jitter (<= 1.65x slot width), or when the newest slot is queried
        // just before the next tick fires (<= 1.35x slot width). Genuine
        // multi-period gaps (>= 1.7x slot width) stay zero.
        for index in grid.indices where counts[index] == 0 {
            let bucket = grid[index]
            let prev = points.last { $0.timestamp < bucket.start }
            let next = points.first { $0.timestamp >= bucket.end }
            if let prev, let next,
               next.timestamp.timeIntervalSince(prev.timestamp) <= width * 1.65 {
                rawMeans[index] = (prev.value + next.value) / 2
            } else if index == grid.count - 1, next == nil, let prev,
                      bucket.end.timeIntervalSince(prev.timestamp) <= width * 1.35 {
                rawMeans[index] = prev.value
            }
        }
        return rawMeans
    }

    /// Median spacing between consecutive source samples. A single point (or
    /// duplicate timestamps) cannot state a cadence, so the tier's declared
    /// resolution is used instead. When the measured median is within normal
    /// runloop timer jitter (<= 25%) of the declared resolution, keep the
    /// declared resolution so a 1.03s timer still builds 30 one-second slots
    /// over a 30-second window instead of 29 fractional slots.
    private static func sampleCadence(
        _ points: [VitalsHistoryPoint],
        fallback: TimeInterval
    ) -> TimeInterval {
        let fallback = max(fallback, 0.001)
        guard points.count >= 2 else { return fallback }
        let spacings = zip(points, points.dropFirst())
            .map { $1.timestamp.timeIntervalSince($0.timestamp) }
            .filter { $0 > 0 }
            .sorted()
        guard !spacings.isEmpty else { return fallback }
        let middle = spacings.count / 2
        let median = spacings.count.isMultiple(of: 2)
            ? (spacings[middle - 1] + spacings[middle]) / 2
            : spacings[middle]
        if abs(median - fallback) <= fallback * 0.25 {
            return fallback
        }
        return max(median, 0.001)
    }

    /// Convenience for render/test seams that only have raw points.
    public static func columns(
        fast: [VitalsHistoryPoint],
        scope: VitalsTimeScope,
        now: Date = Date(),
        fastResolution: TimeInterval = fastInterval,
        maximumColumns: Int = 60
    ) -> [VitalsBucket] {
        columns(
            tiers: VitalsTieredHistory(fast: fast),
            scope: scope,
            now: now,
            fastResolution: fastResolution,
            maximumColumns: maximumColumns
        )
    }

    private static func bucketStart(_ date: Date, interval: TimeInterval) -> Date {
        let seconds = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: floor(seconds / interval) * interval)
    }

    private static func appendCapped(
        _ array: inout [VitalsHistoryPoint],
        _ point: VitalsHistoryPoint,
        capacity: Int
    ) {
        array.append(point)
        if array.count > capacity {
            array.removeFirst(array.count - capacity)
        }
    }
}

// MARK: - Battery State Ribbon

/// A completed ten-minute battery-state sample (0 on battery, 1 charging,
/// 2 full). The ribbon uses these as fixed-width cells.
public struct VitalsStateCell: Identifiable, Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let state: Int?

    public var id: Date { start }

    public init(start: Date, end: Date, state: Int?) {
        self.start = start
        self.end = end
        self.state = state
    }
}

public struct VitalsStateHistory: Codable, Sendable {
    public static let interval: TimeInterval = 600
    public static let capacity = 72

    public var points: [VitalsHistoryPoint]

    public init(points: [VitalsHistoryPoint] = []) {
        self.points = points
    }

    public mutating func appendCompleted(start: Date, state: Int) {
        points.append(VitalsHistoryPoint(timestamp: start, value: Double(state)))
        if points.count > Self.capacity {
            points.removeFirst(points.count - Self.capacity)
        }
    }

    /// Joins the state history onto a strip's buckets. A bucket takes the
    /// state in force at its start: the last point at or before that instant.
    /// A bucket older than the whole state history has no state (`nil`) rather
    /// than borrowing the first recorded one.
    public static func stateValues(
        for buckets: [VitalsBucket],
        points: [VitalsHistoryPoint]
    ) -> [Int?] {
        let ordered = points.sorted { $0.timestamp < $1.timestamp }
        return buckets.map { bucket in
            guard let match = ordered.last(where: { $0.timestamp <= bucket.start }),
                  match.value.isFinite else {
                return nil
            }
            return Int(match.value.rounded())
        }
    }

    /// Fixed-width ten-minute cells ending at the current bucket. Cells with
    /// no recorded state are left empty (the ribbon draws nothing there).
    public func cells(
        range: TimeInterval,
        now: Date,
        currentState: Int?
    ) -> [VitalsStateCell] {
        let interval = Self.interval
        let count = max(Int((range / interval).rounded(.up)), 1)
        let currentStart = Date(
            timeIntervalSince1970: floor(now.timeIntervalSince1970 / interval) * interval
        )
        let gridStart = currentStart.addingTimeInterval(-Double(count - 1) * interval)

        return (0..<count).map { index in
            let start = gridStart.addingTimeInterval(Double(index) * interval)
            let isCurrent = abs(start.timeIntervalSince(currentStart)) < 0.5
            let recorded = points.first { abs($0.timestamp.timeIntervalSince(start)) < 0.5 }
            let state = isCurrent ? (currentState ?? recorded.map { Int($0.value) }) : recorded.map { Int($0.value) }
            return VitalsStateCell(start: start, end: start.addingTimeInterval(interval), state: state)
        }
    }
}
