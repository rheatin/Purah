// Tests/PurahCoreTests/SpringConstraintSolverTests.swift
import Testing
@testable import PurahCore

@Suite("Spring Constraint Solver Tests")
struct SpringConstraintSolverTests {
    @Test("Dragging a pod downward compresses and pushes successor pods without overlap")
    func testDownwardPush() {
        let p1 = SlotPod(
            id: "1", name: "Pod1", systemIcon: "1.circle", edge: .left,
            range: .init(start: 0.20, length: 0.20), ambientStyle: .ghostDot,
            preferredZone: .goldenAction, ergonomicWeight: 30, minLength: 0.10
        )
        let p2 = SlotPod(
            id: "2", name: "Pod2", systemIcon: "2.circle", edge: .left,
            range: .init(start: 0.45, length: 0.20), ambientStyle: .ghostDot,
            preferredZone: .goldenAction, ergonomicWeight: 30, minLength: 0.10
        )
        let p3 = SlotPod(
            id: "3", name: "Pod3", systemIcon: "3.circle", edge: .left,
            range: .init(start: 0.70, length: 0.20), ambientStyle: .ghostDot,
            preferredZone: .quickFlick, ergonomicWeight: 30, minLength: 0.10
        )

        // 用户将 Pod1 向下拖长或下移到 0.20~0.52，侵占 Pod2 空间
        let solved = SpringConstraintSolver.resolve(
            draggedPodId: "1",
            newRange: .init(start: 0.20, length: 0.32),
            allPods: [p1, p2, p3],
            on: .left
        )

        let edgePods = solved.filter { $0.edge == .left }.sorted { $0.range.start < $1.range.start }

        // 验证绝无重叠 (No Overlap Guarantee)
        for i in 0..<(edgePods.count - 1) {
            #expect(edgePods[i].range.end <= edgePods[i + 1].range.start + 0.0001)
        }
        // 验证 Pod2 被弹性向后推挤
        #expect(edgePods[1].range.start >= edgePods[0].range.end)
        // 验证均大于 minLength
        for pod in edgePods {
            #expect(pod.range.length >= pod.minLength - 0.001)
        }
    }
}
