#!/bin/bash
# 打包可以直接給別人下載的 MotionShelf.app：release 編譯、內建範例檔案、Developer ID 簽章、（選用）公證。
# 用法：tools/release.sh [版本號，例如 0.2.0]
# 公證需要先在終端機執行一次（登入資訊存進鑰匙圈，帳號和密碼自己輸入）：
#   xcrun notarytool store-credentials motionshelf-notary
# 沒有這組設定時只簽章、不公證，使用者第一次開啟要右鍵選「打開」。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)}"
PROFILE="${NOTARY_PROFILE:-motionshelf-notary}"
OUT="dist"
APP="$OUT/MotionShelf.app"
ZIP="$OUT/MotionShelf-$VERSION.zip"

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
if [ -z "$IDENTITY" ]; then
  echo "找不到 Developer ID Application 憑證，無法打包給別人用。" >&2
  exit 1
fi

echo "==> 編譯 release（arm64 + x86_64）"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MotionShelf"

echo "==> 組成 $APP"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/project/effects" "$APP/Contents/Resources/project/tools"
cp "$BIN" "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
cp Support/skin.png Support/skin_back.png "$APP/Contents/Resources/"

# 第一次開啟時會複製到 ~/Library/Application Support/MotionShelf（不含收件匣、自訂分類、agent.json 等個人資料）
P="$APP/Contents/Resources/project"
for dir in effects/*/; do
  name="$(basename "$dir")"
  case "$name" in _*) continue ;; esac
  cp -R "$dir" "$P/effects/$name"
done
cp -R skills "$P/skills"
cp tools/check-effects.mjs "$P/tools/"
cp agent.example.json "$P/"

echo "==> 簽章（$IDENTITY）"
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> 壓縮"
ditto -c -k --keepParent "$APP" "$ZIP"

if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "==> 送交 Apple 公證（會上傳 $ZIP，要等幾分鐘）"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
else
  echo "==> 沒有公證設定（$PROFILE），略過公證。使用者第一次開啟要右鍵選「打開」。"
fi

echo "完成：$ZIP"
