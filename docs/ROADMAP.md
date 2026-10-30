# Purah Road Map

The order below is not "what would be fun to build". It is the order in which
things stop a stranger from using Purah, then stop them from trusting it, then
stop them from keeping it.

Last reviewed: 2026-10-30 (v0.7.4)

---

## Where the product stands

| Area | State |
|---|---|
| Features | 10 built-in plugins; the feature set is deeper than most tools in this space |
| Quality | 870+ tests, strict concurrency, source-level guards for tooltips and motion tokens |
| Distribution | Self-signed, on a self-hosted Homebrew tap. Grants survive updates and `brew` installs cleanly; **a DMG download from the website still hits Gatekeeper** |
| Ecosystem | Complete plugin ABI and a developer guide, but the marketplace ships only the built-ins and the only install path is Developer Mode |
| Trust | Permission matrix, risk classification, checksums, signature verification — but **nothing is said at install time** |
| Resources | ~184 MB resident, ~2.4% idle CPU measured. That is the gap between the tagline and the product |
| Diagnostics | No crash reporter and no telemetry. When it breaks, the only report is the user's description |

---

## Phase 0 — Blockers. Ship nothing public until these are done

- [x] **0.1 Distribution without Gatekeeper** — decided 2026-10-30: a
      self-hosted Homebrew tap instead of the $99 Developer ID, and it is live:
      `brew install --cask rheatin/tap/purah`. The official `homebrew/cask` tap
      quarantines downloads and drops casks that fail Gatekeeper, so it cannot
      carry an unnotarized app; a personal tap can. `release.sh` writes
      `dist/purah.rb` on every release and the generated cask is verified to
      download and checksum-match. Notarization is deferred, not cancelled — it
      is the only way to stop the wall for people who download the DMG
      directly, and it stays a Phase 0 item. See
      [`OWNER_ACTIONS.md`](OWNER_ACTIONS.md).
- [x] **0.2 First launch for someone who is not the author** —
      a denied pod used to look identical to an empty one; Calendar and Todo now
      say which it is and offer the grant in place. Decided the open question
      the same day: onboarding **does** ask, but only at the end, in one panel
      with one row per permission an installed plugin declares. Each row is its
      own click, because each one raises its own macOS sheet. Skipping costs
      exactly those features and nothing else. The panel and the settings
      matrix read the same `PermissionInventory`, so neither can list a
      permission the other misses.
- [x] **0.3 Failure visibility** —
      a failed in-place update is reported at the next launch
      (`UpdateInstallMarker`); an abnormal exit is reported at the next launch
      (`LaunchHealthMarker`, added in this release). Both point at the
      diagnostic log.
- [x] **0.4 Update channel** —
      the release manifest is read from the release CDN rather than the
      rate-limited API; a stuck check can no longer spin forever (deadline +
      generation guard); a failed check offers a retry.

## Phase 1 — Making it safe to install

- [ ] **1.1 Install-time permission consent** — before `Dev: Load Package...`
      dlopens a plugin, list what it declares and what denial costs. The
      declaration and request paths exist; only the confirmation is missing.
- [ ] **1.2 Third-party plugin lifecycle** — install, list, update, remove.
      Today a third-party plugin is installable only in Developer Mode and has
      no management surface afterwards. Start from the existing
      `PluginStorageInspectorView`, which already knows every plugin on disk.
- [ ] **1.3 Marketplace: fill it or hide it** — `fullCatalog` is
      `builtInCatalog`. An empty shelf reads worse than no shelf.
- [ ] **1.4 Plugin scaffold** — one command that produces a buildable, loadable
      empty plugin. `Examples/PurahExamplePlugin` is the reference; the
      scaffold removes the "read 300 lines of guide first" tax.

## Phase 2 — Making it worth keeping

- [ ] **2.1 Energy and memory budget** — measure an idle baseline, fail CI when
      it regresses, then hunt the resident timers and always-mounted views.
      The tagline is "ultra-lightweight"; 184 MB has to be earned or the
      tagline has to change.
- [ ] **2.2 Localization** — zh-Hant is complete; ja/ko/fr/de/es carry 70–90
      keys and fall back to English partway. Either finish them or drop them
      from the language picker. Shipping a half-translated language is worse
      than shipping two good ones.
- [ ] **2.3 Defaults for strangers** — the shipped default layout is the
      author's taste. A first run should be legible before it is personal.

## Phase 3 — Growth

- [ ] Shortcuts / URL scheme / scripting API, so other tools can drive Purah
- [ ] Accessibility pass (VoiceOver never covered the rails)
- [ ] Community plugin directory

---

## Explicitly not doing

Named here so they stop resurfacing:

- iOS, iPadOS or Windows companions
- Cloud sync — the JSON export/import in Configuration Backup covers it
- A theme marketplace
- A plugin sandbox: the cost outweighs the benefit. Permission declaration plus
  install-time consent is the trade this product can afford.
