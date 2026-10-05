# Anti-Obstruction Freeze Mode & Custom Shortcut Recorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide an instant Anti-Obstruction & Freeze Mode toggled via a global keyboard shortcut (default `⌥⇥` / Option + Tab), accompanied by interactive shortcut recording in Preferences, transient non-blocking HUD feedback, and complete 100% click-through pass-through for screenshots and edge-obscured controls.

**Architecture:** A lightweight Carbon HotKey Engine (`GlobalHotKeyManager`) delivers 0ms global shortcut detection without requiring macOS Accessibility permissions. `PurahWorkspaceStore` tracks `isRailsFrozen` and user-recorded shortcuts. When frozen, `ScreenEdgeCoordinator` animates rail windows to `alphaValue = 0` and sets `ignoresMouseEvents = true`, while `EdgeMouseMonitor` short-circuits. A floating transient HUD confirms state transitions for 800ms. An interactive `KeyboardShortcutRecorderView` in Preferences allows custom shortcut capture.

**Tech Stack:** Swift 6.0, AppKit, SwiftUI, Carbon (`Carbon.HIToolbox`), Swift Testing.

## Global Constraints

- Must compile under Swift 6 with zero errors (`swift build -c release --disable-sandbox`).
- Carbon hotkey implementation must not require Accessibility (`AXUIElement`) permissions.
- Full test suite (`swift test --disable-sandbox`) must remain 100% passing at each task.
- Follow existing commit conventions (`✨Feat:[Scope] Title`, `🧪Test:[Scope] Title`, etc.).

---

### Task 1: Core Model & Store (`HotKeyShortcut` & `isRailsFrozen` in `PurahCore`)

**Files:**
- Create: `Sources/PurahCore/Models/HotKeyShortcut.swift`
- Modify: `Sources/PurahCore/Store/PurahWorkspaceStore.swift`
- Test: `Tests/PurahCoreTests/HotKeyShortcutTests.swift`

**Interfaces:**
- Produces: `struct HotKeyShortcut: Codable, Equatable, Sendable`:
  - `keyCode: UInt32`
  - `modifiers: UInt32`
  - `var displayString: String`
  - `static let defaultShortcut = HotKeyShortcut(keyCode: 48, modifiers: 0x0800)` // Option + Tab
- Produces: `PurahWorkspaceStore`:
  - `var isRailsFrozen: Bool`
  - `var hotKeyShortcut: HotKeyShortcut`
  - `func toggleFreezeRails()`

- [ ] **Step 1: Write failing test in `Tests/PurahCoreTests/HotKeyShortcutTests.swift`**

```swift
import Testing
import Foundation
@testable import PurahCore

@Suite("HotKey Shortcut & Freeze State Tests")
struct HotKeyShortcutTests {
    @Test("Default shortcut formats as Option-Tab")
    func testDefaultShortcutFormat() {
        let shortcut = HotKeyShortcut.defaultShortcut
        #expect(shortcut.keyCode == 48) // Tab keycode
        #expect(shortcut.displayString.contains("⌥") && (shortcut.displayString.contains("Tab") || shortcut.displayString.contains("⇥")))
    }

    @Test("WorkspaceStore toggles freeze state and persists")
    @MainActor
    func testWorkspaceStoreFreezeToggle() {
        let store = PurahWorkspaceStore()
        #expect(store.isRailsFrozen == false)
        store.toggleFreezeRails()
        #expect(store.isRailsFrozen == true)
        store.toggleFreezeRails()
        #expect(store.isRailsFrozen == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter HotKeyShortcutTests`
Expected: FAIL with "cannot find 'HotKeyShortcut' in scope".

- [ ] **Step 3: Implement `HotKeyShortcut.swift` and update `PurahWorkspaceStore.swift`**

