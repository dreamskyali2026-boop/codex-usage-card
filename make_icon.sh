#!/bin/bash
# 用 SwiftUI 离屏渲染应用图标并打包成 AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=".build/release/CodexUsageCard"

WORK=".build/icon"
rm -rf "${WORK}"
mkdir -p "${WORK}/AppIcon.iconset"

"${BIN}" --icon "${WORK}/icon_1024.png"

sips -z 1024 1024 "${WORK}/icon_1024.png" --out "${WORK}/AppIcon.iconset/icon_512x512@2x.png" >/dev/null
sips -z  512  512 "${WORK}/icon_1024.png" --out "${WORK}/AppIcon.iconset/icon_512x512.png"    >/dev/null
sips -z  512  512 "${WORK}/icon_1024.png" --out "${WORK}/AppIcon.iconset/icon_256x256@2x.png" >/dev/null
sips -z  256  256 "${WORK}/icon_1024.png" --out "${WORK}/AppIcon.iconset/icon_256x256.png"    >/dev/null
sips -z  256  256 "${WORK}/icon_1024.png" --out "${WORK}/AppIcon.iconset/icon_128x128@2x.png" >/dev/null
sips -z  128  128 "${WORK}/icon_1024.png" --out "${WORK}/AppIcon.iconset/icon_128x128.png"    >/dev/null
sips -z   64   64 "${WORK}/icon_1024.png" --out "${WORK}/AppIcon.iconset/icon_32x32@2x.png"   >/dev/null
sips -z   32   32 "${WORK}/icon_1024.png" --out "${WORK}/AppIcon.iconset/icon_32x32.png"      >/dev/null
sips -z   32   32 "${WORK}/icon_1024.png" --out "${WORK}/AppIcon.iconset/icon_16x16@2x.png"   >/dev/null
sips -z   16   16 "${WORK}/icon_1024.png" --out "${WORK}/AppIcon.iconset/icon_16x16.png"      >/dev/null

mkdir -p Assets
iconutil -c icns "${WORK}/AppIcon.iconset" -o Assets/AppIcon.icns
echo "==> Assets/AppIcon.icns 已生成"
