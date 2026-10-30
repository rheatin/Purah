# Owner Actions

`README.md` is for people installing Purah. This file is for the person
shipping it: things only you can do, decisions that are waiting on you, and
known gaps. Product-level gaps live in [`ROADMAP.md`](ROADMAP.md).

Last reviewed: 2026-10-30 (v0.7.3)

---

## 1. Homebrew tap (self-hosted) — published

**Decision (2026-10-30): self-hosted tap, no Apple Developer Program.** Purah
is not notarized, so the official `homebrew/cask` tap will not carry it —
Homebrew quarantines cask downloads on purpose and removes casks that fail
Gatekeeper. A personal tap is not audited that way, so it can.

Live at [`github.com/rheatin/homebrew-tap`](https://github.com/rheatin/homebrew-tap),
installed with:

```bash
brew install --cask rheatin/tap/purah
```

The three parts are `user/tap/cask` — Homebrew's fully qualified form, which
also taps the repo on the way in, so it is the single command to publish.
Homebrew 5 asks users to trust a third-party tap first (`brew trust rheatin/tap`),
and answers that with an error rather than a prompt, so the caveat has to be in
the README.

**Every release:** copy `dist/purah.rb` (written by `release.sh`, with the
version and ZIP checksum filled in) to `Casks/purah.rb` in the tap repo, commit
and push. That generated file is the only place those two values are written —
never hand-edit the tap copy.

Homebrew 5 rejected three stanzas the first time the cask was installed, so the
template now uses the current forms and should not drift back:
`depends_on macos: :sonoma` (not `">= :sonoma"`), no `verified:` on `url`, and
`postflight_steps do run … end` (not `postflight do system_command … end`). Paths
inside that block are `{{appdir}}` template tokens, not Ruby `appdir` — the Ruby
constant does not exist in the steps DSL and fails at cask load.


5. Once the tap works, add the install line to `README.md` §Install.

**What the cask does to Gatekeeper, and why.** Its `postflight` removes
`com.apple.quarantine` from the installed app. Homebrew applies that flag
deliberately so Gatekeeper can judge a download — but a self-signed build has
no notarization for Gatekeeper to accept, so the verdict would always be
"cannot be opened". Clearing it leaves the app in the same state as one built
locally. The DMG path from the Releases page still goes through Gatekeeper
normally. Delete the `postflight` block the day a Developer ID signs a release.

---

## 2. Developer ID + notarization — deferred, not cancelled

$99/year, owner action, and the only thing that would change:

- people downloading the DMG from the website stop hitting the Gatekeeper wall;
- `spctl --assess` passes, so MDM and security tooling stop refusing the app;
- the cask's `postflight` block can be deleted.

It does **not** buy TCC stability. The self-signed `Purah Local` identity already
gives a designated requirement that survives updates, so calendar and reminders
are not re-prompted on every build.

The plumbing is already here:

- `release.sh` notarizes whenever `PURAH_NOTARY_PROFILE` is set
  (`xcrun notarytool store-credentials purah-notary …` once).
- `signing-identity.sh` resolves `APPLE_SIGNING_IDENTITY` first, so setting that
  environment variable is the whole switch.

One-time cost when you do switch: calendar and reminders prompts appear exactly
once more, because the designated requirement changes identity.

---

## 3. Release runbook

```bash
./build.sh --configuration release      # build/Purah.app
PURAH_SIGN_IDENTITY="Developer ID Application: …" \
PURAH_NOTARY_PROFILE="purah-notary" \
  ./release.sh --publish                # bump, build, sign, notarize, publish
```

Both environment variables are optional. Without them the build is signed with
the local `Purah Local` identity and is not notarized.

`release.sh --publish` refuses to run unless the tree is clean, the branch is
`main`, and local `main` contains `origin/main` — a release tagged from an
unmerged branch ships assets that do not match the commit its tag points at.

The DMG carries `Install Purah.command` and `Read Me.txt` from `packaging/`.
The script is what makes an unnotarized build openable: it copies the app into
Applications and clears the quarantine flag, and it says so in the file where
anyone can read it before running it.

Signing decides what the in-app updater can do:

| Build | Self-update | Why |
|---|---|---|
| Developer ID + notarized | Installs in place and relaunches | The download's Team ID and Gatekeeper verdict can both be checked |
| Developer ID only | Installs in place | The download is matched against the published SHA-256; the publisher is known, the app is not notarized |
| Self-signed / ad-hoc | Installs in place; the dialog says the publisher cannot be proven | There is no Team ID to compare, so the SHA-256 is the whole guarantee |

---

## 4. Branches not yet shared

- `fix/updater-check-deadline` — the stuck-check deadline. Not pushed.
- `feat/roadmap-phase0` — launch health marker, Todo permission state,
  `docs/ROADMAP.md`, Drop Shelf split drop target. Not pushed.

No PR has been opened for either. Nothing outside this machine has these fixes.

---

## 5. Known gaps nobody outside can see

- **No crash reporting.** `LaunchHealthMarker` tells the next launch that the
  last one ended badly, and `DiagnosticLogger` writes a local log — but nothing
  comes back to you. Every bug report is someone's description.
- **No telemetry.** Deliberate. It also means the idle CPU and memory figures
  in `ROADMAP.md` are one machine's.
- **Only two languages are complete.** zh-Hans and zh-Hant; the rest fall back
  to English partway. See gap 2.2 in `ROADMAP.md`.
