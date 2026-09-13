#!/bin/bash
# 回归测试：最小化动画必须结束在原生菜单栏用量图标中央。
set -euo pipefail

cd "$(dirname "$0")/.."
BIN="$(mktemp -d)/minimize-animation-geometry"
trap 'rm -f "$BIN"' EXIT

swiftc Sources/CodexUsageCard/MinimizeAnimationGeometry.swift \
       Tests/MinimizeAnimationGeometryProbe.swift \
       -o "$BIN"
"$BIN"
