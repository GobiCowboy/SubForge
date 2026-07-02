#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SubForge"
BUNDLE_ID="com.jago.subforge"
MIN_SYSTEM_VERSION="14.0"
BUILD_CONFIGURATION="debug"
APP_VERSION="${APP_VERSION:-1.0}"
APP_BUILD="${APP_BUILD:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Config/SubForge.entitlements"
DEBUG_ENTITLEMENTS="$ROOT_DIR/Config/SubForge.debug.entitlements"
INHERIT_ENTITLEMENTS="$ROOT_DIR/Config/SubForge.inherit.entitlements"

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
  mkdir -p "$APP_FRAMEWORKS"
  cp "$build_bin" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  if [ -f "$ROOT_DIR/BAK/test_audio.m4a" ]; then
    cp "$ROOT_DIR/BAK/test_audio.m4a" "$APP_RESOURCES/test_audio.m4a"
  fi
  embed_bundled_base_model

  if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
  fi

  if [ -f "$ROOT_DIR/Resources/PrivacyInfo.xcprivacy" ]; then
    cp "$ROOT_DIR/Resources/PrivacyInfo.xcprivacy" "$APP_RESOURCES/PrivacyInfo.xcprivacy"
  fi

  embed_whisper_runtime
  rewrite_runtime_library_paths
  scrub_homebrew_backend_paths
  sign_nested_code_ad_hoc

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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.video</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>SubForge 需要语音识别权限，将用户选择的音频转写为字幕。</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>SubForge 需要控制 Final Cut Pro 来导入导出的 FCPXML。</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

embed_bundled_base_model() {
  local source="${BASE_MODEL_SOURCE:-}"
  local candidates=(
    "$ROOT_DIR/Resources/ggml-base.bin"
    "$ROOT_DIR/BAK/models/ggml-base.bin"
    "$HOME/Library/Application Support/SubForge/models/ggml-base.bin"
    "$HOME/Library/Containers/com.jago.subforge/Data/Library/Application Support/SubForge/models/ggml-base.bin"
  )

  if [ -z "$source" ]; then
    local candidate
    for candidate in "${candidates[@]}"; do
      if [ -f "$candidate" ]; then
        source="$candidate"
        break
      fi
    done
  fi

  if [ -z "$source" ] || [ ! -f "$source" ]; then
    echo "missing bundled Base model; set BASE_MODEL_SOURCE=/path/to/ggml-base.bin" >&2
    exit 1
  fi

  cp "$source" "$APP_RESOURCES/ggml-base.bin"
}

sign_nested_code_ad_hoc() {
  if [ ! -d "$APP_FRAMEWORKS" ]; then
    return
  fi

  find "$APP_FRAMEWORKS" -type f -print0 | while IFS= read -r -d '' mach_o; do
    file "$mach_o" | grep -q "Mach-O" || continue
    if [ "$(basename "$mach_o")" = "whisper-cli" ] && [ -f "$INHERIT_ENTITLEMENTS" ]; then
      codesign --force --timestamp=none \
        --entitlements "$INHERIT_ENTITLEMENTS" \
        --sign - "$mach_o"
    else
      codesign --force --timestamp=none --sign - "$mach_o"
    fi
  done
}

embed_whisper_runtime() {
  if ! command -v brew >/dev/null 2>&1; then
    return
  fi

  local whisper_prefix ggml_prefix libomp_prefix
  whisper_prefix="$(brew --prefix whisper-cpp 2>/dev/null || true)"
  ggml_prefix="$(brew --prefix ggml 2>/dev/null || true)"
  libomp_prefix="$(brew --prefix libomp 2>/dev/null || true)"
  [ -n "$whisper_prefix" ] && whisper_prefix="$(realpath "$whisper_prefix")"
  [ -n "$ggml_prefix" ] && ggml_prefix="$(realpath "$ggml_prefix")"
  [ -n "$libomp_prefix" ] && libomp_prefix="$(realpath "$libomp_prefix")"

  if [ -n "$whisper_prefix" ] && [ -x "$whisper_prefix/bin/whisper-cli" ]; then
    cp "$whisper_prefix/bin/whisper-cli" "$APP_FRAMEWORKS/whisper-cli"
    chmod +x "$APP_FRAMEWORKS/whisper-cli"
  fi

  if [ -n "$whisper_prefix" ] && [ -d "$whisper_prefix/lib" ]; then
    find "$whisper_prefix/lib" -maxdepth 1 -name "libwhisper*.dylib" -exec cp {} "$APP_FRAMEWORKS/" \;
  fi

  if [ -n "$ggml_prefix" ] && [ -d "$ggml_prefix/lib" ]; then
    find "$ggml_prefix/lib" -maxdepth 1 -name "libggml*.dylib" -exec cp {} "$APP_FRAMEWORKS/" \;
  fi

  if [ -n "$ggml_prefix" ] && [ -d "$ggml_prefix/libexec" ]; then
    find "$ggml_prefix/libexec" -maxdepth 1 -name "libggml*.so" ! -name "libggml-metal.so" -exec cp {} "$APP_FRAMEWORKS/" \;
  fi

  if [ -n "$libomp_prefix" ] && [ -f "$libomp_prefix/lib/libomp.dylib" ]; then
    cp "$libomp_prefix/lib/libomp.dylib" "$APP_FRAMEWORKS/libomp.dylib"
  fi
}

