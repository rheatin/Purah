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
    /// The release published no digest for its archive, so there is nothing to
    /// check the download against.
    case unverifiedDownload
    /// The archive did not hash to the published value.
    case checksumMismatch

    public var errorDescription: String? {
        switch self {
        case .unverifiedDownload:
            return "This release does not publish a checksum, so the update was not installed automatically."
        case .checksumMismatch:
            return "The downloaded update did not match its published checksum and was discarded."
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

/// Reports transfer progress for one download, and hands back the finished file.
///
/// `URLSession.download(for:)` without a delegate reports nothing until the
/// file is complete, so the dialog had a `downloading(progress:)` state whose
/// progress was always 0 — and a determinate bar fed 0 renders as the
/// indeterminate "bouncing" bar. The user saw a bar that moved and learned
/// nothing from it.
///
/// The task-based form is used rather than `download(for:delegate:)` because
/// the file at `didFinishDownloadingTo` is deleted the moment that callback
/// returns: with the async form the delegate can take the URL away from the
/// call that is waiting for it. Copying the file here is what keeps it.
final class DownloadProgressObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias Completion = CheckedContinuation<(url: URL, statusCode: Int), Error>

    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: Completion?
    private var downloadedFile: URL?
    private var statusCode: Int = 0
    private var failure: Error?

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func attach(_ continuation: Completion) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // A server that sends no Content-Length cannot be turned into a
        // percentage. Reporting nothing keeps the bar indeterminate, which is
        // the honest answer, rather than inventing motion.
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1
        lock.unlock()

        // `location` is deleted as soon as this returns.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurahDownload-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: location, to: kept)
            lock.lock()
            downloadedFile = kept
            lock.unlock()
        } catch {
            lock.lock()
            failure = error
            lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        let file = downloadedFile
        let code = statusCode
        let recorded = failure
        downloadedFile = nil
        failure = nil
        lock.unlock()

        guard let waiting else { return }
        if let error = error ?? recorded {
            if let file { try? FileManager.default.removeItem(at: file) }
            waiting.resume(throwing: error)
        } else if let file {
            waiting.resume(returning: (file, code))
        } else {
            waiting.resume(throwing: URLError(.cannotCreateFile))
        }
    }
}

/// Source of the latest release manifest. Injected so update checks can be
/// tested without touching the network (a live GitHub query made the integration
/// suite fail whenever the API rate-limited or a release was published).
public protocol UpdateManifestProviding: Sendable {
    func fetchLatestRelease() async throws -> (data: Data, statusCode: Int)
}

/// Production provider: the release's own `release-info.json` asset.
///
/// Not `api.github.com`. The REST API is unauthenticated in this app, so every
/// check joins one bucket of 60 requests per hour per IP address — shared with
/// anything else on that network that talks to GitHub anonymously. When the
/// bucket is empty GitHub answers 403 and the app could only repeat the number
/// back. `releases/latest/download/<asset>` is a redirect to the release CDN:
/// no quota, cacheable, and it hands over exactly the fields below without
/// having to pick a `.dmg` out of an assets array.
public struct ReleaseManifestProvider: UpdateManifestProviding {
    public static let endpoint = URL(string: "https://github.com/rheatin/Purah/releases/latest/download/release-info.json")!
    public let currentVersion: String
    public let session: URLSession

    public init(currentVersion: String, session: URLSession = .shared) {
        self.currentVersion = currentVersion
        self.session = session
    }

