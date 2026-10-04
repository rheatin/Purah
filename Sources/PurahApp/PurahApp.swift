// Sources/PurahApp/PurahApp.swift
import AppKit

@main
struct PurahAppEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