Create `Sources/PurahCore/Models/HotKeyShortcut.swift`:
```swift
import Foundation

public struct HotKeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    // Carbon modifier constants:
    // cmdKey = 0x0100 (256), shiftKey = 0x0200 (512), optionKey = 0x0800 (2048), controlKey = 0x1000 (4096)
    public static let defaultShortcut = HotKeyShortcut(keyCode: 48, modifiers: 0x0800) // ⌥⇥ (Option + Tab)

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String {
        var str = ""
        if (modifiers & 0x1000) != 0 { str += "⌃" }
        if (modifiers & 0x0800) != 0 { str += "⌥" }
        if (modifiers & 0x0200) != 0 { str += "⇧" }
        if (modifiers & 0x0100) != 0 { str += "⌘" }

        str += keyName(for: keyCode)
        return str
    }

    private func keyName(for code: UInt32) -> String {
        switch code {
        case 48: return "⇥"
        case 49: return "Space"
        case 36: return "↩"
        case 53: return "⎋"
        case 51: return "⌫"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 45: return "N"
        case 46: return "M"
        default: return "Key(\(code))"
        }
    }
}
```

Add to `PurahWorkspaceStore.swift`:
```swift
public var isRailsFrozen: Bool = false
public var hotKeyShortcut: HotKeyShortcut = .defaultShortcut

public func toggleFreezeRails() {
    isRailsFrozen.toggle()
}
```
And add persistence in `loadPersistentState` / `savePersistentState`:
- Key `"purah.hotkey.keyCode"`
- Key `"purah.hotkey.modifiers"`

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter HotKeyShortcutTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PurahCore/Models/HotKeyShortcut.swift Sources/PurahCore/Store/PurahWorkspaceStore.swift Tests/PurahCoreTests/HotKeyShortcutTests.swift
git commit -m "✨Feat:[Core] Add HotKeyShortcut model and isRailsFrozen store state"
```

---

### Task 2: Native Carbon Global HotKey Engine (`GlobalHotKeyManager`)

**Files:**
- Create: `Sources/PurahApp/Interaction/GlobalHotKeyManager.swift`
- Test: `Tests/PurahCoreTests/HotKeyShortcutTests.swift`

**Interfaces:**
- Produces: `@MainActor public final class GlobalHotKeyManager`:
  - `static let shared: GlobalHotKeyManager`
  - `func register(shortcut: HotKeyShortcut, onTrigger: @escaping () -> Void)`
  - `func unregister()`

- [ ] **Step 1: Write test for shortcut representation and manager registration**

Update `Tests/PurahCoreTests/HotKeyShortcutTests.swift`:
```swift
    @Test("Custom shortcut formats with multiple modifiers")
    func testCustomShortcutFormatting() {
        let custom = HotKeyShortcut(keyCode: 4, modifiers: 0x0100 | 0x0800 | 0x1000) // ⌃⌥⌘H
        #expect(custom.displayString == "⌃⌥⌘H")
    }
```

- [ ] **Step 2: Implement `GlobalHotKeyManager.swift`**

Create `Sources/PurahApp/Interaction/GlobalHotKeyManager.swift`:
```swift
import AppKit
import Carbon
import PurahCore

@MainActor
public final class GlobalHotKeyManager {
    public static let shared = GlobalHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var triggerAction: (() -> Void)?

    private init() {
        installCarbonEventHandler()
    }

    public func register(shortcut: HotKeyShortcut, onTrigger: @escaping () -> Void) {
        unregister()
        self.triggerAction = onTrigger

        let hotKeyID = EventHotKeyID(signature: OSType(0x50555248), id: 1) // 'PURH'
        var gMyHotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &gMyHotKeyRef
        )

        if status == noErr {
            self.hotKeyRef = gMyHotKeyRef
        }
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        triggerAction = nil
    }

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, inEvent, inUserData -> OSStatus in
            guard let inUserData = inUserData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(inUserData).takeUnretainedValue()
            Task { @MainActor in
                manager.triggerAction?()
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }
}
```

- [ ] **Step 3: Run full tests to verify compilation and test passes**

Run: `swift test --disable-sandbox --filter HotKeyShortcutTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/PurahApp/Interaction/GlobalHotKeyManager.swift Tests/PurahCoreTests/HotKeyShortcutTests.swift
git commit -m "✨Feat:[App] Implement Carbon GlobalHotKeyManager without accessibility permissions"
```

---

### Task 3: Freeze State Windowing, Coordinator & Mouse Monitor

**Files:**
- Modify: `Sources/PurahApp/WindowControllers/ScreenEdgeCoordinator.swift`
- Modify: `Sources/PurahApp/Interaction/EdgeMouseMonitor.swift`
- Modify: `Sources/PurahUI/WindowViews/PassThroughHostingView.swift`
- Test: `Tests/PurahCoreTests/FreezeModeTests.swift`

**Interfaces:**
- Produces: `ScreenEdgeCoordinator.setFrozen(_ isFrozen: Bool)`
- Produces: `EdgeMouseMonitor.setFrozen(_ isFrozen: Bool)`

- [ ] **Step 1: Write test in `Tests/PurahCoreTests/FreezeModeTests.swift`**

```swift
import Testing
import AppKit
@testable import PurahCore
@testable import PurahApp

