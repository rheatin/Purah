// Tests/PurahCoreTests/RubberBandingTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Rubber-Banding Physics Engine Tests")
struct RubberBandingTests {
    @Test("Zero offset produces zero rubberband displacement")
    func testZeroOffset() {
        let result = RubberBandingEngine.rubberband(offset: 0.0, dimension: 100.0)
        #expect(result == 0.0)
    }

    @Test("Rubberband exhibits sub-linear progressive resistance")
    func testSubLinearProgressiveResistance() {
        let r1 = RubberBandingEngine.rubberband(offset: 50.0, dimension: 100.0)
        let r2 = RubberBandingEngine.rubberband(offset: 100.0, dimension: 100.0)
        let r3 = RubberBandingEngine.rubberband(offset: 200.0, dimension: 100.0)

        // As offset doubles, the increment decreases (progressive resistance)
        #expect(r1 > 0.0)
        #expect(r2 > r1)
        #expect(r3 > r2)
        #expect(r2 < r1 * 2.0)
        #expect(r3 < r2 * 2.0)
    }

    @Test("Negative offset exhibits exact symmetric resistance")
    func testSymmetricResistance() {
        let positive = RubberBandingEngine.rubberband(offset: 60.0, dimension: 120.0)
        let negative = RubberBandingEngine.rubberband(offset: -60.0, dimension: 120.0)
        #expect(abs(positive + negative) < 0.0001)
    }

    @Test("Clamp with rubberband preserves in-bounds values")
    func testClampInBounds() {
        let bounds: ClosedRange<Double> = 0.15...0.75
        let result = RubberBandingEngine.clampWithRubberband(value: 0.45, bounds: bounds)
        #expect(result == 0.45)
    }

    @Test("Clamp with rubberband progressively resists out-of-bounds overshoot")
    func testClampOutOfBounds() {
        let bounds: ClosedRange<Double> = 0.20...0.80

        // Below minimum: should be < 0.20, but > 0.0 (damped)
        let below = RubberBandingEngine.clampWithRubberband(value: 0.10, bounds: bounds, dimension: 1.0)
        #expect(below < 0.20)
        #expect(below > 0.10) // Damped, so it doesn't move all the way to 0.10

        // Above maximum: should be > 0.80, but < 0.90 (damped)
        let above = RubberBandingEngine.clampWithRubberband(value: 0.90, bounds: bounds, dimension: 1.0)
        #expect(above > 0.80)
        #expect(above < 0.90) // Damped, so it doesn't move all the way to 0.90
    }
}
