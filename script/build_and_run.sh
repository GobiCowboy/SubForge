#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SubForge"
BUNDLE_ID="com.jago.subforge"
MIN_SYSTEM_VERSION="14.0"
BUILD_CONFIGURATION="debug"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

usage() {
  echo "usage: $0 [run|release|--debug|--logs|--telemetry|--verify|--release-logs|--release-telemetry|--release-verify]" >&2
}

kill_existing() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  (cd "$ROOT_DIR" && swift build -c "$BUILD_CONFIGURATION")
}

stage_bundle() {
  local build_bin
  build_bin="$(cd "$ROOT_DIR" && swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  mkdir -p "$APP_RESOURCES"
  cp "$build_bin" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  if [ -f "$ROOT_DIR/BAK/test_audio.m4a" ]; then
    cp "$ROOT_DIR/BAK/test_audio.m4a" "$APP_RESOURCES/test_audio.m4a"
  fi

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>SubForge 需要语音识别权限来验证 Apple 语音转写能力。</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE" >/dev/null 2>&1 &
}

stream_logs() {
  /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
}

stream_telemetry() {
  /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
}

verify_launch() {
  for _ in {1..20}; do
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  pgrep -x "$APP_NAME" >/dev/null
}

main() {
  case "$MODE" in
    run|"")
      BUILD_CONFIGURATION="debug"
      kill_existing
      build_app
      stage_bundle
      open_app
      ;;
    release)
      BUILD_CONFIGURATION="release"
      kill_existing
      build_app
      stage_bundle
      open_app
      ;;
    --debug|debug)
      BUILD_CONFIGURATION="debug"
      kill_existing
      build_app
      stage_bundle
      lldb -- "$APP_BINARY"
      ;;
    --logs|logs)
      BUILD_CONFIGURATION="debug"
      kill_existing
      build_app
      stage_bundle
      open_app
      stream_logs
      ;;
    --telemetry|telemetry)
      BUILD_CONFIGURATION="debug"
      kill_existing
      build_app
      stage_bundle
      open_app
      stream_telemetry
      ;;
    --verify|verify)
      BUILD_CONFIGURATION="debug"
      kill_existing
      build_app
      stage_bundle
      open_app
      verify_launch
      ;;
    --release-logs|release-logs)
      BUILD_CONFIGURATION="release"
      kill_existing
      build_app
      stage_bundle
      open_app
      stream_logs
      ;;
    --release-telemetry|release-telemetry)
      BUILD_CONFIGURATION="release"
      kill_existing
      build_app
      stage_bundle
      open_app
      stream_telemetry
      ;;
    --release-verify|release-verify)
      BUILD_CONFIGURATION="release"
      kill_existing
      build_app
      stage_bundle
      open_app
      verify_launch
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main
