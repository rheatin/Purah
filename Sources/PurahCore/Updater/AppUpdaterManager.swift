// Sources/PurahCore/Updater/AppUpdaterManager.swift
import Foundation
import AppKit
import Observation

public enum UpdateCheckState: Sendable, Equatable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case updateAvailable(AppReleaseInfo)
    /// A newer release exists but this build cannot replace itself — it was
    /// ad-hoc signed, so no Team ID can vouch for the download. The dialog
    /// offers the download instead of quitting into a failed install.
    case manualUpdateRequired(AppReleaseInfo)
    case downloading(progress: Double)
    case installing
    case failed(error: String)
}

/// Why the app declined to install an update in place.
///
/// The failure modes *after* the installer starts are reported by the shell
/// script through `UpdateInstallMarker`, not here — by then this process has
/// already quit and cannot run Swift.
public enum UpdateInstallError: LocalizedError, Equatable {
    case unsignedBuild

    public var errorDescription: String? {
        switch self {
        case .unsignedBuild:
            return "This build is not signed with a Developer ID, so it cannot verify an update."
        }
    }
}

/// Marker written by the install script when it could not swap the bundle, so
/// the next launch can say what happened instead of silently looking normal.
public enum UpdateInstallMarker {
    public static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Purah", isDirectory: true)
            .appendingPathComponent("update-failed.txt")
    }

    /// Returns the recorded reason, and clears it — a warning that survives
    /// every launch forever is noise, not information.
    public static func readAndClear(at location: URL? = nil) -> String? {
        let source = location ?? url
        guard let data = try? Data(contentsOf: source),
              let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        clear(at: location)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func clear(at location: URL? = nil) {
        try? FileManager.default.removeItem(at: location ?? url)
    }
}

/// Source of the latest release manifest. Injected so update checks can be
/// tested without touching the network (a live GitHub query made the integration
/// suite fail whenever the API rate-limited or a release was published).
public protocol UpdateManifestProviding: Sendable {
    func fetchLatestRelease() async throws -> (data: Data, statusCode: Int)
}

/// Production provider: GitHub Releases API over `URLSession`.
public struct GitHubReleaseProvider: UpdateManifestProviding {
    public static let endpoint = URL(string: "https://api.github.com/repos/rheatin/Purah/releases/latest")!
    public let currentVersion: String
    public let session: URLSession

    public init(currentVersion: String, session: URLSession = .shared) {
        self.currentVersion = currentVersion
        self.session = session
    }

    public func fetchLatestRelease() async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Purah-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10.0
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
    }
}

/// Reads the signing identity of a bundle.
///
/// The install script had its expected Team ID passed in as an empty string
/// (a placeholder that nothing ever filled), so *every* update compared a real
/// team against `""`, failed, and exited — after the app had already quit. The
/// user was left with no app and no explanation.
///
/// Asking the running bundle for its own Team ID removes the placeholder: a
/// Developer ID build automatically knows who signs its updates, and an ad-hoc
/// build (no team) learns that it cannot vouch for anything.
///
/// Goes through `/usr/bin/codesign` rather than `SecCodeCopySigningInformation`:
/// `PurahCore` must not link Security.framework (see `SecretStore`), and using
/// the same tool the install script uses keeps the two answers identical.
public enum CodeSigning {
    public static func teamIdentifier(ofBundleAt url: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Ad-hoc signatures print `TeamIdentifier=not set`, which is a string,
        // not a missing key — treating it as a team name would make an ad-hoc
        // build look signed.
        for line in output.components(separatedBy: .newlines) {
            guard let range = line.range(of: "TeamIdentifier=") else { continue }
            let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return value.isEmpty || value == "not set" ? nil : value
        }
        return nil
    }
}

@Observable
@MainActor
public final class AppUpdaterManager {
    public static let shared = AppUpdaterManager()

    public let currentVersion: String
    public var state: UpdateCheckState = .idle
    public var lastCheckDate: Date?
    private let manifestProvider: (any UpdateManifestProviding)?

    /// The bundle being replaced, and the team allowed to replace it.
    ///
    /// `expectedTeamIdentifier` is `nil` for an ad-hoc/unsigned build. That is
    /// not a failure at construction time — it means in-place replacement is
    /// impossible, and `downloadAndInstall` must not quit into a doomed script.
    public let bundleURL: URL

    private let explicitTeamIdentifier: String?
    private var teamResolution: TeamResolution = .pending

    private enum TeamResolution {
        case pending
        case resolved(String?)
    }

    /// The Team ID this build was signed with, or `nil` when ad-hoc.
    ///
    /// Resolved on first use rather than in `init`: this spawns `codesign`, and
    /// the manager is constructed long before anyone asks about updates.
    public var expectedTeamIdentifier: String? {
        if let explicitTeamIdentifier { return explicitTeamIdentifier }
        if case .resolved(let cached) = teamResolution { return cached }
        let resolved = CodeSigning.teamIdentifier(ofBundleAt: bundleURL)
        teamResolution = .resolved(resolved)
        return resolved
    }

    /// Opened instead of downloading when this build cannot self-install.
    /// Injected so tests do not launch a browser.
    private let openURL: @MainActor (URL) -> Void

    /// Whether this build can install an update by itself.
    public var canInstallInPlace: Bool { expectedTeamIdentifier != nil }

