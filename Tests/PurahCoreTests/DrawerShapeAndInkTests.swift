// Tests/PurahCoreTests/DrawerShapeAndInkTests.swift
import Testing
import SwiftUI
import Foundation
@testable import PurahCore
@testable import PurahUI

/// Guards the two design tokens that used to be copy-pasted: the edge-flush
/// drawer outline (seven hand-written copies) and the slate ink for badges on
/// fixed light fills (ten literals).
@MainActor
@Suite("Drawer Shape & Ink Tokens")
struct DrawerShapeAndInkTests {

    @Test("A right-rail drawer rounds its floating edge and sits flush on the bezel")
    func testRightRailShape() {
        let radii = PurahDrawerShape.cornerRadii(edge: .right, radius: PurahDrawerShape.compositeRadius)
        #expect(radii.topLeading == PurahDrawerShape.compositeRadius)
        #expect(radii.bottomLeading == PurahDrawerShape.compositeRadius)
        #expect(radii.topTrailing == 0)
        #expect(radii.bottomTrailing == 0)
    }

    @Test("A left-rail drawer mirrors the right-rail shape")
    func testLeftRailShape() {
        let radii = PurahDrawerShape.cornerRadii(edge: .left, radius: PurahDrawerShape.compositeRadius)
        #expect(radii.topTrailing == PurahDrawerShape.compositeRadius)
        #expect(radii.bottomTrailing == PurahDrawerShape.compositeRadius)
        #expect(radii.topLeading == 0)
        #expect(radii.bottomLeading == 0)
    }

    @Test("Stepped cards use a tighter radius than composite drawers")
    func testSteppedRadiusIsTighter() {
        #expect(PurahDrawerShape.steppedRadius < PurahDrawerShape.compositeRadius)
        let radii = PurahDrawerShape.cornerRadii(edge: .right, radius: PurahDrawerShape.steppedRadius)
        #expect(radii.topLeading == PurahDrawerShape.steppedRadius)
    }

    @Test("No file spells out the drawer outline by hand any more")
    func testNoHandWrittenDrawerShapes() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PurahUI")

        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") && !$0.hasSuffix("PurahDrawerShape.swift") }

        var offenders: [String] = []
        for relative in files {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            if text.contains("topLeadingRadius: edge ==") {
                offenders.append(relative)
            }
        }
        #expect(offenders.isEmpty,
                "drawer outlines must go through PurahDrawerShape: \(offenders.joined(separator: ", "))")
    }

    @Test("The slate ink token keeps the documented value")
    func testSlateInkValue() throws {
        let nsColor = try #require(NSColor(Color.slateInk).usingColorSpace(.sRGB))
        #expect(abs(nsColor.redComponent - 0.059) < 0.01)
        #expect(abs(nsColor.greenComponent - 0.067) < 0.01)
        #expect(abs(nsColor.blueComponent - 0.102) < 0.01)
    }

    @Test("No file spells out the slate ink literal any more")
    func testNoHardcodedSlateInk() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PurahUI")

        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") && !$0.hasSuffix("ThemePalette.swift") }

        var offenders: [String] = []
        for relative in files {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            if text.contains("red: 0.059, green: 0.067, blue: 0.102") {
                offenders.append(relative)
            }
        }
        #expect(offenders.isEmpty,
                "use Color.slateInk instead of the literal: \(offenders.joined(separator: ", "))")
    }

    @Test("highContrastInk picks white on very dark fills and slate on light ones")
    func testHighContrastInkSwitchesOnLuminance() throws {
        let onDark = Color(red: 0.02, green: 0.02, blue: 0.03).highContrastInk
        let onLight = Color(red: 0.95, green: 0.75, blue: 0.2).highContrastInk

        let darkInk = try #require(NSColor(onDark).usingColorSpace(.sRGB))
        let lightInk = try #require(NSColor(onLight).usingColorSpace(.sRGB))
        #expect(darkInk.redComponent > 0.9, "very dark fills need white ink")
        #expect(lightInk.redComponent < 0.2, "light fills need slate ink")
    }
}
