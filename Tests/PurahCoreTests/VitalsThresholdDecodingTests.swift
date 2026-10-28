// Tests/PurahCoreTests/VitalsThresholdDecodingTests.swift
import Testing
import Foundation
@testable import PurahCore

/// `VitalsColorThresholds` is persisted in `UserDefaults` and rendered as
/// percentages via `Int(threshold * 100)`. `Int(_:)` traps on infinity and NaN,
/// so a stored value that scales to either kills the app when the Vitals
/// settings pane opens.
///
/// `Codable`'s synthesized decoder assigned whatever the stored blob contained,
/// and a memberwise `init` cannot enforce anything a decoder bypasses. These
/// tests pin the clamping decoder that now sits in the way.
@Suite("Vitals Threshold Decoding")
struct VitalsThresholdDecodingTests {

    private func decode(_ json: String) throws -> VitalsColorThresholds {
        try JSONDecoder().decode(VitalsColorThresholds.self, from: Data(json.utf8))
    }

    /// A full, well-formed blob — the shape `save()` actually writes.
    private func fullBlob(overrides: [String: String] = [:]) -> String {
        var fields: [String: String] = [
            "cpuWarning": "0.5", "cpuDanger": "0.8",
            "gpuWarning": "0.5", "gpuDanger": "0.8",
            "ramWarning": "0.7", "ramDanger": "0.85",
            "diskWarning": "0.8", "diskDanger": "0.9",
            "batteryLow": "0.2",
            "networkWarningMB": "10", "networkDangerMB": "50"
        ]
        for (key, value) in overrides { fields[key] = value }
        let body = fields.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", ")
        return "{\(body)}"
    }

    // MARK: - The crash this exists to prevent

    /// `1e308 * 100` overflows to infinity, and `Int(infinity)` traps. This is
    /// the exact expression `VitalsPluginSettingsView` evaluates for its
    /// warning label, so without the clamp the settings pane is a crash on a
    /// blob anyone can hand-edit.
    @Test("A value that would scale to infinity is clamped, not fatal")
    func testHugeValueCannotReachIntegerConversion() throws {
        let thresholds = try decode(fullBlob(overrides: ["cpuWarning": "1e308", "cpuDanger": "1e308"]))

        #expect(thresholds.cpuWarning.isFinite)
        #expect(thresholds.cpuDanger.isFinite)
        #expect(thresholds.cpuWarning <= 1.0)
        #expect(thresholds.cpuDanger <= 1.0)

        // The assertion that matters: the pane's own expression, run for real.
        // It traps rather than returning, so reaching the expectation below is
        // the proof.
        let scaled = thresholds.cpuWarning * 100.0
        #expect(scaled.isFinite)
        #expect(Int(scaled) == 100)
    }

    @Test("Negative ratios are clamped into 0...1")
    func testNegativeRatioClamped() throws {
        let thresholds = try decode(fullBlob(overrides: ["cpuWarning": "-5", "diskWarning": "-0.4"]))
        #expect(thresholds.cpuWarning == 0.0)
        #expect(thresholds.diskWarning == 0.0)
    }

    @Test("Over-100% ratios are clamped to 1")
    func testRatioAboveOneClamped() throws {
        let thresholds = try decode(fullBlob(overrides: ["ramDanger": "4.2", "batteryLow": "17"]))
        #expect(thresholds.ramDanger == 1.0)
        #expect(thresholds.batteryLow == 1.0)
    }

    @Test("Network boundaries are clamped to the slider's megabyte span")
    func testNetworkBoundsClamped() throws {
        let high = try decode(fullBlob(overrides: ["networkWarningMB": "1e308", "networkDangerMB": "1e308"]))
        #expect(high.networkWarningMB == 200.0)
        #expect(high.networkDangerMB == 200.0)

        let low = try decode(fullBlob(overrides: ["networkWarningMB": "-40", "networkDangerMB": "0"]))
        #expect(low.networkWarningMB == 1.0)
        #expect(low.networkDangerMB == 1.0)
    }

    /// JSON cannot spell NaN or an infinity, so the only way one arrives from
    /// storage is a number so large it overflows on scale — covered above. The
    /// initialiser rejects a non-finite value too, so a future caller that
    /// computes one cannot smuggle it past the type.
    @Test("Constructing with a non-finite value substitutes the default")
    func testNonFiniteFallsBackToDefault() {
        let defaults = VitalsColorThresholds()
        let poisoned = VitalsColorThresholds(
            cpuWarning: .nan, cpuDanger: .infinity,
            gpuWarning: -.infinity, gpuDanger: .nan,
            ramWarning: .nan, ramDanger: .nan,
            diskWarning: .nan, diskDanger: .nan,
            batteryLow: .nan,
            networkWarningMB: .nan, networkDangerMB: .nan
        )
        for value in [
            poisoned.cpuWarning, poisoned.cpuDanger, poisoned.gpuWarning,
            poisoned.gpuDanger, poisoned.ramWarning, poisoned.ramDanger,
            poisoned.diskWarning, poisoned.diskDanger, poisoned.batteryLow,
            poisoned.networkWarningMB, poisoned.networkDangerMB
        ] {
            #expect(value.isFinite)
        }
        #expect(poisoned.cpuWarning == defaults.cpuWarning)
        #expect(poisoned.networkDangerMB == defaults.networkDangerMB)
    }

    // MARK: - Tolerating older and partial blobs

    @Test("A blob missing fields keeps defaults for them instead of failing")
    func testMissingFieldsUseDefaults() throws {
        // The shape an older build wrote, before the network knobs existed.
        let thresholds = try decode(#"{"cpuWarning": 0.33, "cpuDanger": 0.66}"#)
        #expect(thresholds.cpuWarning == 0.33)
        #expect(thresholds.cpuDanger == 0.66)
        // Absent keys fall back to the shipped defaults.
        let defaults = VitalsColorThresholds()
        #expect(thresholds.ramWarning == defaults.ramWarning)
        #expect(thresholds.networkDangerMB == defaults.networkDangerMB)
    }

    @Test("A malformed field falls back to its default instead of failing the decode")
    func testWrongTypeFieldUsesDefault() throws {
        let thresholds = try decode(fullBlob(overrides: ["cpuWarning": "\"not a number\""]))
        #expect(thresholds.cpuWarning == VitalsColorThresholds().cpuWarning)
        // The rest of the blob still applies.
        #expect(thresholds.cpuDanger == 0.8)
    }

    @Test("A legal blob round-trips unchanged")
    func testLegalValuesSurviveRoundTrip() throws {
        let original = VitalsColorThresholds(
            cpuWarning: 0.42, cpuDanger: 0.91,
            gpuWarning: 0.13, gpuDanger: 0.77,
            ramWarning: 0.61, ramDanger: 0.88,
            diskWarning: 0.55, diskDanger: 0.95,
            batteryLow: 0.35,
            networkWarningMB: 25, networkDangerMB: 120
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(VitalsColorThresholds.self, from: data)
        #expect(restored == original)
    }

    /// The clamp must not quietly rewrite values the sliders can legitimately
    /// produce, or the user's tuned thresholds would drift on every launch.
    @Test("Clamping leaves every slider-reachable value untouched")
    func testSliderReachableValuesUntouched() throws {
        // Endpoints of the ranges in HardwareVitalsPlugin's threshold rows and
        // the battery / network sliders.
        let thresholds = try decode(fullBlob(overrides: [
            "cpuWarning": "0.10", "cpuDanger": "0.99",
            "gpuWarning": "0.90", "gpuDanger": "0.50",
            "batteryLow": "0.05",
            "networkWarningMB": "1", "networkDangerMB": "200"
        ]))
        #expect(thresholds.cpuWarning == 0.10)
        #expect(thresholds.cpuDanger == 0.99)
        #expect(thresholds.gpuDanger == 0.50)
        #expect(thresholds.batteryLow == 0.05)
        #expect(thresholds.networkWarningMB == 1)
        #expect(thresholds.networkDangerMB == 200)
    }
}
