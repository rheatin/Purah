// Tests/PurahCoreTests/TypographyTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Optical Typography & Tracking Tests")
struct TypographyTests {
    @Test("Size-specific optical tracking follows Apple WWDC typography standards")
    func testOpticalTrackingValues() {
        // Large Display / Headlines (>= 18pt): negative tracking (-0.40)
        #expect(PurahTypography.opticalTracking(for: 24.0) == -0.40)
        #expect(PurahTypography.opticalTracking(for: 18.0) == -0.40)

        // Section Headers (14 ~ 17pt): negative tracking (-0.20)
        #expect(PurahTypography.opticalTracking(for: 16.0) == -0.20)
        #expect(PurahTypography.opticalTracking(for: 14.0) == -0.20)

        // Body / Standard Text (10 ~ 13pt): neutral tracking (0.00)
        #expect(PurahTypography.opticalTracking(for: 13.0) == 0.0)
        #expect(PurahTypography.opticalTracking(for: 11.0) == 0.0)
        #expect(PurahTypography.opticalTracking(for: 10.0) == 0.0)

        // Captions / Monospaced Preview (8.5 ~ 9.5pt): positive tracking (+0.20)
        #expect(PurahTypography.opticalTracking(for: 9.5) == 0.20)
        #expect(PurahTypography.opticalTracking(for: 8.5) == 0.20)

        // Micro Badges / Telemetry Numbers (<= 8.0pt): positive tracking (+0.35)
        #expect(PurahTypography.opticalTracking(for: 8.0) == 0.35)
        #expect(PurahTypography.opticalTracking(for: 7.0) == 0.35)
    }
}
