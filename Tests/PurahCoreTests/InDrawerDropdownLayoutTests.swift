// Tests/PurahCoreTests/InDrawerDropdownLayoutTests.swift
import Foundation
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("In-Drawer Dropdown Layout")
struct InDrawerDropdownLayoutTests {
    @Test("No open panels produce no interactive frame")
    func emptyFrameUnionIsNil() {
        #expect(InDrawerDropdownFrameMath.union(of: []) == nil)
        #expect(InDrawerDropdownFrameMath.union(of: [.zero]) == nil)
    }

    @Test("Multiple open panels contribute one bounding frame")
    func frameUnionCoversEveryPanel() {
        let first = CGRect(x: 20, y: 40, width: 160, height: 80)
        let second = CGRect(x: 100, y: 10, width: 120, height: 60)

        #expect(
            InDrawerDropdownFrameMath.union(of: [first, second])
                == CGRect(x: 20, y: 10, width: 200, height: 110)
        )
    }

    @Test("Dismissing the drawer clears a reported dropdown frame")
    @MainActor
    func drawerDismissalClearsDropdownFrame() {
        let suiteName = "test_dropdown_frame_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PurahWorkspaceStore(userDefaults: defaults)
        store.activeDropdownScreenFrame = CGRect(x: 10, y: 20, width: 80, height: 40)

        store.dismissActiveDrawer()

        #expect(store.activeDropdownScreenFrame == nil)
    }
}
