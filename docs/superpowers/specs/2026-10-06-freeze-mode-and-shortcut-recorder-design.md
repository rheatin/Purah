# Design Spec: Anti-Obstruction Freeze Mode & Custom Shortcut Recorder

## 1. Overview
When using macOS with edge-docked utility rails (like Project Purah), two scenarios require temporary suppression of the UI:
1. **Screen Capture & Recording**: Taking clean full-screen or window screenshots without edge rails or active/pinned drawers obscuring content.
2. **Edge-Obscuring Underlying UI**: Clicking buttons, tabs, scrollbars, or sliders docked directly at the physical screen boundary in IDEs, web browsers, or full-screen applications without accidentally triggering Purah hover expansion.

This feature introduces an instant **Anti-Obstruction & Freeze Mode (防遮挡与冻结模式)** toggled via a global keyboard shortcut (default `⌥⇥` / Option + Tab), complete with interactive shortcut recording in Preferences, transient non-blocking HUD feedback, and 100% click-through pass-through.

---

## 2. Architecture & Components

### 2.1 Carbon Global HotKey Manager (`GlobalHotKeyManager`)
- **Technology**: Native macOS Carbon Event HotKey APIs (`RegisterEventHotKey`, `UnregisterEventHotKey`, `InstallEventHandler`).
- **Permissions**: **Zero accessibility permissions required**. Carbon hotkeys fire across all spaces, full-screen apps, and secure input modes with 0ms latency.
- **Model (`HotKeyShortcut`)**:
  - `keyCode: UInt32` (Default: `48` for Tab).
  - `modifiers: UInt32` (Default: `optionKey` / `0x0800`).
  - Formatted display string helper (e.g., `"⌥Tab"` or `"⌥⇥"`).
  - Persistence in `UserDefaults` (`purah.hotkey.keyCode`, `purah.hotkey.modifiers`).

### 2.2 Freeze State & Window Management (`ScreenEdgeCoordinator` & `PurahWorkspaceStore`)
- **Store State**: `store.isRailsFrozen: Bool` (persisted or runtime toggle).
- **When Freeze is Activated (`isRailsFrozen = true`)**:
  1. `ScreenEdgeCoordinator.setFrozen(true)`:
     - Retracts all unpinned and pinned drawer cards smoothly (`response: 0.18, dampingFraction: 0.92`).
     - Sets `alphaValue = 0.0` on both `leftRailWindow` and `rightRailWindow`.
     - Forces `ignoresMouseEvents = true` on both windows.
  2. `EdgeMouseMonitor.setFrozen(true)`:
     - Short-circuits mouse handling on the very first line (`guard !isFrozen else { return }`), producing 0% CPU consumption and preventing accidental hover expansion.
  3. `AppDelegate.updateStatusItemForFreeze()`:
     - Changes status item icon to `eye.slash.fill`.
     - Dynamically changes menu title from "Freeze Rails (⌥⇥)" to "Unfreeze Rails (⌥⇥)".
  4. `TransientHUDController.showHUD(isFrozen: true)`:
     - Presents a lightweight floating pill HUD (`❄️ Rails Frozen`) for 800ms that fades away automatically.
- **When Freeze is Deactivated (`isRailsFrozen = false`)**:
  1. Windows fade back to `alphaValue = 1.0`.
  2. Edge hover detection resumes normally.
  3. Status item returns to `circle.grid.2x1.fill`.
  4. HUD displays `✨ Rails Active`.

### 2.3 Transient Floating HUD (`TransientHUDController`)
- **Window Attributes**:
  - Borderless `.floating` NSPanel, `.nonactivatingPanel`.
  - `ignoresMouseEvents = true` (never intercepts clicks or steals focus).
  - Placed at lower center of the screen (`visibleFrame.midX`, `visibleFrame.minY + 80`).
- **Appearance**: Translucent dark frosted glass capsule with SF Symbol and typography.
- **Lifetime**: 800ms duration, then dissolves cleanly.

### 2.4 Interactive Shortcut Recorder (`KeyboardShortcutRecorderView`)
- **Location**: `PreferencesView` under a new or integrated "Keyboard & Hotkeys" section (in General or Settings).
- **Interactions**:
  - **Idle State**: Displays key badge pill (e.g., `⌥ Tab`).
  - **Recording State**: Clicking the badge enters recording mode with a pulsing border and `"Press shortcut..."`.
  - **Capture**: Monitors `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`.
  - **Validation**:
    - Requires at least one modifier (`Command`, `Option`, `Control`, `Shift`) unless a function key (F1-F12) is pressed.
    - `Escape` cancels recording and retains the previous shortcut.
    - Provides a "Reset to Default (⌥⇥)" button.
  - **Re-binding**: Instantly unregisters old Carbon hotkey and registers new hotkey upon capture.

---

## 3. Data Flow & State Synchronization

```
User presses ⌥⇥ (or custom shortcut)
               │
               ▼
   GlobalHotKeyManager (Carbon)
               │
               ▼
      AppDelegate.toggleFreeze()
      ┌────────┴──────────────────────────┐
      ▼                                   ▼
PurahWorkspaceStore             ScreenEdgeCoordinator
(isRailsFrozen = true)          (alpha = 0, ignoresMouse = true)
      │                                   │
      ├─────────────────┬─────────────────┤
      ▼                 ▼                 ▼
EdgeMouseMonitor   Status Item        Transient HUD
(suspended)        (eye.slash.fill)   (❄️ Rails Frozen - 800ms)
```

---

## 4. Verification & Testing Plan

1. **Unit Tests (`HotKeyManagerTests.swift`)**:
   - `testHotKeyShortcutDisplayString`: Verify correct key string formatting for `⌥⇥`, `⌃⌥⌘H`, etc.
   - `testFreezeStateStoreToggle`: Verify `store.isRailsFrozen` defaults to `false`, toggles accurately, and updates persistent state.
2. **Integration Verification (`FullIntegrationTests.swift`)**:
   - Verify `ScreenEdgeCoordinator.setFrozen(true)` sets `ignoresMouseEvents = true` on both windows.
   - Verify `EdgeMouseMonitor` suppresses candidate dwell and velocity evaluations when frozen.
3. **Build & Release**:
   - Run `swift test --disable-sandbox`.
   - Run `swift build -c release --disable-sandbox`.
