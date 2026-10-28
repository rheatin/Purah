#!/bin/bash
# ==============================================================================
#  Install Purah.command
#
#  它只做三件事 / It does exactly three things:
#    1. 把 Purah.app 复制到「应用程序」
#       Copy Purah.app into /Applications
#    2. 解除这个文件的「下载隔离」标记
#       Remove the quarantine flag macOS puts on downloaded files
#    3. 打开 Purah
#       Launch it
#
#  为什么要第 2 步 / Why step 2:
#  Purah 是 MIT 开源的免费软件，作者没有每年 99 美元的 Apple 开发者账号，
#  所以系统无法验证它的签名，双击会提示「无法打开」。这个标记只表示
#  「这个文件来自网络」，删掉它不会改动应用的任何内容 —— 你可以逐行读完
#  下面全部代码再决定。
#
#  Purah is free and MIT-licensed. Its author does not have a $99/year Apple
#  Developer account, so macOS cannot verify the signature and refuses to open
#  it. The flag this removes only records "downloaded from the internet"; it
#  changes nothing inside the app. Read the whole script before running it.
# ==============================================================================
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Purah"
SOURCE="$(pwd)/${APP_NAME}.app"

say()  { printf '%s\n' "$1"; }
fail() {
    printf '\n%s\n\n' "$1" >&2
    read -r -p "按回车键关闭窗口 / Press Return to close " _ || true
    exit 1
}

# ------------------------------------------------------------------------------
# 1. The app has to be here. A user who copied only the script somewhere else
#    gets told what to do instead of a bare "no such file".
# ------------------------------------------------------------------------------
[ -d "$SOURCE" ] || fail "找不到 Purah.app，请把本文件放在与 Purah.app 相同的文件夹里再双击。
Cannot find Purah.app. Keep this file in the same folder as Purah.app and run it again."

# ------------------------------------------------------------------------------
# 2. Quit a running copy. Replacing a bundle that is still running leaves the
#    old process alive and the new one unopened — the user sees "nothing happened".
# ------------------------------------------------------------------------------
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    say "正在关闭 Purah / Quitting the running Purah…"
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 25); do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.2
    done
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    sleep 0.3
fi

# ------------------------------------------------------------------------------
# 3. Destination. Admin users can write to /Applications; everyone else gets a
#    per-user Applications folder rather than an admin password prompt they did
#    not ask for.
# ------------------------------------------------------------------------------
if [ -w "/Applications" ]; then
    TARGET_DIR="/Applications"
else
    TARGET_DIR="$HOME/Applications"
    mkdir -p "$TARGET_DIR"
    say "没有写入「应用程序」的权限，改装到 $TARGET_DIR
No write access to /Applications, installing into $TARGET_DIR instead."
fi
DEST="${TARGET_DIR}/${APP_NAME}.app"

# ------------------------------------------------------------------------------
# 4. Replace, then clear the quarantine flag.
# ------------------------------------------------------------------------------
say "正在安装到 ${DEST} / Installing to ${DEST}…"
rm -rf "$DEST"
cp -Rp "$SOURCE" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 5. Launch.
# ------------------------------------------------------------------------------
open "$DEST" >/dev/null 2>&1 || true

say ""
say "✅ 安装完成，Purah 已启动。"
say "✅ Installed. Purah is now running."
say ""
say "Purah 不会出现在 Dock 里 —— 把鼠标移到屏幕左/右边缘就能唤出它。"
say "Purah has no Dock icon — move the cursor to the left or right screen edge."
say ""
say "如果系统仍然提示「无法验证开发者」，请打开"
say "  系统设置 → 隐私与安全性 → 仍要打开"
say "If macOS still refuses to open it: System Settings → Privacy & Security → Open Anyway."
say ""
say "你可以把这个窗口关掉了。 / You can close this window."
