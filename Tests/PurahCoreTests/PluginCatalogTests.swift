// Tests/PurahCoreTests/PluginCatalogTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

/// The remote catalog is an index, not a payload. These tests pin the two
/// properties that make that safe: a remote entry can never shadow a built-in,
/// and a catalog row without a code reference is never offered as installable.
@MainActor
@Suite("Plugin Catalog")
struct PluginCatalogTests {

    private func manifest(
        id: String,
        name: String = "Test Plugin",
        downloadUrl: String? = "https://example.com/p.dylib"
    ) -> PurahPluginManifest {
        PurahPluginManifest(
            id: id,
            displayName: name,
            systemIcon: "puzzlepiece",
            author: "Tester",
            version: "1.0.0",
            description: "A test plugin",
            defaultEdge: .right,
            preferredZone: .goldenAction,
            defaultColorHex: "#123456",
            isCommunity: true,
            downloadUrl: downloadUrl
        )
    }

    private func isolatedService() -> PluginCatalogService {
        PluginCatalogService(
            provider: nil,
            userDefaults: UserDefaults(suiteName: "test_catalog_\(UUID().uuidString)")!
        )
    }

    @Test("A catalog decodes from its wire shape")
    func testDecode() throws {
        let json = """
        {
          "schemaVersion": 1,
          "plugins": [
            {
              "id": "com.example.zen",
              "displayName": "Zen Counter",
              "systemIcon": "circle.dashed",
              "author": "Example",
              "version": "1.2.0",
              "description": "Counts down",
              "defaultEdge": "right",
              "preferredZone": "goldenAction",
              "ergonomicWeight": 30,
              "minLengthRatio": 0.12,
              "defaultColorHex": "#00D1FF",
              "defaultDrawerWidth": 300,
              "category": "Lightweight",
              "permissions": [],
              "tags": ["timer"],
              "isCommunity": true,
              "downloadUrl": "https://example.com/zen.dylib"
            }
          ]
        }
        """
        let catalog = try PluginCatalogService.decode(Data(json.utf8))

        #expect(catalog.schemaVersion == 1)
        #expect(catalog.entries.count == 1)
        #expect(catalog.entries[0].id == "com.example.zen")
        #expect(catalog.entries[0].defaultEdge == .right)
        #expect(catalog.entries[0].downloadUrl == "https://example.com/zen.dylib")
    }

