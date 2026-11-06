// Tests/PurahCoreTests/PodColorPickerTests.swift
import Testing
import Foundation
import PurahCore
@testable import PurahUI

@Suite("Pod Accent Colour Picker")
@MainActor
struct PodColorPickerTests {

    @Test("Every manifest accent round-trips through HSB byte-for-byte")
    func manifestAccentsRoundTrip() {
        for manifest in PurahPluginManifest.builtInCatalog {
            let hex = manifest.defaultColorHex.uppercased()
            #expect(PurahHSB(hex: hex).hex == hex, "\(manifest.id) lost its colour")
        }

        // A spread beyond the catalog: the extremes, a neutral, and values with
        // no short decimal representation.
        let spread = ["#000000", "#FFFFFF", "#808080", "#FF0000", "#00FF00", "#0000FF",
                      "#123456", "#ABCDEF", "#010203", "#FF9F0A", "#A855F7"]
        for hex in spread {
            #expect(PurahHSB(hex: hex).hex == hex)
        }
    }

    @Test("A grey keeps the hue the person chose")
    func greyKeepsHue() {
        for hex in ["#808080", "#000000", "#FFFFFF", "#010101"] {
            let reconciled = PurahHSB.reconciled(from: hex, preservingHue: 0.62)
            #expect(abs(reconciled.hue - 0.62) < 0.000_001, "\(hex) snapped the hue back")
        }

        // A colour that has a hue of its own still takes it.
        let teal = PurahHSB.reconciled(from: "#00E5A3", preservingHue: 0.62)
        #expect(abs(teal.hue - PurahHSB(hex: "#00E5A3").hue) < 0.000_001)
    }

    @Test("Preset accents are unique, capped at six, and every one parses")
    func presetsAreUniqueAndValid() {
        for defaultHex: String? in [nil, "#FF9F0A", "#00E5A3", "#123456"] {
            let presets = PurahColorPresets.standard(defaultHex: defaultHex)
            #expect(presets.count <= PurahColorPresets.maximum)
            #expect(Set(presets.map(\.hex)).count == presets.count)
            for preset in presets {
                #expect(HexColor.parse(preset.hex) != nil, "\(preset.hex) does not parse")
                #expect(!preset.name.isEmpty)
            }
        }

        // A pod whose own accent is not in the first six still has one selected
        // tile: its colour replaces the last entry rather than being dropped.
        let swapped = PurahColorPresets.standard(defaultHex: "#FF9F0A")
        #expect(swapped.count == PurahColorPresets.maximum)
        #expect(swapped.contains { $0.hex == "#FF9F0A" })
    }

    @Test("Hex commits normalise the accepted forms and reject junk")
    func hexCommitNormalises() {
        let current = "#123456"
        #expect(PurahHSB.normalizedHex("#0af", fallingBackTo: current) == "#00AAFF")
        #expect(PurahHSB.normalizedHex("00e5a3", fallingBackTo: current) == "#00E5A3")
        #expect(PurahHSB.normalizedHex("zzz", fallingBackTo: current) == current)
        #expect(PurahHSB.normalizedHex("", fallingBackTo: current) == current)
    }
}
