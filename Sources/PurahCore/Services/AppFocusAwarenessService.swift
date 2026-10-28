// Sources/PurahCore/Services/AppFocusAwarenessService.swift
import Foundation
import AppKit
import Observation

/// One rule in the focus rule set: "while `bundleId` is frontmost, pods behave
/// like this".
///
/// Scoped to a bundle identifier rather than a display name because that is
/// what survives an app being renamed, and it is what
/// `NSRunningApplication` reports. A rule for an app that is not installed is
/// inert rather than wrong, so rules can be set up ahead of a toolchain.
public struct AppFocusRule: Codable, Sendable, Equatable, Identifiable {
    public var bundleId: String
    /// A friendly name captured when the rule was created, for display only.
    /// Never matched against — see `bundleId`.
    public var displayName: String
    /// Pod ids pulled onto the first rail page.
    public var surfacedPodIds: [String]
    /// Pod ids pushed off the first page. Empty and `surfacedPodIds` do the
    /// same job in opposite directions; both exist because "I want Terminal
    /// here" and "I want Music gone" are different intents and the second one
    /// should not require listing everything else.
    public var hiddenPodIds: [String]

    public var id: String { bundleId }

    public init(
        bundleId: String,
        displayName: String = "",
        surfacedPodIds: [String] = [],
        hiddenPodIds: [String] = []
    ) {
        self.bundleId = bundleId
        self.displayName = displayName.isEmpty ? bundleId : displayName
        self.surfacedPodIds = surfacedPodIds
        self.hiddenPodIds = hiddenPodIds
    }

    public var isInert: Bool {
        surfacedPodIds.isEmpty && hiddenPodIds.isEmpty
    }
}

/// Settings for focus-driven layout adaptation.
public struct AppFocusSettings: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    /// Rules keyed by bundle id. A dictionary rather than an array so the same
    /// app cannot end up with two contradictory rules after an import merges
    /// with an existing set.
    public var rules: [String: AppFocusRule]

    public init(isEnabled: Bool = false, rules: [String: AppFocusRule] = [:]) {
        self.isEnabled = isEnabled
        self.rules = rules
    }

    public var sortedRules: [AppFocusRule] {
        rules.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    // Tolerant decoding: the rules dictionary is the part most likely to arrive
    // from an older build or a hand-edited blob, and one unreadable rule should
    // not discard the rest.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = ((try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? nil) ?? false
        let raw = (try? container.decodeIfPresent([String: AppFocusRule].self, forKey: .rules)) ?? nil
        rules = raw ?? [:]
    }
}

/// Notices which application is frontmost and asks the store to arrange the
/// rails around it.
///
/// Deliberately *not* a general "workspace automation" engine. It changes which
/// rail page a pod sits on; it never resizes a pod, never reorders within a
/// page, and never changes which plugins are installed. Those are the parts of
/// the layout a person sculpts by hand, and having them move under the cursor
/// when they switch apps is the failure mode that makes this class of feature
/// unpleasant.
@Observable
@MainActor
public final class AppFocusAwarenessService {
    public static let shared = AppFocusAwarenessService()

    /// The frontmost application's bundle id, or nil when Purah itself is
    /// frontmost (its own settings window should not change the layout).
    public private(set) var activeBundleId: String?
    public private(set) var activeAppName: String?

    /// The last application that was frontmost *other than Purah*.
    ///
    /// `activeBundleId` is deliberately nil while Purah is frontmost, but the
    /// settings window needs to answer "add a rule for the app I was just in"
    /// — and at that moment Purah is the active app, so asking
    /// `NSRunningApplication.isActive` finds nothing. This remembers the last
    /// real answer instead.
    public private(set) var lastExternalBundleId: String?
    public private(set) var lastExternalAppName: String?

    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?
    @ObservationIgnored nonisolated(unsafe) private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var pendingTask: Task<Void, Never>?

    /// The rule currently applied, so leaving an app can undo exactly that.
    @ObservationIgnored private var appliedRule: AppFocusRule?

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
        // Catch up with whatever is already frontmost. Without this a rule only
        // took effect after the user switched away and back, which reads as
        // "the feature does nothing".
        let frontmost = NSWorkspace.shared.frontmostApplication
        evaluate(
            bundleId: frontmost?.bundleIdentifier,
            name: frontmost?.localizedName
        )
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

    /// Exposed for tests and for the settings preview, which needs to answer
    /// "what would activating this app do" without activating it.
    public func evaluate(bundleId: String?, name: String?) {
        guard let store = boundStore else { return }
        let settings = store.appFocusSettings

        // Purah's own settings window activating must not rearrange anything:
        // the user is configuring the feature, and watching the layout jump
        // while they pick a rule would be actively confusing.
        let isSelf = bundleId == Bundle.main.bundleIdentifier
        activeBundleId = isSelf ? nil : bundleId
        activeAppName = isSelf ? nil : name
        if !isSelf, let bundleId {
            lastExternalBundleId = bundleId
            lastExternalAppName = name
        }

        guard settings.isEnabled else {
            revertIfNeeded(store: store)
            return
        }
        guard !isSelf, let bundleId, let rule = settings.rules[bundleId], !rule.isInert else {
            revertIfNeeded(store: store)
            return
        }

        appliedRule = rule
        store.applyFocusRule(rule)
    }

    /// Puts back what the rule moved.
    ///
    /// Only the page assignments the rule touched are restored, from the
    /// snapshot the store took. Restoring the whole layout would discard any
    /// hand-sculpting done while the rule was active.
    private func revertIfNeeded(store: PurahWorkspaceStore) {
        guard appliedRule != nil else { return }
        appliedRule = nil
        store.clearFocusRule()
    }

    /// Called when the feature is switched off, so the rails do not stay in the
    /// last app's arrangement with no rule left to explain it.
    public func stop() {
        pendingTask?.cancel()
        pendingTask = nil
        if let store = boundStore {
            revertIfNeeded(store: store)
        }
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
    }
}
