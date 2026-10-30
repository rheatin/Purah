#!/usr/bin/env bash
# ==============================================================================
# release.sh - Package Purah release distribution (DMG, ZIP, Checksums, Updates)
# ==============================================================================
set -euo pipefail

# Terminal colors
BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
MAGENTA="\033[0;35m"
RESET="\033[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$REPO_ROOT"
source "$REPO_ROOT/signing-identity.sh"

VERSION=""
SKIP_TESTS=false
SKIP_TAG=false
PUBLISH=false
BUMP_TYPE="patch"
CUSTOM_NOTES=""
CUSTOM_NOTES_FILE=""

print_usage() {
    echo -e "${BOLD}Usage:${RESET} ./release.sh [version] [options]

${BOLD}Arguments:${RESET}
  [version]                       Release version (e.g. 0.2.0).
                                  If omitted with --publish, automatically bumps patch version.
                                  If omitted without --publish, uses current version.

${BOLD}Options:${RESET}
  -v, --version <version>         Specify explicit release version
      --bump <patch|minor|major>  Version increment level (default: patch)
      --skip-tag, --no-tag        Do not auto-bump version or create/push git tags
      --skip-tests                Skip test execution before packaging
      --publish                   Publish to GitHub Releases via gh CLI
      --notes <text>              Specify release notes string
      --notes-file <file>         Specify release notes file path
  -h, --help                      Show this help message

${BOLD}Examples:${RESET}
  ./release.sh                    # Package current version into dist/
  ./release.sh 0.2.0              # Explicitly set 0.2.0 and package into dist/
  ./release.sh --publish          # Auto-bump patch version (e.g. 0.1.8 -> 0.1.9), tag & publish
  ./release.sh --publish --bump minor # Auto-bump minor version (e.g. 0.1.8 -> 0.2.0), tag & publish
  ./release.sh --publish --skip-tag   # Publish current version without bumping or creating git tags
"
}

# Parse positional argument or options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        --bump)
            BUMP_TYPE="$2"
            shift 2
            ;;
        --skip-tag|--no-tag)
            SKIP_TAG=true
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --publish)
            PUBLISH=true
            shift
            ;;
        --notes)
            CUSTOM_NOTES="$2"
            shift 2
            ;;
        --notes-file)
            CUSTOM_NOTES_FILE="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            if [[ -z "$VERSION" && "$1" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.]+)?$ ]]; then
                VERSION="$1"
                shift
            else
                echo -e "${RED}Error: Unknown argument or option $1${RESET}" >&2
                print_usage
                exit 1
            fi
            ;;
    esac
done

# Helper function to bump semantic version
bump_semver() {
    local v="$1"
    local level="${2:-patch}"
    local major minor patch
    IFS='.' read -r major minor patch <<< "$v"
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}
    
    case "$level" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch|*)
            patch=$((patch + 1))
            ;;
    esac
    echo "${major}.${minor}.${patch}"
}

# ------------------------------------------------------------------------------
# Publish preconditions
#
# The v0.6.0 tag was created on a feature branch: the release pointed at `main`
# while the tag ref pointed at a commit that had never been merged, so the
# published DMG contained none of that branch's work. Nothing in this script
# was checking, because `git tag` and `git push` were allowed to run from
# wherever the script happened to be invoked.
#
# A published release is immutable in practice — users have downloaded it — so
# these checks run before anything is built, bumped, or tagged.
# ------------------------------------------------------------------------------
require_publish_prerequisites() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo -e "${RED}Error: --publish requires a git repository.${RESET}" >&2
        exit 1
    fi

    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$branch" != "main" ]; then
        echo -e "${RED}Error: releases are published from 'main', not '${branch}'.${RESET}" >&2
        echo -e "${YELLOW}   A tag on an unmerged branch produces a release whose assets${RESET}" >&2
        echo -e "${YELLOW}   do not match the merge commit it points at.${RESET}" >&2
        echo -e "   Merge first:  ${BOLD}git checkout main && git merge --ff-only ${branch}${RESET}" >&2
        exit 1
    fi

    if [ -n "$(git status --porcelain)" ]; then
        echo -e "${RED}Error: the working tree has uncommitted changes.${RESET}" >&2
        git status --short | sed 's/^/   /' >&2
        echo -e "   Commit or stash them: a release must be reproducible from a commit.${RESET}" >&2
        exit 1
    fi

    if git rev-parse --verify origin/main >/dev/null 2>&1; then
        if ! git merge-base --is-ancestor origin/main HEAD; then
            echo -e "${RED}Error: local main is behind or has diverged from origin/main.${RESET}" >&2
            echo -e "   ${BOLD}git pull --ff-only${RESET} first.${RESET}" >&2
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠️  origin/main not found locally — skipping the up-to-date check.${RESET}" >&2
        echo -e "${YELLOW}   Run 'git fetch origin' to enable it.${RESET}" >&2
    fi
}

