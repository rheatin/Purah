// Tests/PurahCoreTests/AlertBeaconRenderingTests.swift
import Testing
import AppKit
import QuartzCore
import SwiftUI
import Foundation
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

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

    @Test("Halo alpha reaches zero at the limit and never rises")
    func testHaloProfileFalloff() {
        #expect(PurahAlertHaloProfile.alpha(atNormalizedOffset: 0) == 1)
        #expect(PurahAlertHaloProfile.alpha(atNormalizedOffset: 1) == 0)
        #expect(PurahAlertHaloProfile.alpha(atNormalizedOffset: 2) == 0)

        var previous = 1.0
        for index in 0...100 {
            let value = PurahAlertHaloProfile.alpha(
                atNormalizedOffset: Double(index) / 100
            )
            #expect(value.isFinite)
            #expect(value >= 0 && value <= 1)
            #expect(value <= previous)
            previous = value
        }

        for degenerate in [Double.nan, .infinity, -.infinity] {
            let value = PurahAlertHaloProfile.alpha(atNormalizedOffset: degenerate)
            #expect(value.isFinite)
            #expect(value >= 0 && value <= 1)
        }
    }

    @Test("Canvas width is compact when docked, alert-width when needed, and full when expanded")
    func testCanvasWidthSelection() {
        #expect(PurahRailCanvas.width(isExpanded: false, isAlerting: false) == 28)
        #expect(PurahRailCanvas.width(isExpanded: false, isAlerting: true) == 48)
        #expect(PurahRailCanvas.width(isExpanded: true, isAlerting: false) == 580)
        #expect(PurahRailCanvas.width(isExpanded: true, isAlerting: true) == 580)
        #expect(AmbientRailWindow.compactCanvasWidth == PurahRailCanvas.compactWidth)
        #expect(AmbientRailWindow.alertCanvasWidth == PurahRailCanvas.alertWidth)
        #expect(AmbientRailWindow.maxCanvasWidth == PurahRailCanvas.maxWidth)
        #expect(PurahRailCanvas.haloLimit(baseWidth: 8) == 40)
        #expect(PurahRailCanvas.haloLimit(baseWidth: 48) == 0)
    }

    @Test("isAnyRailAlerting follows enabled pod alerts, acknowledgments, and style")
    func testAnyRailAlertingState() throws {
        let suite = "alert_beacon_any_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PurahWorkspaceStore(userDefaults: defaults)
        let podId = try #require(store.pods.first(where: \.isEnabled)?.id)

        #expect(!store.isAnyRailAlerting)
        store.setPluginAlert(id: podId, isAlerting: true)
        #expect(store.isAnyRailAlerting)

        store.alertStyle = .off
        #expect(!store.isAnyRailAlerting)

        store.alertStyle = .breathingBeacon
        #expect(store.isAnyRailAlerting)
        store.acknowledgeAlert(id: podId)
        #expect(!store.isAnyRailAlerting)
    }

    @Test("A docked rail window follows alert changes without moving its screen edge")
    func testDockedWindowFollowsAlertState() async throws {
        let suite = "alert_beacon_window_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let screen = try #require(NSScreen.main ?? NSScreen.screens.first)
        let store = PurahWorkspaceStore(userDefaults: defaults)
        let podId = try #require(store.pods.first(where: \.isEnabled)?.id)
        let window = AmbientRailWindow(edge: .right, screen: screen, store: store)
        defer { window.close() }

        #expect(window.frame.width == AmbientRailWindow.compactCanvasWidth)
        let screenEdge = window.frame.maxX

        store.setPluginAlert(id: podId, isAlerting: true)
        await waitUntil { window.frame.width == AmbientRailWindow.alertCanvasWidth }
        #expect(window.frame.width == AmbientRailWindow.alertCanvasWidth)
        #expect(window.frame.maxX == screenEdge)
        #expect(window.ignoresMouseEvents)

        window.setExpanded(true)
        #expect(window.frame.width == AmbientRailWindow.maxCanvasWidth)
        window.setExpanded(false)
        #expect(window.frame.width == AmbientRailWindow.alertCanvasWidth)

        store.acknowledgeAlert(id: podId)
        await waitUntil { window.frame.width == AmbientRailWindow.compactCanvasWidth }
        #expect(window.frame.width == AmbientRailWindow.compactCanvasWidth)
        #expect(window.frame.maxX == screenEdge)
        #expect(window.ignoresMouseEvents)
    }

    @Test("Baked halo pixels at the alert-canvas limit are fully transparent")
    func testBakedHaloOuterEdgeIsTransparent() throws {
        let baseWidth: CGFloat = 8
        let haloLimit = PurahRailCanvas.haloLimit(baseWidth: baseWidth)
        let coreWidth: CGFloat = 14
        let inset: CGFloat = 36
        let size = CGSize(width: coreWidth + inset * 2, height: 136)
        let bitmapScale: CGFloat = 2

        let left = try #require(AlertBeaconLayerView.renderHalo(
            size: size,
            inset: inset,
            cornerRadius: 4,
            blur: 6,
            color: .systemPink,
            opacity: 0.8,
            edge: .left,
            baseWidth: baseWidth,
            haloLimit: haloLimit
        ))
        let leftLimitX = Int(((inset + baseWidth + haloLimit) * bitmapScale).rounded(.down))
        let leftMiddleY = left.height / 2
        let leftLastX = left.width - 1
        #expect(alpha(in: left, x: leftLimitX, y: leftMiddleY) == 0)
        #expect(alpha(in: left, x: leftLastX, y: leftMiddleY) == 0)

        let right = try #require(AlertBeaconLayerView.renderHalo(
            size: size,
            inset: inset,
            cornerRadius: 4,
            blur: 6,
            color: .systemPink,
            opacity: 0.8,
            edge: .right,
            baseWidth: baseWidth,
            haloLimit: haloLimit
        ))
        let rightLimitX = Int(((inset + coreWidth - baseWidth - haloLimit) * bitmapScale).rounded(.down))
        let rightMiddleY = right.height / 2
        #expect(alpha(in: right, x: rightLimitX, y: rightMiddleY) == 0)
        #expect(alpha(in: right, x: 0, y: rightMiddleY) == 0)
    }

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

    @Test("Beacon Bar leaves no dot, halo, or extrusion layers behind")
    func testBeaconBarHasNoLegacyLayers() throws {
        let code = try codeLines.joined(separator: "\n")
        for legacyLayer in ["breathingFlash", "beaconDot", "breathingExtrusion"] {
            #expect(
                !code.contains(legacyLayer),
                "\(legacyLayer) belongs to the rejected beacon design and must stay deleted"
            )
        }
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
            (.sonarWave, 3)
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

    @Test("Sonar has exactly three staggered pill ripples and no halo layers")
    func testSonarRipples() throws {
        let view = makeView(style: .sonarWave, edge: .left, baseWidth: 8)
        let animated = animatedLayers(of: view)
        #expect(animated.count == 3)
        #expect(Set(animated.map(ObjectIdentifier.init)) == Set(view.sonarRings.map(ObjectIdentifier.init)))
        #expect(view.glowInner.isHidden)
        #expect(view.glowOuter.isHidden)
        #expect(view.beaconBloom.isHidden)
        #expect(view.beaconBar.isHidden)

        var beginTimes: [CFTimeInterval] = []
        for ring in view.sonarRings {
            #expect(ring.anchorPoint.x == 0)
            #expect(ring.animation(forKey: "ripple") != nil)
            #expect(ring.animation(forKey: "line") != nil)
            let grow = try #require(ring.animation(forKey: "grow") as? CABasicAnimation)
            #expect(grow.repeatCount == .infinity)
            #expect(grow.duration == 3.6)
            let scale = try #require(grow.toValue as? NSNumber).doubleValue
            let expectedScale: Double = (8.0 + 40.0 * 0.9) / 8.0
            #expect(abs(scale - expectedScale) < 0.001)
            beginTimes.append(grow.beginTime)

            let fade = try #require(ring.animation(forKey: "ripple") as? CABasicAnimation)
            #expect(fade.fromValue as? Double == 0.65)
            #expect(fade.toValue as? Double == 0.0)
            let width = try #require(ring.animation(forKey: "line") as? CABasicAnimation)
            #expect(width.fromValue as? Double == 1.6)
            #expect(width.toValue as? Double == 0.6)
        }
        beginTimes.sort()
        let expectedGap: CFTimeInterval = 1.2
        let firstGap = beginTimes[1] - beginTimes[0]
        let secondGap = beginTimes[2] - beginTimes[1]
        #expect(abs(firstGap - expectedGap) < 0.01)
        #expect(abs(secondGap - expectedGap) < 0.01)
    }

    @Test("Beacon Bar is a tinted double-flashing pill with no halos; subtle glow has halos only")
    func testBeaconBarAndSubtleGlowAreDistinct() throws {
        let breathing = makeView(style: .breathingBeacon, edge: .left, baseWidth: 8)
        #expect(!breathing.beaconBloom.isHidden)
        #expect(!breathing.beaconBar.isHidden)
        #expect(breathing.glowInner.isHidden)
        #expect(breathing.glowOuter.isHidden)
        #expect(breathing.sonarRings.allSatisfy { $0.isHidden })

        let sublayers = try #require(breathing.layer?.sublayers)
        let bloomIndex = try #require(sublayers.firstIndex { $0 === breathing.beaconBloom })
        let barIndex = try #require(sublayers.firstIndex { $0 === breathing.beaconBar })
        #expect(bloomIndex < barIndex, "the bloom must render behind the Beacon Bar")

        let expectedHeight: CGFloat = 64 * 0.72
        let expectedLeftMinX: CGFloat = 8 + 4
        let expectedMinY: CGFloat = (64 - expectedHeight) / 2
        #expect(abs(breathing.beaconBar.frame.minX - expectedLeftMinX) < 0.001)
        #expect(breathing.beaconBar.frame.width == 8)
        #expect(abs(breathing.beaconBar.frame.height - expectedHeight) < 0.001)
        #expect(abs(breathing.beaconBar.frame.minY - expectedMinY) < 0.001)
        #expect(breathing.beaconBar.cornerRadius == 4)
        #expect(breathing.beaconBar.shadowRadius == 6)
        #expect(breathing.beaconBar.shadowOpacity == 0.55)
        #expect(breathing.beaconBar.shadowOffset == .zero)
        #expect(breathing.beaconBar.opacity == 0)
        #expect(breathing.beaconBloom.opacity == 0)

        let bloomFrame = breathing.beaconBloomCoreFrame
        let expectedBloomMinX: CGFloat = breathing.beaconBar.frame.minX - 3
        let expectedBloomMinY: CGFloat = breathing.beaconBar.frame.minY - 3
        let expectedBloomWidth: CGFloat = breathing.beaconBar.frame.width + 6
        let expectedBloomHeight: CGFloat = breathing.beaconBar.frame.height + 6
        #expect(abs(bloomFrame.minX - expectedBloomMinX) < 0.001)
        #expect(abs(bloomFrame.minY - expectedBloomMinY) < 0.001)
        #expect(abs(bloomFrame.width - expectedBloomWidth) < 0.001)
        #expect(abs(bloomFrame.height - expectedBloomHeight) < 0.001)
        let bloomContents = try #require(breathing.beaconBloom.contents)
        #expect(CFGetTypeID(bloomContents as CFTypeRef) == CGImage.typeID)

        let blink = try #require(
            breathing.beaconBar.animation(forKey: "blink") as? CAKeyframeAnimation
        )
        let bloomBlink = try #require(
            breathing.beaconBloom.animation(forKey: "blink") as? CAKeyframeAnimation
        )
        #expect(bloomBlink.duration == blink.duration)
        #expect(bloomBlink.keyTimes?.map(\.doubleValue) == blink.keyTimes?.map(\.doubleValue))
        #expect(
            bloomBlink.values?.compactMap { ($0 as? NSNumber)?.doubleValue }
                == blink.values?.compactMap { ($0 as? NSNumber)?.doubleValue }
        )
        #expect(blink.duration == 2.0)
        #expect(blink.repeatCount == .infinity)
        #expect(blink.isRemovedOnCompletion == false)
        #expect(blink.timingFunction?.isEqual(CAMediaTimingFunction(name: .linear)) == true)
        #expect(blink.keyTimes?.map(\.doubleValue) == [0, 0.05, 0.10, 0.15, 0.225, 1.0])
        #expect(blink.values?.compactMap { ($0 as? NSNumber)?.doubleValue } == [0, 1.0, 0.35, 1.0, 0, 0])

        let glow = makeView(style: .subtleGlow, edge: .left, baseWidth: 8)
        #expect(glow.beaconBloom.isHidden)
        #expect(glow.beaconBar.isHidden)
        #expect(!glow.glowInner.isHidden)
        #expect(!glow.glowOuter.isHidden)
        let inner = try #require(glow.glowInner.animation(forKey: "pulse") as? CABasicAnimation)
        let outer = try #require(glow.glowOuter.animation(forKey: "pulse") as? CABasicAnimation)
        let innerFrom = (inner.fromValue as? Float) ?? 0
        let innerTo = (inner.toValue as? Float) ?? 0
        let outerFrom = (outer.fromValue as? Float) ?? 0
        let outerTo = (outer.toValue as? Float) ?? 0
        let expectedInnerFrom: Float = 0.55
        let expectedInnerTo: Float = 0.85
        let expectedOuterFrom: Float = 0.50
        let expectedOuterTo: Float = 0.80
        #expect(inner.duration == 2.0)
        #expect(abs(innerFrom - expectedInnerFrom) < 0.001)
        #expect(abs(innerTo - expectedInnerTo) < 0.001)
        #expect(outer.duration == 2.0)
        #expect(abs(outerFrom - expectedOuterFrom) < 0.001)
        #expect(abs(outerTo - expectedOuterTo) < 0.001)

        let right = makeView(style: .breathingBeacon, edge: .right, baseWidth: 8)
        #expect(!right.beaconBloom.isHidden)
        let expectedRightMinX: CGFloat = -(8 + 4) - 8
        #expect(abs(right.beaconBar.frame.minX - expectedRightMinX) < 0.001)

        let off = makeView(style: .off, edge: .left, baseWidth: 8)
        #expect(off.beaconBloom.isHidden)
    }

    @Test("Changing style hides the bloom and removes its animation")
    func testBeaconBloomStopsWhenStyleChanges() {
        let view = makeView(style: .breathingBeacon, edge: .left, baseWidth: 8)
        #expect(view.beaconBloom.animation(forKey: "blink") != nil)

        view.configure(
            edge: .left,
            baseWidth: 8,
            haloLimit: PurahRailCanvas.haloLimit(baseWidth: 8),
            tint: .systemPink,
            style: .subtleGlow
        )
        #expect(view.beaconBloom.isHidden)
        #expect(view.beaconBloom.animation(forKey: "blink") == nil)
    }

    @Test("Beacon Bar and sonar growth stay inside the halo limit")
    func testAnimatedStylesRespectHaloLimit() throws {
        let baseWidth: CGFloat = 8
        let haloLimit = PurahRailCanvas.haloLimit(baseWidth: baseWidth)
        let maximumWidth = baseWidth + haloLimit

        let breathing = makeView(style: .breathingBeacon, edge: .left, baseWidth: baseWidth)
        #expect(breathing.beaconBar.frame.minX >= 0)
        #expect(breathing.beaconBar.frame.width <= baseWidth)
        #expect(breathing.beaconBar.frame.maxX <= maximumWidth)

        let sonar = makeView(style: .sonarWave, edge: .left, baseWidth: baseWidth)
        for ring in sonar.sonarRings {
            let grow = try #require(ring.animation(forKey: "grow") as? CABasicAnimation)
            let ringScale = try #require(grow.toValue as? NSNumber).doubleValue
            let ringWidth = baseWidth * ringScale
            #expect(ringWidth <= maximumWidth)
        }
    }

    @Test("Beacon Bar plus shadow fits inside the compact rail canvas")
    func testBeaconBarShadowFitsCompactCanvas() throws {
        let baseWidth: CGFloat = 8

        for edge in [MountEdge.left, .right] {
            let view = makeView(style: .breathingBeacon, edge: edge, baseWidth: baseWidth)
            let bar = view.beaconBar
            let inwardExtent = edge == .left
                ? bar.frame.maxX + bar.shadowRadius
                : abs(bar.frame.minX) + bar.shadowRadius
            let expectedExtent = baseWidth + 4 + baseWidth + bar.shadowRadius
            #expect(inwardExtent == expectedExtent)
            #expect(
                inwardExtent <= PurahRailCanvas.compactWidth,
                "\(edge) Beacon Bar and shadow reached \(inwardExtent)pt"
            )
        }
    }

    @Test("Beacon bloom stays inside the alert canvas")
    func testBeaconBloomFitsAlertCanvas() throws {
        let baseWidth: CGFloat = 8
        let blur: CGFloat = 8

        for edge in [MountEdge.left, .right] {
            let view = makeView(style: .breathingBeacon, edge: edge, baseWidth: baseWidth)
            let innerEdge = edge == .left
                ? view.beaconBar.frame.maxX
                : abs(view.beaconBar.frame.minX)

            let expectedInnerEdge: CGFloat = baseWidth + 4 + baseWidth
            let expectedBloomLimit: CGFloat = 28
            #expect(abs(innerEdge - expectedInnerEdge) < 0.001)
            #expect(abs(view.beaconBloomHaloLimit - expectedBloomLimit) < 0.001)
            #expect(
                innerEdge + view.beaconBloomHaloLimit
                    <= PurahRailCanvas.alertWidth
            )

            let bloomCore = view.beaconBloomCoreFrame
            let drawnExtent = edge == .left
                ? bloomCore.maxX + blur
                : abs(bloomCore.minX) + blur
            #expect(
                drawnExtent <= PurahRailCanvas.alertWidth,
                "\(edge) bloom plus blur reached \(drawnExtent)pt"
            )
        }
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
        let expectedMinX: CGFloat = -6
        let expectedMaxX: CGFloat = 8
        #expect(abs(visible.minX - expectedMinX) < 0.001, "got minX \(visible.minX)")
        #expect(abs(visible.maxX - expectedMaxX) < 0.001, "got maxX \(visible.maxX)")
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
        view.configure(
            edge: edge,
            baseWidth: baseWidth,
            haloLimit: PurahRailCanvas.haloLimit(baseWidth: baseWidth),
            tint: .systemPink,
            style: style
        )
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func alpha(in image: CGImage, x: Int, y: Int) -> UInt8 {
        guard x >= 0, x < image.width, y >= 0, y < image.height,
              let provider = image.dataProvider,
              let data = provider.data else { return 0 }
        let bytes = data as Data
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = y * image.bytesPerRow + x * bytesPerPixel
        guard offset + bytesPerPixel <= bytes.count else { return 0 }
        return bytes[offset + bytesPerPixel - 1]
    }

    private func animatedLayers(of view: AlertBeaconLayerView) -> [CALayer] {
        (view.layer?.sublayers ?? []).filter { !($0.animationKeys() ?? []).isEmpty }
    }

    /// Sublayers are installed in a fixed order: inner halo, outer halo, bloom, bar, sonar rings.
    private func halos(of view: AlertBeaconLayerView) throws -> (CALayer, CALayer) {
        (view.glowInner, view.glowOuter)
    }
}
