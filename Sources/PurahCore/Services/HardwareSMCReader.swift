import Foundation
import PurahSMC

/// Best-effort thermal sensors through AppleSMC.
///
/// Intel Macs expose `TC0P` / `TG0P`; Apple Silicon exposes the `Tp*` and
/// `Tg*` sensor families instead. The reader takes the hottest plausible
/// sensor from each family and ignores anything outside a sane range, so an
/// absent key degrades to `nil` rather than a fabricated reading.
enum HardwareSMCReader {
    private static let cpuKeys = [
        "Tp01", "Tp05", "Tp09", "Tp0A", "Tp0g", "Tp0o",
        "TPDX", "TPD0", "TC0P", "TC0D"
    ]
    private static let gpuKeys = [
        "Tg0e", "Tg0f", "Tg0m", "Tg0n", "Tg0q", "Tg0r",
        "TG0P", "TG0D"
    ]
    private static let fanKeys = ["F0Ac", "F1Ac", "F0Mn"]

    static func thermalReadings() -> (cpu: Double?, gpu: Double?, fanRPM: Int?) {
        let cpu = hottest(cpuKeys)
        let gpu = hottest(gpuKeys)
        let fan = fanKeys.compactMap(read).first
        return (
            cpu,
            gpu,
            fan.map { Int($0.rounded()) }
        )
    }

    private static func hottest(_ keys: [String]) -> Double? {
        let readings = keys.compactMap(read).filter { $0 > 1 && $0 < 150 }
        return readings.max()
    }

    private static func read(_ key: String) -> Double? {
        var value = 0.0
        let success = key.withCString { pointer in
            purah_smc_read_number(pointer, &value)
        }
        guard success == 1, value.isFinite else { return nil }
        return value
    }
}
