// Tests/PurahCoreTests/PurahCoreTests.swift
import Testing
@testable import PurahCore

@Suite("PurahCore Foundation Tests")
struct PurahCoreTests {
    @Test("Verify PurahCore version identifier")
    func verifyVersion() {
        #expect(PurahCore.version == "0.1.1")
    }
}
