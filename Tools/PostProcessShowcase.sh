#!/bin/bash
set -e

INPUT_RAW="/tmp/purah_d5_full_take.mp4"
PROCESSED_VIDEO="assets/purah-showcase-30s.mp4"
PROCESSED_GIF="assets/purah-showcase-30s.gif"

if [ ! -f "$INPUT_RAW" ]; then
    echo "❌ Input $INPUT_RAW not found!"
    exit 1
fi

echo "🎬 Processing raw capture into sanitized 30s showcase..."

# 1. Obscure / Crop top menu bar (top 72px completely cropped or frosted blurred)
# Logical height: 1117 (retina 2234), top menubar: ~72px.
# We crop out the top 72px and scale cleanly to 1920x1080
/opt/homebrew/bin/ffmpeg -y -i "$INPUT_RAW" \
    -filter_complex "\
      [0:v]crop=3456:2162:0:72,scale=1920:1080:flags=lanczos,fps=30[v]" \
    -map "[v]" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    /tmp/d5_sanitized_main.mp4

# 2. Add video-shotcraft audio & intro/outro
INTRO_SOUND="/Users/char/.pi/agent/skills/video-shotcraft/assets/sfx/whoosh-fast.mp3"
BGM="/Users/char/.pi/agent/skills/video-shotcraft/assets/music/modern-elevation-120bpm-c.mp3"

/opt/homebrew/bin/ffmpeg -y -i /tmp/d5_sanitized_main.mp4 \
    -stream_loop -1 -i "$BGM" \
    -filter_complex "\
      [1:a]volume=0.38,afade=t=in:ss=0:d=1.5,afade=t=out:st=26:d=2[bgm]; \
      [0:v]fade=t=in:st=0:d=0.8,fade=t=out:st=26.5:d=1.5[vout]" \
    -map "[vout]" -map "[bgm]" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 192k \
    -t 28 \
    "$PROCESSED_VIDEO"

echo "🖼️ Generating optimized showcase GIF..."
/opt/homebrew/bin/ffmpeg -y -i "$PROCESSED_VIDEO" \
    -filter_complex "[0:v]fps=16,scale=960:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" \
    "$PROCESSED_GIF"

echo "✅ Generated: $PROCESSED_VIDEO ($(ls -lh $PROCESSED_VIDEO | awk '{print $5}'))"
echo "✅ Generated: $PROCESSED_GIF ($(ls -lh $PROCESSED_GIF | awk '{print $5}'))"
