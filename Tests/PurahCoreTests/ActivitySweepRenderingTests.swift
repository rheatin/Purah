// Tests/PurahCoreTests/ActivitySweepRenderingTests.swift
import Testing
import AppKit
import QuartzCore
import SwiftUI
import Foundation
@testable import PurahCore
@testable import PurahUI

/// The "this pod is working" sweep used to be drawn by the AI Assistant's own
/// rail bar with `TimelineView(.animation)`, which re-runs the hosting view's
/// display list on every frame. It is now host-rendered from
/// `PurahPodCapabilityProvider.activity(store:)` and animated by Core
/// Animation, so the cost is the render server's and a plugin only reports
/// state.
@MainActor
@Suite("Activity Sweep Rendering")
struct ActivitySweepRenderingTests {

    private var sweepURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PurahUI/Common/DynamicActivitySweepModifier.swift")
    }

    private var beaconURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PurahUI/Common/DynamicAttentionBeaconModifier.swift")
    }

    private func codeLines(of url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///")
            }
    }

    // MARK: - The sweep stays off the main thread

    @Test("The sweep is not driven by a SwiftUI timeline")
    func testNoTimelineView() throws {
        let offenders = try codeLines(of: sweepURL).filter { $0.contains("TimelineView") }
        #expect(offenders.isEmpty, "the sweep must animate on the render server: \(offenders)")
    }

    @Test("The band travels on a Core Animation position.y loop")
    func testBandAnimates() throws {
        let view = makeView(isAnimated: true)
        let band = try #require(view.layer?.sublayers?.first)
        let anim = try #require(band.animation(forKey: "sweep") as? CABasicAnimation)

        #expect(anim.keyPath == "position.y")
        #expect(anim.repeatCount == .infinity)
        #expect(anim.isRemovedOnCompletion == false)
        #expect(anim.duration == 1.4)
    }

    @Test("The band starts above the bar and ends below it")
    func testBandTravel() throws {
        let view = makeView(isAnimated: true)
        let band = try #require(view.layer?.sublayers?.first)
        let anim = try #require(band.animation(forKey: "sweep") as? CABasicAnimation)
        let bandH = ActivitySweepLayerView.bandHeight(for: 120)
        let from = try #require(anim.fromValue as? NSNumber).doubleValue
        let to = try #require(anim.toValue as? NSNumber).doubleValue

        #expect(abs(from - (-bandH / 2)) < 0.001, "got from \(from)")
        #expect(abs(to - (120 + bandH / 2)) < 0.001, "got to \(to)")
    }

    @Test("Reduce Motion shows a still band instead of a frozen frame of travel")
    func testReduceMotionIsStill() throws {
        let view = makeView(isAnimated: false)
        let band = try #require(view.layer?.sublayers?.first)

        #expect(band.animation(forKey: "sweep") == nil)
        #expect(band.opacity < 1, "a still band must not read as a paused animation")
        #expect(abs(band.position.y - 60) < 0.001, "Reduce Motion centres the band")
    }

    @Test("The band height is proportionate but never invisible on a short chip")
    func testBandHeight() {
        func approx(_ value: CGFloat, _ expected: CGFloat) -> Bool {
            abs(value - expected) < 0.001
        }
        #expect(approx(ActivitySweepLayerView.bandHeight(for: 120), 33.6))
        #expect(approx(ActivitySweepLayerView.bandHeight(for: 22), 14))
        #expect(approx(ActivitySweepLayerView.bandHeight(for: 400), 112))
    }

    // MARK: - Zero-block click-through

    @Test("The sweep never becomes a hit-test target")
    func testNeverHitTestable() {
        let view = makeView(isAnimated: true)
        #expect(view.hitTest(NSPoint(x: 4, y: 32)) == nil)
        #expect(!view.isOpaque)
    }

    // MARK: - The alert is acknowledged by the drawer, not by hover

    @Test("The alert beacon has no hover dismissal")
    func testBeaconHasNoHoverDismissal() throws {
        let code = try codeLines(of: beaconURL).joined(separator: "\n")
        #expect(!code.contains("onHoverDismiss"), "hover is not an acknowledgment path")
        #expect(!code.contains(".onHover"), "hover is not an acknowledgment path")
    }

    // MARK: - Helpers

    private func makeView(isAnimated: Bool) -> ActivitySweepLayerView {
        let view = ActivitySweepLayerView()
        view.isAnimated = isAnimated
        view.frame = CGRect(x: 0, y: 0, width: 8, height: 120)
        view.layoutSubtreeIfNeeded()
        return view
    }
}
