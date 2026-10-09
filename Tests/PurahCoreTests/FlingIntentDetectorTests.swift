// Tests/PurahCoreTests/FlingIntentDetectorTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Fling Intent & Dwell Engine Tests")
struct FlingIntentDetectorTests {
    @Test("Rapid vertical movement suppresses drawer popup")
    func testVerticalFlingSuppression() {
        let detector = FlingIntentDetector()
        // Vy = 1200 pt/s, Vx = 80 pt/s (rapid vertical swipe along edge, e.g. moving towards window buttons)
        let intent = detector.evaluate(
            point: CGPoint(x: 2.0, y: 300.0),
            velocity: CGPoint(x: 80.0, y: 1200.0),
            edge: .left,
            edgeMargin: 8.0
        )
        #expect(intent == .verticalFlingSuppressed)
    }

    @Test("Horizontal impact with low vertical speed qualifies for candidate dwell")
    func testCandidateDwell() {
        let detector = FlingIntentDetector()
        // Vx = -400 pt/s (moving directly towards left bezel), Vy = 50 pt/s
        let intent = detector.evaluate(
            point: CGPoint(x: 1.0, y: 400.0),
            velocity: CGPoint(x: -400.0, y: 50.0),
            edge: .left,
            edgeMargin: 8.0
        )
        #expect(intent == .candidateDwell)
    }

    @Test("Dwell timer triggers only after exceeding threshold")
    func testDwellTiming() {
        var tracker = DwellTracker(threshold: 0.16) // 160ms
        let now = Date()

        // Initial entry is in dwelling state
        let state1 = tracker.update(podId: "cal", intent: .candidateDwell, timestamp: now)
        #expect(state1 == .dwelling(podId: "cal", progress: 0.0))

        // Not triggered yet at 80ms
        let state2 = tracker.update(podId: "cal", intent: .candidateDwell, timestamp: now.addingTimeInterval(0.08))
        if case .dwelling(let podId, let progress) = state2 {
            #expect(podId == "cal")
            #expect(abs(progress - 0.5) < 0.01)
        } else {
            #expect(Bool(false), "Expected dwelling state")
        }

        // Triggered after 170ms exceeding threshold
        let state3 = tracker.update(podId: "cal", intent: .candidateDwell, timestamp: now.addingTimeInterval(0.17))
        #expect(state3 == .triggered(podId: "cal"))
    }

    @Test("EdgeTriggerSensitivity presets and dwell threshold values")
    @MainActor
    func testEdgeTriggerSensitivity() {
        let agile = EdgeTriggerSensitivity.agile
        let balanced = EdgeTriggerSensitivity.balanced
        let cautious = EdgeTriggerSensitivity.cautious

        #expect(agile.initialDwellSeconds == 0.08)
        #expect(balanced.initialDwellSeconds == 0.15)
        #expect(cautious.initialDwellSeconds == 0.40)

        #expect(agile.deepEdgeDwellSeconds < balanced.deepEdgeDwellSeconds)
        #expect(balanced.deepEdgeDwellSeconds < cautious.deepEdgeDwellSeconds)

        let store = PurahWorkspaceStore()
        store.edgeTriggerSensitivity = .cautious
        store.savePersistentState()

        #expect(agile.exitGraceDurationSeconds == 0.18)
        #expect(balanced.exitGraceDurationSeconds == 0.28)
        #expect(cautious.exitGraceDurationSeconds == 0.40)

        #expect(agile.overshootCatchCorridor == 35.0)
        #expect(balanced.overshootCatchCorridor == 50.0)
        #expect(cautious.overshootCatchCorridor == 65.0)

        store.applySensitivityPreset(.cautious)
        #expect(store.activeExitGraceSeconds == 0.40)
        #expect(store.activeCatchCorridor == 65.0)

        store.edgeTriggerSensitivity = .custom
        store.customExitGraceMs = 350.0
        store.customCatchCorridorPt = 55.0
        #expect(store.activeExitGraceSeconds == 0.35)
        #expect(store.activeCatchCorridor == 55.0)
        store.savePersistentState()

        let reloaded = PurahWorkspaceStore()
        #expect(reloaded.edgeTriggerSensitivity == .custom)

        // Teardown cleanup
        UserDefaults.standard.removeObject(forKey: "purah.edgeTriggerSensitivity")
        UserDefaults.standard.removeObject(forKey: "purah.customInitialDwellMs")
        UserDefaults.standard.removeObject(forKey: "purah.customExitGraceMs")
        UserDefaults.standard.removeObject(forKey: "purah.customCatchCorridorPt")
    }
}
