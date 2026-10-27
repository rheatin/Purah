// Tests/PurahCoreTests/AlertBeaconRenderingTests.swift
import Testing
import AppKit
import QuartzCore
import SwiftUI
import Foundation
@testable import PurahCore
@testable import PurahUI

/// The alert beacon used to pulse from `TimelineView(.periodic, 30fps)`.
/// Each tick invalidated the enclosing hosting view's display list, so a single
/// alerting pod cost 5.68% of a core on a ten-pod rail (11.68% with eight) while
/// the same rail with nothing alerting cost 0.02%. Pausing the clock barely
/// helped, which is why the animation had to move to Core Animation.
///
/// These tests protect that decision: the pulse must stay off the main thread,
/// the bloom must keep its soft falloff, and the geometry must stay on the
/// screen side of the rail.
@MainActor
@Suite("Alert Beacon Rendering")
struct AlertBeaconRenderingTests {

    private var sourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PurahUI/Common/DynamicAttentionBeaconModifier.swift")
    }

    private func sourceLines() throws -> [String] {
        try String(contentsOf: sourceURL, encoding: .utf8)
            .components(separatedBy: .newlines)
    }

    private var codeLines: [String] {
        get throws {
            try sourceLines().filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///")
            }
        }
    }

    // MARK: - The pulse stays off the main thread

    @Test("The beacon no longer drives its pulse from a SwiftUI timeline")
    func testNoTimelineView() throws {
        let offenders = try codeLines.filter { $0.contains("TimelineView") }
        #expect(
            offenders.isEmpty,
            """
            The beacon must not use TimelineView: it re-runs the hosting view's \
            display list every tick (measured 5.68% CPU for one alerting pod). \
            Found: \(offenders)
            """
        )
    }

    @Test("The beacon no longer reinstates a SwiftUI forever animation")
    func testNoRepeatForever() throws {
        let offenders = try codeLines.filter { $0.contains("repeatForever") }
        #expect(offenders.isEmpty, "SwiftUI repeatForever keeps the main thread awake: \(offenders)")
    }

    @Test("Reduce Motion keeps a static outline instead of a frozen pulse frame")
    func testReduceMotionStillHandled() throws {
        let code = try codeLines.joined(separator: "\n")
        #expect(code.contains("reduceMotion"), "the beacon must still consider Reduce Motion")
        #expect(
            code.contains("strokeBorder"),
            "Reduce Motion renders the static outline, not a paused layer animation"
        )
    }

    // MARK: - Animation is real (not an invisible overlay)

    @Test("Each animated style installs a Core Animation pulse")
    func testStylesAnimate() {
        for (style, expected) in [
            (PluginAlertStyle.subtleGlow, 2),
            (.breathingBeacon, 2),
            (.sonarWave, 1)
        ] {
            let view = makeView(style: style, edge: .left, baseWidth: 8)
            let animated = animatedLayers(of: view)
            #expect(
                animated.count == expected,
                "\(style.rawValue) should animate \(expected) layer(s), got \(animated.count)"
            )
        }
    }

    @Test("An off beacon animates nothing")
    func testOffStyleIsStill() {
        let view = makeView(style: .off, edge: .left, baseWidth: 8)
        #expect(animatedLayers(of: view).isEmpty)
    }

    @Test("Pulses repeat forever and autorverse, so one animation covers a full cycle")
    func testPulseCurve() {
        let view = makeView(style: .subtleGlow, edge: .left, baseWidth: 8)
        let pulses = (view.layer?.sublayers ?? [])
            .compactMap { $0.animation(forKey: "pulse") as? CABasicAnimation }
        #expect(!pulses.isEmpty)
        for pulse in pulses {
            #expect(pulse.autoreverses)
            #expect(pulse.repeatCount == .infinity)
            #expect(pulse.isRemovedOnCompletion == false)
        }
    }

    @Test("The sonar ring expands from the rail edge and repeats")
    func testSonarRipple() throws {
        let view = makeView(style: .sonarWave, edge: .left, baseWidth: 8)
        let ring = try #require(view.layer?.sublayers?.first {
            $0.animation(forKey: "grow") != nil
        } as? CAShapeLayer)

        let grow = try #require(ring.animation(forKey: "grow") as? CABasicAnimation)
        #expect(grow.repeatCount == .infinity)
        // (baseWidth + 26) / baseWidth for an 8pt rail.
        let scale = try #require(grow.toValue as? NSNumber).doubleValue
        #expect(abs(scale - 34.0 / 8.0) < 0.001, "expected 4.25x, got \(scale)")
        // Left rail grows from its left edge, so the ring blooms inward.
        #expect(ring.anchorPoint.x == 0)
    }

    // MARK: - Geometry

    @Test("Halos keep their original edge alignment and visible width")
    func testHaloFrames() throws {
        let view = makeView(style: .subtleGlow, edge: .left, baseWidth: 8)
        let (inner, outer) = try halos(of: view)

        // Each halo's frame includes a transparent margin for the baked blur.
        // Verify the *visible* rect against what the SwiftUI original drew: a
        // leading-aligned overlay inside the 8pt bar frame, so a 14pt halo
        // spans x 0...14 and spills inward over the rail, never off-screen.
        for (halo, expectedWidth, expectedMinX, expectedMaxX) in [
            (inner, 14.0, 0.0, 14.0),
            (outer, 22.0, 0.0, 22.0)
        ] {
            let padding = (halo.frame.width - expectedWidth) / 2
            #expect(padding > 0, "the bitmap needs a margin or the blur is clipped")
            let visible = halo.frame.insetBy(dx: padding, dy: padding)
            #expect(abs(visible.width - expectedWidth) < 0.001,
                    "frame \(halo.frame) → visible \(visible)")
            #expect(abs(visible.minX - expectedMinX) < 0.001, "got minX \(visible.minX)")
            #expect(abs(visible.maxX - expectedMaxX) < 0.001, "got maxX \(visible.maxX)")
        }
    }

    @Test("Right-rail halos mirror the left, spilling inward from the bezel")
    func testRightEdgeGeometry() throws {
        let view = makeView(style: .subtleGlow, edge: .right, baseWidth: 8)
        let (inner, _) = try halos(of: view)
        let padding = (inner.frame.width - 14.0) / 2
        let visible = inner.frame.insetBy(dx: padding, dy: padding)
        #expect(abs(visible.minX - (-6)) < 0.001, "got minX \(visible.minX)")
        #expect(abs(visible.maxX - 8) < 0.001, "got maxX \(visible.maxX)")
    }

    @Test("Halo contents are a real blurred bitmap, not a flat fill")
    func testHaloHasSoftFalloff() throws {
        let view = makeView(style: .subtleGlow, edge: .left, baseWidth: 8)
        let (inner, _) = try halos(of: view)

        let contents = try #require(inner.contents, "the halo must carry a bitmap")
        #expect(CFGetTypeID(contents as CFTypeRef) == CGImage.typeID)
        let image = contents as! CGImage

        // Read the alpha of a row through the middle straight from the bitmap.
        // A blurred rounded rect is opaque at the centre and fades to nothing
        // at the edges; a flat fill would stay fully opaque right to the edge.
        let w = image.width, h = image.height
        let provider = try #require(image.dataProvider)
        let data = try #require(provider.data) as Data
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = image.bitsPerPixel / 8
        let middleRow = h / 2
        func alpha(x: Int) -> UInt8 {
            let offset = middleRow * bytesPerRow + x * bytesPerPixel
            guard offset + bytesPerPixel <= data.count else { return 0 }
            // Non-premultiplied would put alpha last; premultipliedLast does
            // too, so the final component is alpha either way.
            return [UInt8](data)[offset + bytesPerPixel - 1]
        }

        let centre = alpha(x: w / 2)
        let edge = alpha(x: 1)
        // The blur spreads the 0.80 baked opacity down to ~0.6 at its peak, so
        // the centre settles near 154/255 rather than saturation.
        #expect(centre > 120, "the core should be visibly solid, got \(centre) in \(w)x\(h)")
        #expect(edge < 40, "the blur should fade out at the edge, got \(edge)")
    }

    @Test("The beacon dot sits just outside the bar on the screen side")
    func testBeaconDotPlacement() throws {
        let left = makeView(style: .breathingBeacon, edge: .left, baseWidth: 8)
        #expect(try dot(of: left).frame.minX == 12, "left rail places the dot at baseWidth + 4")

        let right = makeView(style: .breathingBeacon, edge: .right, baseWidth: 8)
        #expect(try dot(of: right).frame.maxX == -4, "right rail mirrors the dot leftward")
    }

    // MARK: - Zero-block click-through

    @Test("The beacon never becomes a hit-test target")
    func testNeverHitTestable() {
        let view = makeView(style: .subtleGlow, edge: .left, baseWidth: 8)
        #expect(view.hitTest(NSPoint(x: 4, y: 32)) == nil)
        #expect(!view.isOpaque)
    }

    // MARK: - Helpers

    private func makeView(
        style: PluginAlertStyle,
        edge: MountEdge,
        baseWidth: CGFloat
    ) -> AlertBeaconLayerView {
        let view = AlertBeaconLayerView()
        view.frame = CGRect(x: 0, y: 0, width: baseWidth, height: 64)
        view.configure(edge: edge, baseWidth: baseWidth, tint: .systemPink, style: style)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func animatedLayers(of view: AlertBeaconLayerView) -> [CALayer] {
        (view.layer?.sublayers ?? []).filter { !($0.animationKeys() ?? []).isEmpty }
    }

    /// Sublayers are installed in a fixed order: inner halo, outer halo, dot, ring.
    private func halos(of view: AlertBeaconLayerView) throws -> (CALayer, CALayer) {
        let layers = try #require(view.layer?.sublayers)
        #expect(layers.count == 4)
        return (layers[0], layers[1])
    }

    private func dot(of view: AlertBeaconLayerView) throws -> CALayer {
        let layers = try #require(view.layer?.sublayers)
        return layers[2]
    }
}
