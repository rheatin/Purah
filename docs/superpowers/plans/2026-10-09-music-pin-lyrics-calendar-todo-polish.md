# Music Pin, Artwork, Lyrics, Calendar & Todo Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate duplicate pin buttons across all plugins, fix music artwork loss during track switching, update music source badge to music.note, add native local lyrics for tall music drawers, propagate native calendar/reminder category colors to rail chips, and make calendar drawer cards dynamically adapt to height across three tiers.

**Architecture:**
- **Pin Button Deduplication:** Standardize drawer headers so exactly 1 pin button is rendered per card.
- **Music Artwork Engine:** Update `MusicPluginState` and `SystemMusicSyncService` to cache and fetch artwork immediately on notification without dropping artwork data during in-drawer track changes.
- **Apple Music Local Lyrics:** Extract `lyrics of current track` via AppleScript into `MusicTrackInfo.lyrics`. Render flowing lyrics view in `MusicDrawerView` when height $\ge 260\text{pt}$ and lyrics are non-empty.
- **EventKit Category Colors:** Extract `cgColor` from `EKCalendar` for events and reminders, map to hex, and feed into `PurahPluginSubItem.tintColorHex` to colorize individual rail chips and card badges.
- **Calendar Responsive Tiers:** Update `CalendarItemDrawerView` with 3 height tiers: Compact ($< 65\text{pt}$), Standard ($65\text{pt} \le h < 120\text{pt}$), and Flagship ($\ge 120\text{pt}$).

**Tech Stack:** Swift 6.0+, SwiftUI, AppKit, EventKit, Observation framework, Swift Testing.

## Global Constraints
- Target macOS 14.0+.
- Zero compiler warnings with `-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`.
- Strict concurrency checked across all modified files.
- No network requests for lyrics (local Apple Music AppleScript only per user directive).
- Tests must pass with `swift test --disable-sandbox -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --no-parallel`.

---

### Task 1: Eliminate Duplicate Pin Buttons Across All Plugins

**Files:**
- Modify: `Sources/PurahUI/DrawerPanels/MusicDrawerView.swift:91-99, 197-205, 314-322`
- Modify: `Sources/PurahUI/DrawerPanels/CalendarDrawerView.swift:259-261`
- Modify: `Sources/PurahUI/Plugins/CommunityPodPlugin.swift:63-65`
- Test: `Tests/PurahCoreTests/DrawerInteractionUITests.swift`

**Interfaces:**
- Produces: Drawer views that do not duplicate the pin button rendered by outer `AmbientRailStripView.pluginDrawerCard`.

- [ ] **Step 1: Check existing pin buttons in drawer views**
Identify all drawer panels where `PurahPinButton` is included internally despite being wrapped by `pluginDrawerCard`.
Remove the internal `PurahPinButton` from `MusicDrawerView` (Tier 1, Tier 2, Tier 3), `CalendarDrawerView`, and `CommunityPodPlugin`.

- [ ] **Step 2: Update `MusicDrawerView.swift`**
In `MusicDrawerView.swift`, remove the internal `PurahPinButton` in all three tiers:
- Tier 1: Lines 93-98
- Tier 2: Lines 199-204
- Tier 3: Lines 316-321
Also remove duplicate `CalendarDrawerView.swift:259` and `CommunityPodPlugin.swift:64`.

- [ ] **Step 3: Run test suite to verify tests pass**
Run: `swift test --filter DrawerInteractionUITests --disable-sandbox`
Expected: PASS

- [ ] **Step 4: Commit Task 1**
```bash
git add Sources/PurahUI/DrawerPanels/ Sources/PurahUI/Plugins/CommunityPodPlugin.swift
git commit -m "🐛Fix:[UI] Eliminate duplicate pin buttons in Music, Calendar and Community drawer cards"
```

---

### Task 2: Fix Music Artwork Loss on Track Switch & Update Badge to Music Note Icon

**Files:**
- Modify: `Sources/PurahUI/Plugins/BuiltInPluginStates.swift:487-545`
- Modify: `Sources/PurahCore/Services/SystemMusicSyncService.swift:262-300`
- Modify: `Sources/PurahUI/DrawerPanels/MusicDrawerView.swift:484-493`
- Test: `Tests/PurahCoreTests/MusicSyncTests.swift`

