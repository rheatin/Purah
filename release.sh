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

VERSION=""
SKIP_TESTS=false
PUBLISH=false
CUSTOM_NOTES=""
CUSTOM_NOTES_FILE=""

print_usage() {
    cat <<EOF
${BOLD}Usage:${RESET} ./release.sh [version] [options]

${BOLD}Arguments:${RESET}
  [version]                       Release version (e.g. 0.1.0 or 0.2.0).
                                  If omitted, reads current version from PurahCore.swift.

${BOLD}Options:${RESET}
  -v, --version <version>         Specify release version
      --skip-tests                Skip test execution before packaging
      --publish                   Publish to GitHub Releases via gh CLI
      --notes <text>              Specify release notes string
      --notes-file <file>         Specify release notes file path
  -h, --help                      Show this help message

${BOLD}Examples:${RESET}
  ./release.sh                    # Package current version into dist/
  ./release.sh 2.1.0              # Bump to 2.1.0 and package into dist/
  ./release.sh --publish          # Package and publish GitHub release via gh CLI
EOF
}

# Parse positional argument or options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            VERSION="$2"
            shift 2
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

# 1. Resolve version
PURAH_CORE_FILE="Sources/PurahCore/PurahCore.swift"
INFO_PLIST_FILE="Sources/PurahApp/Resources/Info.plist"

CURRENT_VERSION=$(grep -oE 'public static let version = "[^"]+"' "$PURAH_CORE_FILE" | cut -d'"' -f2)

if [ -z "$VERSION" ]; then
    VERSION="$CURRENT_VERSION"
    echo -e "${CYAN}📌 Using current version: ${BOLD}v${VERSION}${RESET}"
else
    if [ "$VERSION" != "$CURRENT_VERSION" ]; then
        echo -e "${YELLOW}📝 Updating version from ${CURRENT_VERSION} to ${VERSION}...${RESET}"
        sed -i '' "s/public static let version = \"[^\"]*\"/public static let version = \"${VERSION}\"/" "$PURAH_CORE_FILE"
        if command -v plutil >/dev/null 2>&1; then
            plutil -replace CFBundleShortVersionString -string "${VERSION}" "$INFO_PLIST_FILE"
        fi
        echo -e "${GREEN}✓ Updated ${PURAH_CORE_FILE} and ${INFO_PLIST_FILE}${RESET}"
    fi
fi

TAG_NAME="v${VERSION}"
DIST_DIR="dist"
mkdir -p "$DIST_DIR"

echo -e "\n${BOLD}${CYAN}🚀 [Purah Release] Preparing release ${TAG_NAME}...${RESET}\n"

# 2. Run full test verification
if [ "$SKIP_TESTS" = false ]; then
    echo -e "${CYAN}🧪 Step 1/5: Running test suite verification...${RESET}"
    swift test --disable-sandbox -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --no-parallel
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

echo -e "   └── Building DMG: ${DMG_PATH}"
hdiutil create -volname "Purah" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" > /dev/null

rm -rf "$DMG_STAGING"

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

# Summary of artifacts
echo -e "${BOLD}${GREEN}====================================================================${RESET}"
echo -e "${BOLD}${GREEN}🎉 Release artifacts generated successfully in ${DIST_DIR}/ :${RESET}"
echo -e "   • ${BOLD}${DMG_FILENAME}${RESET} ($(du -sh "$DMG_PATH" | cut -f1)) [SHA256: ${DMG_SHA256:0:16}...]"
echo -e "   • ${BOLD}${ZIP_FILENAME}${RESET} ($(du -sh "$ZIP_PATH" | cut -f1)) [SHA256: ${ZIP_SHA256:0:16}...]"
echo -e "   • ${BOLD}release-info.json${RESET} (In-App Auto-Updater manifest)"
echo -e "   • ${BOLD}release-notes.txt${RESET}"
echo -e "${BOLD}${GREEN}====================================================================${RESET}\n"

# 6. Publish via GitHub CLI (optional)
if [ "$PUBLISH" = true ]; then
    echo -e "${CYAN}🌐 Step 5/5: Publishing to GitHub Releases via gh CLI...${RESET}"
    if ! command -v gh &> /dev/null; then
        echo -e "${RED}Error: GitHub CLI (gh) is not installed. Please install it with 'brew install gh'.${RESET}" >&2
        exit 1
    fi

    # Check if tag exists locally
    if ! git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
        echo -e "   └── Tagging git commit with ${TAG_NAME}..."
        git tag -a "$TAG_NAME" -m "Release ${TAG_NAME}"
    fi

    # Push tag to origin
    echo -e "   └── Pushing tag ${TAG_NAME} to remote..."
    git push origin "$TAG_NAME" || true

    # Create release
    echo -e "   └── Creating GitHub release..."
    gh release create "$TAG_NAME" \
        "$DMG_PATH" \
        "$ZIP_PATH" \
        "${DMG_PATH}.sha256" \
        "${ZIP_PATH}.sha256" \
        "$RELEASE_INFO_PATH" \
        --title "Purah ${TAG_NAME}" \
        --notes-file "$NOTES_PATH"

    echo -e "\n${BOLD}${GREEN}🚀 Release ${TAG_NAME} published successfully on GitHub!${RESET}"
else
    echo -e "${MAGENTA}💡 To publish this release to GitHub, run:${RESET}"
    echo -e "   ${BOLD}./release.sh --publish${RESET}"
    echo -e "   or manually with:"
    echo -e "   ${BOLD}gh release create ${TAG_NAME} dist/* --title \"Purah ${TAG_NAME}\" --notes-file dist/release-notes.txt${RESET}\n"
fi
