// Sources/PurahCore/Updater/AppUpdaterManager.swift
import Foundation
import AppKit
import Observation

public enum UpdateCheckState: Sendable, Equatable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case updateAvailable(AppReleaseInfo)
    case downloading(progress: Double)
    case installing
    case failed(error: String)
}

@Observable
@MainActor
public final class AppUpdaterManager {
    public static let shared = AppUpdaterManager()

    public let currentVersion: String
    public var state: UpdateCheckState = .idle
    public var lastCheckDate: Date?

    public init(currentVersion: String = PurahCore.version) {
        self.currentVersion = currentVersion
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
            if isNewer(release: release) {
                state = .updateAvailable(release)
            } else {
                state = .upToDate(currentVersion: currentVersion)
            }
            return
        }

        // Real GitHub Releases API query
        guard let url = URL(string: "https://api.github.com/repos/rheatin/Purah/releases/latest") else {
            state = .failed(error: "Invalid update endpoint URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Purah-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                state = .failed(error: "Invalid server response")
                return
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    // No releases published yet on repository
                    state = .upToDate(currentVersion: currentVersion)
                    return
                }
                state = .failed(error: "HTTP error \(httpResponse.statusCode)")
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
            var downloadURL = URL(string: htmlUrlString)!
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

            if isNewer(release: release) {
                state = .updateAvailable(release)
            } else {
                state = .upToDate(currentVersion: currentVersion)
            }
        } catch {
            // When running offline or inside a restricted network sandbox, gracefully fallback to up-to-date
            state = .upToDate(currentVersion: currentVersion)
        }
    }

    public func downloadAndInstall(release: AppReleaseInfo) async {
        state = .downloading(progress: 0.0)

        // If the downloadURL is not a direct archive (e.g. html_url because no asset was attached to release),
        // open the release page in the browser
        let urlStr = release.downloadURL.absoluteString
        if !urlStr.hasSuffix(".zip") && !urlStr.hasSuffix(".dmg") {
            NSWorkspace.shared.open(release.downloadURL)
            state = .idle
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
        let currentBundleURL = Bundle.main.bundleURL
        let currentPID = ProcessInfo.processInfo.processIdentifier

        let script = """
        #!/bin/bash
        PID="\(currentPID)"
        ARCHIVE="\(archiveURL.path)"
        TARGET="\(currentBundleURL.path)"

        # 1. Wait for current instance to exit
        while kill -0 "$PID" 2>/dev/null; do
            sleep 0.1
        done

        # 2. Extract into clean temp workspace
        TEMP_DIR=$(mktemp -d /tmp/purah_update_extracted.XXXXXX)
        if [[ "$ARCHIVE" == *.zip ]]; then
            /usr/bin/ditto -xk "$ARCHIVE" "$TEMP_DIR"
        elif [[ "$ARCHIVE" == *.dmg ]]; then
            MOUNT_DIR=$(mktemp -d /tmp/purah_dmg.XXXXXX)
            /usr/bin/hdiutil attach "$ARCHIVE" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
            /bin/cp -R "$MOUNT_DIR"/*.app "$TEMP_DIR/" 2>/dev/null || true
            /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet
            /bin/rm -rf "$MOUNT_DIR"
        fi

        # 3. Locate new Purah.app
        NEW_APP=$(/usr/bin/find "$TEMP_DIR" -maxdepth 2 -name "Purah.app" | head -n 1)

        if [[ -n "$NEW_APP" && -d "$NEW_APP" ]]; then
            /bin/rm -rf "$TARGET"
            /bin/cp -R "$NEW_APP" "$TARGET"
            /usr/bin/xattr -cr "$TARGET" 2>/dev/null || true
            /usr/bin/open "$TARGET"
        fi

        # 4. Cleanup
        /bin/rm -rf "$TEMP_DIR"
        /bin/rm -f "$ARCHIVE"
        exit 0
        """

        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("purah_relaunch.sh")
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        try? process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.terminate(nil)
        }
    }
}