if [ "$PUBLISH" = true ]; then
    require_publish_prerequisites
fi

# 1. Resolve version
PURAH_CORE_FILE="Sources/PurahCore/PurahCore.swift"
INFO_PLIST_FILE="Sources/PurahApp/Resources/Info.plist"

CURRENT_VERSION=$(grep -oE 'public static let version = "[^"]+"' "$PURAH_CORE_FILE" | cut -d'"' -f2)

# Check highest git tag
HIGHEST_GIT_TAG=$(git tag -l "v*" 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' | sort -V | tail -n1 | sed 's/^v//' || echo "")

if [ -z "$VERSION" ]; then
    if [ "$PUBLISH" = true ] && [ "$SKIP_TAG" = false ]; then
        # Determine base version: max between CURRENT_VERSION and HIGHEST_GIT_TAG
        BASE_VERSION="$CURRENT_VERSION"
        if [ -n "$HIGHEST_GIT_TAG" ]; then
            BASE_VERSION=$(python3 -c "
import sys
v1 = [int(x) for x in sys.argv[1].split('.')]
v2 = [int(x) for x in sys.argv[2].split('.')]
print(sys.argv[1] if v1 >= v2 else sys.argv[2])
" "$CURRENT_VERSION" "$HIGHEST_GIT_TAG")
        fi

        VERSION=$(bump_semver "$BASE_VERSION" "$BUMP_TYPE")
        echo -e "${GREEN}✨ Auto-bumping version (${BUMP_TYPE}): ${BOLD}v${BASE_VERSION} -> v${VERSION}${RESET}"
    else
        VERSION="$CURRENT_VERSION"
        echo -e "${CYAN}📌 Using current version: ${BOLD}v${VERSION}${RESET}"
    fi
fi

# Apply version updates if needed
if [ "$VERSION" != "$CURRENT_VERSION" ]; then
    echo -e "${YELLOW}📝 Updating version from ${CURRENT_VERSION} to ${VERSION}...${RESET}"
    sed -i '' "s/public static let version = \"[^\"]*\"/public static let version = \"${VERSION}\"/" "$PURAH_CORE_FILE"
    if command -v plutil >/dev/null 2>&1; then
        plutil -replace CFBundleShortVersionString -string "${VERSION}" "$INFO_PLIST_FILE"

        # CFBundleVersion is the monotonically increasing build number. It sat
        # at "2" across every release so far, so a crash report could not say
        # which build it came from. Increment it whenever a release is cut.
        if [ "$PUBLISH" = true ] && [ "$SKIP_TAG" = false ]; then
            CURRENT_BUILD=$(plutil -extract CFBundleVersion raw "$INFO_PLIST_FILE" 2>/dev/null || echo "0")
            case "$CURRENT_BUILD" in
                ''|*[!0-9]*) CURRENT_BUILD=0 ;;
            esac
            plutil -replace CFBundleVersion -string "$((CURRENT_BUILD + 1))" "$INFO_PLIST_FILE"
            echo -e "   └── Build number: ${CURRENT_BUILD} → $((CURRENT_BUILD + 1))"
        fi
    fi
    echo -e "${GREEN}✓ Updated ${PURAH_CORE_FILE} and ${INFO_PLIST_FILE}${RESET}"

    # Commit version bump if git is in a repository and publish is requested
    if [ "$PUBLISH" = true ] && [ "$SKIP_TAG" = false ]; then
        git add "$PURAH_CORE_FILE" "$INFO_PLIST_FILE"
        git commit -m "📦Build:[Release] Bump version to v${VERSION}"
        echo -e "${GREEN}✓ Committed version bump: v${VERSION}${RESET}"
    fi
fi

TAG_NAME="v${VERSION}"
DIST_DIR="dist"
mkdir -p "$DIST_DIR"

echo -e "\n${BOLD}${CYAN}🚀 [Purah Release] Preparing release ${TAG_NAME}...${RESET}\n"

# 2. Run full test verification
if [ "$SKIP_TESTS" = false ]; then
    echo -e "${CYAN}🧪 Step 1/5: Running test suite verification...${RESET}"
    swift test --disable-sandbox -Xswiftc -warnings-as-errors --no-parallel
    echo -e "${GREEN}✓ All tests passed successfully.${RESET}\n"
else
    echo -e "${YELLOW}⚠️  Skipping test execution (--skip-tests specified)${RESET}\n"
fi

# 3. Build .app bundle
echo -e "${CYAN}🔨 Step 2/5: Building release .app bundle via build.sh...${RESET}"
./build.sh --configuration release
echo -e "${GREEN}✓ Release .app build ready.${RESET}\n"

APP_PATH="build/Purah.app"
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: ${APP_PATH} does not exist!${RESET}" >&2
    exit 1
fi

# 3b. Sign and notarize
#
# An ad-hoc signature is not distributable: Gatekeeper blocks the download on
# another Mac, and — more importantly for Purah — TCC records permission grants
# against the code signature, so an unsigned rebuild silently loses the user's
# calendar, reminders and accessibility access. Signing has to happen here,
# before packaging, so the DMG contains the signed bundle.
#
# The identity is read from the environment so a release machine can be
# configured once. Without it we still produce artifacts, but we say plainly
# that they are not distributable instead of shipping something that fails on
# the user's machine.
SIGN_IDENTITY="$(purah_resolve_signing_identity)"
NOTARY_PROFILE="${PURAH_NOTARY_PROFILE:-}"

if [ -n "$SIGN_IDENTITY" ]; then
    echo -e "${CYAN}🔏 Step 2b/5: Signing with ${SIGN_IDENTITY}...${RESET}"

    # Sign inner bundles first: re-signing a bundle that contains an already
    # signed nested bundle invalidates the outer seal.
    ENTITLEMENTS_FILE="Sources/PurahApp/Resources/Purah.entitlements"
    ENTITLEMENTS_ARGS=()
    if [ -f "$ENTITLEMENTS_FILE" ]; then
        ENTITLEMENTS_ARGS=(--entitlements "$ENTITLEMENTS_FILE")
    fi

    find "$APP_PATH/Contents" -type f \( -name "*.dylib" -o -name "*.bundle" \) -print0 2>/dev/null \
        | while IFS= read -r -d '' nested; do
            codesign --force --timestamp --options runtime \
                --sign "$SIGN_IDENTITY" "$nested" 2>/dev/null || true
        done

    codesign --force --timestamp --options runtime \
        "${ENTITLEMENTS_ARGS[@]}" \
        --sign "$SIGN_IDENTITY" \
        "$APP_PATH"
    echo -e "${GREEN}✓ Signed ${APP_PATH}${RESET}"

    # Verify before doing the expensive notarization round-trip.
    if ! codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | tail -3; then
        echo -e "${RED}Error: signature verification failed.${RESET}" >&2
        exit 1
    fi

    if [ -n "$NOTARY_PROFILE" ]; then
        echo -e "${CYAN}🍎 Step 2c/5: Notarizing (profile: ${NOTARY_PROFILE})...${RESET}"
        # Notarization needs a zip, and the ticket must be stapled to the app
        # *and* to the DMG built later, so staple here and again after hdiutil.
        NOTARY_ZIP="build/purah-notarize.zip"
        rm -f "$NOTARY_ZIP"
        ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

        if xcrun notarytool submit "$NOTARY_ZIP" \
             --keychain-profile "$NOTARY_PROFILE" \
             --wait 2>&1 | tee /tmp/purah-notary.log | tail -5; then
            xcrun stapler staple "$APP_PATH"
            echo -e "${GREEN}✓ Notarized and stapled.${RESET}"
        else
            echo -e "${RED}Error: notarization failed. See /tmp/purah-notary.log${RESET}" >&2
            exit 1
        fi
        rm -f "$NOTARY_ZIP"
    else
        echo -e "${YELLOW}⚠️  Signed but not notarized (set PURAH_NOTARY_PROFILE).${RESET}"
        echo -e "${YELLOW}   Gatekeeper will still warn on other Macs.${RESET}"
        echo -e "${YELLOW}   The in-app updater will offer a manual download instead of installing.${RESET}"
    fi
else
    echo -e "${YELLOW}⚠️  No signing identity found — building UNSIGNED.${RESET}"
    echo -e "${YELLOW}   This artifact is for local use only: it will be blocked by${RESET}"
    echo -e "${YELLOW}   Gatekeeper elsewhere, and each rebuild resets TCC grants.${RESET}"
    echo -e "${YELLOW}   Set PURAH_SIGN_IDENTITY, or create one valid codesigning identity.${RESET}"
    echo -e "${YELLOW}   Available identities:${RESET}"
    security find-identity -v -p codesigning 2>/dev/null | sed 's/^/     /' || true
fi

# 4. Generate release notes
echo -e "${CYAN}📝 Step 3/5: Generating release notes...${RESET}"
NOTES_PATH="${DIST_DIR}/release-notes.txt"

if [ -n "$CUSTOM_NOTES_FILE" ] && [ -f "$CUSTOM_NOTES_FILE" ]; then
    cp "$CUSTOM_NOTES_FILE" "$NOTES_PATH"
elif [ -n "$CUSTOM_NOTES" ]; then
    echo -e "$CUSTOM_NOTES" > "$NOTES_PATH"
else
    PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -n "$PREV_TAG" ]; then
        LOG_RANGE="${PREV_TAG}..HEAD"
    else
        LOG_RANGE="HEAD~15..HEAD"
    fi

    cat <<EOF > "$NOTES_PATH"
