import AppKit
import SwiftUI
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("Vitals drawer render", .serialized)
@MainActor
struct VitalsDrawerRenderTests {
    private let size = CGSize(width: 400, height: 340)
    private let outputDirectory = URL(fileURLWithPath: "/tmp/purah-vitals-renders", isDirectory: true)

    @Test("Every render seam produces a non-empty drawer image")
    func renderSeamsProduceDrawerImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-vitals-render-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "vitals_render_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        let storage = ScopedPluginStorage(pluginId: "vitals-render", defaults: defaults)
        let state = VitalsPluginState(storage: storage)
        let store = PurahWorkspaceStore(userDefaults: defaults)
        let service = HardwareVitalsService(
            storageDirectory: directory,
            processNetworkSampler: ProcessNetworkSampler(runner: { nil }),
            diskIOProbe: {
                (
                    readBytesPerSec: 0,
                    writeBytesPerSec: 0,
                    readTotalGB: 0,
                    writeTotalGB: 0
                )
            },
            batteryProbe: {
                (
                    level: 80,
                    isCharging: false,
                    source: "Battery",
                    healthPercent: 92,
                    cycleCount: 143,
                    temperatureCelsius: 31,
                    isPresent: true,
                    voltageVolts: 12.2,
                    chargeWatts: -8,
                    timeRemainingMinutes: 240,
                    condition: "Normal",
                    systemWatts: 8,
                    systemVolts: 12.2,
                    systemAmps: 0.66,
                    adapterWatts: 0,
                    maxCapacityMAh: 5_000,
                    designCapacityMAh: 5_500
                )
            }
        )
        defer { service.stopMonitoring() }
        service.isDrawerVisible = true
        service.refreshMetrics(includeProcesses: false)

        let now = Date()
        let twelveHours = points(span: 43_200, step: 720, now: now) {
            0.18 + 0.62 * abs(sin($0 * 0.7))
        }
        let states = points(span: 43_200, step: 600, now: now) {
            Double(Int(abs($0) / 600) % 3)
        }
        let fiveMinutes = points(span: 300, step: 1, now: now) {
            0.25 + 0.5 * abs(sin($0 * 0.05))
        }
        let oneHour = points(span: 3_600, step: 10, now: now) {
            0.2 + 0.55 * abs(sin($0 * 0.01))
        }
        let short = points(span: 90, step: 3, now: now) {
            0.1 + 0.8 * abs(sin($0 * 0.2))
        }
        let shortStates = points(span: 1_800, step: 600, now: now) {
            Double(Int(abs($0) / 600) % 3)
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        state.dashboardTab = .overview
        let overview = HardwareVitalsDrawerView(
            state: state,
            store: store,
            service: service,
            historyOverride: [
                .cpu: fiveMinutes,
                .gpu: fiveMinutes,
                .ram: fiveMinutes,
                .power: twelveHours
            ],
            batteryStateOverride: states
        )
        let overviewBitmap = try render(overview, named: "overview-12h.png")
        #expect(inkPixelCount(overviewBitmap) > 500)

        state.dashboardTab = .compute
        let computePlain = HardwareVitalsDrawerView(
            state: state,
            store: store,
            service: service,
            historyOverride: [.cpu: oneHour, .gpu: oneHour, .ram: oneHour]
        )
        let computeHover = HardwareVitalsDrawerView(
            state: state,
            store: store,
            service: service,
            historyOverride: [.cpu: oneHour, .gpu: oneHour, .ram: oneHour],
            columnHoverPreviews: [.cpu: 10]
        )
        let plainBitmap = try render(computePlain, named: nil)
        let hoverBitmap = try render(computeHover, named: "compute-hover.png")
        #expect(inkPixelCount(hoverBitmap) > 500)
        #expect(differingPixelCount(plainBitmap, hoverBitmap) > 100)

        state.dashboardTab = .power
        let power = HardwareVitalsDrawerView(
            state: state,
            store: store,
            service: service,
            historyOverride: [.power: twelveHours],
            batteryHoverPreview: 2,
            batteryStateOverride: states
        )
        let powerBitmap = try render(power, named: "power-hover.png")
        #expect(inkPixelCount(powerBitmap) > 500)

        state.dashboardTab = .overview
        let shortOverview = HardwareVitalsDrawerView(
            state: state,
            store: store,
            service: service,
            historyOverride: [
                .cpu: short,
                .gpu: short,
                .ram: short,
                .power: short
            ],
            batteryStateOverride: shortStates
        )
        let shortBitmap = try render(shortOverview, named: "overview-short.png")
        #expect(inkPixelCount(shortBitmap) > 500)
    }

    private func points(
        span: TimeInterval,
        step: TimeInterval,
        now: Date,
        value: (TimeInterval) -> Double
    ) -> [VitalsHistoryPoint] {
        stride(from: -span, through: 0, by: step).map { offset in
            VitalsHistoryPoint(
                timestamp: now.addingTimeInterval(offset),
                value: value(offset)
            )
        }
    }

    private func render(_ view: some View, named name: String?) throws -> NSBitmapImageRep {
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .environment(\.colorScheme, .dark)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let scale: CGFloat = 2
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int((size.width * scale).rounded()),
                pixelsHigh: Int((size.height * scale).rounded()),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

        if let name {
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: outputDirectory.appendingPathComponent(name))
        }
        return bitmap
    }

    private func inkPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                let brightness = Double(color.redComponent)
                    + Double(color.greenComponent)
                    + Double(color.blueComponent)
                if Double(color.alphaComponent) > 0.1, brightness > 0.12 {
                    count += 1
                }
            }
        }
        return count
    }

    private func differingPixelCount(
        _ first: NSBitmapImageRep,
        _ second: NSBitmapImageRep
    ) -> Int {
        guard first.pixelsWide == second.pixelsWide,
              first.pixelsHigh == second.pixelsHigh else { return 0 }
        var count = 0
        for y in 0..<first.pixelsHigh {
            for x in 0..<first.pixelsWide {
                guard let a = first.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let b = second.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                let delta = abs(a.redComponent - b.redComponent)
                    + abs(a.greenComponent - b.greenComponent)
                    + abs(a.blueComponent - b.blueComponent)
                if delta > 0.05 {
                    count += 1
                }
            }
        }
        return count
    }
}