    public init(
        currentVersion: String = PurahCore.version,
        manifestProvider: (any UpdateManifestProviding)? = nil,
        bundleURL: URL = Bundle.main.bundleURL,
        expectedTeamIdentifier: String? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.currentVersion = currentVersion
        self.manifestProvider = manifestProvider
        self.bundleURL = bundleURL
        self.explicitTeamIdentifier = expectedTeamIdentifier
        self.openURL = openURL
    }

    public func isNewer(release: AppReleaseInfo) -> Bool {
        guard let current = SemanticVersion(currentVersion),
              let remote = SemanticVersion(release.version) else {
            return false
        }
        return current < remote
    }

    public func checkForUpdates(simulatedRelease: AppReleaseInfo? = nil) async {
        state = .checking
        lastCheckDate = Date()

        if let release = simulatedRelease {
            state = availability(of: release)
            return
        }

        // Real GitHub Releases API query
        let provider = manifestProvider ?? GitHubReleaseProvider(currentVersion: currentVersion)

        do {
            let (data, statusCode) = try await provider.fetchLatestRelease()

            guard statusCode == 200 else {
                if statusCode == 404 {
                    // No releases published yet on repository
                    state = .upToDate(currentVersion: currentVersion)
                    return
                }
                state = .failed(error: "HTTP error \(statusCode)")
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                state = .failed(error: "Invalid release manifest")
                return
            }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let bodyText = (json["body"] as? String) ?? "Maintenance and ergonomic improvements."
            let htmlUrlString = (json["html_url"] as? String) ?? "https://github.com/rheatin/Purah/releases"

            // Look for downloadable .zip or .dmg asset
            guard let fallbackURL = URL(string: htmlUrlString) ?? URL(string: "https://github.com/rheatin/Purah/releases") else {
                state = .failed(error: "Invalid release URL")
                return
            }
            var downloadURL = fallbackURL
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       (name.hasSuffix(".zip") || name.hasSuffix(".dmg")),
                       let browserURL = asset["browser_download_url"] as? String,
                       let u = URL(string: browserURL) {
                        downloadURL = u
                        break
                    }
                }
            }

            let release = AppReleaseInfo(
                version: remoteVersion,
                releaseDate: Date(),
                releaseNotes: bodyText,
                downloadURL: downloadURL
            )

            state = availability(of: release)
        } catch {
            // When running offline or inside a restricted network sandbox, gracefully fallback to up-to-date
            state = .upToDate(currentVersion: currentVersion)
        }
    }

    /// A newer release that this build cannot install in place is still worth
    /// telling the user about — it becomes a manual download, not silence.
    private func availability(of release: AppReleaseInfo) -> UpdateCheckState {
        guard isNewer(release: release) else {
            return .upToDate(currentVersion: currentVersion)
        }
        return canInstallInPlace ? .updateAvailable(release) : .manualUpdateRequired(release)
    }

    public func downloadAndInstall(release: AppReleaseInfo) async {
        state = .downloading(progress: 0.0)

        // If the downloadURL is not a direct archive (e.g. html_url because no asset was attached to release),
        // open the release page in the browser
        let urlStr = release.downloadURL.absoluteString
        if !urlStr.hasSuffix(".zip") && !urlStr.hasSuffix(".dmg") {
            openURL(release.downloadURL)
            state = .idle
            return
        }

        // An ad-hoc build has no Team ID, so the install script would reject
        // every download — after this process had already quit. Send the user
        // to the release page instead of terminating into a dead end.
        guard expectedTeamIdentifier != nil else {
            openURL(release.downloadURL)
            state = .failed(error: UpdateInstallError.unsignedBuild.localizedDescription)
            return
        }

        let downloadDir = FileManager.default.temporaryDirectory.appendingPathComponent("PurahUpdate", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)
        let archiveFilename = release.downloadURL.lastPathComponent
        let targetArchiveURL = downloadDir.appendingPathComponent(archiveFilename)
        try? FileManager.default.removeItem(at: targetArchiveURL)

        do {
            var request = URLRequest(url: release.downloadURL)
            request.setValue("Purah-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 60.0

            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                state = .failed(error: "Download failed (invalid status code)")
                return
            }

            try FileManager.default.moveItem(at: tempURL, to: targetArchiveURL)
            state = .installing

            // Perform in-place atomic replacement and seamless relaunch
            performInPlaceReplacementAndRelaunch(archiveURL: targetArchiveURL)
        } catch {
            state = .failed(error: "Download error: \(error.localizedDescription)")
        }
    }

    private func performInPlaceReplacementAndRelaunch(archiveURL: URL) {
        // Guarded by the caller; the script below trusts this string.
        guard let teamID = expectedTeamIdentifier else { return }
        let currentBundleURL = bundleURL
        let currentPID = ProcessInfo.processInfo.processIdentifier

        // A stale marker from an older attempt must not be shown as this one's
        // outcome.
        UpdateInstallMarker.clear()

        let script = UpdateInstallScript.source(markerPath: UpdateInstallMarker.url.path)
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_relaunch_\(UUID().uuidString).sh")

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            state = .failed(error: "Could not prepare the update: \(error.localizedDescription)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, "\(currentPID)", archiveURL.path, currentBundleURL.path, teamID]

        // Quitting when the installer never started would leave the user with
        // no app and no explanation — the same dead end as the Team ID bug,
        // reached by a different path.
        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
            state = .failed(error: "Could not start the update: \(error.localizedDescription)")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.terminate(nil)
        }
    }
}
