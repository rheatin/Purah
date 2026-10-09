#!/bin/bash
set -e

# ==============================================================================
# Purah Real Screen Demo Recorder
# 录制真实的 macOS 屏幕交互，并转换为高质量 GitHub README 演示 GIF
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🎨 [1/4] 检查构建最新版本 Purah..."
swift build -c release --disable-sandbox

APP_BIN=".build/out/Products/Release/Purah"
if [ ! -f "$APP_BIN" ]; then
    APP_BIN=".build/release/Purah"
fi

if [ ! -f "$APP_BIN" ]; then
    echo "❌ 未找到构建的可执行文件，请确认 swift build 成功！"
    exit 1
fi

echo "🚀 [2/4] 启动真实 Purah 应用程序..."
# 杀死可能存在的旧进程
pkill -x Purah 2>/dev/null || true
"$APP_BIN" &
APP_PID=$!
sleep 1.5

RAW_VIDEO="/tmp/purah_raw_capture.mp4"
rm -f "$RAW_VIDEO"

RECORD_SECONDS=14
echo "🎬 [3/4] 准备开始录制屏幕 (将持续 $RECORD_SECONDS 秒)..."
echo "   提示: 请在倒计时结束后，将鼠标滑向屏幕边缘体验交互："
echo "   1. 滑向屏幕右侧边缘唤出【音乐律动】与【日程】"
echo "   2. 滑向屏幕左侧边缘唤出【终端】"
echo "   3. 按下 Option+Tab (⌥⇥) 体验一键冻结"
echo ""

for i in 3 2 1; do
    echo "   ⏳ $i 秒后开始录像..."
    sleep 1
done

echo "🔴 录像中... 请操作！"
# -v: 录制视频, -k: 捕获鼠标点击波纹, -C: 捕获光标, -V: 指定录制秒数
screencapture -v -k -C -V "$RECORD_SECONDS" "$RAW_VIDEO"

echo "⏹ 录制完成！关闭演示进程..."
kill $APP_PID 2>/dev/null || true

if [ ! -f "$RAW_VIDEO" ]; then
    echo "❌ 录像文件未能成功生成，请检查终端是否有「屏幕录制 (Screen Recording)」系统权限。"
    exit 1
fi

echo "🪄 [4/4] 正在压制高质量自适应调色板 GIF 与高清视频..."
mkdir -p assets

# 复制高清 MP4
cp "$RAW_VIDEO" assets/purah-demo.mp4

# 使用 ffmpeg 提取 256 色最优调色板并进行 Bayer 抖动压制
PALETTE="/tmp/purah_real_palette.png"
/opt/homebrew/bin/ffmpeg -y -i "$RAW_VIDEO" \
    -vf "fps=25,scale=960:-1:flags=lanczos,palettegen=stats_mode=diff" \
    "$PALETTE"

/opt/homebrew/bin/ffmpeg -y -i "$RAW_VIDEO" -i "$PALETTE" \
    -lavfi "fps=25,scale=960:-1:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    assets/purah-demo.gif

rm -f "$RAW_VIDEO" "$PALETTE"

echo ""
echo "🎉 真实演示录制成功！"
echo "   • GIF 演示图: assets/purah-demo.gif ($(du -h assets/purah-demo.gif | awk '{print $1}'))"
echo "   • MP4 原画视频: assets/purah-demo.mp4 ($(du -h assets/purah-demo.mp4 | awk '{print $1}'))"
