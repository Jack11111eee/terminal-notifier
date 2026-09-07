#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Local review builds use ad-hoc signing unless an identity is explicitly supplied.
export SIGN_IDENTITY="${SIGN_IDENTITY:--}"
export INSTALL=0
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/terminal-notifier-module-cache}"
bash "$PROJECT_DIR/build.sh"

APP_BUNDLE="$PROJECT_DIR/build/Terminal Notifier.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")
DMG_PATH="$PROJECT_DIR/build/Terminal-Notifier-${VERSION}-macOS-arm64.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/terminal-notifier-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_BUNDLE" "$STAGING_DIR/Terminal Notifier.app"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/Read Me.txt" <<'NOTES'
Terminal Notifier — Modern macOS preview

Drag Terminal Notifier.app to Applications to install.
Quit an existing Terminal Notifier instance before opening this build.
This is a local review build; it is not notarized.
Requires an Apple silicon Mac running macOS 13 or later.
Liquid Glass is available on macOS 26 and later; older systems use native materials.

拖动 Terminal Notifier.app 到 Applications 安装。
启动此构建前，请先退出已运行的 Terminal Notifier。
这是本地试用构建，未经公证。
需要 Apple 芯片 Mac，支持 macOS 13 及以上版本。
macOS 26 使用 Liquid Glass，较旧系统使用原生材质。

UI refinement build R6 / 界面优化第六版
- Resizable settings, history and self-check windows / 可缩放窗口
- Full-height native-style glass sidebar / 贯通标题栏的原生风格玻璃侧栏
- Separate native material layout for compatibility mode / 兼容模式使用独立的原生材质布局
- Centered history search and fewer separators / 居中历史搜索与减少分割线
- Compact reminders that do not take keyboard focus / 不抢键盘焦点的紧凑提醒
- Separate Close, Later and Open source actions / 独立的关闭、稍后、打开来源操作
- System appearance, accessible controls and reduced motion / 系统外观、辅助功能及减少动态效果支持
NOTES

codesign --verify --deep --strict "$STAGING_DIR/Terminal Notifier.app"
hdiutil create -volname 'Terminal Notifier' -srcfolder "$STAGING_DIR" -format UDZO -ov "$DMG_PATH"
hdiutil verify "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "DMG: $DMG_PATH"
