// Sources/PurahCore/Services/AppIdentity.swift
import AppKit

/// Turns a bundle identifier into something a person can read.
///
/// A whitelist of raw bundle ids is unusable in settings — `so.stencil.tern`
/// means nothing until it says "Tern" — and the name must survive the app not
/// being installed, so the identifier is the fallback rather than an error.
public enum AppIdentity {
    @MainActor
    public static func displayName(forBundleId bundleId: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url) {
            let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            if let found = (display ?? name), !found.isEmpty {
                return found
            }
        }
        // A rule for an app that is not installed is still a valid rule; it just
        // has no name to show.
        return bundleId
    }

    /// The running app with this bundle id, if it is running at all.
    @MainActor
    public static func runningApp(forBundleId bundleId: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    /// The app's own icon, for a whitelist row.
    ///
    /// A generic SF Symbol next to an app name is worse than the real icon: it
    /// does not help tell a list of apps apart and, when the symbol does not
    /// exist on the running system, renders as an empty square.
    @MainActor
    public static func icon(forBundleId bundleId: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
