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
public final class AppUpdaterManager: @unchecked Sendable {
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

        // 模拟网络时延与远端发布解析
        try? await Task.sleep(nanoseconds: 500_000_000)

        if let release = simulatedRelease {
            if isNewer(release: release) {
                state = .updateAvailable(release)
            } else {
                state = .upToDate(currentVersion: currentVersion)
            }
            return
        }

        // 默认模拟查询：生成当前最优版本
        state = .upToDate(currentVersion: currentVersion)
    }

    public func simulateFoundNewVersion() {
        let newRelease = AppReleaseInfo(
            version: "2.1.0",
            releaseNotes: """
            ## Purah Pad v2.1.0 更新日志 (Ancient Zonai Upgrade)
            - [新增] 左纳乌能源监控微光柱 (Battery Indicator Pod)
            - [优化] 进一步提升 Fling 意图识别算法，完全杜绝关闭窗口时的误触
            - [优化] 增加对超宽带曲面多显示器边缘的动态自适应
            - [修复] 修复待办事项分段清除时的微光呼吸动画抖动
            """,
            downloadURL: URL(string: "https://github.com/purah/releases/tag/v2.1.0")!
        )
        state = .updateAvailable(newRelease)
    }
}
