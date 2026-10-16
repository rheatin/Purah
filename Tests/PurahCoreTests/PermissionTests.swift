// Tests/PurahCoreTests/PermissionTests.swift
import Testing
import EventKit
@testable import PurahCore

@Suite("Permission and System Access Tests")
@MainActor
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
        #expect(manager.musicStatus == .standardCapability)
        #expect(manager.musicStatus.isGranted == true)
    }

    @Test("Capability enforcement guards undeclared capabilities with strict error")
    func testCapabilityEnforcement() {
        let manager = PermissionManager()
        let declared: [PluginPermission] = [.machTelemetry, .fileSystem]

        // Undeclared permission throws .permissionNotDeclared
        #expect(throws: PurahCapabilityError.self) {
            try manager.enforceCapability(pluginId: "vitals", permission: .shellExecution, declaredIn: declared)
        }

        // Declared standard capability succeeds without error
        #expect(throws: Never.self) {
            try manager.enforceCapability(pluginId: "vitals", permission: .machTelemetry, declaredIn: declared)
        }
    }
}
