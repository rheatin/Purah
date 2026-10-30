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

    /// `requestAccess(for:)` used to end in `default: return true`, so any
    /// capability added later was silently "granted" and never prompted. That
    /// switch is exhaustive now; this pins the other half — the set of
    /// capabilities that legitimately need no prompt. Adding a case and
    /// forgetting it lands it here, where it fails loudly.
    @Test("Only the ambient capabilities report 'no prompt needed'")
    func testStandardCapabilitiesArePinned() {
        let manager = PermissionManager()
        let unprompted = PluginPermission.allCases.filter { manager.status(for: $0) == .standardCapability }
        #expect(Set(unprompted) == [.appleMusic, .shellExecution, .machTelemetry, .fileSystem, .pasteboard])
    }

    @Test("Microphone is gated by TCC rather than treated as ambient")
    func testMicrophoneIsGated() {
        let manager = PermissionManager()
        #expect(manager.status(for: .microphone) != .standardCapability)
        #expect(PluginPermission.microphone.isTCCRestricted)
        #expect(PluginPermission.microphone.privacySettingsAnchor == "Privacy_Microphone")
    }

    /// A plugin built against a newer Purah may name a capability this build
    /// has never seen. Decoding strictly failed the whole manifest, so the
    /// plugin vanished on install with no explanation.
    @Test("An unknown capability name is kept, not rejected")
    func testUnknownCapabilityIsKept() throws {
        let calendar = try #require(PurahPluginManifest.builtInCatalog.first { $0.id == "calendar" })
        let encoded = try JSONEncoder().encode(calendar)
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["permissions"] = ["Calendar", "Camera"]

        let manifest = try JSONDecoder().decode(
            PurahPluginManifest.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(manifest.permissions == [.calendar])
        #expect(manifest.unsupportedPermissions == ["Camera"])
    }
}
