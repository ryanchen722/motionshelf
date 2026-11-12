#!/bin/bash
# 編譯 MotionShelf、包成 .app，然後啟動。用法：./run.sh
set -euo pipefail
cd "$(dirname "$0")"

swift build

APP="build/MotionShelf.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/debug/MotionShelf "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp Support/skin.png Support/skin_back.png "$APP/Contents/Resources/"
# 用固定的開發者憑證簽章，macOS 才會記住「允許取用文件檔案夾」，不會每次編譯都再問；沒有憑證時改用臨時簽章
codesign --force --sign "Apple Development" "$APP" >/dev/null 2>&1 || codesign --force --sign - "$APP" >/dev/null 2>&1

# 如果舊的還開著，先關掉
pkill -x MotionShelf || true
sleep 0.3
open "$APP"
echo "MotionShelf 已啟動：按 ⌥Space 顯示／隱藏面板"
