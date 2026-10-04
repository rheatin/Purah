// Sources/PurahCore/Models/ItemDrawerState.swift
import Foundation

public enum ItemDrawerState: Sendable, Equatable {
    case expandedDrawer  // Fully extruded drawer showing detailed contents
    case neighborPeek    // Immediate neighbor peeking out as an accent tab
    case dockedFlush     // Docked flush against the edge rail
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
