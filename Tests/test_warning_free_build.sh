#!/bin/bash
# 回归检查：每次在独立构建目录完整编译，确保项目不产生 Swift 警告。
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d -t codex-usage-card-warning-check)"
trap 'rm -rf "$BUILD_DIR"' EXIT

if ! OUTPUT=$(swift build -c release --build-path "$BUILD_DIR" 2>&1); then
  printf '%s\n' "$OUTPUT"
  echo "FAIL: 项目未能完成无警告构建。"
  exit 1
fi

printf '%s\n' "$OUTPUT"
if rg --fixed-strings --quiet "warning:" <<< "$OUTPUT"; then
  echo "FAIL: 构建仍包含 Swift 警告。"
  exit 1
fi

echo "PASS: 项目完成无警告构建。"
