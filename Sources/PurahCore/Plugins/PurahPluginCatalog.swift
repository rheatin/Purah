// Sources/PurahCore/Plugins/PurahPluginCatalog.swift
import Foundation
import Observation

/// A remotely published plugin catalog — the data source behind the
/// marketplace.
///
/// The catalog is *only* an index. It names plugins and points at where their
/// code lives; it never contains plugin code, and it cannot by itself put
/// anything on the rail. Installing a catalog entry still goes through
/// `PluginMarketManager.install(id:)`, which refuses ids with no registered
/// implementation. That separation is what keeps a compromised catalog from
/// silently mounting code.
///
/// Decoding is strict about the fields that decide where a plugin lands
/// (`id`, `displayName`, `systemIcon`, `defaultEdge`, `preferredZone`) and
/// lenient about presentation fields, so an older client can read a catalog
/// written for a newer one.
public struct PurahPluginCatalog: Codable, Sendable, Equatable {
    /// Schema version. A future major bump can change entry shape; clients
    /// older than the catalog still decode the entries they understand.
    public var schemaVersion: Int
    public var entries: [PurahPluginManifest]

    public init(schemaVersion: Int = 1, entries: [PurahPluginManifest]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, plugins
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        // `plugins` is the wire name: it reads naturally in a catalog file and
        // keeps the JSON independent of our internal type names.
        entries = try container.decodeIfPresent([PurahPluginManifest].self, forKey: .plugins) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(entries, forKey: .plugins)
    }

    /// Entries that carry no code reference are rejected: a catalog row that
    /// cannot say where its plugin comes from would install a pod whose drawer
    /// can never open.
    public var installableEntries: [PurahPluginManifest] {
        entries.filter { $0.downloadUrl?.isEmpty == false }
    }

    /// Drops entries whose ids collide, keeping the first. A catalog is
    /// hand-maintained, and a duplicate id would otherwise make the grid show
    /// the same plugin twice with the last one winning the install.
    public func deduplicated() -> PurahPluginCatalog {
        var seen = Set<String>()
        let unique = entries.filter { seen.insert($0.id).inserted }
        return PurahPluginCatalog(schemaVersion: schemaVersion, entries: unique)
    }
}

/// Where a catalog comes from. Injected so the marketplace can be exercised
/// without the network — the same shape `UpdateManifestProviding` uses.
public protocol PluginCatalogProviding: Sendable {
    func fetchCatalog() async throws -> Data
}

public enum PluginCatalogError: LocalizedError, Sendable, Equatable {
    case network(String)
    case badStatus(Int)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .network(let detail):
            return "Couldn't reach the plugin catalog: \(detail)"
        case .badStatus(let code):
            return "The plugin catalog returned HTTP \(code)."
        case .malformed(let detail):
            return "The plugin catalog couldn't be read: \(detail)"
        }
    }
}

/// Production provider: a single JSON document over HTTPS.
public struct RemotePluginCatalogProvider: PluginCatalogProviding {
    public let url: URL
    public let session: URLSession

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }
    public func fetchCatalog() async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Purah-Market/1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15.0

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PluginCatalogError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw PluginCatalogError.badStatus(status)
        }
        return data
    }
}

/// Loads, caches, and exposes the remote catalog.
///
/// The bundled catalog is always present, so the marketplace works offline and
/// on first launch. A successful fetch replaces the *remote* portion only —
/// built-ins never disappear because a server said so.
@Observable
@MainActor
public final class PluginCatalogService: Sendable {
    public static let shared = PluginCatalogService()

    public enum State: Sendable, Equatable {
        case idle
        case loading
        case loaded(entryCount: Int)
        case failed(String)
    }

    public private(set) var state: State = .idle
    /// Remote entries only. `PluginMarketManager` merges these after the
    /// built-in catalog.
    public private(set) var remoteEntries: [PurahPluginManifest] = []
    public private(set) var lastRefresh: Date?

    /// `nil` disables remote fetching entirely (tests, offline builds).
    @ObservationIgnored private var provider: (any PluginCatalogProviding)?
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    private static let cacheKey = "purah.market.remoteCatalog"
    private static let cacheDateKey = "purah.market.remoteCatalogDate"
    @ObservationIgnored private let userDefaults: UserDefaults

    public init(
        provider: (any PluginCatalogProviding)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.provider = provider
        self.userDefaults = userDefaults
        restoreCachedEntries()
    }

    /// Installs the production provider. Split from `init` so tests can build a
    /// service with no network at all.
    public func configure(provider: (any PluginCatalogProviding)?) {
        self.provider = provider
    }

    public var hasRemoteSource: Bool { provider != nil }

    /// The published catalog endpoint, or `nil` while no catalog repo exists.
    ///
    /// Kept here rather than hardcoded at the call site so pointing the
    /// marketplace at a real index is a one-line change once the repo is up.
    public static var catalogURL: URL? { nil }

    public static var productionProvider: (any PluginCatalogProviding)? {
        guard let url = catalogURL else { return nil }
        return RemotePluginCatalogProvider(url: url)
    }

    /// Fetches the catalog, replacing the cached copy on success.
    ///
    /// Failures are non-fatal by design: a user with no network keeps the
    /// catalog they last saw. `state` carries the error so the UI can say so
    /// without emptying the grid.
    public func refresh(force: Bool = false) async {
        guard let provider else { return }
        if !force, case .loading = state { return }

        state = .loading
        let task = Task { [weak self] in
            do {
                let data = try await provider.fetchCatalog()
                let catalog = try Self.decode(data)
                self?.apply(catalog)
            } catch {
                self?.fail(with: error)
            }
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Cancels any in-flight refresh. Called when the marketplace closes so a
    /// slow request does not outlive the view that asked for it.
    public func cancel() {
        inFlight?.cancel()
        inFlight = nil
        if case .loading = state {
            state = lastRefresh == nil ? .idle : .loaded(entryCount: remoteEntries.count)
        }
    }

    public static func decode(_ data: Data) throws -> PurahPluginCatalog {
        do {
            return try JSONDecoder().decode(PurahPluginCatalog.self, from: data)
        } catch {
            throw PluginCatalogError.malformed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func apply(_ catalog: PurahPluginCatalog) {
        let deduped = catalog.deduplicated()
        remoteEntries = deduped.entries
        lastRefresh = Date()
        state = .loaded(entryCount: remoteEntries.count)
        persistCache()
        DiagnosticLogger.shared.info(
            "Market",
            "Catalog refreshed: \(remoteEntries.count) remote entries"
        )
    }

    private func fail(with error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        state = .failed(message)
        DiagnosticLogger.shared.warn("Market", "Catalog refresh failed: \(message)")
    }

    private func persistCache() {
        guard let data = try? JSONEncoder().encode(remoteEntries) else { return }
        userDefaults.set(data, forKey: Self.cacheKey)
        userDefaults.set(Date().timeIntervalSince1970, forKey: Self.cacheDateKey)
    }

    private func restoreCachedEntries() {
        guard let data = userDefaults.data(forKey: Self.cacheKey),
              let entries = try? JSONDecoder().decode([PurahPluginManifest].self, from: data) else {
            return
        }
        remoteEntries = entries
        if let stamp = userDefaults.object(forKey: Self.cacheDateKey) as? TimeInterval {
            lastRefresh = Date(timeIntervalSince1970: stamp)
        }
        state = .loaded(entryCount: entries.count)
    }
}
