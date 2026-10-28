// Sources/PurahCore/Services/AppProfileSwitchService.swift
import AppKit
import Foundation
import Observation

/// The app a whitelist edit is about, with a name to show for it.
public struct RememberedApp: Sendable, Equatable {
    public let bundleId: String
    public let name: String

    public init(bundleId: String, name: String) {
        self.bundleId = bundleId
        self.name = name
    }
}

/// Notices which application is frontmost and switches to the profile that
/// app's whitelist entry points at.
///
/// The unit of adaptation is the context profile, not a per-app rule: an app is
/// either on a profile's whitelist or it is not, and everything off the list
/// gets the default profile. That way "Xcode needs Terminal and Vitals" and
/// "Café needs nothing but Music" are the same kind of statement, expressed
/// with the same editing tools the person already uses for the rails.
///
/// It never resizes a pod, reorders within a page, or mounts plugins on its
/// own. Those come from the profile the person chose — this class only decides
/// *which* profile is in force.
@Observable
@MainActor
public final class AppProfileSwitchService {
    public static let shared = AppProfileSwitchService()

    /// The frontmost application's bundle id, or nil when Purah itself is
    /// frontmost (its own settings window should not change the layout).
    public private(set) var activeBundleId: String?
    public private(set) var activeAppName: String?

    /// The last application that was frontmost *other than Purah*.
    ///
    /// `activeBundleId` is deliberately nil while Purah is frontmost, but the
    /// settings window needs to answer "what does the app I was just in get" —
    /// and at that moment Purah is the active app, so asking
    /// `NSRunningApplication.isActive` finds nothing. This remembers the last
    /// real answer instead.
    public private(set) var lastExternalBundleId: String?
    public private(set) var lastExternalAppName: String?

    /// The profile the frontmost app resolves to right now, whether or not it
    /// could be applied. `nil` means "no whitelist entry and no default".
    public private(set) var resolvedProfileId: UUID?

    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?
    @ObservationIgnored nonisolated(unsafe) private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var pendingTask: Task<Void, Never>?

    /// Debounce window. Activation notifications arrive in bursts when switching
    /// Spaces or when a dialog takes focus momentarily; applying a layout on
    /// each one would make the rail flicker through intermediate states.
    @ObservationIgnored private var debounceMilliseconds: Int = 250

    public init(debounceMilliseconds: Int = 250) {
        self.debounceMilliseconds = debounceMilliseconds
    }

    deinit {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    public func bindStore(_ store: PurahWorkspaceStore) {
        boundStore = store
        startObserving()
        // Catch up with whatever is already frontmost. Without this a switch
        // only took effect after the user switched away and back, which reads
        // as "the feature does nothing".
        evaluateCurrentApp()
    }

    private func startObserving() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let bundleId = app.bundleIdentifier
            let name = app.localizedName
            Task { @MainActor [weak self] in
                self?.scheduleEvaluation(bundleId: bundleId, name: name)
            }
        }
    }

    private func scheduleEvaluation(bundleId: String?, name: String?) {
        pendingTask?.cancel()
        let delay = debounceMilliseconds
        pendingTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(delay))
            }
            guard !Task.isCancelled else { return }
            self?.evaluate(bundleId: bundleId, name: name)
        }
    }

    public func evaluateCurrentApp() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        evaluate(bundleId: frontmost?.bundleIdentifier, name: frontmost?.localizedName)
    }

    /// Resolves an app to a profile and asks the store to switch to it.
    ///
    /// Exposed for tests and for the settings preview, which needs to answer
    /// "what would activating this app do" without activating it.
    public func evaluate(bundleId: String?, name: String?) {
        guard let store = boundStore else { return }

        // Purah's own settings window activating must not rearrange anything:
        // the user is configuring the feature, and watching the layout jump
        // while they pick a profile would be actively confusing.
        let isSelf = bundleId == Bundle.main.bundleIdentifier
        activeBundleId = isSelf ? nil : bundleId
        activeAppName = isSelf ? nil : name
        if !isSelf, let bundleId {
            lastExternalBundleId = bundleId
            lastExternalAppName = name
        }

        guard store.isAppProfileSwitchingEnabled, let resolvedId = resolvedProfileId(for: activeBundleId, in: store) else {
            resolvedProfileId = nil
            return
        }
        resolvedProfileId = resolvedId
        store.switchProfile(id: resolvedId)
    }

    /// Applies what the recalled app resolves to, without claiming it is
    /// frontmost.
    ///
    /// Used when the feature is switched on or its whitelist is edited from
    /// inside the settings window — the app that matters there is the one the
    /// person came from, and seeing its profile is the only feedback that the
    /// whitelist entry took.
    public func applyRememberedAppResolution(in store: PurahWorkspaceStore? = nil) {
        guard let target = store ?? boundStore else { return }
        applyResolution(in: target)
    }

    /// Adds the app the person was just in to a profile's whitelist.
    public func addRememberedApp(to profileId: UUID, store: PurahWorkspaceStore) {
        guard let candidate = rememberedAppCandidate() else { return }
        store.assignApp(bundleId: candidate.bundleId, to: profileId)
        applyResolution(in: store)
    }

    /// The app a whitelist edit should be about: the last one the person was
    /// in, falling back to any other regular app when nothing was observed yet.
    ///
    /// `.regular` only — agents and background helpers have bundle ids but no
    /// window a person could ever have been "in".
    public func rememberedAppCandidate() -> RememberedApp? {
        if let bundleId = lastExternalBundleId {
            return RememberedApp(
                bundleId: bundleId,
                name: lastExternalAppName ?? AppIdentity.displayName(forBundleId: bundleId)
            )
        }
        let ownBundleId = Bundle.main.bundleIdentifier
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.activationPolicy == .regular
                && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != ownBundleId
        }), let id = app.bundleIdentifier {
            return RememberedApp(
                bundleId: id,
                name: app.localizedName ?? AppIdentity.displayName(forBundleId: id)
            )
        }
        return nil
    }

    private func applyResolution(in store: PurahWorkspaceStore) {
        guard store.isAppProfileSwitchingEnabled,
              let target = resolvedProfileId(for: lastExternalBundleId, in: store) else { return }
        resolvedProfileId = target
        store.switchProfile(id: target)
    }

    /// The whitelist entry for an app, falling back to the default profile.
    ///
    /// The default must be an explicit choice: with no profile marked as the
    /// fallback, an unlisted app leaves the current profile alone rather than
    /// guessing which of the user's profiles was "meant" for it.
    private func resolvedProfileId(for bundleId: String?, in store: PurahWorkspaceStore) -> UUID? {
        let profiles = store.contextProfiles
        if let bundleId, let id = profiles.profileId(forApp: bundleId) {
            return id
        }
        return profiles.defaultProfile?.id
    }
}
