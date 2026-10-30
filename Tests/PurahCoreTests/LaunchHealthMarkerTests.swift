// Tests/PurahCoreTests/LaunchHealthMarkerTests.swift
import Testing
import Foundation
@testable import PurahCore

/// The app has no crash reporter. A marker file is the whole mechanism behind
/// "Purah closed unexpectedly last time" — it has to survive a process that
/// never ran its cleanup, and disappear when one did.
@Suite("Launch Health Marker Tests")
struct LaunchHealthMarkerTests {

    private func temporaryMarker() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-marker-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("running.marker")
    }

    @Test("A first launch reports no failure and leaves a marker")
    func firstLaunchIsClean() throws {
        let marker = temporaryMarker()
        defer { try? FileManager.default.removeItem(at: marker.deletingLastPathComponent()) }

        #expect(LaunchHealthMarker.noteLaunch(at: marker) == false)
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("A clean exit lets the next launch report no failure")
    func cleanExitClearsTheMarker() {
        let marker = temporaryMarker()
        defer { try? FileManager.default.removeItem(at: marker.deletingLastPathComponent()) }

        LaunchHealthMarker.noteLaunch(at: marker)
        LaunchHealthMarker.noteCleanExit(at: marker)
        #expect(LaunchHealthMarker.noteLaunch(at: marker) == false)
    }

    @Test("A marker left behind means the last run never finished")
    func leftoverMarkerReportsTheCrash() {
        let marker = temporaryMarker()
        defer { try? FileManager.default.removeItem(at: marker.deletingLastPathComponent()) }

        LaunchHealthMarker.noteLaunch(at: marker)
        // No `noteCleanExit`: the process died before it could run.
        #expect(LaunchHealthMarker.noteLaunch(at: marker) == true)
    }
}