# Purah ${TAG_NAME}

## What's New
$(git log $LOG_RANGE --pretty=format:"* %s (%h)" --no-merges 2>/dev/null || echo "* Performance enhancements and architecture improvements.")

## System Requirements
* macOS 14.0 (Sonoma) or newer (Apple Silicon & Intel)
EOF
fi
echo -e "${GREEN}✓ Generated ${NOTES_PATH}${RESET}\n"

# 5. Packaging (DMG, ZIP, Checksums)
echo -e "${CYAN}📦 Step 4/5: Packaging distribution artifacts...${RESET}"

ZIP_FILENAME="Purah-${TAG_NAME}-macOS.zip"
ZIP_PATH="${DIST_DIR}/${ZIP_FILENAME}"

DMG_FILENAME="Purah-${TAG_NAME}-macOS.dmg"
DMG_PATH="${DIST_DIR}/${DMG_FILENAME}"

# 5a. Create Apple-compliant ZIP
rm -f "$ZIP_PATH"
echo -e "   └── Archiving ZIP: ${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

# 5b. Create macOS DMG with Applications symlink
rm -f "$DMG_PATH"
DMG_STAGING="build/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

cp -Rp "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# The installer and the note are the difference between "downloaded an app"
# and "an app that opens". An ad-hoc build is refused by Gatekeeper on the
# first launch, and since macOS 15 removed the right-click bypass, the user's
# only route is System Settings → Privacy & Security → Open Anyway. The
# script does that part for them (and says so, in full, where they can read it).
if [ -f "packaging/Install Purah.command" ]; then
    cp "packaging/Install Purah.command" "$DMG_STAGING/"
    chmod +x "$DMG_STAGING/Install Purah.command"
    cp "packaging/Read Me.txt" "$DMG_STAGING/"
