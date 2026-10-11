// Sources/PurahCore/Models/MusicRailStyle.swift
import Foundation

public enum MusicRailStyle: String, Codable, Sendable, CaseIterable {
    case minimalist = "minimalist"         // 1. 普通静止 Pod (极简纯净圆角胶囊)
    case smoothProgress = "smoothProgress" // 2. 60 FPS 平滑流淌进度条 (时间锚点无顿挫刷新)
    case dynamicWaveform = "dynamicWaveform" // 3. 流体律动音浪 (叠加声波与频谱动态)
}
