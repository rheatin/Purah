import AppKit
import SwiftUI
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("Header Menu Tint Render", .serialized)
struct HeaderMenuTintRenderTests {
    @Test("Header menu ink carries the supplied tint")
    @MainActor
    func headerMenuInkCarriesTint() throws {
        let title = try tintedTitlePixelCount(text: "Design notes")
        let blue = try tintedPixelCount(
            tintHex: "#0A84FF",
            sample: .notesPill("Design notes")
        )
        let yellow = try tintedPixelCount(
            tintHex: "#FFD60A",
            sample: .notesPill("Design notes")
        )
        let sparkles = try tintedPixelCount(
            tintHex: "#FFD60A",
            sample: .sparklesButton
        )

        print("HEADER_TINT_PIXELS title=\(title) blue=\(blue) yellow=\(yellow) sparkles=\(sparkles)")
        #expect(title > 0, "The menu title rendered without tinted ink")
        // The trigger has no resting fill, so these are ink pixels only:
        // measured 671 title / 795 blue / 673 yellow / 81 sparkles. The floors
        // sit well below that but above the icon-and-chevron-only range, so a
        // regression to an unpainted title fails instead of hiding in a pill.
        #expect(blue > 700, "Blue menu ink is missing or reduced to the icon and chevron")
        #expect(yellow > 600, "Yellow menu ink is missing or reduced to the icon and chevron")
        #expect(sparkles > 40, "Sparkles menu glyph rendered without its tint")
    }

    @Test("Header menu trigger has no resting plate")
    @MainActor
    func headerMenuTriggerHasNoRestingPlate() throws {
        let plain = try tintedPixelCount(
            tintHex: "#0A84FF",
            sample: .notesPill("Design notes")
        )
        let titleOnly = try tintedPixelCount(
            tintHex: "#0A84FF",
            sample: .titleOnlyPill("Design notes"),
            trailingInkExclusion: 10
        )

        print("HEADER_PLATE_PIXELS plain=\(plain) titleOnly=\(titleOnly)")
        // A resting `menuFill` plate covered the whole label, so most of its
        // area matched the tint family. Ink alone is a small fraction of that.
        #expect(plain < 1_400, "A resting fill is still painted behind the menu label")
        #expect(titleOnly > 300, "The title's own ink did not render")
    }

    @MainActor
    private func tintedTitlePixelCount(text: String) throws -> Int {
        try tintedPixelCount(
            tintHex: "#0A84FF",
            sample: .titleOnlyPill(text),
            trailingInkExclusion: 10
        )
    }

    @MainActor
    private func tintedPixelCount(
        tintHex: String,
        sample: HeaderMenuSample,
        trailingInkExclusion: CGFloat = 0
    ) throws -> Int {
        let tint = Color(hex: tintHex)
        let root = sample.view(tint: tint)
            .padding(10)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .frame(width: 240, height: 56)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 240, height: 56)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        // Render at a fixed 2x. `bitmapImageRepForCachingDisplay` follows the
        // window's backing scale, so on a screen-less session the same view
        // produced a quarter of the ink pixels and these floors failed.
        let scale: CGFloat = 2
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int((hosting.bounds.width * scale).rounded()),
                pixelsHigh: Int((hosting.bounds.height * scale).rounded()),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = hosting.bounds.size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

        let components = try #require(HexColor.parse(tintHex))
        return countTintedPixels(
            in: bitmap,
            tint: components,
            trailingInkExclusion: Int((trailingInkExclusion * scale).rounded())
        )
    }

    /// Matches only the blue and yellow tint families used below. Add matching
    /// rules before using this with green Vitals or red Music pills.
    private func countTintedPixels(
        in bitmap: NSBitmapImageRep,
        tint: HexColor.Components,
        trailingInkExclusion: Int
    ) -> Int {
        var matchingXPositions: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.sRGB) else {
                    continue
                }
                let r = Double(color.redComponent)
                let g = Double(color.greenComponent)
                let b = Double(color.blueComponent)

                if tint.blue > 0.8 {
                    if b > 0.45, b > r + 0.12, b > g + 0.08 {
                        matchingXPositions.append(x)
                    }
                } else if tint.red > 0.8, tint.green > 0.6 {
                    if r > 0.6, g > 0.45, b < 0.3,
                       r > b + 0.35, g > b + 0.25 {
                        matchingXPositions.append(x)
                    }
                }
            }
        }

        guard trailingInkExclusion > 0 else {
            return matchingXPositions.count
        }
        guard let rightmostMatch = matchingXPositions.max() else { return 0 }
        let xLimit = rightmostMatch - trailingInkExclusion
        return matchingXPositions.count { $0 <= xLimit }
    }

}

private enum HeaderMenuSample {
    case notesPill(String)
    case titleOnlyPill(String)
    case sparklesButton

    @MainActor @ViewBuilder
    func view(tint: Color) -> some View {
        switch self {
        case .notesPill(let text):
            Menu {
                Button("Sample") {}
            } label: {
                PurahHeaderMenuLabel(
                    text: text,
                    icon: "doc.text",
                    tint: tint,
                    maxTextWidth: 120,
                    isEmphasized: true
                )
            }
            .purahHeaderMenuStyle()
        case .titleOnlyPill(let text):
            Menu {
                Button("Sample") {}
            } label: {
                PurahHeaderMenuLabel(
                    text: text,
                    tint: tint,
                    maxTextWidth: 120,
                    isEmphasized: true
                )
            }
            .purahHeaderMenuStyle()
        case .sparklesButton:
            PurahHeaderMenuButton(
                systemImage: "sparkles",
                help: "Sample",
                tint: tint,
                isEmphasized: true
            ) {
                Button("Sample") {}
            }
        }
    }
}