else
    echo -e "${YELLOW}⚠️  packaging/Install Purah.command missing — the DMG will have no installer.${RESET}" >&2
fi

echo -e "   └── Building DMG: ${DMG_PATH}"
hdiutil create -volname "Purah" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" > /dev/null

rm -rf "$DMG_STAGING"

# 5b2. Sign and staple the DMG itself.
#
# Stapling only the app is not enough: a user who downloads the DMG and opens it
# before dragging the app out sees the disk image's own Gatekeeper verdict.
if [ -n "$SIGN_IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
    echo -e "   └── Signing and stapling DMG..."
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
    xcrun stapler staple "$DMG_PATH" || {
        echo -e "${RED}Error: could not staple the DMG.${RESET}" >&2
        exit 1
    }
fi

# 5c. Calculate SHA-256 Checksums
echo -e "   └── Computing SHA-256 checksums..."
DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d ' ' -f 1)
ZIP_SHA256=$(shasum -a 256 "$ZIP_PATH" | cut -d ' ' -f 1)

echo "$DMG_SHA256  $DMG_FILENAME" > "${DMG_PATH}.sha256"
echo "$ZIP_SHA256  $ZIP_FILENAME" > "${ZIP_PATH}.sha256"

# 5d. Generate AppReleaseInfo JSON for in-app updater
ISO_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
REMOTE_REPO_URL=$(git config --get remote.origin.url | sed 's/\.git$//' | sed 's|^git@github.com:|https://github.com/|' || echo "https://github.com/rheatin/Purah")
DOWNLOAD_URL="${REMOTE_REPO_URL}/releases/download/${TAG_NAME}/${DMG_FILENAME}"

