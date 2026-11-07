# Purah Road Map

The order below is not "what would be fun to build". It is the order in which
things stop a stranger from using Purah, then stop them from trusting it, then
stop them from keeping it.

Last reviewed: 2026-11-07 (v0.7.18)

---

## Where the product stands

| Area | State |
|---|---|
| Features | 10 built-in plugins; the feature set is deeper than most tools in this space |
| Quality | 1,197 tests in 137 suites, strict concurrency, source-level guards for tooltips and motion tokens, and a pixel-level render test for the header tint |
| Distribution | Self-signed, on a self-hosted Homebrew tap. Grants survive updates and `brew` installs cleanly; **a DMG download from the website still hits Gatekeeper** |
| Ecosystem | Complete plugin ABI and a developer guide, but the marketplace has no published catalog (`PluginCatalogService.catalogURL` is `nil`) and nothing downloads a plugin: the only install path is Developer Mode |
| Trust | Permission matrix, risk classification, checksums, signature verification, and a per-permission review sheet before a catalog install. **A sideloaded package still mounts without one** — its manifest does not exist until it has been compiled |
| Resources | ~33–46 MB physical footprint idle (Music.app running adds ~8–13 MB), ~53 MB worst case after touring every pod with the process tab open. The old "~156 MB" figure was `ps` RSS, which counts shared read-only framework pages — `__TEXT` alone is 564 MB resident inside the 2.9 GB dyld shared cache. ~1.1–1.2% idle CPU; the Vitals drawer used to add ~6.3% while it was open, it now adds ~1.7–1.9% (v0.7.15) |
| Diagnostics | A local crash reporter (`crash-log.txt`, never uploaded), launch-health and update-install markers, and an exportable diagnostic log. No telemetry and no remote reporting |

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
      dlopens a plugin, list what it declares and what denial costs. **Half
      done (v0.7.18):** a catalog install now goes through
      `SecurityConfirmationSheet`, which lists every declared capability and
      its consequence. The sideload path still mounts silently, because the
      manifest does not exist until the package has been compiled — the
      confirmation has to sit between "compiled" and "registered".
- [ ] **1.2 Third-party plugin lifecycle** — install, list, update, remove.
      **Half done (v0.7.18):** install, rebuild from the remembered package
      folder, list (Marketplace + the System storage table), remove with
      confirmation, and re-load on the next launch all exist. Missing: update
      from a source, and a management surface that is not Developer Mode.
      Start from the existing `PluginStorageInspectorView`, which already knows
      every plugin on disk.
- [ ] **1.3 Marketplace: fill it or hide it** — the invented catalog is gone
      (it mounted pods that could only render their own description back).
      `PluginCatalogService` was added to read a published index, but
      `catalogURL` is `nil`, nothing downloads a plugin from `downloadUrl`, and
      `PluginMarketManager.install(id:)` refuses any id without a registered
      implementation — so the shelf lists the built-ins and nothing else.
      Either publish a catalog *and* a downloader, or say on the page that
      this Purah installs built-ins only.
- [ ] **1.4 Plugin scaffold** — one command that produces a buildable, loadable
      empty plugin. `Examples/PurahExamplePlugin` is the reference; the
      scaffold removes the "read 300 lines of guide first" tax.

## Phase 2 — Making it worth keeping

- [ ] **2.1 Energy and memory budget** — measure an idle baseline, fail CI when
      it regresses, then hunt the resident timers and always-mounted views.
      The tagline is "ultra-lightweight"; the footprint has to be earned or the
      tagline has to change. **Measure `phys_footprint`, never `ps` RSS** —
      RSS counts shared framework pages and made the old figure 3× too high
      (156 MB vs 46 MB for the same process). A drawer that adds 6% while it
      is open is the same problem in miniature — v0.7.15 fixed the one case
      that was measured, not the class.
- [ ] **2.2 Localization** — zh-Hant is complete; es carries 169 keys and
      ja/ko/fr/de 151 each, so they fall back to English for most of the app.
      Either finish them or drop them from the language picker. Shipping a
      half-translated language is worse than shipping two good ones.
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