rewrite_runtime_library_paths() {
  if [ ! -d "$APP_FRAMEWORKS" ]; then
    return
  fi

  find "$APP_FRAMEWORKS" -type f \( -name "*.dylib" -o -name "*.so" -o -name "whisper-cli" \) -print0 | while IFS= read -r -d '' mach_o; do
    file "$mach_o" | grep -q "Mach-O" || continue

    if [[ "$(basename "$mach_o")" == *.dylib ]]; then
      install_name_tool -id "@loader_path/$(basename "$mach_o")" "$mach_o" 2>/dev/null || true
    fi

    otool -L "$mach_o" 2>/dev/null | awk '/@rpath\/|\/opt\/homebrew|\/usr\/local/ {print $1}' | while read -r dependency; do
      local name
      name="$(basename "$dependency")"
      if [ -f "$APP_FRAMEWORKS/$name" ]; then
        install_name_tool -change "$dependency" "@loader_path/$name" "$mach_o" 2>/dev/null || true
      fi
    done
  done
}

scrub_homebrew_backend_paths() {
  if [ ! -d "$APP_FRAMEWORKS" ]; then
    return
  fi

  local old="/opt/homebrew/Cellar/ggml/0.15.1/libexec"
  local replacement="/SubForgeNoBackendDirectory/unused_path_"

  find "$APP_FRAMEWORKS" -type f -print0 | while IFS= read -r -d '' mach_o; do
    file "$mach_o" | grep -q "Mach-O" || continue
    if strings "$mach_o" | grep -q "$old"; then
      perl -0pi -e "s|\\Q$old\\E|$replacement|g" "$mach_o"
    fi
  done
}

sign_bundle_if_requested() {
  local identity="${CODE_SIGN_IDENTITY:--}"
  local entitlements="$ENTITLEMENTS"
  local timestamp_arg="--timestamp"
  local options_arg="--options runtime"
  if [ "$identity" = "-" ]; then
    timestamp_arg="--timestamp=none"
    options_arg=""
    entitlements="$DEBUG_ENTITLEMENTS"
  fi

  codesign --force \
    ${options_arg:+--options runtime} \
    "$timestamp_arg" \
    --entitlements "$entitlements" \
    --sign "$identity" \
    "$APP_BUNDLE"
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
      sign_bundle_if_requested
      open_app
      ;;
    release)
      BUILD_CONFIGURATION="release"
      kill_existing
      build_app
      stage_bundle
      sign_bundle_if_requested
      open_app
      ;;
    --debug|debug)
      BUILD_CONFIGURATION="debug"
      kill_existing
      build_app
      stage_bundle
      sign_bundle_if_requested
      lldb -- "$APP_BINARY"
      ;;
    --logs|logs)
      BUILD_CONFIGURATION="debug"
      kill_existing
      build_app
      stage_bundle
      sign_bundle_if_requested
      open_app
      stream_logs
      ;;
    --telemetry|telemetry)
      BUILD_CONFIGURATION="debug"
      kill_existing
      build_app
      stage_bundle
      sign_bundle_if_requested
      open_app
      stream_telemetry
      ;;
    --verify|verify)
      BUILD_CONFIGURATION="debug"
      kill_existing
      build_app
      stage_bundle
      sign_bundle_if_requested
      open_app
      verify_launch
      ;;
    --release-logs|release-logs)
      BUILD_CONFIGURATION="release"
      kill_existing
      build_app
      stage_bundle
      sign_bundle_if_requested
      open_app
      stream_logs
      ;;
    --release-telemetry|release-telemetry)
      BUILD_CONFIGURATION="release"
      kill_existing
      build_app
      stage_bundle
      sign_bundle_if_requested
      open_app
      stream_telemetry
      ;;
    --release-verify|release-verify)
      BUILD_CONFIGURATION="release"
      kill_existing
      build_app
      stage_bundle
      sign_bundle_if_requested
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
