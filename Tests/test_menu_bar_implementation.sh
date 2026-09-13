#!/bin/bash
# 回归测试：菜单栏图标必须由 macOS 原生状态栏托管，不能是普通悬浮窗。
set -euo pipefail

cd "$(dirname "$0")/.."
SOURCE="Sources/CodexUsageCard/App.swift"
CARD_VIEW="Sources/CodexUsageCard/CardView.swift"
STORE="Sources/CodexUsageCard/Store.swift"

if ! rg --fixed-strings --quiet "NSStatusBar.system.statusItem" "$SOURCE"; then
  echo "FAIL: 菜单栏图标尚未使用 NSStatusBar.system.statusItem。"
  exit 1
fi

if ! rg --fixed-strings --quiet "final class UsageMenuBarView: NSView" "$SOURCE"; then
  echo "FAIL: 菜单栏尚未使用自绘用量视图，图标可能不可见。"
  exit 1
fi

if ! rg --fixed-strings --quiet 'item.autosaveName = "CodexUsageMenuBar"' "$SOURCE"; then
  echo "FAIL: 菜单栏项目尚未使用稳定身份，可能继续恢复旧的隐藏位置。"
  exit 1
fi

if ! rg --fixed-strings --quiet "item.isVisible = true" "$SOURCE"; then
  echo "FAIL: 菜单栏项目尚未明确要求显示。"
  exit 1
fi

if rg --fixed-strings --quiet "item.view = statusView" "$SOURCE"; then
  echo "FAIL: 菜单栏仍在使用已弃用的 NSStatusItem.view。"
  exit 1
fi

if ! rg --fixed-strings --quiet "item.button" "$SOURCE" \
   || ! rg --fixed-strings --quiet "button.addSubview(statusView)" "$SOURCE" \
   || ! rg --fixed-strings --quiet "statusView.update(usedPercent:" "$SOURCE"; then
  echo "FAIL: 菜单栏按钮尚未承载自绘用量圆环和百分比。"
  exit 1
fi

if rg --fixed-strings --quiet "statusView.update(usedPercent: primary?.usedPercent, tint: NSColor(store.statusTint))" "$SOURCE"; then
  echo "FAIL: 菜单栏圆环仍错误跟随个人主题色。"
  exit 1
fi

if ! rg --fixed-strings --quiet "static func alertTint(for percent: Double?) -> Color" "$STORE" || ! rg --fixed-strings --quiet "case ..<50: return .green" "$STORE" || ! rg --fixed-strings --quiet "case ..<80: return .yellow" "$STORE" || ! rg --fixed-strings --quiet "default: return .red" "$STORE"; then
  echo "FAIL: 尚未定义共享的绿、黄、红三档警示色。"
  exit 1
fi

if ! rg --fixed-strings --quiet "UsagePalette.alertTint(for: usedPercent)" "$SOURCE" || ! rg --fixed-strings --quiet "UsagePalette.alertTint(for: store.snapshot.primary?.usedPercent)" "$CARD_VIEW"; then
  echo "FAIL: 顶部圆环与卡片主圆环没有共用同一套警示色规则。"
  exit 1
fi

if ! rg --fixed-strings --quiet "onPrimaryAction = { [weak self] in self?.toggleClicked() }" "$SOURCE"; then
  echo "FAIL: 左键没有直接显示或隐藏卡片。"
  exit 1
fi

if ! rg --fixed-strings --quiet "onSecondaryAction = { [weak self, weak statusView] in" "$SOURCE" \
   || ! rg --fixed-strings --quiet "self.showStatusMenu(in: statusView)" "$SOURCE"; then
  echo "FAIL: 右键没有保留操作菜单。"
  exit 1
fi

if rg --fixed-strings --quiet "onToggleCollapse: { [weak self] in self?.store.collapsed.toggle() }" "$SOURCE"; then
  echo "FAIL: 最小化按钮仍在显示桌面胶囊，而非收起到菜单栏。"
  exit 1
fi

if ! rg --fixed-strings --quiet "minimizeToMenuBar" "$SOURCE"; then
  echo "FAIL: 尚未提供收起到菜单栏的行为。"
  exit 1
fi

if ! rg --fixed-strings --quiet 'help: "收起到顶部菜单栏"' "$CARD_VIEW"; then
  echo "FAIL: 最小化按钮的提示文案仍未说明会收起到顶部菜单栏。"
  exit 1
fi

echo "PASS: 菜单栏图标由 macOS 原生状态栏托管。"