RELEASE_INFO_PATH="${DIST_DIR}/release-info.json"
cat <<EOF > "$RELEASE_INFO_PATH"
{
  "version": "${VERSION}",
  "releaseDate": "${ISO_DATE}",
  "releaseNotes": $(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' < "$NOTES_PATH"),
  "downloadURL": "${DOWNLOAD_URL}",
  "isMandatory": false,
  "sha256": "${DMG_SHA256}"
}
EOF
echo -e "${GREEN}✓ Created updater metadata: ${RELEASE_INFO_PATH}${RESET}\n"

# 5e. Generate the Homebrew cask for the self-hosted tap
#     The tap lives in its own repo (github.com/rheatin/homebrew-tap); this
#     file is the only place the version and checksum are written, so copy it
#     over Casks/purah.rb after every release. See docs/OWNER_ACTIONS.md.
CASK_PATH="${DIST_DIR}/purah.rb"
cat <<EOF > "$CASK_PATH"
cask "purah" do
  version "${VERSION}"
  sha256 "${ZIP_SHA256}"

  url "https://github.com/rheatin/Purah/releases/download/v#{version}/Purah-v#{version}-macOS.zip"
  name "Purah"
  desc "Magnetic edge rails for files, notes, music and scripts"
  homepage "https://github.com/rheatin/Purah/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Purah.app"

  # Homebrew quarantines cask downloads on purpose so Gatekeeper can judge them.
  # Purah is self-signed rather than notarized, so that verdict is always
  # "cannot be opened" — the flag is cleared here, which leaves the app in the
  # same state as one built on this machine. Delete this block the day a
  # Developer ID certificate signs a release.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Purah.app"]
  end

  caveats <<~EOS
    Purah is self-signed, not notarized by Apple, and this tap clears the
    download quarantines Homebrew applies for that reason. The DMG from
    https://github.com/rheatin/Purah/releases/latest goes through Gatekeeper
    as usual if you would rather approve it yourself.
  EOS
end
EOF
echo -e "${GREEN}✓ Created Homebrew cask: ${CASK_PATH}${RESET}\n"

# Summary of artifacts
echo -e "${BOLD}${GREEN}====================================================================${RESET}"
echo -e "${BOLD}${GREEN}🎉 Release artifacts generated successfully in ${DIST_DIR}/ :${RESET}"
echo -e "   • ${BOLD}${DMG_FILENAME}${RESET} ($(du -sh "$DMG_PATH" | cut -f1)) [SHA256: ${DMG_SHA256:0:16}...]"
echo -e "   • ${BOLD}${ZIP_FILENAME}${RESET} ($(du -sh "$ZIP_PATH" | cut -f1)) [SHA256: ${ZIP_SHA256:0:16}...]"
echo -e "   • ${BOLD}release-info.json${RESET} (In-App Auto-Updater manifest)"
echo -e "   • ${BOLD}release-notes.txt${RESET}"
echo -e "   • ${BOLD}purah.rb${RESET} (Homebrew cask → homebrew-tap/Casks/purah.rb)"
echo -e "${BOLD}${GREEN}====================================================================${RESET}\n"

# 6. Publish via GitHub CLI (optional)
if [ "$PUBLISH" = true ]; then
    echo -e "${CYAN}🌐 Step 5/5: Publishing to GitHub Releases via gh CLI...${RESET}"
    if ! command -v gh &> /dev/null; then
        echo -e "${RED}Error: GitHub CLI (gh) is not installed. Please install it with 'brew install gh'.${RESET}" >&2
        exit 1
    fi

    if [ "$SKIP_TAG" = false ]; then
        # The version-bump commit is made locally at the start of this script.
        # Nothing ever pushed it, so the release commit lived only on whichever
        # machine cut the release — that is exactly how v0.6.0's "Bump version
        # to v0.6.0" commit ended up on a feature branch while the tag (and the
        # GitHub release) pointed at a different history.
        #
        # A tag must name a commit that exists on the remote, or `git checkout
        # vX.Y.Z` after a fresh clone fails. Push `main` before tagging.
        echo -e "   └── Pushing main to origin..."
        if ! git push origin main; then
            echo -e "${RED}Error: could not push main to origin.${RESET}" >&2
            echo -e "   Nothing was tagged or published; the version bump is still local.${RESET}" >&2
            exit 1
        fi

        # A tag that already exists and points somewhere else is a release that
        # was tagged from the wrong commit. Refuse to publish over it: the fix
        # is to delete the bad tag deliberately, not to have this script guess.
        if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
            EXISTING_SHA=$(git rev-parse "${TAG_NAME}^{commit}")
            HEAD_SHA=$(git rev-parse HEAD)
            if [ "$EXISTING_SHA" != "$HEAD_SHA" ]; then
                echo -e "${RED}Error: ${TAG_NAME} already exists and points at ${EXISTING_SHA:0:7}, not HEAD (${HEAD_SHA:0:7}).${RESET}" >&2
                echo -e "   Delete it first if it is wrong:  ${BOLD}git tag -d ${TAG_NAME} && git push origin :refs/tags/${TAG_NAME}${RESET}" >&2
                exit 1
            fi
            echo -e "   └── Tag ${TAG_NAME} already points at HEAD."
        else
            echo -e "   └── Tagging git commit with ${TAG_NAME}..."
            git tag -a "$TAG_NAME" -m "Release ${TAG_NAME}"
        fi

        # A failed push used to be swallowed (`|| true`). A tag that never
        # reached origin while the release did leaves the release pointing at a
        # commit nobody can check out.
        echo -e "   └── Pushing tag ${TAG_NAME} to remote..."
        if ! git push origin "$TAG_NAME"; then
            echo -e "${RED}Error: could not push ${TAG_NAME} to origin.${RESET}" >&2
            echo -e "   The local tag was left in place; push it and re-run with --skip-tag.${RESET}" >&2
            exit 1
        fi
    else
        echo -e "   └── ${YELLOW}Skipping git tagging and tag push (--skip-tag specified)${RESET}"
    fi

    # Create release (or update if already exists)
    echo -e "   └── Publishing to GitHub release ${TAG_NAME}..."
    if ! gh release create "$TAG_NAME" \
        "$DMG_PATH" \
        "$ZIP_PATH" \
        "${DMG_PATH}.sha256" \
        "${ZIP_PATH}.sha256" \
        "$RELEASE_INFO_PATH" \
        --title "Purah ${TAG_NAME}" \
        --notes-file "$NOTES_PATH" 2>/dev/null; then
        echo -e "   └── Release ${TAG_NAME} already exists, updating assets..."
        gh release upload "$TAG_NAME" \
            "$DMG_PATH" \
            "$ZIP_PATH" \
            "${DMG_PATH}.sha256" \
            "${ZIP_PATH}.sha256" \
            "$RELEASE_INFO_PATH" \
            --clobber
    fi

    echo -e "\n${BOLD}${GREEN}🚀 Release ${TAG_NAME} published successfully on GitHub!${RESET}"
else
    echo -e "${MAGENTA}💡 To publish this release to GitHub, run:${RESET}"
    echo -e "   ${BOLD}./release.sh --publish${RESET}"
    echo -e "   or manually with:"
    echo -e "   ${BOLD}gh release create ${TAG_NAME} dist/* --title \"Purah ${TAG_NAME}\" --notes-file dist/release-notes.txt${RESET}\n"
fi
