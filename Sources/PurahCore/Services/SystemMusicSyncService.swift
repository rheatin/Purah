// Sources/PurahCore/Services/SystemMusicSyncService.swift
import Foundation
import AppKit
import Observation

@Observable
public final class SystemMusicSyncService: @unchecked Sendable {
    public static let shared = SystemMusicSyncService()

    private var notificationObserver: Any?
    public private(set) var isMusicAppConnected: Bool = false
    public private(set) var lastNotificationDate: Date?

    public init() {
        startListening()
    }

    public func startListening(into store: PurahWorkspaceStore? = nil) {
        let center = DistributedNotificationCenter.default()
        let name = NSNotification.Name("com.apple.Music.playerInfo")

        notificationObserver = center.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self, weak store] notification in
            self?.handlePlayerInfo(notification: notification, store: store)
        }
    }

    public func handlePlayerInfo(notification: Notification, store: PurahWorkspaceStore?) {
        guard let userInfo = notification.userInfo else { return }
        lastNotificationDate = Date()
        isMusicAppConnected = true

        let playerState = userInfo["Player State"] as? String ?? ""
        let isPlaying = (playerState == "Playing")
        let title = userInfo["Name"] as? String ?? "未知曲目"
        let artist = userInfo["Artist"] as? String ?? "Apple 音乐"

        let totalTimeMs = (userInfo["Total Time"] as? Double) ?? 180000.0
        let currentPosSec = (userInfo["Player Position"] as? Double) ?? 0.0
        let totalSec = max(totalTimeMs / 1000.0, 1.0)
        let progress = min(max(currentPosSec / totalSec, 0.0), 1.0)

        // 生成律动波形振幅
        let samples: [Double] = (0..<10).map { _ in
            isPlaying ? Double.random(in: 0.25...0.95) : 0.15
        }

        if let store = store {
            store.musicTrack = MusicTrackInfo(
                title: title,
                artist: artist,
                isPlaying: isPlaying,
                playbackProgress: progress,
                waveformSamples: samples
            )
        }
    }

    public var isMusicAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    public func togglePlayPause(store: PurahWorkspaceStore?) {
        store?.musicTrack.isPlaying.toggle()
        if isMusicAppRunning {
            Task.detached { [weak self] in
                self?.runAppleScript("tell application \"Music\" to playpause")
            }
        }
    }

    public func nextTrack(store: PurahWorkspaceStore?) {
        if isMusicAppRunning {
            Task.detached { [weak self] in
                self?.runAppleScript("tell application \"Music\" to next track")
            }
        }
    }

    public func previousTrack(store: PurahWorkspaceStore?) {
        if isMusicAppRunning {
            Task.detached { [weak self] in
                self?.runAppleScript("tell application \"Music\" to previous track")
            }
        }
    }

    @discardableResult
    private func runAppleScript(_ script: String) -> Bool {
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }
}
