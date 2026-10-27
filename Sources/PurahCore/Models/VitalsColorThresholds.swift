// Sources/PurahCore/Models/VitalsColorThresholds.swift
import Foundation

/// The green / amber / red boundaries the Vitals pod colours itself against.
///
/// Every stored value is pushed through `Legality` on the way in, including
/// when it arrives from `UserDefaults`. That is what stops a hand-edited or
/// corrupted `thresholds` blob from killing the app: the settings view renders
/// these values as percentages via `Int(threshold * 100)`, and `Int(_:)` traps
/// on infinity and NaN. A stored `1e308` scales to `inf` and takes the process
/// down the moment the Vitals settings pane opens.
///
/// `Codable`'s synthesized decoder would assign whatever the blob contained —
/// a memberwise `init` cannot enforce anything the decoder bypasses, so both
/// entry points now go through the same clamp.
public struct VitalsColorThresholds: Codable, Sendable, Equatable {
    public var cpuWarning: Double = 0.50
    public var cpuDanger: Double = 0.80
    public var gpuWarning: Double = 0.50
    public var gpuDanger: Double = 0.80
    public var ramWarning: Double = 0.70
    public var ramDanger: Double = 0.85
    public var diskWarning: Double = 0.80
    public var diskDanger: Double = 0.90
    public var batteryLow: Double = 0.20
    public var networkWarningMB: Double = 10.0
    public var networkDangerMB: Double = 50.0

    public init(
        cpuWarning: Double = 0.50,
        cpuDanger: Double = 0.80,
        gpuWarning: Double = 0.50,
        gpuDanger: Double = 0.80,
        ramWarning: Double = 0.70,
        ramDanger: Double = 0.85,
        diskWarning: Double = 0.80,
        diskDanger: Double = 0.90,
        batteryLow: Double = 0.20,
        networkWarningMB: Double = 10.0,
        networkDangerMB: Double = 50.0
    ) {
        self.cpuWarning = Legality.clamp(cpuWarning, to: Legality.ratio, fallback: 0.50)
        self.cpuDanger = Legality.clamp(cpuDanger, to: Legality.ratio, fallback: 0.80)
        self.gpuWarning = Legality.clamp(gpuWarning, to: Legality.ratio, fallback: 0.50)
        self.gpuDanger = Legality.clamp(gpuDanger, to: Legality.ratio, fallback: 0.80)
        self.ramWarning = Legality.clamp(ramWarning, to: Legality.ratio, fallback: 0.70)
        self.ramDanger = Legality.clamp(ramDanger, to: Legality.ratio, fallback: 0.85)
        self.diskWarning = Legality.clamp(diskWarning, to: Legality.ratio, fallback: 0.80)
        self.diskDanger = Legality.clamp(diskDanger, to: Legality.ratio, fallback: 0.90)
        self.batteryLow = Legality.clamp(batteryLow, to: Legality.ratio, fallback: 0.20)
        self.networkWarningMB = Legality.clamp(networkWarningMB, to: Legality.megabytes, fallback: 10.0)
        self.networkDangerMB = Legality.clamp(networkDangerMB, to: Legality.megabytes, fallback: 50.0)
    }

    // MARK: - Legal ranges

    /// The values each knob is allowed to hold.
    ///
    /// The spans match the slider bounds in `HardwareVitalsPlugin` so that what
    /// the pane can display is exactly what it can produce. A metric ratio is
    /// 0…1; the network boundaries are megabytes and use the same 1…200 the
    /// sliders do.
    private enum Legality {
        /// A ratio of "used" out of 1.0.
        static let ratio: ClosedRange<Double> = 0...1
        /// Megabytes per second-ish, matching the network sliders.
        static let megabytes: ClosedRange<Double> = 1...200

        /// Clamps into `range`, replacing non-finite input with `fallback`.
        ///
        /// The finiteness test is not redundant with the clamp: `max(nan, 0)`
        /// is `nan`, so a NaN would sail through `min(max(...))` unchanged and
        /// reach `Int(_:)` to trap exactly as the value it was meant to stop.
        static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
            guard value.isFinite else { return fallback }
            return min(max(value, range.lowerBound), range.upperBound)
        }
    }

    /// Builds a legal value from whatever was persisted.
    ///
    /// A missing key falls back to its default rather than failing the whole
    /// decode: a blob written by an older build is missing whichever fields
    /// were added since, and refusing it would silently reset every knob the
    /// user had tuned.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = VitalsColorThresholds()

        func decode(_ key: CodingKeys, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            let stored = (try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil
            guard let stored else { return fallback }
            return Legality.clamp(stored, to: range, fallback: fallback)
        }

        self.init(
            cpuWarning: decode(.cpuWarning, defaults.cpuWarning, Legality.ratio),
            cpuDanger: decode(.cpuDanger, defaults.cpuDanger, Legality.ratio),
            gpuWarning: decode(.gpuWarning, defaults.gpuWarning, Legality.ratio),
            gpuDanger: decode(.gpuDanger, defaults.gpuDanger, Legality.ratio),
            ramWarning: decode(.ramWarning, defaults.ramWarning, Legality.ratio),
            ramDanger: decode(.ramDanger, defaults.ramDanger, Legality.ratio),
            diskWarning: decode(.diskWarning, defaults.diskWarning, Legality.ratio),
            diskDanger: decode(.diskDanger, defaults.diskDanger, Legality.ratio),
            batteryLow: decode(.batteryLow, defaults.batteryLow, Legality.ratio),
            networkWarningMB: decode(.networkWarningMB, defaults.networkWarningMB, Legality.megabytes),
            networkDangerMB: decode(.networkDangerMB, defaults.networkDangerMB, Legality.megabytes)
        )
    }
}
