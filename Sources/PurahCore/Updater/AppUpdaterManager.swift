// Sources/PurahCore/Updater/AppUpdaterManager.swift
import Foundation
import Observation

public enum UpdateCheckState: Sendable, Equatable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case updateAvailable(AppReleaseInfo)
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

        // Simulate network delay and remote release resolution
        try? await Task.sleep(nanoseconds: 500_000_000)

        if let release = simulatedRelease {
            if isNewer(release: release) {
                state = .updateAvailable(release)
            } else {
                state = .upToDate(currentVersion: currentVersion)
            }
            return
        }

        // Default simulated query: currently up to date
        state = .upToDate(currentVersion: currentVersion)
    }
}