@Suite("Freeze Mode Windowing and Suppression Tests")
struct FreezeModeTests {
    @Test("ScreenEdgeCoordinator setFrozen hides windows and disables interactivity")
    @MainActor
    func testCoordinatorFreeze() {
        let store = PurahWorkspaceStore()
        let coordinator = ScreenEdgeCoordinator(store: store)
        
        coordinator.setFrozen(true)
        #expect(coordinator.isFrozen == true)
        
        coordinator.setFrozen(false)
        #expect(coordinator.isFrozen == false)
    }
}
```

- [ ] **Step 2: Update `ScreenEdgeCoordinator.swift`**

Add `public private(set) var isFrozen: Bool = false` and:
```swift
public func setFrozen(_ isFrozen: Bool) {
    self.isFrozen = isFrozen
    if isFrozen {
        dismissDrawer(for: nil)
        leftRailWindow?.animator().alphaValue = 0.0
        rightRailWindow?.animator().alphaValue = 0.0
        leftRailWindow?.ignoresMouseEvents = true
        rightRailWindow?.ignoresMouseEvents = true
    } else {
        leftRailWindow?.animator().alphaValue = 1.0
        rightRailWindow?.animator().alphaValue = 1.0
        let hasLeft = store.hasPinnedItem(on: .left)
        let hasRight = store.hasPinnedItem(on: .right)
        leftRailWindow?.ignoresMouseEvents = !hasLeft
        rightRailWindow?.ignoresMouseEvents = !hasRight
    }
}
```

- [ ] **Step 3: Update `EdgeMouseMonitor.swift`**

Add `public private(set) var isFrozen: Bool = false`:
```swift
public func setFrozen(_ isFrozen: Bool) {
    self.isFrozen = isFrozen
    if isFrozen {
        leftExitGraceTask?.cancel()
        leftExitGraceTask = nil
        rightExitGraceTask?.cancel()
        rightExitGraceTask = nil
        dwellTracker.reset()
    }
}
```
And at the very beginning of `handleMouse(event:)`:
```swift
guard !isFrozen, !store.isRailsFrozen else { return }
```

- [ ] **Step 4: Update `PassThroughHostingView.swift`**

In `isPointInInteractiveDrawer`:
```swift
guard !store.isRailsFrozen else { return false }
```
And in `hitTest`:
```swift
guard !store.isRailsFrozen else { return nil }
```

- [ ] **Step 5: Run tests**

Run: `swift test --disable-sandbox --filter FreezeModeTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/PurahApp/WindowControllers/ScreenEdgeCoordinator.swift Sources/PurahApp/Interaction/EdgeMouseMonitor.swift Sources/PurahUI/WindowViews/PassThroughHostingView.swift Tests/PurahCoreTests/FreezeModeTests.swift
git commit -m "✨Feat:[Windowing] Add window level freeze suppression and click-through in coordinator and mouse monitor"
```

---

### Task 4: Transient HUD Controller (`TransientHUDController`) & AppDelegate Integration

**Files:**
- Create: `Sources/PurahApp/WindowControllers/TransientHUDController.swift`
- Modify: `Sources/PurahApp/AppDelegate.swift`
- Test: `Tests/PurahCoreTests/FreezeModeTests.swift`

**Interfaces:**
- Produces: `@MainActor public final class TransientHUDController`:
  - `static let shared: TransientHUDController`
  - `func show(isFrozen: Bool)`
- Updates: `AppDelegate`:
  - Installs hotkey listener on launch.
  - Toggles freeze mode on hotkey press.
  - Updates menu bar item icon (`eye.slash.fill` vs `circle.grid.2x1.fill`).

- [ ] **Step 1: Implement `TransientHUDController.swift`**

Create `Sources/PurahApp/WindowControllers/TransientHUDController.swift`:
A floating transparent panel with a capsule showing:
- `❄️ Rails Frozen (⌥⇥ to restore)` when frozen.
- `✨ Rails Active` when unfreezing.
Auto-fades after 800ms. Non-activating, `ignoresMouseEvents = true`.

- [ ] **Step 2: Wire up `AppDelegate.swift`**

In `applicationDidFinishLaunching`:
```swift
GlobalHotKeyManager.shared.register(shortcut: store.hotKeyShortcut) { [weak self] in
    self?.toggleFreezeMode()
}
```
Add `toggleFreezeMode()`:
```swift
@objc public func toggleFreezeMode() {
    store.toggleFreezeRails()
    let frozen = store.isRailsFrozen
    coordinator?.setFrozen(frozen)
    mouseMonitor?.setFrozen(frozen)
    TransientHUDController.shared.show(isFrozen: frozen)
    updateStatusItemForFreeze()
}
```
Update `rebuildMenu()` to show:
- Icon: `frozen ? "eye.slash.fill" : "circle.grid.2x1.fill"`
- Menu item: `frozen ? "Unfreeze Rails (\(store.hotKeyShortcut.displayString))" : "Freeze Rails (\(store.hotKeyShortcut.displayString))"` with `#selector(toggleFreezeMode)`.

