#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-settings}"
SETTINGS_VISUAL_MODE="${2:-}"
APP_BUNDLE="$PROJECT_DIR/build/TerminalNotifier.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/TerminalNotifier"
LOG_FILE="/tmp/terminal-notifier-preview.log"

case "$MODE" in
    settings|history|overlay|all) ;;
    *)
        echo "Usage: $0 [settings|history|overlay|all]" >&2
        exit 64
        ;;
esac

case "$SETTINGS_VISUAL_MODE" in
    ""|modern|compatible) ;;
    *)
        echo "Usage: $0 [settings|history|overlay|all] [modern|compatible]" >&2
        exit 64
        ;;
esac

echo "=== Terminal Notifier preview: $MODE ==="

if pgrep -f "TerminalNotifier.*--preview" >/dev/null 2>&1; then
    echo "Stopping previous preview instance..."
    while IFS= read -r pid; do
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    done < <(pgrep -f "TerminalNotifier.*--preview" || true)
fi

CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/build/ModuleCache" "$PROJECT_DIR/build.sh"

echo "Opening preview app..."
if [[ ! -x "$APP_EXECUTABLE" ]]; then
    echo "Preview executable is missing or not executable: $APP_EXECUTABLE" >&2
    exit 66
fi

: > "$LOG_FILE"
PREVIEW_ARGS=(--preview "$MODE")
if [[ -n "$SETTINGS_VISUAL_MODE" ]]; then
    PREVIEW_ARGS+=(--settings-visual-mode "$SETTINGS_VISUAL_MODE")
fi
nohup "$APP_EXECUTABLE" "${PREVIEW_ARGS[@]}" >"$LOG_FILE" 2>&1 &
echo "Preview process started with PID $!"
echo "Log: $LOG_FILE"
