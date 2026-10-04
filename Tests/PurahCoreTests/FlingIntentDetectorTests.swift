// Tests/PurahCoreTests/FlingIntentDetectorTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Fling Intent & Dwell Engine Tests")
struct FlingIntentDetectorTests {
    @Test("Rapid vertical movement suppresses drawer popup")
    func testVerticalFlingSuppression() {
        let detector = FlingIntentDetector()
        // Vy = 1200 pt/s, Vx = 80 pt/s (快速纵向滑过边缘，例如去点关闭按钮)
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
        // Vx = -400 pt/s (向左冲撞左屏幕边), Vy = 50 pt/s
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
        let tracker = DwellTracker(threshold: 0.16) // 160ms
        let now = Date()

        // 刚进入时处于 dwelling 状态
        let state1 = tracker.update(podId: "cal", intent: .candidateDwell, timestamp: now)
        #expect(state1 == .dwelling(podId: "cal", progress: 0.0))

        // 80ms 后尚未触发
        let state2 = tracker.update(podId: "cal", intent: .candidateDwell, timestamp: now.addingTimeInterval(0.08))
        if case .dwelling(let podId, let progress) = state2 {
            #expect(podId == "cal")
            #expect(abs(progress - 0.5) < 0.01)
        } else {
            #expect(Bool(false), "Expected dwelling state")
        }

        // 170ms 后触发抽屉展开
        let state3 = tracker.update(podId: "cal", intent: .candidateDwell, timestamp: now.addingTimeInterval(0.17))
        #expect(state3 == .triggered(podId: "cal"))
    }
}
