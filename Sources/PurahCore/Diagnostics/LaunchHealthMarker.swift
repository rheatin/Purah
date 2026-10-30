// Sources/PurahCore/Diagnostics/LaunchHealthMarker.swift
import Foundation

/// Records that a run is in progress, so the next launch can tell a clean quit
/// from a crash, a force quit, or a power loss.
///
/// Nothing in the app notices an abnormal exit: the process simply stops
/// existing, and the next launch looks exactly like every other one. A marker
/// written at launch and removed on `applicationWillTerminate` turns that
/// silence into one sentence the person can act on — which is the only signal
/// available without shipping a crash reporter.
public enum LaunchHealthMarker {
    public static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Purah", isDirectory: true)
            .appendingPathComponent("running.marker")
    }

    /// Leaves the marker for this run and reports whether the previous one
    /// failed to remove it.
    ///
    /// - Returns: `true` when the last run never reached a clean exit.
    @discardableResult
    public static func noteLaunch(at location: URL? = nil) -> Bool {
        let fileManager = FileManager.default
        let target = location ?? url
        let previousRunEndedAbruptly = fileManager.fileExists(atPath: target.path)
        try? fileManager.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data().write(to: target)
        return previousRunEndedAbruptly
    }

    public static func noteCleanExit(at location: URL? = nil) {
        try? FileManager.default.removeItem(at: location ?? url)
    }
}
