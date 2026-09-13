#!/bin/bash
# 构建「Codex 用量」液态玻璃小卡片为 macOS .app
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Codex用量"
BUNDLE_ID="com.qoder.codex-usage-card"
EXEC_NAME="CodexUsageCard"
VERSION="1.0.0"

echo "==> swift build (release)"
swift build -c release

BIN=".build/release/${EXEC_NAME}"
APP="${APP_NAME}.app"

echo "==> 组装 ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/${EXEC_NAME}"

if [ -f "Assets/AppIcon.icns" ]; then
  cp "Assets/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>Codex 用量</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${EXEC_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>本地工具，不上传任何数据</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

echo "==> 签名 (ad-hoc)"
codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || echo "签名跳过（不影响本地运行）"

echo "==> 完成: $(pwd)/${APP}"
echo "    启动: open \"${APP}\"   或   ./${APP}/Contents/MacOS/${EXEC_NAME}"
