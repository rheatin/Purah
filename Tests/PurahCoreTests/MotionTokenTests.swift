// Tests/PurahCoreTests/MotionTokenTests.swift
import Testing
import SwiftUI
import Foundation
@testable import PurahUI

/// The named springs exist so a transition says *what kind* of motion it is.
/// Adopting one must never change how anything feels, so the values are pinned
/// here against the literals they replaced.
@MainActor
@Suite("Motion Tokens")
struct MotionTokenTests {

    private func spring(_ animation: Animation) -> (response: Double, damping: Double)? {
        // `Animation` is opaque; compare by its description, which carries both
        // parameters in a stable form on macOS.
        let text = String(describing: animation)
        guard let response = value(in: text, after: "response: "),
              let damping = value(in: text, after: "dampingFraction: ") else {
            return nil
        }
        return (response, damping)
    }

    private func value(in text: String, after label: String) -> Double? {
        guard let range = text.range(of: label) else { return nil }
        let rest = text[range.upperBound...]
        let digits = rest.prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    @Test("Drawer entrance and exit match the documented curves")
    func testDrawerPair() throws {
        let entrance = try #require(spring(PurahMotionPolicy.drawerEntrance))
        #expect(entrance.response == 0.30)
        #expect(entrance.damping == 0.80)

        let exit = try #require(spring(PurahMotionPolicy.drawerExit))
        #expect(exit.response == 0.20)
        #expect(exit.damping == 0.92)
    }

    @Test("Every named spring keeps the value it replaced")
    func testNamedValuesArePinned() throws {
        let expected: [(String, Animation, Double, Double)] = [
            ("surface", PurahMotionPolicy.surface, 0.28, 0.82),
            ("surfaceSoft", PurahMotionPolicy.surfaceSoft, 0.25, 0.82),
            ("micro", PurahMotionPolicy.micro, 0.22, 0.82),
            ("microLight", PurahMotionPolicy.microLight, 0.24, 0.85),
            ("pin", PurahMotionPolicy.pin, 0.28, 0.65),
            ("buttonPop", PurahMotionPolicy.buttonPop, 0.26, 0.55),
            ("confirm", PurahMotionPolicy.confirm, 0.20, 0.80),
            ("press", PurahMotionPolicy.press, 0.16, 0.65),
            ("pageFlip", PurahMotionPolicy.pageFlip, 0.32, 0.82),
            ("hover", PurahMotionPolicy.hover, 0.25, 0.70),
            ("hoverSoft", PurahMotionPolicy.hoverSoft, 0.28, 0.70),
            ("shelfRow", PurahMotionPolicy.shelfRow, 0.24, 0.78),
            ("chipLift", PurahMotionPolicy.chipLift, 0.32, 0.75),
            ("railReflow", PurahMotionPolicy.railReflow, 0.30, 0.80)
        ]

        for (name, animation, response, damping) in expected {
            let parsed = try #require(spring(animation), "\(name) could not be inspected")
            #expect(parsed.response == response, "\(name) response drifted")
            #expect(parsed.damping == damping, "\(name) damping drifted")
        }
    }

    /// A curve used exactly once does not earn a name — naming it would imply a
    /// system where there is only a local decision.
    @Test("Inline springs are the one-off curves only")
    func testInlineSpringsAreRare() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PurahUI")

        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") && !$0.hasSuffix("PurahMotionPolicy.swift") }

        var inline = 0
        for relative in files {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            inline += text.components(separatedBy: ".spring(response:").count - 1
        }

        #expect(inline <= 12,
                "\(inline) springs are still inline; route repeated curves through PurahMotionPolicy")
    }

    @Test("Reduce Motion still overrides any one-shot animation")
    func testReduceMotionOverride() {
        let overridden = PurahMotionPolicy.animation(PurahMotionPolicy.drawerEntrance, reduceMotion: true)
        #expect(overridden == .easeInOut(duration: 0.16))

        let untouched = PurahMotionPolicy.animation(PurahMotionPolicy.drawerEntrance, reduceMotion: false)
        #expect(untouched == PurahMotionPolicy.drawerEntrance)
    }
}
