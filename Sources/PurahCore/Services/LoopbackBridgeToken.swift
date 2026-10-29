// Sources/PurahCore/Services/LoopbackBridgeToken.swift
import Foundation

/// A per-launch secret for the loopback endpoints Purah exposes to tools it
/// started. Both bridges need one; `SystemRandomNumberGenerator` is the
/// platform CSPRNG.
enum LoopbackBridgeToken {
    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<24)
            .map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }
            .joined()
    }
}
