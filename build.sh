#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXECUTABLE_NAME="TerminalNotifier"
APP_BUNDLE_NAME="Terminal Notifier"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_BUNDLE_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
SIGN_IDENTITY="${SIGN_IDENTITY:-TerminalNotifierDev}"
INSTALL="${INSTALL:-0}"

echo "=== Building $APP_BUNDLE_NAME ==="
echo "Target: arm64-apple-macosx13.0"
echo "Signing identity: $SIGN_IDENTITY"
echo "Install to /Applications: $INSTALL"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

SOURCES=()
while IFS= read -r -d '' source_file; do
    SOURCES+=("$source_file")
done < <(find "$PROJECT_DIR/TerminalNotifier" -name "*.swift" -print0)

echo "Compiling Swift sources..."
swiftc \
    -o "$MACOS_DIR/$EXECUTABLE_NAME" \
    -framework AppKit \
    -framework SwiftUI \
    -framework ServiceManagement \
    -target arm64-apple-macosx13.0 \
    -O \
    "${SOURCES[@]}"

echo "Copying Info.plist..."
cp "$PROJECT_DIR/TerminalNotifier/Info.plist" "$CONTENTS/Info.plist"
printf "APPL????" > "$CONTENTS/PkgInfo"
cp "$PROJECT_DIR/TerminalNotifier/Messages/"*.json "$RESOURCES_DIR/"
cp "$PROJECT_DIR/TerminalNotifier/Resources/"*.png "$RESOURCES_DIR/"
cp "$PROJECT_DIR/TerminalNotifier/Resources/"*.icns "$RESOURCES_DIR/"

echo "Signing app bundle..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

if [[ "$INSTALL" == "1" ]]; then
    echo "Copying to /Applications..."
    rm -rf "/Applications/$APP_BUNDLE_NAME.app"
    ditto "$APP_BUNDLE" "/Applications/$APP_BUNDLE_NAME.app"
fi

echo ""
echo "=== Build complete ==="
echo "App bundle: $APP_BUNDLE"
if [[ "$INSTALL" == "1" ]]; then
    echo "Installed:  /Applications/$APP_BUNDLE_NAME.app"
fi
echo ""
echo "To run: open \"$APP_BUNDLE\""
