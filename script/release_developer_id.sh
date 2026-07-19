#!/usr/bin/env bash
# macOS 站外分发（Developer ID）打包脚本。
# 渠道约定见 114 / 117：developer-id / direct。
# 与 release_appstore.sh 完全分离，不混用 provisioning profile 与 Developer ID notarization。
set -euo pipefail

APP_NAME="SubForge"
BUNDLE_ID="com.jago.subforge"
TEAM_ID="${TEAM_ID:-4UNNXY925R}"
APP_VERSION="${APP_VERSION:-1.0}"
APP_BUILD="${APP_BUILD:-$(date +%Y%m%d%H%M%S)}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-14.0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-Apple-Notary}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/developer-id"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_NOTICES="$APP_RESOURCES/ThirdPartyNotices"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
# 站外分发专用：不要用 App Store 的 sandbox entitlements，否则无法启动。
ENTITLEMENTS="$ROOT_DIR/Config/SubForge.developer-id.entitlements"
INHERIT_ENTITLEMENTS="$ROOT_DIR/Config/SubForge.inherit.entitlements"
ZIP_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION.zip"

SIGN_IDENTITY="${SIGN_IDENTITY:-}"

require_file() {
  if [ ! -e "$1" ]; then
    echo "missing required file: $1" >&2
    exit 1
  fi
}

find_codesigning_identity() {
  local explicit="$1"
  shift
  if [ -n "$explicit" ]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  local pattern
  for pattern in "$@"; do
    local match
    match="$(security find-identity -p codesigning -v 2>/dev/null | sed -n "s/.*\"\($pattern[^\"]*\)\".*/\1/p" | head -n 1)"
    if [ -n "$match" ]; then
      printf '%s\n' "$match"
      return 0
    fi
  done
  return 1
}

build_app() {
  (cd "$ROOT_DIR" && swift build -c release)
}

