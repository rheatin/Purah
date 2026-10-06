# Design Spec: Rubber-Banding Soft Boundaries & Optical Typography System

## 1. Overview
This specification delivers two foundational Apple Design refinements to Project Purah based on Apple's WWDC human interface philosophies (*Designing Fluid Interfaces* & *The Details of UI Typography*):
1. **P3 — Rubber-Banding Soft Boundaries**: Introducing Apple's exact progressive resistance formula ($f(x, D) = \frac{x \cdot D \cdot c}{D + c \cdot |x|}$) to pod resizing and positioning gestures. Eliminating jarring hard stops when dragging past minimum/maximum bounds or screen boundaries, replaced with physical mechanical elasticity and a spring snap-back release.
2. **P4 — Optical Typography System**: Establishing size-specific optical letter-spacing (tracking) across all typography in Purah. Large titles receive negative tracking (`-0.20` to `-0.40pt`) for cohesive visual presence; micro captions, monospaced terminal text, and status badges receive positive tracking (`+0.20` to `+0.35pt`) to prevent character crowding on dense Retina screens.

---

## 2. Rubber-Banding Soft Boundaries Architecture (P3)

### 2.1 The Physics Engine (`RubberBandingEngine`)
Create `Sources/PurahCore/LayoutEngine/RubberBandingEngine.swift` as a pure mathematical solver:
```swift
public enum RubberBandingEngine {
    public static let defaultConstant: Double = 0.55

    /// Apple's exact rubberband equation: (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    public static func rubberband(offset: Double, dimension: Double, constant: Double = defaultConstant) -> Double {
        guard dimension > 0 else { return offset * constant }
        return (offset * dimension * constant) / (dimension + constant * abs(offset))
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
```

### 2.2 Interactive Capsule Resizing (`PodCapsuleView`)
- In `PodCapsuleView.swift`:
  - When dragging the bottom resize handle:
    - Compute unconstrained `rawLength = (resizeInitialLength ?? pod.range.length) + deltaRatio`.
    - Apply `RubberBandingEngine.clampWithRubberband` against the legal range `pod.minLength...maxAllowedLength`.
    - During active gesture, the capsule stretches smoothly with progressive resistance past the limit.
  - On `onEnded`:
    - Animate with spring (`response: 0.30, dampingFraction: 0.80`) back to the rigid clamped legal range and notify `onResize`.

### 2.3 Interactive Anchor Move (`PodCapsuleView`)
- When dragging the pod header to reposition:
  - If dragged past safe bounds (`0.02...0.98`), apply rubberband resistance.
  - On `onEnded`, spring smoothly snaps back into legal safe bounds.

---

## 3. Optical Typography System Architecture (P4)

### 3.1 Optical Tracking Mapping (`PurahTypography`)
Create `Sources/PurahUI/Theme/PurahTypography.swift`:
```swift
public enum PurahTypography {
    public static func opticalTracking(for size: CGFloat) -> CGFloat {
        if size >= 18.0 {
            return -0.40  // Large headers & display numbers
        } else if size >= 14.0 {
            return -0.20  // Section titles & card names
        } else if size <= 8.0 {
            return 0.35   // Micro badges, telemetry numbers, tiny caps
        } else if size <= 9.5 {
            return 0.20   // Captions, monospaced preview, process rows
        } else {
            return 0.00   // Body & standard text (10~13pt)
        }
    }
}
```

### 3.2 View Modifiers & Style Helpers
```swift
public struct OpticalTextModifier: ViewModifier {
    public let size: CGFloat

    public func body(content: Content) -> some View {
        content.tracking(PurahTypography.opticalTracking(for: size))
    }
}

public extension View {
    func opticalTracking(size: CGFloat) -> some View {
        self.modifier(OpticalTextModifier(size: size))
    }
}

public extension Text {
    func purahTitle(size: CGFloat = 15, weight: Font.Weight = .bold, design: Font.Design = .rounded) -> Text {
        self.font(.system(size: size, weight: weight, design: design))
            .tracking(PurahTypography.opticalTracking(for: size))
    }

    func purahBody(size: CGFloat = 11, weight: Font.Weight = .medium, design: Font.Design = .default) -> Text {
        self.font(.system(size: size, weight: weight, design: design))
            .tracking(PurahTypography.opticalTracking(for: size))
    }

    func purahCaption(size: CGFloat = 9, weight: Font.Weight = .regular, design: Font.Design = .default) -> Text {
        self.font(.system(size: size, weight: weight, design: design))
            .tracking(PurahTypography.opticalTracking(for: size))
    }

    func purahBadge(size: CGFloat = 7.5, weight: Font.Weight = .bold, design: Font.Design = .monospaced) -> Text {
        self.font(.system(size: size, weight: weight, design: design))
            .tracking(PurahTypography.opticalTracking(for: size))
    }
}
```

### 3.3 Component Rollout Scope
- **Drawer Cards**:
  - `ScriptItemDrawerView`: titles (11pt bold), badges (`SHORTCUT` 7pt +0.35pt tracking), preview (8.5pt mono +0.2pt tracking), Run button (9pt bold +0.2pt tracking).
  - `VitalsItemDrawerView` & `HardwareVitalsDrawerView`: metric titles, telemetry percentage labels, process list names, free GB values.
  - `CalendarDrawerView` & `TodoDrawerView`: event titles, time badges, task labels.
  - `MusicDrawerView`, `DropShelfDrawerView`, `QuickNoteDrawerView`.
- **Rail Bars**: micro glyphs, time indicators, status indicators.
- **Settings & Preferences**: header titles, capacity overload warnings, configuration captions.

---

## 4. Verification & Testing Plan

1. **Rubber-Banding Unit Tests** (`Tests/PurahCoreTests/RubberBandingTests.swift`):
   - Verify `rubberband(offset:dimension:constant:)` returns 0 for 0 offset.
   - Verify sub-linear growth ($f(2x) < 2f(x)$).
   - Verify asymptotic convergence towards limit.
   - Verify `clampWithRubberband` leaves in-bounds values untouched and damps out-of-bounds values symmetrically.
2. **Optical Typography Unit Tests** (`Tests/PurahCoreTests/TypographyTests.swift`):
   - Verify optical tracking thresholds:
     - $\ge 18\text{pt} \implies -0.40$
     - $15\text{pt} \implies -0.20$
     - $11\text{pt} \implies 0.0$
     - $9\text{pt} \implies +0.20$
     - $7.5\text{pt} \implies +0.35$
3. **Full System Test Suite**:
   - `swift test --disable-sandbox --no-parallel`: ensure all 111+ tests pass with zero regressions.
   - `swift build -c release --disable-sandbox`: clean compilation under Swift 6 strict concurrency checking.
