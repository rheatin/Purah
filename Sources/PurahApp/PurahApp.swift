// Sources/PurahApp/PurahApp.swift
import AppKit

@main
struct PurahAppEntry {
    static func main() {
        // Enforce single instance: if another instance is already running, activate it and exit immediately
        guard SingleInstanceGuard.enforce() else {
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
