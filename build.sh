#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TerminalNotifier"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "=== Building $APP_NAME ==="

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

SOURCES=$(find "$PROJECT_DIR/TerminalNotifier" -name "*.swift" -print0 | xargs -0 echo)

echo "Compiling Swift sources..."
swiftc \
    -o "$MACOS_DIR/$APP_NAME" \
    -framework AppKit \
    -framework SwiftUI \
    -framework ServiceManagement \
    -target arm64-apple-macosx13.0 \
    -O \
    $SOURCES

echo "Copying Info.plist..."
cp "$PROJECT_DIR/TerminalNotifier/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJECT_DIR/TerminalNotifier/Messages/"*.json "$RESOURCES_DIR/"

echo ""
echo "=== Build complete ==="
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "Or:    $MACOS_DIR/$APP_NAME"
