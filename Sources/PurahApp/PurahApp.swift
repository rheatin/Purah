// Sources/PurahApp/PurahApp.swift
import AppKit
import PurahCore

@main
struct PurahAppEntry {
    static func main() {
        // Enforce single instance: if another instance is already running, activate it and exit immediately
        guard SingleInstanceGuard.enforce() else {
            exit(0)
        }

        // Must run before anything reads UserDefaults — including the store,
        // which this file creates inside `AppDelegate()`. Copying settings from
        // a retired bundle identifier here keeps the identifier change from
        // wiping the user's pod layout on first launch of the new build.
        BundleIdentityMigration.migrateIfNeeded(into: .standard)

        // Before the app does anything that can fail: a crash during startup is
        // exactly the kind no window survives to report.
        CrashReporter.install()

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
