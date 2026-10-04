// Sources/PurahCore/Models/ItemDrawerState.swift
import Foundation

public enum ItemDrawerState: Sendable, Equatable {
    case expandedDrawer  // 完全弹出的抽屉 (显示全部详细内容)
    case neighborPeek     // 隔壁的 item，略微伸出来一点 (不显示内容，作为精致手柄/Tab)
    case dockedFlush      // 剩下的不弹出，贴边保持原状
}

public enum ItemSteppedDrawerCalculator {
    public static func state(for index: Int, activeIndex: Int?, totalCount: Int) -> ItemDrawerState {
        guard let activeIndex = activeIndex, activeIndex >= 0, activeIndex < totalCount else {
            return .dockedFlush
        }
        if index == activeIndex {
            return .expandedDrawer
        } else if abs(index - activeIndex) == 1 {
            return .neighborPeek
        } else {
            return .dockedFlush
        }
    }
}
