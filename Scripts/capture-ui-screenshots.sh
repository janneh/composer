#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-capture}"
ARTIFACT_DIR="${UI_ARTIFACT_DIR:-$ROOT_DIR/Artifacts/UI}"
BASELINE_DIR="${UI_BASELINE_DIR:-$ROOT_DIR/References/UI}"
FIXTURE_ROOT="${COMPOSER_UI_FIXTURE_ROOT:-$ROOT_DIR/.build/ui-screenshots}"
STORE_PATH="$FIXTURE_ROOT/composer-ui-fixture.json"
APP_PATH="${XCODE_APP:-$ROOT_DIR/.build/XcodeDerivedData/Build/Products/Debug/Composer.app}"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/Composer"
APP_LOG="$FIXTURE_ROOT/composer-app.log"

if [[ "$MODE" != "capture" && "$MODE" != "check" && "$MODE" != "bless" ]]; then
    echo "Usage: $0 [capture|check|bless]" >&2
    exit 64
fi

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 69
    fi
}

require_command make
require_command swift
require_command osascript
require_command screencapture
require_command shasum
require_command pgrep

if pgrep -x Composer >/dev/null 2>&1; then
    echo "Close the running Composer app before capturing UI screenshots." >&2
    exit 70
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    make -C "$ROOT_DIR" xcode-build build-cli
fi

if [[ ! -x "$APP_EXECUTABLE" ]]; then
    echo "Composer app executable was not found at $APP_EXECUTABLE" >&2
    exit 66
fi

mkdir -p "$ARTIFACT_DIR" "$BASELINE_DIR" "$FIXTURE_ROOT"
rm -f "$STORE_PATH" "$APP_LOG"

BIN_PATH="$(
    env CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache" \
        swift build --disable-sandbox --cache-path "$ROOT_DIR/.build/swiftpm-cache" --show-bin-path
)"
COMPOSERCTL="$BIN_PATH/composerctl"

"$COMPOSERCTL" --store "$STORE_PATH" project add --name "UI Fixture" --repo "$ROOT_DIR" --agent codex --model "gpt-5.2"
"$COMPOSERCTL" --store "$STORE_PATH" task add --project "UI Fixture" --identifier CMP-101 --title "Tighten empty board layout" --description "Keep lanes pinned below diagnostics and let tasks grow downward." --state backlog --priority normal --label design --label layout
"$COMPOSERCTL" --store "$STORE_PATH" task add --project "UI Fixture" --identifier CMP-102 --title "Review ready dispatch copy" --description "Confirm action labels remain readable in the compact toolbar." --state ready --priority high --label copy
"$COMPOSERCTL" --store "$STORE_PATH" task add --project "UI Fixture" --identifier CMP-103 --title "Run provider smoke check" --description "Keep runtime status rows stable while an agent run is active." --state running --priority urgent --label runtime
"$COMPOSERCTL" --store "$STORE_PATH" task add --project "UI Fixture" --identifier CMP-104 --title "Validate inspector scroll behavior" --description "Use a long task body so the inspector must scroll inside a short window without moving the board offscreen." --state human-review --priority high --label review
"$COMPOSERCTL" --store "$STORE_PATH" task add --project "UI Fixture" --identifier CMP-105 --title "Prepare merge handoff" --description "Confirm merge lane cards preserve spacing and borders." --state merging --priority normal --label merge
"$COMPOSERCTL" --store "$STORE_PATH" task add --project "UI Fixture" --identifier CMP-106 --title "Document UI quality checks" --description "Keep this completed task visible in the done lane." --state done --priority low --label docs

COMPOSER_STORE_BACKEND=json COMPOSER_STORE_PATH="$STORE_PATH" "$APP_EXECUTABLE" >"$APP_LOG" 2>&1 &
APP_PID=$!

cleanup() {
    if kill -0 "$APP_PID" >/dev/null 2>&1; then
        kill "$APP_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

sleep 2

osascript <<'APPLESCRIPT'
tell application "Composer" to activate
delay 0.4
tell application "System Events"
    tell process "Composer"
        set frontmost to true
        set position of window 1 to {96, 96}
        set size of window 1 to {1280, 760}
    end tell
end tell
APPLESCRIPT
sleep 0.6
screencapture -x "$ARTIFACT_DIR/main-1280x760.png"

osascript <<'APPLESCRIPT'
tell application "System Events"
    click at {430, 450}
end tell
APPLESCRIPT
sleep 0.5
screencapture -x "$ARTIFACT_DIR/selected-task-1280x760.png"

osascript <<'APPLESCRIPT'
tell application "System Events"
    tell process "Composer"
        set position of window 1 to {96, 96}
        set size of window 1 to {840, 720}
    end tell
end tell
APPLESCRIPT
sleep 0.6
screencapture -x "$ARTIFACT_DIR/compact-840x720.png"

if [[ "$MODE" == "bless" ]]; then
    cp "$ARTIFACT_DIR"/*.png "$BASELINE_DIR"/
    echo "Blessed UI screenshots into $BASELINE_DIR"
    exit 0
fi

if [[ "$MODE" == "capture" ]]; then
    echo "Captured UI screenshots in $ARTIFACT_DIR"
    exit 0
fi

status=0
for artifact in "$ARTIFACT_DIR"/*.png; do
    baseline="$BASELINE_DIR/$(basename "$artifact")"
    if [[ ! -f "$baseline" ]]; then
        echo "Missing UI screenshot baseline: $baseline" >&2
        status=1
        continue
    fi

    artifact_hash="$(shasum -a 256 "$artifact" | awk '{print $1}')"
    baseline_hash="$(shasum -a 256 "$baseline" | awk '{print $1}')"
    if [[ "$artifact_hash" != "$baseline_hash" ]]; then
        echo "UI screenshot changed: $(basename "$artifact")" >&2
        echo "  artifact: $artifact" >&2
        echo "  baseline: $baseline" >&2
        status=1
    fi
done

if [[ "$status" -eq 0 ]]; then
    echo "UI screenshots match baselines in $BASELINE_DIR"
fi

exit "$status"
