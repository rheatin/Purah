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

    @Test("Dragging a lower pod upward squeezes preceding pods with rigid zero overlap")
    func testUpwardSqueeze() {
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

        // 用户将 Pod3 强行向上拖拽至 0.05（试图侵占 Pod1 和 Pod2）
        let solved = SpringConstraintSolver.resolve(
            draggedPodId: "3",
            newRange: .init(start: 0.05, length: 0.20),
            allPods: [p1, p2, p3],
            on: .left
        )

        let edgePods = solved.filter { $0.edge == .left }.sorted { $0.range.start < $1.range.start }

        // 验证绝对零重叠：每一项的 end 必须小于等于下一项的 start
        for i in 0..<(edgePods.count - 1) {
            #expect(edgePods[i].range.end <= edgePods[i + 1].range.start + 0.0001,
                    "Pod \(edgePods[i].id) end (\(edgePods[i].range.end)) overlaps next start (\(edgePods[i + 1].range.start))")
        }

        // 验证 Pod3 绝不能骑到 Pod1 和 Pod2 的头上
        let p3Solved = edgePods.first { $0.id == "3" }!
        let p2Solved = edgePods.first { $0.id == "2" }!
        let p1Solved = edgePods.first { $0.id == "1" }!

        #expect(p3Solved.range.start >= p2Solved.range.end - 0.0001)
        #expect(p2Solved.range.start >= p1Solved.range.end - 0.0001)

        // 验证所有 Pod 均大于各自的 minLength
        for pod in edgePods {
            #expect(pod.range.length >= pod.minLength - 0.001)
        }

        // 验证顶部贴边安全利用率：Pod1 应该被推挤到接近 0.01 的天花板
        #expect(p1Solved.range.start >= SpringConstraintSolver.defaultBounds.lowerBound)
        #expect(p1Solved.range.start <= 0.05)
    }
}
