import AppKit
import SwiftUI
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("Vitals flat series render", .serialized)
struct VitalsFlatSeriesRenderTests {
    @Test("An overview cell with a constant series draws a stroke, never a fill")
    @MainActor
    func constantSeriesHasNoAreaFill() throws {
        for constant in [0.0, 0.42] {
            let values = Array(repeating: constant, count: 40)
            let extent = try magentaExtentBelowLine(values: values)
            let fillPixels = try magentaPixelsBelowLine(values: values)
            let inkPixels = try magentaPixelTotal(values: values)

            print("VITALS_FLAT_SERIES value=\(constant) extent=\(extent) fill=\(fillPixels) ink=\(inkPixels)")
            #expect(extent <= 8, "A constant \(constant) series painted an area fill")
            #expect(inkPixels > 100, "The constant series did not draw its stroke")
        }
    }

    @Test("A one-point wobble still draws a line, not an area fill")
    @MainActor
    func onePointWobbleHasNoAreaFill() throws {
        let values = (0..<40).map { $0.isMultiple(of: 2) ? 0.54 : 0.55 }
        let extent = try magentaExtentBelowLine(values: values)
        let fillPixels = try magentaPixelsBelowLine(values: values)

        print("VITALS_WOBBLE extent=\(extent) fill=\(fillPixels)")
        #expect(extent <= 8, "A one-point wobble painted an area fill")
        #expect(fillPixels == 0, "A one-point wobble painted an area fill")
    }

    @MainActor
    private func cell(values: [Double]) -> some View {
        let now = Date()
        let points = values.enumerated().map { index, value in
            VitalsHistoryPoint(
                timestamp: now.addingTimeInterval(-Double(index)),
                value: value
            )
        }
        let level = values.last ?? 0
        let drawer = HardwareVitalsDrawerView(
            state: VitalsPluginState(),
            store: PurahWorkspaceStore(),
            service: .shared
        )
        return drawer.overviewCell(
            title: "RAM",
            value: "\(Int((level * 100).rounded()))%",
            ratio: level,
            tint: Color(hex: "#FF00FF"),
            detail: "flat",
            history: points,
            spokenLabel: "RAM"
        )
        .frame(width: 200, height: 80)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    @MainActor
    private func bitmap(values: [Double]) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: cell(values: values))
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let scale: CGFloat = 2
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(200 * scale),
                pixelsHigh: Int(80 * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = NSSize(width: 200, height: 80)
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    /// A stroke is a line: the row with the most tinted pixels is the stroke,
    /// and nothing tinted may reach more than a line-width below it. An area
    /// fill would extend to the plot's bottom edge.
    @MainActor
    private func magentaExtentBelowLine(values: [Double]) throws -> Int {
        let rep = try bitmap(values: values)
        var rowCounts = [Int](repeating: 0, count: rep.pixelsHigh)
        var maxY = 0
        let xLimit = Int(Double(rep.pixelsWide) * 0.92)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<xLimit {
                guard isMagenta(rep, x: x, y: y) else { continue }
                rowCounts[y] += 1
                maxY = max(maxY, y)
            }
        }
        // The rail sits near the top; look for the stroke below it.
        let searchStart = Int(Double(rep.pixelsHigh) * 0.30)
        let lineY = (searchStart..<rep.pixelsHigh).max { rowCounts[$0] < rowCounts[$1] } ?? searchStart
        return maxY - lineY
    }

    @MainActor
    private func magentaPixelsBelowLine(values: [Double]) throws -> Int {
        let rep = try bitmap(values: values)
        var rowCounts = [Int](repeating: 0, count: rep.pixelsHigh)
        let xLimit = Int(Double(rep.pixelsWide) * 0.92)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<xLimit where isMagenta(rep, x: x, y: y) {
                rowCounts[y] += 1
            }
        }
        let searchStart = Int(Double(rep.pixelsHigh) * 0.30)
        let lineY = (searchStart..<rep.pixelsHigh).max { rowCounts[$0] < rowCounts[$1] } ?? searchStart
        let startY = min(lineY + 12, rep.pixelsHigh)
        var count = 0
        for y in startY..<rep.pixelsHigh {
            for x in 0..<xLimit where isMagenta(rep, x: x, y: y) {
                count += 1
            }
        }
        return count
    }

    @MainActor
    private func magentaPixelTotal(values: [Double]) throws -> Int {
        let rep = try bitmap(values: values)
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where isMagenta(rep, x: x, y: y) {
                count += 1
            }
        }
        return count
    }

    private func isMagenta(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Bool {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
            return false
        }
        let red = Double(color.redComponent)
        let green = Double(color.greenComponent)
        let blue = Double(color.blueComponent)
        return red > 0.02
            && blue > 0.02
            && abs(red - blue) < 0.08
            && green < min(red, blue) * 0.5
    }
}
