import Foundation
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("Settings Rail")
struct SettingsRailTests {
    @Test("Every global settings selection has a stable id, icon and localized title")
    @MainActor
    func globalSelectionModel() {
        let localization = LocalizationManager.shared
        let savedLanguage = localization.currentLanguage
        defer { localization.currentLanguage = savedLanguage }
        localization.currentLanguage = .english

        #expect(
            PreferencesSelection.globalCases.map(\.id)
                == ["layout", "general", "motion", "plugins", "permissions", "system"]
        )
        for item in PreferencesSelection.globalCases {
            #expect(item.icon?.isEmpty == false, "\(item.id) has no icon")
            #expect(item.localizedTitle?.isEmpty == false, "\(item.id) has no title")
        }

        let pod = PreferencesSelection.pod("depth-sensor")
        #expect(pod.id == "pod:depth-sensor")
        #expect(pod.podId == "depth-sensor")
        #expect(pod.icon == nil)
        #expect(pod.localizedTitle == nil)
    }

    @Test("Mounted pods keep rail order before unmounted plugins sort by name")
    func railOrdering() {
        let mounted = [
            entry("zeta", "Zeta", isMounted: true),
            entry("alpha", "Alpha", isMounted: true),
        ]
        let registered = [
            entry("delta", "Delta"),
            entry("charlie", "Charlie"),
            entry("zeta", "Duplicate Zeta"),
            entry("alpha", "Duplicate Alpha"),
            entry("bravo", "Bravo"),
        ]

        let ordered = SettingsPodIndex.ordered(
            mounted: mounted,
            registered: registered
        )

        #expect(ordered.map(\.id) == ["zeta", "alpha", "bravo", "charlie", "delta"])
        #expect(ordered.prefix(2).allSatisfy { $0.isMounted })
        #expect(ordered.suffix(3).allSatisfy { !$0.isMounted })
    }

    @Test("PreferencesView accepts pod and global initial selections")
    @MainActor
    func preferencesInitialSelection() {
        let suite = "SettingsRailTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PurahWorkspaceStore(userDefaults: defaults)

        let podView = PreferencesView(
            store: store,
            initialTab: .general,
            initialPluginId: "calendar"
        )
        #expect(podView.selection == .pod("calendar"))

        let globalView = PreferencesView(store: store, initialTab: .layout)
        #expect(globalView.selection == .layout)

        let systemView = PreferencesView(store: store, initialTab: .diagnostics)
        #expect(systemView.selection == .system)
    }

    private func entry(
        _ id: String,
        _ name: String,
        isMounted: Bool = false
    ) -> SettingsPodIndexEntry {
        SettingsPodIndexEntry(
            id: id,
            displayName: name,
            icon: "circle",
            isMounted: isMounted,
            isEnabled: true
        )
    }
}
