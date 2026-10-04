// Tests/PurahCoreTests/PermissionTests.swift
import Testing
import EventKit
@testable import PurahCore

@Suite("Permission and System Access Tests")
struct PermissionTests {
    @Test("PermissionManager converts EKAuthorizationStatus correctly")
    func testStatusConversion() {
        let notDetermined = PermissionManager.status(from: .notDetermined)
        #expect(notDetermined == .notDetermined)

        let denied = PermissionManager.status(from: .denied)
        #expect(denied == .denied)

        let restricted = PermissionManager.status(from: .restricted)
        #expect(restricted == .restricted)

        if #available(macOS 14.0, *) {
            let fullAccess = PermissionManager.status(from: .fullAccess)
            #expect(fullAccess == .authorized)
        }
    }

    @Test("Music permission is naturally granted without TCC calendar restrictions")
    func testMusicStatus() {
        let manager = PermissionManager()
        #expect(manager.musicStatus == .authorized)
    }
}
