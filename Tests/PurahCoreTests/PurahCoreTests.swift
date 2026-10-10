// Tests/PurahCoreTests/PurahCoreTests.swift
import Testing
@testable import PurahCore

@Suite("PurahCore Foundation Tests")
struct PurahCoreTests {
    @Test("Verify PurahCore version identifier")
    func verifyVersion() {
        #expect(SemanticVersion(PurahCore.version) != nil)
        #expect(!PurahCore.version.isEmpty)
    }
}