    @Test("Malformed JSON surfaces as a readable error")
    func testMalformed() {
        #expect(throws: PluginCatalogError.self) {
            try PluginCatalogService.decode(Data("{ not json".utf8))
        }
    }

    @Test("An entry with no download target is not installable")
    func testMissingDownloadUrl() {
        let catalog = PurahPluginCatalog(entries: [
            manifest(id: "a", downloadUrl: "https://example.com/a.dylib"),
            manifest(id: "b", downloadUrl: nil),
            manifest(id: "c", downloadUrl: "")
        ])

        #expect(catalog.installableEntries.map(\.id) == ["a"])
    }

    @Test("Duplicate ids collapse to the first entry")
    func testDeduplication() {
        let catalog = PurahPluginCatalog(entries: [
            manifest(id: "dup", name: "First"),
            manifest(id: "dup", name: "Second"),
            manifest(id: "other")
        ])

        let deduped = catalog.deduplicated()
        #expect(deduped.entries.count == 2)
        #expect(deduped.entries.first?.displayName == "First")
    }

    @Test("A remote entry can never shadow a built-in id")
    func testRemoteCannotShadowBuiltIn() {
        let store = PurahWorkspaceStore(
            userDefaults: UserDefaults(suiteName: "test_catalog_shadow_\(UUID().uuidString)")!
        )
        let market = PluginMarketManager(store: store)
        let builtInCount = market.availableCatalog.count

        market.applyRemoteCatalog([
            manifest(id: "vitals", name: "Hijacked Vitals"),
            manifest(id: "com.example.new")
        ])

        let vitals = market.availableCatalog.first { $0.id == "vitals" }
        #expect(vitals?.displayName == "Hardware Vitals",
                "A remote entry must not replace a built-in plugin's identity")
        #expect(market.availableCatalog.contains { $0.id == "com.example.new" })
        #expect(market.availableCatalog.count == builtInCount + 1)
    }

    @Test("Remote entries append after built-ins so grid order is stable")
    func testRemoteAppendsAfterBuiltIns() {
        let store = PurahWorkspaceStore(
            userDefaults: UserDefaults(suiteName: "test_catalog_order_\(UUID().uuidString)")!
        )
        let market = PluginMarketManager(store: store)
        let builtInIds = market.builtInCatalog.map(\.id)

        market.applyRemoteCatalog([manifest(id: "com.example.zzz")])

        #expect(Array(market.availableCatalog.prefix(builtInIds.count)).map(\.id) == builtInIds)
        #expect(market.availableCatalog.last?.id == "com.example.zzz")
    }

    @Test("Resetting the catalog drops remote entries and keeps built-ins")
    func testReset() {
        let store = PurahWorkspaceStore(
            userDefaults: UserDefaults(suiteName: "test_catalog_reset_\(UUID().uuidString)")!
        )
        let market = PluginMarketManager(store: store)
        market.applyRemoteCatalog([manifest(id: "com.example.temp")])
        #expect(market.availableCatalog.contains { $0.id == "com.example.temp" })

        market.resetToBuiltInCatalog()

        #expect(!market.availableCatalog.contains { $0.id == "com.example.temp" })
        #expect(market.availableCatalog.count == market.builtInCatalog.count)
    }

    @Test("A service with no provider never fetches and stays idle")
    func testNoProviderStaysIdle() async {
        let service = isolatedService()
        #expect(!service.hasRemoteSource)

        await service.refresh(force: true)

        #expect(service.state == .idle)
        #expect(service.remoteEntries.isEmpty)
    }

    @Test("A successful fetch populates and caches the entries")
    func testFetchAndCache() async throws {
        let defaults = UserDefaults(suiteName: "test_catalog_cache_\(UUID().uuidString)")!
        let payload = PurahPluginCatalog(entries: [manifest(id: "com.example.cached")])
        let data = try JSONEncoder().encode(payload)
        let service = PluginCatalogService(
            provider: StubProvider(data: data),
            userDefaults: defaults
        )

        await service.refresh()

        #expect(service.state == .loaded(entryCount: 1))
        #expect(service.remoteEntries.map(\.id) == ["com.example.cached"])

        // A second launch restores from cache without touching the network.
        let relaunched = PluginCatalogService(provider: nil, userDefaults: defaults)
        #expect(relaunched.remoteEntries.map(\.id) == ["com.example.cached"])
        #expect(relaunched.lastRefresh != nil)
    }

    @Test("A failed fetch keeps the last known catalog instead of emptying it")
    func testFailureKeepsCache() async throws {
        let defaults = UserDefaults(suiteName: "test_catalog_fail_\(UUID().uuidString)")!
        let payload = PurahPluginCatalog(entries: [manifest(id: "com.example.keep")])
        let seeded = PluginCatalogService(
            provider: StubProvider(data: try JSONEncoder().encode(payload)),
            userDefaults: defaults
        )
        await seeded.refresh()

        let failing = PluginCatalogService(
            provider: StubProvider(error: PluginCatalogError.network("offline")),
            userDefaults: defaults
        )
        await failing.refresh(force: true)

        guard case .failed = failing.state else {
            Issue.record("Expected a failed state, got \(failing.state)")
            return
        }
        #expect(failing.remoteEntries.map(\.id) == ["com.example.keep"],
                "An offline refresh must not wipe the catalog the user already has")
    }

    /// The shipped example is the schema's living documentation. If it ever
    /// stops decoding, the wire format changed and the doc is wrong.
    @Test("The example catalog decodes and is installable")
    func testExampleCatalogIsValid() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Examples/catalog.json")
        let data = try Data(contentsOf: url)

        let catalog = try PluginCatalogService.decode(data)

        #expect(catalog.schemaVersion == 1)
        #expect(!catalog.entries.isEmpty)
        #expect(catalog.installableEntries.count == catalog.entries.count,
                "Every entry in the shipped catalog must name a download target")
        #expect(Set(catalog.entries.map(\.id)).count == catalog.entries.count,
                "The shipped catalog must not contain duplicate ids")
    }
}

private struct StubProvider: PluginCatalogProviding {
    let result: Result<Data, Error>

    init(data: Data) { self.result = .success(data) }
    init(error: Error) { self.result = .failure(error) }

    func fetchCatalog() async throws -> Data {
        try result.get()
    }
}
