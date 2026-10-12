#!/bin/bash
set -e

# ==============================================================================
# Purah Real Screen Demo Recorder
# Records native macOS screen interactions and converts to high-quality README demo GIF
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🎨 [1/4] Checking and building latest release of Purah..."
swift build -c release --disable-sandbox

APP_BIN=".build/out/Products/Release/Purah"
if [ ! -f "$APP_BIN" ]; then
    APP_BIN=".build/release/Purah"
fi

if [ ! -f "$APP_BIN" ]; then
    echo "❌ Build binary not found, please verify swift build succeeded!"
    exit 1
fi

echo "🚀 [2/4] Launching Purah application..."
# Terminate any existing instance
pkill -x Purah 2>/dev/null || true
"$APP_BIN" &
APP_PID=$!
sleep 1.5

RAW_VIDEO="/tmp/purah_raw_capture.mp4"
rm -f "$RAW_VIDEO"

RECORD_SECONDS=14
echo "🎬 [3/4] Ready to record screen (duration: $RECORD_SECONDS seconds)..."
echo "   Tip: After countdown, move mouse to screen edges to test interactions:"
echo "   1. Slide towards right edge to reveal Music Wave & Calendar"
echo "   2. Slide towards left edge to reveal Terminal"
echo "   3. Press Option+Tab (⌥⇥) to toggle Freeze Mode"
echo ""

for i in 3 2 1; do
    echo "   ⏳ Recording starts in $i seconds..."
    sleep 1
done

echo "🔴 Recording in progress... Please interact!"
# -v: record video, -k: capture click ripples, -C: capture cursor, -V: duration in seconds
screencapture -v -k -C -V "$RECORD_SECONDS" "$RAW_VIDEO"

echo "⏹ Recording complete! Terminating demo process..."
kill $APP_PID 2>/dev/null || true

if [ ! -f "$RAW_VIDEO" ]; then
    echo "❌ Recording video was not generated. Please check Screen Recording system permissions."
    exit 1
fi

echo "🪄 [4/4] Encoding high-quality adaptive palette GIF and HD video..."
mkdir -p assets

# Copy HD MP4
cp "$RAW_VIDEO" assets/purah-demo.mp4

# Extract optimal 256-color palette and encode with Bayer dithering via ffmpeg
PALETTE="/tmp/purah_real_palette.png"
/opt/homebrew/bin/ffmpeg -y -i "$RAW_VIDEO" \
    -vf "fps=25,scale=960:-1:flags=lanczos,palettegen=stats_mode=diff" \
    "$PALETTE"

/opt/homebrew/bin/ffmpeg -y -i "$RAW_VIDEO" -i "$PALETTE" \
    -lavfi "fps=25,scale=960:-1:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    assets/purah-demo.gif

rm -f "$RAW_VIDEO" "$PALETTE"

echo ""
echo "🎉 Demo recording and encoding complete!"
echo "   • GIF Demo: assets/purah-demo.gif ($(du -h assets/purah-demo.gif | awk '{print $1}'))"
echo "   • MP4 Video: assets/purah-demo.mp4 ($(du -h assets/purah-demo.mp4 | awk '{print $1}'))"
