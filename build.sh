#!/usr/bin/env bash
# ==============================================================================
# build.sh - Build and package Purah into a macOS Application Bundle (.app)
# ==============================================================================
set -euo pipefail

# Terminal colors
BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$REPO_ROOT"

CONFIGURATION="release"
CLEAN=false
OPEN_APP=false

print_usage() {
    cat <<EOF
${BOLD}Usage:${RESET} ./build.sh [options]

${BOLD}Options:${RESET}
  -c, --configuration <debug|release>  Build configuration (default: release)
      --clean                          Clean build artifacts before building
      --open                           Launch the application after successful build
  -h, --help                           Show this help message

${BOLD}Environment Variables:${RESET}
  APPLE_SIGNING_IDENTITY               Codesign identity (default: "-" ad-hoc)

EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --open)
            OPEN_APP=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${RESET}" >&2
            print_usage
            exit 1
            ;;
    esac
done

if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
    echo -e "${RED}Error: Configuration must be 'debug' or 'release'. Got: $CONFIGURATION${RESET}" >&2
    exit 1
fi

echo -e "${BOLD}${CYAN}🔨 [Purah] Starting build in '${CONFIGURATION}' mode...${RESET}"
START_TIME=$(date +%s)

# Optional clean
if [ "$CLEAN" = true ]; then
    echo -e "${YELLOW}🧹 Cleaning build artifacts...${RESET}"
    swift package clean
    rm -rf build/
fi

# 1. Compile Swift package with strict concurrency
BUILD_FLAGS=(
    -c "$CONFIGURATION"
    --disable-sandbox
    -Xswiftc -strict-concurrency=complete
    -Xswiftc -warnings-as-errors
)

echo -e "${CYAN}📦 Compiling Swift modules (PurahCore, PurahUI, PurahApp)...${RESET}"
swift build "${BUILD_FLAGS[@]}"

# 2. Locate built binary directory
BIN_DIR=$(swift build -c "$CONFIGURATION" --disable-sandbox --show-bin-path)
EXECUTABLE_PATH="${BIN_DIR}/Purah"

if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo -e "${RED}Error: Executable not found at $EXECUTABLE_PATH${RESET}" >&2
    exit 1
fi

# 3. Create .app bundle directory structure
APP_BUNDLE="build/Purah.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo -e "${CYAN}📁 Assembling ${APP_BUNDLE}...${RESET}"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy main binary
cp -p "$EXECUTABLE_PATH" "${MACOS_DIR}/Purah"

# Copy Info.plist
INFO_PLIST="Sources/PurahApp/Resources/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    cp -p "$INFO_PLIST" "${CONTENTS_DIR}/Info.plist"
else
    echo -e "${RED}Error: $INFO_PLIST missing!${RESET}" >&2
    exit 1
fi

# Copy AppIcon.icns
APP_ICON="Sources/PurahApp/Resources/AppIcon.icns"
if [ -f "$APP_ICON" ]; then
    cp -p "$APP_ICON" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Copy all SPM resource bundles (including SwiftTerm Metal shaders and Purah bundles)
shopt -s nullglob
RESOURCE_BUNDLES=("${BIN_DIR}"/*.bundle)
for bundle in "${RESOURCE_BUNDLES[@]}"; do
    echo -e "   └── Packaging resource bundle: $(basename "$bundle")"
    cp -Rp "$bundle" "$RESOURCES_DIR/"
done
shopt -u nullglob

# 4. Code signing
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:--}"
echo -e "${CYAN}🔏 Signing application bundle (Identity: ${SIGNING_IDENTITY})...${RESET}"

# Sign nested resource bundles first if any
find "${RESOURCES_DIR}" -name "*.bundle" -type d -exec codesign --force --sign "$SIGNING_IDENTITY" {} +

# Sign the overall .app bundle
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

# 5. Verify codesign
echo -e "${CYAN}🔍 Verifying codesign signature...${RESET}"
codesign --verify --deep --strict "$APP_BUNDLE"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo -e "${BOLD}${GREEN}✅ Successfully built ${APP_BUNDLE} (${APP_SIZE}) in ${ELAPSED}s${RESET}"

# Optional launch
if [ "$OPEN_APP" = true ]; then
    echo -e "${CYAN}🚀 Launching ${APP_BUNDLE}...${RESET}"
    open "$APP_BUNDLE"
fi