stage_bundle() {
  local build_bin
  build_bin="$(cd "$ROOT_DIR" && swift build -c release --show-bin-path)/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
  cp "$build_bin" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
  fi

  if [ -f "$ROOT_DIR/Resources/PrivacyInfo.xcprivacy" ]; then
    cp "$ROOT_DIR/Resources/PrivacyInfo.xcprivacy" "$APP_RESOURCES/PrivacyInfo.xcprivacy"
  fi

  if [ -f "$ROOT_DIR/BAK/test_audio.m4a" ]; then
    cp "$ROOT_DIR/BAK/test_audio.m4a" "$APP_RESOURCES/test_audio.m4a"
  fi

  embed_bundled_base_model
  embed_whisper_runtime
  embed_funasr_runtime
  embed_funasr_models
  embed_third_party_notices
  rewrite_runtime_library_paths
  scrub_homebrew_backend_paths
  clean_bundle_metadata

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
  <key>CFBundleDisplayName</key>
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

# 默认不内置 Whisper 模型；用户设置页下载。需要打进包时设 BUNDLE_WHISPER_BASE=1 或 BASE_MODEL_SOURCE。
embed_bundled_base_model() {
  if [ "${BUNDLE_WHISPER_BASE:-0}" != "1" ] && [ -z "${BASE_MODEL_SOURCE:-}" ]; then
    echo "note: skip embedding Whisper base model (in-app download)" >&2
    return 0
  fi

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
    echo "note: Whisper base model not found; shipping without bundled model" >&2
    return 0
  fi

  cp "$source" "$APP_RESOURCES/ggml-base.bin"
}

embed_whisper_runtime() {
  local whisper_prefix ggml_prefix libomp_prefix
  whisper_prefix="$(realpath "$(brew --prefix whisper-cpp)")"
  ggml_prefix="$(realpath "$(brew --prefix ggml)")"
  libomp_prefix="$(realpath "$(brew --prefix libomp)")"

  require_file "$whisper_prefix/bin/whisper-cli"
  cp "$whisper_prefix/bin/whisper-cli" "$APP_FRAMEWORKS/whisper-cli"
  chmod +x "$APP_FRAMEWORKS/whisper-cli"

  find "$whisper_prefix/lib" -maxdepth 1 -name "libwhisper*.dylib" -exec cp {} "$APP_FRAMEWORKS/" \;
  find "$ggml_prefix/lib" -maxdepth 1 -name "libggml*.dylib" -exec cp {} "$APP_FRAMEWORKS/" \;
  find "$ggml_prefix/libexec" -maxdepth 1 -name "libggml*.so" -exec cp {} "$APP_FRAMEWORKS/" \;

  require_file "$libomp_prefix/lib/libomp.dylib"
  cp "$libomp_prefix/lib/libomp.dylib" "$APP_FRAMEWORKS/libomp.dylib"
}

embed_funasr_runtime() {
  local source="${FUNASR_CLI_SOURCE:-$ROOT_DIR/vendor/funasr/llama-funasr-sensevoice}"
  if [ ! -f "$source" ]; then
    echo "note: FunASR runtime missing at $source (optional for Developer ID; run script/download_funasr_runtime.sh)" >&2
    return 0
  fi
  cp "$source" "$APP_FRAMEWORKS/llama-funasr-sensevoice"
  chmod +x "$APP_FRAMEWORKS/llama-funasr-sensevoice"
  local vad_source
  vad_source="$(dirname "$source")/llama-funasr-vad"
  if [ -f "$vad_source" ]; then
    cp "$vad_source" "$APP_FRAMEWORKS/llama-funasr-vad"
    chmod +x "$APP_FRAMEWORKS/llama-funasr-vad"
  fi
}

embed_funasr_models() {
  if [ "${BUNDLE_FUNASR_MODELS:-0}" != "1" ]; then
    echo "note: FunASR model weights are downloaded on demand (set BUNDLE_FUNASR_MODELS=1 to embed)" >&2
    return 0
  fi

  local dest="$APP_RESOURCES/funasr"
  mkdir -p "$dest"
  local asr_name="sensevoice-small-q8.gguf"
  local vad_name="fsmn-vad.gguf"
  local asr_src="" vad_src=""
  local asr_candidates=(
    "${FUNASR_MODEL_SOURCE:-}"
    "$ROOT_DIR/Resources/funasr/$asr_name"
    "$HOME/Library/Application Support/SubForge/models/funasr/$asr_name"
    "$HOME/Library/Containers/com.jago.subforge/Data/Library/Application Support/SubForge/models/funasr/$asr_name"
  )
  local vad_candidates=(
    "${FUNASR_VAD_SOURCE:-}"
    "$ROOT_DIR/Resources/funasr/$vad_name"
    "$HOME/Library/Application Support/SubForge/models/funasr/$vad_name"
    "$HOME/Library/Containers/com.jago.subforge/Data/Library/Application Support/SubForge/models/funasr/$vad_name"
  )
  local c
  for c in "${asr_candidates[@]}"; do
    if [ -n "$c" ] && [ -f "$c" ]; then asr_src="$c"; break; fi
  done
  for c in "${vad_candidates[@]}"; do
    if [ -n "$c" ] && [ -f "$c" ]; then vad_src="$c"; break; fi
  done
  if [ -z "$asr_src" ] || [ -z "$vad_src" ]; then
    echo "warning: FunASR models missing; shipping without bundled FunASR weights" >&2
    return 0
  fi
  cp "$asr_src" "$dest/$asr_name"
  cp "$vad_src" "$dest/$vad_name"
}

embed_third_party_notices() {
  if [ ! -d "$APP_FRAMEWORKS" ] || [ ! -f "$APP_FRAMEWORKS/whisper-cli" ]; then
    return
  fi

  local whisper_prefix ggml_prefix libomp_prefix
  whisper_prefix="$(realpath "$(brew --prefix whisper-cpp)")"
  ggml_prefix="$(realpath "$(brew --prefix ggml)")"
  libomp_prefix="$(realpath "$(brew --prefix libomp)")"

  local whisper_license="$whisper_prefix/LICENSE"
  local ggml_license="$ggml_prefix/LICENSE"
  local libomp_license="$libomp_prefix/LICENSE.TXT"

  require_file "$whisper_license"
  require_file "$ggml_license"
  require_file "$libomp_license"

  mkdir -p "$APP_NOTICES"
  cp "$whisper_license" "$APP_NOTICES/whisper-cpp-LICENSE.txt"
  cp "$ggml_license" "$APP_NOTICES/ggml-LICENSE.txt"
  cp "$libomp_license" "$APP_NOTICES/libomp-LICENSE.txt"
}

rewrite_runtime_library_paths() {
  if [ ! -d "$APP_FRAMEWORKS" ]; then
    return
  fi

  find "$APP_FRAMEWORKS" -type f \( -name "*.dylib" -o -name "*.so" -o -name "whisper-cli" -o -name "llama-funasr-sensevoice" -o -name "llama-funasr-vad" \) -print0 | while IFS= read -r -d '' mach_o; do
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

clean_bundle_metadata() {
  find "$APP_BUNDLE" -name "._*" -delete
  find "$APP_BUNDLE" -print0 | xargs -0 xattr -c 2>/dev/null || true
  dot_clean -m "$APP_BUNDLE" 2>/dev/null || true
}

sign_nested_code() {
  local identity="$1"

  # 站外主程序无 App Sandbox。子进程 whisper-cli 若再签 sandbox+inherit，
  # 会被系统以信号 5 (SIGTRAP) 杀掉（用户可见：whisper-cli 被运行库中断）。
  # 因此 nested code 与主 app 使用同一套 developer-id entitlements。
  if [ -d "$APP_FRAMEWORKS" ]; then
    find "$APP_FRAMEWORKS" -type f -print0 | while IFS= read -r -d '' mach_o; do
      file "$mach_o" | grep -q "Mach-O" || continue
      codesign --force --timestamp --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$identity" "$mach_o"
    done
  fi
}

sign_app() {
  local identity
  identity="$(find_codesigning_identity "$SIGN_IDENTITY" \
    "Developer ID Application: .*($TEAM_ID)")" || {
      echo "missing Developer ID Application signing identity for team $TEAM_ID" >&2
      echo "Install a Developer ID Application certificate, or set SIGN_IDENTITY." >&2
      exit 1
    }

  echo "Signing with: $identity"
  sign_nested_code "$identity"
  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$identity" "$APP_BUNDLE"
}

zip_app() {
  rm -f "$ZIP_PATH"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
}

notarize_app() {
  require_file "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
}

staple_app() {
  xcrun stapler staple "$APP_BUNDLE"
  rm -f "$ZIP_PATH"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
}

verify_dist() {
  require_file "$ENTITLEMENTS"
  require_file "$INHERIT_ENTITLEMENTS"
  plutil -lint "$INFO_PLIST" "$ENTITLEMENTS" "$INHERIT_ENTITLEMENTS"
  if [ -f "$APP_RESOURCES/PrivacyInfo.xcprivacy" ]; then
    plutil -lint "$APP_RESOURCES/PrivacyInfo.xcprivacy"
  else
    echo "missing embedded PrivacyInfo.xcprivacy" >&2
    exit 1
  fi
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  spctl -a -vv "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
}

main() {
  build_app
  stage_bundle
  sign_app
  zip_app
  notarize_app
  staple_app
  verify_dist
  echo "Developer ID artifact ready: $ZIP_PATH"
}

main
