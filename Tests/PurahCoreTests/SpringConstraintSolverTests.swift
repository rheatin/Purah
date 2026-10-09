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

        // User drags Pod1 downward into 0.20~0.52, encroaching on Pod2 space
        let solved = SpringConstraintSolver.resolve(
            draggedPodId: "1",
            newRange: .init(start: 0.20, length: 0.32),
            allPods: [p1, p2, p3],
            on: .left
        )

        let edgePods = solved.filter { $0.edge == .left }.sorted { $0.range.start < $1.range.start }

        // Verify zero-overlap invariant
        for i in 0..<(edgePods.count - 1) {
            #expect(edgePods[i].range.end <= edgePods[i + 1].range.start + 0.0001)
        }
        // Verify Pod2 is elastically pushed downward
        #expect(edgePods[1].range.start >= edgePods[0].range.end)
        // Verify all lengths satisfy minLength
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

        // User forcefully drags Pod3 upward to 0.05 encroaching on Pod1 and Pod2
        let solved = SpringConstraintSolver.resolve(
            draggedPodId: "3",
            newRange: .init(start: 0.05, length: 0.20),
            allPods: [p1, p2, p3],
            on: .left
        )

        let edgePods = solved.filter { $0.edge == .left }.sorted { $0.range.start < $1.range.start }

        // Verify strict zero-overlap: each item end must be <= next start
        for i in 0..<(edgePods.count - 1) {
            #expect(edgePods[i].range.end <= edgePods[i + 1].range.start + 0.0001,
                    "Pod \(edgePods[i].id) end (\(edgePods[i].range.end)) overlaps next start (\(edgePods[i + 1].range.start))")
        }

        // Verify Pod3 never leapfrogs preceding pods
        let p3Solved = edgePods.first { $0.id == "3" }!
        let p2Solved = edgePods.first { $0.id == "2" }!
        let p1Solved = edgePods.first { $0.id == "1" }!

        #expect(p3Solved.range.start >= p2Solved.range.end - 0.0001)
        #expect(p2Solved.range.start >= p1Solved.range.end - 0.0001)

        // Verify all pods maintain respective minLengths
        for pod in edgePods {
            #expect(pod.range.length >= pod.minLength - 0.001)
        }

        // Verify top boundary safety: Pod1 should be pushed near the safe top ceiling
        #expect(p1Solved.range.start >= SpringConstraintSolver.defaultBounds.lowerBound)
        #expect(p1Solved.range.start <= 0.05)
    }
}