**Interfaces:**
- Produces:
  - `MusicPluginState`: preserves existing artwork or loads cached artwork on track notification, and immediately triggers async `fetchArtwork` so artwork never disappears when skipping tracks in an open drawer.
  - `MusicDrawerView`: renders `music.note` badge instead of `apple.logo` for Apple Music.

- [ ] **Step 1: Update `MusicDrawerView.sourceIconName` to use `music.note` for Apple Music**
In `MusicDrawerView.swift:491`, replace `"apple.logo"` with `"music.note"`.

- [ ] **Step 2: Fix artwork retention and automatic fetching in `BuiltInPluginStates.swift`**
In `MusicPluginState`:
- Retain existing `artworkData` if the title and artist match `cachedArtworkKey`.
- When `handleAppleMusicNotification` or `handleSpotifyNotification` receives a new track, immediately fire an async Task to `SystemMusicSyncService.shared.fetchArtwork(title:artist:album:)` and update `self.track.artworkData` upon arrival.

- [ ] **Step 3: Run MusicSyncTests to verify**
Run: `swift test --filter MusicSyncTests --disable-sandbox`
Expected: PASS

- [ ] **Step 4: Commit Task 2**
```bash
git add Sources/PurahUI/Plugins/BuiltInPluginStates.swift Sources/PurahUI/DrawerPanels/MusicDrawerView.swift Sources/PurahCore/Services/SystemMusicSyncService.swift
git commit -m "🐛Fix:[Music] Prevent artwork drop on track skip and replace source badge with music.note"
```

---

### Task 3: Local Apple Music Lyrics Support in Tall Drawer Mode

**Files:**
- Modify: `Sources/PurahCore/Pods/MusicPodModel.swift`
- Modify: `Sources/PurahCore/Services/SystemMusicSyncService.swift`
- Modify: `Sources/PurahUI/Plugins/BuiltInPluginStates.swift`
- Modify: `Sources/PurahUI/DrawerPanels/MusicDrawerView.swift`
- Test: `Tests/PurahCoreTests/MusicSyncTests.swift`

**Interfaces:**
- Produces:
  - `MusicTrackInfo.lyrics: String?`
  - `SystemMusicSyncService.fetchLocalLyrics() -> String?`: queries AppleScript `tell application "Music" to get lyrics of current track` safely without network calls.
  - `MusicDrawerView`: when drawer height $\ge 260\text{pt}$ (Tier 3), if `track.lyrics` is present and non-empty, render an elegant semi-transparent scrolling lyrics sheet. If empty, cleanly preserve the vinyl/album art stage without clutter.

- [ ] **Step 1: Add `lyrics: String?` to `MusicTrackInfo`**
In `Sources/PurahCore/Pods/MusicPodModel.swift`, add `public var lyrics: String? = nil` with backward-compatible initializers.

- [ ] **Step 2: Implement `fetchLocalLyrics()` in `SystemMusicSyncService.swift`**
Add safe AppleScript method returning string of lyrics for Apple Music. Update `pollCurrentPlayingState` and track change handling to populate `lyrics`.

- [ ] **Step 3: Update `MusicDrawerView.swift` with Lyrics section**
In Tier 3 of `MusicDrawerView.swift`:
When `track.lyrics` is available, render a scrolling lyrical stanza with smooth typography and frosted glass container. If no lyrics, cleanly retain album art.

- [ ] **Step 4: Run Music tests to verify**
Run: `swift test --filter MusicSyncTests --disable-sandbox`
Expected: PASS

- [ ] **Step 5: Commit Task 3**
```bash
git add Sources/PurahCore/Pods/MusicPodModel.swift Sources/PurahCore/Services/SystemMusicSyncService.swift Sources/PurahUI/Plugins/BuiltInPluginStates.swift Sources/PurahUI/DrawerPanels/MusicDrawerView.swift
git commit -m "✨Feat:[Music] Add local Apple Music lyrics support for tall drawer cards"
```

---

### Task 4: Calendar & Todo Native Category Colors and Display

**Files:**
- Modify: `Sources/PurahCore/Pods/TodoPodModel.swift`
- Modify: `Sources/PurahCore/Services/SystemCalendarSyncService.swift`
- Modify: `Sources/PurahCore/Services/SystemRemindersSyncService.swift`
- Modify: `Sources/PurahUI/Plugins/BuiltInPlugins.swift`
- Modify: `Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift`
- Test: `Tests/PurahCoreTests/CalendarSyncTests.swift`
- Test: `Tests/PurahCoreTests/RemindersSyncTests.swift`

