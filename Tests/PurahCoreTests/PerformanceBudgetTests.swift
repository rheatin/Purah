// Tests/PurahCoreTests/PerformanceBudgetTests.swift
import Testing
import Foundation
@testable import PurahCore

/// Latency and allocation budgets for the paths that run while the cursor is
/// moving.
///
/// These exist because the app makes specific performance promises —
/// `compactCanvasWidth` saves framebuffer memory, edge triggers respond within a
/// dwell window, 60/120 FPS visuals — and none of them were guarded. Background
/// apps degrade gradually: nobody files a bug for "the rail feels slightly
/// heavy now", so a budget is the only thing that notices.
///
/// Budgets are set generously (roughly 10x the measured figure on a developer
/// Mac). The intent is to catch an order-of-magnitude regression — an accidental
/// O(n²), a synchronous disk read on the hot path — not to police a few
/// microseconds of noise. A tight budget on shared CI hardware fails randomly
/// and gets deleted, which is worse than no budget at all.
@Suite("Performance Budget Tests", .serialized)
struct PerformanceBudgetTests {

    private static func makePods(count: Int) -> [SlotPod] {
        (0..<count).map { idx in
            SlotPod(
                id: "pod-\(idx)",
                nameKey: "pod.\(idx)",
                defaultName: "Pod \(idx)",
                systemIcon: "circle",
                edge: idx % 2 == 0 ? .left : .right,
                range: NormalizedRange(start: Double(idx) / Double(count), length: 0.08),
                ambientStyle: .ghostDot,
                preferredZone: .goldenAction,
                ergonomicWeight: 1.0,
                isEnabled: true
            )
        }
    }

    /// Median of a handful of runs, after a warm-up.
    ///
    /// A single sample is too noisy on a machine doing anything else; the median
    /// of five ignores one pathological scheduling hiccup.
    private static func measure(_ runs: Int = 5, _ body: () -> Void) -> Double {
        body() // warm-up: pays for first-call lazy caches
        var samples: [Double] = []
        for _ in 0..<runs {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    @Test("Layout of a full rail stays well under a frame budget")
    func testLayoutLatency() {
        // 12 pods is more than the rails ever hold (the product caps at the
        // ergonomic minimums), so this is already a worst case.
        let pods = Self.makePods(count: 12)

        let ms = Self.measure {
            _ = ErgonomicAutoLayoutEngine.layout(pods: pods, on: .left)
            _ = ErgonomicAutoLayoutEngine.layout(pods: pods, on: .right)
        }

        // A layout runs on every resize and every breathing tick. At 60 FPS the
        // entire frame is 16.7ms; layout must be a small fraction of that.
        #expect(ms < 4.0, "Layout of 12 pods took \(ms)ms, budget is 4ms")
        print("Layout 12 pods: \(ms)ms")
    }

    @Test("Layout cost grows linearly, not quadratically")
    func testLayoutScaling() {
        let small = Self.makePods(count: 4)
        let large = Self.makePods(count: 32)

        let smallMs = Self.measure {
            _ = ErgonomicAutoLayoutEngine.layout(pods: small, on: .left)
        }
        let largeMs = Self.measure {
            _ = ErgonomicAutoLayoutEngine.layout(pods: large, on: .left)
        }

        // 8x the pods. Linear would be 8x; the budget allows 30x so that
        // constant overhead on a tiny sample cannot trip it, while an O(n²)
        // (which would be ~64x) still fails.
        let ratio = largeMs / max(smallMs, 0.0001)
        #expect(ratio < 30.0,
                "8x more pods cost \(String(format: "%.1f", ratio))x the time — superlinear")
        print("Layout scaling: 4 pods \(smallMs)ms, 32 pods \(largeMs)ms (ratio \(String(format: "%.1f", ratio))x)")
    }

    @Test("Dragging a pod re-solves the rail cheaply")
    func testDragSolveLatency() {
        // This runs on every mouse-drag frame while the user sculpts a rail.
        let pods = Self.makePods(count: 10)
        let draggedId = try! #require(pods.first(where: { $0.edge == .left })?.id)

        let ms = Self.measure {
            _ = SpringConstraintSolver.resolve(
                draggedPodId: draggedId,
                newRange: NormalizedRange(start: 0.30, length: 0.12),
                allPods: pods,
                on: .left
            )
        }
        #expect(ms < 2.0, "Drag re-solve took \(ms)ms, budget is 2ms")
        print("Drag re-solve (10 pods): \(ms)ms")
    }

    @Test("Building the diagnostics report stays readable, not a hang")
    @MainActor
    func testDiagnosticReportLatency() {
        // This runs when the user opens the Diagnostics pane. It walks 200 log
        // entries and reads the crash log; if it ever started doing real work
        // per entry, the pane would appear frozen.
        for i in 0..<300 {
            DiagnosticLogger.shared.info("Perf", "synthetic entry \(i)")
        }

        let ms = Self.measure {
            _ = DiagnosticLogger.shared.generateReport()
        }
        #expect(ms < 50.0, "Report generation took \(ms)ms, budget is 50ms")
        print("Diagnostics report: \(ms)ms")
    }
}
