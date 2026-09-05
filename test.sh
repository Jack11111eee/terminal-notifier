#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/terminal-notifier-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
PLATFORM_DEVELOPER="$(xcrun --show-sdk-platform-path)/Developer"
DEVELOPER_FRAMEWORKS="$PLATFORM_DEVELOPER/Library/Frameworks"

SOURCES=()
while IFS= read -r -d '' source_file; do
    SOURCES+=("$source_file")
done < <(find "$PROJECT_DIR/TerminalNotifier" -name '*.swift' ! -path '*/App/main.swift' -print0)

swiftc \
    -target "$(uname -m)-apple-macosx13.0" \
    -I "$PLATFORM_DEVELOPER/usr/lib" \
    -L "$PLATFORM_DEVELOPER/usr/lib" \
    -Xlinker -rpath -Xlinker "$PLATFORM_DEVELOPER/usr/lib" \
    -F "$DEVELOPER_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$DEVELOPER_FRAMEWORKS" \
    -module-cache-path "$TEST_DIR/ModuleCache" \
    -o "$TEST_DIR/RegressionTests" \
    -framework AppKit \
    -framework SwiftUI \
    -framework ServiceManagement \
    -framework XCTest \
    "${SOURCES[@]}" \
    "$PROJECT_DIR/Tests/RegressionTests.swift"

"$TEST_DIR/RegressionTests"
