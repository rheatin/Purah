// Tests/PurahCoreTests/AccessibilityLabelTests.swift
import Testing
import Foundation
@testable import PurahCore

/// Purah lays every settings row out by hand, so a control's accessible name is
/// never produced for free the way it is in a plain `Form`. Two specific shapes
/// silently produce an unlabelled control:
///
///   1. `Toggle("")` — the empty label is deliberate (the visible title is a
///      sibling `Text`), but nothing then names the switch for VoiceOver.
///   2. `Slider(...)` — carries no label at all by default.
///
/// Both are fine *as long as* the control is given an accessibility label
/// nearby. These tests read the source and check that every instance is
/// accounted for, which is the only way to catch it without a running app and a
/// screen reader.
@Suite("Accessibility Labelling Tests")
struct AccessibilityLabelTests {

    private static var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PurahCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/PurahUI")
    }

    /// Every `Toggle("")` / `Slider(...)` control and the label attached to it.
    ///
    /// "Attached" means an `accessibilityLabel` / `purahRowAccessibility` call in
    /// the control's own modifier chain. The chain is found by bracket depth, not
    /// by a fixed line window: a slider's `value:` binding alone can span 14
    /// lines, and the label sits after it.
    private static func unlabelledControls(openers: [String], markers: [String]) -> [String] {
        var problems: [String] = []
        guard let walker = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            return ["Sources/PurahUI not found"]
        }
        for case let file as URL in walker where file.pathExtension == "swift" {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = source.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Skip prose: this file's own doc comments quote `Toggle("")`.
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                guard openers.contains(where: { line.contains($0) }) else { continue }

                // Walk the control's argument list, then its modifier chain.
                var depth = 0
                var started = false
                var cursor = index
                while cursor < lines.count {
                    for character in lines[cursor] {
                        if character == "(" { depth += 1; started = true }
                        else if character == ")" { depth -= 1 }
                    }
                    if started && depth == 0 { break }
                    cursor += 1
                }
                var end = cursor
                var probe = cursor + 1
                while probe < lines.count {
                    let next = lines[probe].trimmingCharacters(in: .whitespaces)
                    // A comment explains the modifier below it; it does not end
                    // the chain, so step over it rather than stopping there.
                    if next.hasPrefix("//") {
                        probe += 1
                        continue
                    }
                    guard next.hasPrefix(".") else { break }
                    end = probe
                    probe += 1
                }
                let statement = lines[index...end].joined(separator: "\n")
                if !markers.contains(where: { statement.contains($0) }) {
                    problems.append("\((file.path as NSString).lastPathComponent):\(index + 1) \(trimmed)")
                }
            }
        }
        return problems
    }

    @Test("Every Toggle(\"\") is given an accessible name")
    func testEmptyTogglesAreLabelled() {
        let problems = Self.unlabelledControls(
            openers: ["Toggle(\"\",", "Toggle(\"\")"],
            markers: [".accessibilityLabel(", ".purahRowAccessibility(", ".accessibilityValue("]
        )
        #expect(problems.isEmpty, "Unlabelled toggles: \(problems)")
    }

    @Test("Every Slider is given an accessible name")
    func testSlidersAreLabelled() {
        let problems = Self.unlabelledControls(
            openers: ["Slider("],
            markers: [".accessibilityLabel(", ".purahRowAccessibility(", ".accessibilityValue("]
        )
        #expect(problems.isEmpty, "Unlabelled sliders: \(problems)")
    }

    @Test("Row label helper joins title and detail, and skips a duplicate detail")
    @MainActor
    func testRowLabelComposition() {
        #expect(PurahA11y.rowLabel("Decompose") == "Decompose")
        #expect(PurahA11y.rowLabel("Decompose", detail: "Splits the pod into chips.")
                == "Decompose. Splits the pod into chips.")
        // A subtitle identical to the title would otherwise be read twice.
        #expect(PurahA11y.rowLabel("Same", detail: "Same") == "Same")
        #expect(PurahA11y.rowLabel("Same", detail: "") == "Same")
    }
}
