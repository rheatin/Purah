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

    @Test("Focus handoff is nonce-guarded and manual rail selection clears it")
    func focusHandoff() {
        var focus = SettingsFocusHandoff()
        focus.deliver("calendar")
        let firstNonce = focus.nonce
        #expect(focus.podId == "calendar")

        focus.clearIfCurrent(podId: "calendar", nonce: firstNonce)
        #expect(focus.podId == nil)

        focus.deliver("calendar")
        let staleNonce = focus.nonce
        focus.deliver("calendar")
        focus.clearIfCurrent(podId: "calendar", nonce: staleNonce)
        #expect(focus.podId == "calendar")

        focus.clearIfCurrent(podId: "calendar", nonce: focus.nonce)
        #expect(focus.podId == nil)

        focus.deliver("calendar")
        focus.clearForManualSelection()
        #expect(focus.podId == nil)
    }

    @Test("Pod alert summary gives silence and the master switch precedence")
    @MainActor
    func podAlertSummaryPrecedence() {
        let localization = LocalizationManager.shared
        let savedLanguage = localization.currentLanguage
        defer { localization.currentLanguage = savedLanguage }
        localization.currentLanguage = .english

        let allChannels = Set(AlertChannel.allCases)
        #expect(
            PodAlertSummary.text(
                style: .sonarWave,
                channels: allChannels,
                podEnabled: false,
                globalChannels: nil
            ) == "Silenced"
        )
        #expect(
            PodAlertSummary.text(
                style: .sonarWave,
                channels: allChannels,
                podEnabled: true,
                globalChannels: nil
            ) == "Notifications are off"
        )
        #expect(
            PodAlertSummary.text(
                style: .breathingBeacon,
                channels: [],
                podEnabled: true,
                globalChannels: allChannels
            ) == "No delivery method"
        )
        #expect(
            PodAlertSummary.text(
                style: .breathingBeacon,
                channels: [.sound],
                podEnabled: true,
                globalChannels: [.railEffect, .toast]
            ) == "No delivery method"
        )
        #expect(
            PodAlertSummary.text(
                style: .breathingBeacon,
                channels: [.sound, .railEffect, .toast],
                podEnabled: true,
                globalChannels: allChannels
            ) == "Beacon Bar · Edge + Toast + Sound"
        )
    }

    @Test("Pod storage summary shows total, assets, then cache")
    @MainActor
    func podStorageSummaryFormatting() {
        let localization = LocalizationManager.shared
        let savedLanguage = localization.currentLanguage
        defer { localization.currentLanguage = savedLanguage }
        localization.currentLanguage = .english

        #expect(
            PodStorageSummary.text(
                assetsBytes: 2_048,
                dataBytes: 4_096,
                cacheBytes: 0
            ) == "6 KB · 2 KB assets · 0 cache"
        )
    }

    @Test("A single-plugin storage measurement excludes every other pod")
    func singlePluginStorageMeasurement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsRailStorage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let pluginsBase = root.appendingPathComponent("Plugins", isDirectory: true)
        let alpha = PurahPluginFileStorage(
            pluginId: "alpha",
            customBaseDirectory: pluginsBase
        )
        let beta = PurahPluginFileStorage(
            pluginId: "beta",
            customBaseDirectory: pluginsBase
        )
        let alphaAsset = alpha.assetsDirectory.appendingPathComponent("asset.bin")
        let alphaData = alpha.dataDirectory.appendingPathComponent("index.json")
        let betaAsset = beta.assetsDirectory.appendingPathComponent("large.bin")
        try writeBytes(4_096, to: alphaAsset)
        try writeBytes(4_096, to: alphaData)
        try writeBytes(65_536, to: betaAsset)

        let roots = PluginStorageRoots(
            pluginsBase: pluginsBase,
            clipboard: root.appendingPathComponent("Clipboard", isDirectory: true),
            vitals: root.appendingPathComponent("Vitals", isDirectory: true)
        )
        let measured = try #require(
            PluginStorageScanner.measure(pluginId: "alpha", roots: roots)
        )

        #expect(measured.assetsBytes == (try allocatedBytes(of: alphaAsset)))
        #expect(measured.dataBytes == (try allocatedBytes(of: alphaData)))
        #expect(measured.cacheBytes == 0)
        #expect(measured.assetsBytes < (try allocatedBytes(of: betaAsset)))
        #expect(measured.target.rootURL == alpha.rootDirectory)
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

    private func writeBytes(_ count: Int, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xA5, count: count).write(to: url)
    }

    private func allocatedBytes(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(
            forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        )
        return Int64(try #require(
            values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize
        ))
    }
}
