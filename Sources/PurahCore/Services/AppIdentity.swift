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

    /// Apps a person could plausibly be "in", for the whitelist picker.
    ///
    /// `.regular` only: agents, background helpers and login items have bundle
    /// ids but no window anyone could be working in, and listing them would
    /// bury the ten apps that matter under a hundred that cannot be frontmost.
    /// Deduplicated by bundle id because several instances of one app are still
    /// one app to the person choosing.
    @MainActor
    public static func runningAppCandidates(excluding excludedBundleId: String? = nil) -> [AppCandidate] {
        let own = excludedBundleId ?? Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var candidates: [AppCandidate] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleId = app.bundleIdentifier,
                  bundleId != own,
                  seen.insert(bundleId).inserted else { continue }
            candidates.append(AppCandidate(
                bundleId: bundleId,
                name: app.localizedName ?? displayName(forBundleId: bundleId)
            ))
        }
        return candidates.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

/// One app offered in the whitelist picker.
public struct AppCandidate: Sendable, Equatable, Identifiable {
    public let bundleId: String
    public let name: String

    public var id: String { bundleId }

    public init(bundleId: String, name: String) {
        self.bundleId = bundleId
        self.name = name
    }
}
