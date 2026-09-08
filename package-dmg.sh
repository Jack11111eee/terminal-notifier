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

codesign --verify --deep --strict "$STAGING_DIR/Terminal Notifier.app"
hdiutil create -volname 'Terminal Notifier' -srcfolder "$STAGING_DIR" -format UDZO -ov "$DMG_PATH"
hdiutil verify "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "DMG: $DMG_PATH"