    public func fetchLatestRelease() async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: Self.endpoint)
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
    private let defaults: UserDefaults

    /// Whether Purah looks for a new release on its own shortly after launch.
    ///
    /// On by default: an app that never mentions updates is an app people run
    /// a year out of date. The launch check is silent — it opens the dialog
    /// only when there is something to install.
    public static let autoCheckDefaultsKey = "purah.updater.autoCheck"

    /// How often a check that was not explicitly requested may ask again.
    /// Opening the update dialog repeatedly is not asking a new question.
    public static let minimumCheckInterval: TimeInterval = 15 * 60

    /// How long a check may stay in `.checking` before the dialog gives up.
    ///
    /// The manifest request carries a 10s idle timeout, but that only covers
    /// the request itself: a proxy holding the socket open, a redirect chain
    /// that never resolves, or a continuation that never reaches the main
    /// actor all leave `state` at `.checking` with nothing to end it. The
    /// dialog then shows a spinner with no button at all (the `.checking`
    /// branch renders no action), and the guard in `checkForUpdates` refuses
    /// every later click — including the one from reopening the window. The
    /// spinner only cleared when the orphaned request finally landed, which is
    /// exactly what "close it and reopen and it's suddenly there" looked like.
    public let checkDeadline: TimeInterval

    /// Bumped by every check that starts. A watchdog or a late reply from an
    /// abandoned check compares against it, so neither can overwrite the
    /// result of a check that replaced it.
    private var checkGeneration = 0

    public var isAutoCheckEnabled: Bool {
        get { defaults.object(forKey: Self.autoCheckDefaultsKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.autoCheckDefaultsKey) }
    }

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
    ///
    /// True even without a Team ID. Every Purah release is ad-hoc signed, so
    /// requiring a team made in-place installation unreachable for the shipped
    /// build — the guard below could never pass, and every update degraded to
    /// "open the release page in a browser". An ad-hoc build is still replaced
    /// safely by a different check: the download is matched against the
    /// SHA-256 the release publishes before any of this runs, and the install
    /// script verifies the bundle's own signature is intact. What it cannot
    /// prove is *who* signed it, so that is stated in the UI rather than
    /// silently assumed.
    public var canInstallInPlace: Bool { true }

    /// Whether the replacement can be proven to come from a known publisher.
    ///
    /// `false` for an ad-hoc build: its signature is only a checksum over the
    /// bundle, and anyone can produce one. The update still installs, but the
    /// dialog says so instead of implying a stronger guarantee than exists.
    public var hasVerifiedPublisher: Bool { expectedTeamIdentifier != nil }

    public init(
        currentVersion: String = PurahCore.version,
        manifestProvider: (any UpdateManifestProviding)? = nil,
        bundleURL: URL = Bundle.main.bundleURL,
        expectedTeamIdentifier: String? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        defaults: UserDefaults = .standard,
        checkDeadline: TimeInterval = 20
    ) {
        self.currentVersion = currentVersion
        self.manifestProvider = manifestProvider
        self.bundleURL = bundleURL
        self.explicitTeamIdentifier = expectedTeamIdentifier
        self.openURL = openURL
        self.defaults = defaults
        self.checkDeadline = checkDeadline
    }

    public func isNewer(release: AppReleaseInfo) -> Bool {
        guard let current = SemanticVersion(currentVersion),
              let remote = SemanticVersion(release.version) else {
            return false
        }
        return current < remote
    }

    public func checkForUpdates(force: Bool = false, simulatedRelease: AppReleaseInfo? = nil) async {
        // Two entry points ask at once — the menu item and the dialog's own
        // `.task` — and the bottom button used to start a third. A second
        // request while one is in flight raced the first for `state`, so the
        // dialog could settle on whichever happened to finish last.
        guard state != .checking else { return }

        // The same question twice in a quarter of an hour has the same answer.
        // Ask GitHub every time the dialog opens and the update check becomes
        // the busiest thing the app does; an explicit "check again" forces it.
        if !force, simulatedRelease == nil,
           let last = lastCheckDate,
           Date().timeIntervalSince(last) < Self.minimumCheckInterval {
            return
        }

        checkGeneration &+= 1
        let generation = checkGeneration
        state = .checking
        lastCheckDate = Date()

        // The watchdog is what gives `.checking` an exit. It fires after the
        // request deadline; if this check has been replaced by then, the
        // generation no longer matches and it leaves the newer one alone.
        let deadline = checkDeadline
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadline))
            guard let self,
                  self.checkGeneration == generation,
                  case .checking = self.state else { return }
            // Recorded so the next occurrence can be diagnosed: the dialog
            // only says "timed out", and whether that was DNS, a proxy holding
            // the socket open, or a dead continuation is not visible there.
            DiagnosticLogger.shared.log(
                level: .warning,
                category: "Updater",
                message: "Update check produced no answer within \(Int(deadline))s; abandoned."
            )
            self.state = .failed(error: "The update check timed out. Try again.")
        }

        if let release = simulatedRelease {
            state = availability(of: release)
            return
        }

        let provider = manifestProvider ?? ReleaseManifestProvider(currentVersion: currentVersion)

        do {
            let (data, statusCode) = try await provider.fetchLatestRelease()

            // Answers that arrive after this check stopped being the current
            // one are dropped, not applied: they describe a question nobody
            // is showing any more.
            guard generation == checkGeneration else { return }

            guard statusCode == 200 else {
                if statusCode == 404 {
                    // Nothing published yet — or a release older than the
                    // manifest. Either way there is nothing to install.
                    state = .upToDate(currentVersion: currentVersion)
                    return
                }
                // 403/429 used to surface as "HTTP error 403", which tells the
                // person nothing they can act on. Say what happened instead.
                state = .failed(
                    error: statusCode == 403 || statusCode == 429
                        ? "GitHub is limiting update checks right now. Try again in a little while."
                        : "Update check failed (HTTP \(statusCode))."
                )
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let release = try? decoder.decode(AppReleaseInfo.self, from: data) else {
                state = .failed(error: "The release manifest could not be read.")
                return
            }

            state = availability(of: release)
        } catch {
            guard generation == checkGeneration else { return }
            // Not the same thing as "you are up to date". The launch check
            // stays silent because it only presents for a real update; a
            // manual check says it could not reach GitHub.
            state = .failed(error: "Could not reach GitHub. Check your connection and try again.")
        }
    }

    /// A newer release this build can safely install is offered as an install;
    /// one it cannot is offered as a manual download, not as silence.
    ///
    /// The remaining reason an update cannot install by itself is a release
    /// that publishes no digest. That is knowable here, from the manifest, so
    /// it is reported before anything is downloaded rather than after the
    /// archive has already been fetched and refused.
    private func availability(of release: AppReleaseInfo) -> UpdateCheckState {
        guard isNewer(release: release) else {
            return .upToDate(currentVersion: currentVersion)
        }
        let installable = canInstallInPlace && release.normalizedSHA256 != nil
        return installable ? .updateAvailable(release) : .manualUpdateRequired(release)
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

        // An ad-hoc build has no Team ID. It no longer refuses to install for
        // that reason: the download is matched against the release's published
        // SHA-256 below before anything is handed to the installer, which is
        // the check that actually protects the user. The missing publisher
        // proof is reported by `hasVerifiedPublisher`, not used as a veto.

        // A release that publishes no digest cannot be verified, and that is
        // knowable before spending a download on it. Checked here rather than
        // after the transfer so the user gets the release page immediately
        // instead of watching 6 MB arrive and then be deleted.
        guard release.normalizedSHA256 != nil else {
            openURL(release.downloadURL)
            state = .failed(error: UpdateInstallError.unverifiedDownload.localizedDescription)
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

            // Progress is reported by a per-download delegate; without it the
            // transfer is a black box until the archive is complete.
            let observer = DownloadProgressObserver { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(progress: fraction)
                }
            }
            let session = URLSession(configuration: .default, delegate: observer, delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }

            let (tempURL, statusCode) = try await withCheckedThrowingContinuation { (continuation: DownloadProgressObserver.Completion) in
                observer.attach(continuation)
                session.downloadTask(with: request).resume()
            }
            guard statusCode == 200 else {
                try? FileManager.default.removeItem(at: tempURL)
                state = .failed(error: "Download failed (invalid status code)")
                return
            }

            // Check the archive against the digest the release published for
            // it, before it is handed to a script that will replace the app.
            // Presence was already checked above; this is the value comparison.
            guard let expected = release.normalizedSHA256 else {
                try? FileManager.default.removeItem(at: tempURL)
                openURL(release.downloadURL)
                state = .failed(error: UpdateInstallError.unverifiedDownload.localizedDescription)
                return
            }
            do {
                try FileChecksum.verify(fileAt: tempURL, matches: expected)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                DiagnosticLogger.shared.error(
                    "Updater",
                    "Downloaded archive failed checksum verification: \(error.localizedDescription)"
                )
                state = .failed(error: UpdateInstallError.checksumMismatch.localizedDescription)
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
        // Empty for an ad-hoc build, which the script reads as "no publisher to
        // compare against" rather than "no verification".
        let teamID = expectedTeamIdentifier ?? ""
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