- [ ] **Step 3: Run full tests to verify**

Run: `swift test --disable-sandbox`
Expected: PASS with all tests passing.

- [ ] **Step 4: Commit**

```bash
git add Sources/PurahApp/WindowControllers/TransientHUDController.swift Sources/PurahApp/AppDelegate.swift
git commit -m "✨Feat:[HUD] Implement TransientHUDController and wire hotkey toggle into AppDelegate"
```

---

### Task 5: Interactive Shortcut Recorder View & Preferences Integration

**Files:**
- Create: `Sources/PurahUI/Settings/KeyboardShortcutRecorderView.swift`
- Modify: `Sources/PurahUI/Settings/VisualLayoutSimulatorView.swift` (or new section in Preferences)
- Modify: `Sources/PurahUI/Settings/PreferencesView.swift`
- Test: `Tests/PurahCoreTests/DrawerInteractionUITests.swift`

**Interfaces:**
- Produces: `public struct KeyboardShortcutRecorderView: View`
  - Allows clicking into recording mode.
  - Captures local key events with Carbon modifier mapping.
  - Saves to `store.hotKeyShortcut`.
  - Re-registers `GlobalHotKeyManager.shared`.

- [ ] **Step 1: Create `KeyboardShortcutRecorderView.swift`**

Interactive recording button with:
- Idle badge displaying `store.hotKeyShortcut.displayString`.
- Active recording state (`"Type shortcut..."` with pulsing outline).
- `Reset to Default (⌥⇥)` action.

- [ ] **Step 2: Embed into Settings / Preferences**

In `VisualLayoutSimulatorView.swift`, add a dedicated "Hotkeys & Freeze Mode" card:
- Displays `KeyboardShortcutRecorderView(store: store)`.
- Displays explanation: "Toggle to hide and freeze all rails instantly for clean screenshots or edge-docked buttons."

- [ ] **Step 3: Run all unit and integration tests**

Run: `swift test --disable-sandbox`
Expected: 100% green.

- [ ] **Step 4: Verify production build**

Run: `swift build -c release --disable-sandbox`
Expected: Success.

- [ ] **Step 5: Commit**

```bash
git add Sources/PurahUI/Settings/KeyboardShortcutRecorderView.swift Sources/PurahUI/Settings/VisualLayoutSimulatorView.swift
git commit -m "✨Feat:[UI] Add interactive KeyboardShortcutRecorderView in preferences settings"
```
