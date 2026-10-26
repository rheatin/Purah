// Tests/PurahCoreTests/PurahMotionPolicyTests.swift
import Testing
import Foundation
import SwiftUI
@testable import PurahCore
@testable import PurahUI

/// Every continuously-animating site now asks this policy instead of checking
/// `accessibilityReduceMotion` on its own — several of them used to forget.
@Suite("Motion Policy Tests")
struct PurahMotionPolicyTests {

    @Test("Ambient animation is allowed only when Reduce Motion is off")
    func testAmbientGating() {
        #expect(PurahMotionPolicy.allowsAmbientAnimation(reduceMotion: false))
        #expect(!PurahMotionPolicy.allowsAmbientAnimation(reduceMotion: true))
    }

    @Test("Reduce Motion collapses spring transitions to a short cross-fade")
    func testAnimationCollapse() {
        let spring = Animation.spring(response: 0.30, dampingFraction: 0.80)
        #expect(PurahMotionPolicy.animation(spring, reduceMotion: false) == spring)
        #expect(
            PurahMotionPolicy.animation(spring, reduceMotion: true)
                == Animation.easeInOut(duration: 0.16)
        )
    }

    /// Source-level guard so a new forever-animation cannot slip in unguarded.
    ///
    /// Two shapes are accepted:
    ///  * `TimelineView(.animation(… paused: <condition>))` — the clock itself
    ///    is pausable, and the condition must mention Reduce Motion.
    ///  * `withAnimation(….repeatForever(…))` — one of the preceding lines must
    ///    short-circuit on `allowsAmbientAnimation` / `reduceMotion`.
    @Test("No animation site reintroduces an unguarded forever loop")
    func testNoUnguardedForeverLoops() throws {
        let uiRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PurahUI")

        let files = try FileManager.default
            .subpathsOfDirectory(atPath: uiRoot.path)
            .filter { $0.hasSuffix(".swift") }

        var violations: [String] = []

        for relativePath in files {
            // The policy's own doc comment mentions these APIs.
            guard !relativePath.hasSuffix("PurahMotionPolicy.swift") else { continue }

            let url = uiRoot.appendingPathComponent(relativePath)
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.components(separatedBy: .newlines)

            for (index, line) in lines.enumerated() {
                // Ignore doc comments; they legitimately name the APIs.
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }

                if line.contains(".repeatForever") {
                    let window = lines[max(0, index - 16)...index].joined(separator: "\n")
                    let isGuarded = window.contains("allowsAmbientAnimation")
                        || window.contains("reduceMotion")
                    if !isGuarded {
                        violations.append("\(relativePath):\(index + 1) forever animation without a Reduce Motion guard")
                    }
                }

                if line.contains("TimelineView(.animation") {
                    let isPausable = line.contains("paused:")
                    let mentionsMotion = line.contains("reduceMotion")
                        || lines[max(0, index - 16)...index].joined(separator: "\n").contains("reduceMotion")
                    if !isPausable || !mentionsMotion {
                        violations.append("\(relativePath):\(index + 1) TimelineView(.animation is not pausable on Reduce Motion")
                    }
                }
            }
        }

        #expect(violations.isEmpty, "\(violations.joined(separator: "\n"))")
    }
}
