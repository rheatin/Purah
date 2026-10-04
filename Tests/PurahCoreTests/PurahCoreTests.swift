// Tests/PurahCoreTests/PurahCoreTests.swift
import Testing
@testable import PurahCore

@Suite("PurahCore Foundation Tests")
struct PurahCoreTests {
    @Test("Verify PurahCore version identifier")
    func verifyVersion() {
        #expect(PurahCore.version == "2.0.0")
    }
}
