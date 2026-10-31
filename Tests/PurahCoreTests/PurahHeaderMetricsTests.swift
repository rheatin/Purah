// Tests/PurahCoreTests/PurahHeaderMetricsTests.swift
import Testing
import SwiftUI
import Foundation
@testable import PurahUI

/// The header was drawn seven different ways at once: five plugins each
/// hand-rolled a chip with their own font size (7.5 to 9.5pt), corner radius
/// (3 / 3.5 / 4), fill opacity (0.12 to 0.20) and spacing (2 to 5). Every one
/// of those is now one of these numbers.
///
/// Pinned so the drift cannot come back quietly: a new control that needs a
/// different size is a design decision, and it should fail here first.
@Suite("Drawer Header Metrics")
struct PurahHeaderMetricsTests {

    @Test("Controls share one glyph size and one hit box")
    func testControlSize() {
        #expect(PurahHeaderMetrics.glyphSize == 11)
        #expect(PurahHeaderMetrics.hitSize == 20)
        #expect(PurahHeaderMetrics.buttonCorner == 5)
    }

    @Test("Pills share one type size, padding and corner")
    func testPillSize() {
        #expect(PurahHeaderMetrics.pillFontSize == 8.5)
        #expect(PurahHeaderMetrics.pillPaddingH == 5)
        #expect(PurahHeaderMetrics.pillPaddingV == 1.5)
        #expect(PurahHeaderMetrics.pillCorner == 4)
    }

    @Test("The three fills are distinguishable at a glance")
    func testFillLadder() {
        // hover < pill < active. Equal values would make hover and selection
        // look the same, which is exactly the bug this ordering prevents.
        #expect(PurahHeaderMetrics.hoverFill == 0.08)
        #expect(PurahHeaderMetrics.menuFill == 0.10)
        #expect(PurahHeaderMetrics.pillFill == 0.14)
        #expect(PurahHeaderMetrics.activeFill == 0.16)
        #expect(PurahHeaderMetrics.selectedFill == 0.20)
        #expect(PurahHeaderMetrics.hoverFill < PurahHeaderMetrics.pillFill)
        #expect(PurahHeaderMetrics.pillFill < PurahHeaderMetrics.activeFill)
        #expect(PurahHeaderMetrics.activeFill < PurahHeaderMetrics.selectedFill)
    }
}

@Suite("Drawer Item Rhythm")
struct PurahItemRhythmTests {
    @Test("Rail steps and content rows keep separate spacing scales")
    func testSpacingScales() {
        #expect(PurahItemRhythm.railStepGap == 2.5)
        #expect(PurahItemRhythm.rowGap == 4)
        #expect(PurahItemRhythm.sectionGap == 8)
        #expect(PurahItemRhythm.railStepGap < PurahItemRhythm.rowGap)
        #expect(PurahItemRhythm.rowGap < PurahItemRhythm.sectionGap)
    }

    @Test("Content rows share one inset and one corner")
    func testRowMetrics() {
        #expect(PurahItemRhythm.contentInset == 8)
        #expect(PurahItemRhythm.rowHorizontalInset == 8)
        #expect(PurahItemRhythm.rowVerticalInset == 6)
        #expect(PurahItemRhythm.rowCornerRadius == 8)
    }
}
