// Sources/PurahCore/LayoutEngine/RubberBandingEngine.swift
import Foundation

public enum RubberBandingEngine {
    public static let defaultConstant: Double = 0.55

    /// Apple's exact rubberband equation from WWDC Designing Fluid Interfaces:
    /// (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    public static func rubberband(offset: Double, dimension: Double, constant: Double = defaultConstant) -> Double {
        guard dimension > 0 else { return offset * constant }
        let sign = offset >= 0 ? 1.0 : -1.0
        let absOffset = abs(offset)
        let damped = (absOffset * dimension * constant) / (dimension + constant * absOffset)
        return sign * damped
    }

    /// Clamps a continuous value within bounds [min...max], applying progressive rubberband resistance when out-of-bounds
    public static func clampWithRubberband(
        value: Double,
        bounds: ClosedRange<Double>,
        dimension: Double = 1.0,
        constant: Double = defaultConstant
    ) -> Double {
        if value < bounds.lowerBound {
            let overshoot = value - bounds.lowerBound
            return bounds.lowerBound + rubberband(offset: overshoot, dimension: dimension, constant: constant)
        } else if value > bounds.upperBound {
            let overshoot = value - bounds.upperBound
            return bounds.upperBound + rubberband(offset: overshoot, dimension: dimension, constant: constant)
        }
        return value
    }
}