**Interfaces:**
- Produces:
  - `CalendarEventItem.colorHex`: populated from `ekEvent.calendar?.cgColor`.
  - `TodoItem.listColorHex`: populated from `ekReminder.calendar?.cgColor`.
  - `CalendarPlugin.steppedItems` & `TodoPlugin.steppedItems`: passes `colorHex` / `listColorHex` to `tintColorHex`, colorizing each sub-item chip on the rail.
  - Card views render colored category badges.

- [ ] **Step 1: Update `TodoItem` to include `listColorHex: String?`**
In `Sources/PurahCore/Pods/TodoPodModel.swift`, add `public var listColorHex: String? = nil`.

- [ ] **Step 2: Extract native `cgColor` in Sync Services**
In `SystemCalendarSyncService.swift:106`, extract `colorHex` from `ekEvent.calendar?.cgColor`.
In `SystemRemindersSyncService.swift:80`, extract `listColorHex` from `rem.calendar?.cgColor`.

- [ ] **Step 3: Pass `tintColorHex` in `steppedItems`**
In `BuiltInPlugins.swift`:
- `CalendarPlugin.steppedItems`: pass `tintColorHex: event.colorHex`.
- `TodoPlugin.steppedItems`: pass `tintColorHex: todo.listColorHex`.

- [ ] **Step 4: Update card category badges in `ItemDrawerCardView.swift`**
In `TodoItemDrawerView` and `CalendarItemDrawerView`, render category pills with colored dot indicators matching the native category color.

- [ ] **Step 5: Run tests to verify**
Run: `swift test --filter CalendarSyncTests --disable-sandbox`
Run: `swift test --filter RemindersSyncTests --disable-sandbox`
Expected: PASS

- [ ] **Step 6: Commit Task 4**
```bash
git add Sources/PurahCore/Pods/ Sources/PurahCore/Services/ Sources/PurahUI/Plugins/BuiltInPlugins.swift Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift
git commit -m "✨Feat:[Events] Propagate native calendar and reminder category colors to rail chips and drawer badges"
```

---

### Task 5: Adaptive Multi-Tier Layout for Calendar Drawers

**Files:**
- Modify: `Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift`
- Test: `Tests/PurahCoreTests/DrawerInteractionUITests.swift`

**Interfaces:**
- Produces:
  - `CalendarItemDrawerView`: dynamically adapts layout based on `cardH`:
    - **Compact Tier** ($< 65\text{pt}$): 1-row compact layout.
    - **Standard Tier** ($65\text{pt} \le \text{cardH} < 120\text{pt}$): 2-row layout with category pill, title, time, and location.
    - **Flagship Tier** ($\ge 120\text{pt}$): rich calendar board card with large title, countdown, location, full action buttons.

- [ ] **Step 1: Implement 3-tier adaptive body in `CalendarItemDrawerView`**
In `ItemDrawerCardView.swift`, inspect `cardH` and branch into:
- `compactEventCard(...)`
- `standardEventCard(...)`
- `flagshipEventCard(...)`

- [ ] **Step 2: Test rendering across height variations**
Verify all 3 tiers compile cleanly without clipping.

- [ ] **Step 3: Run DrawerInteractionUITests**
Run: `swift test --filter DrawerInteractionUITests --disable-sandbox`
Expected: PASS

- [ ] **Step 4: Commit Task 5**
```bash
git add Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift
git commit -m "💄UI:[Calendar] Add three-tier responsive height adaptation to calendar drawer cards"
```

---

### Task 6: Full Verification with Strict Concurrency & Test Suite

**Files:**
- Tests across all suites

- [ ] **Step 1: Run full test suite**
Run: `swift test --disable-sandbox -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --no-parallel`
Expected: 100% pass, 0 errors, 0 warnings.

- [ ] **Step 2: Run release build**
Run: `./build.sh --configuration release`
Expected: `build/Purah.app` built and signed cleanly.

- [ ] **Step 3: Commit Task 6**
```bash
git commit --allow-empty -m "🧪Test:[Regression] Verify strict concurrency and full test suite pass on polish features"
```
