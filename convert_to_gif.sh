#!/bin/bash
set -e

# ==============================================================================
# Convert any real screen recording (.mov / .mp4) to Purah's optimized GIF & MP4
# ==============================================================================

if [ -z "$1" ]; then
    echo "使用方法: ./convert_to_gif.sh <视频文件路径, 如 screen_recording.mov>"
    exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ 找不到指定视频文件: $INPUT_FILE"
    exit 1
fi

mkdir -p assets
PALETTE="/tmp/purah_custom_palette.png"

echo "🎬 正在处理真实录像: $INPUT_FILE"

# 1. 输出优化版 MP4
/opt/homebrew/bin/ffmpeg -y -i "$INPUT_FILE" \
    -c:v libx264 -pix_fmt yuv420p -crf 18 -preset fast \
    assets/purah-demo.mp4

# 2. 提取 256 色最优差异调色板
/opt/homebrew/bin/ffmpeg -y -i assets/purah-demo.mp4 \
    -vf "fps=25,scale=960:-1:flags=lanczos,palettegen=stats_mode=diff" \
    "$PALETTE"

# 3. 压制高画质、抗断层 Bayer 抖动 GIF
/opt/homebrew/bin/ffmpeg -y -i assets/purah-demo.mp4 -i "$PALETTE" \
    -lavfi "fps=25,scale=960:-1:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    assets/purah-demo.gif

rm -f "$PALETTE"

echo ""
echo "🎉 转换完成！已更新资产："
echo "   • GIF 动图: assets/purah-demo.gif ($(du -h assets/purah-demo.gif | awk '{print $1}'))"
echo "   • MP4 视频: assets/purah-demo.mp4 ($(du -h assets/purah-demo.mp4 | awk '{print $1}'))"
