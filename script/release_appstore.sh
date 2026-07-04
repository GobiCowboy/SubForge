#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SubForge"
BUNDLE_ID="com.jago.subforge"
TEAM_ID="${TEAM_ID:-4UNNXY925R}"
APP_VERSION="${APP_VERSION:-1.0}"
APP_BUILD="${APP_BUILD:-$(date +%Y%m%d%H%M%S)}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-14.0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/appstore"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_NOTICES="$APP_RESOURCES/ThirdPartyNotices"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Config/SubForge.entitlements"
DEBUG_ENTITLEMENTS="$ROOT_DIR/Config/SubForge.debug.entitlements"
INHERIT_ENTITLEMENTS="$ROOT_DIR/Config/SubForge.inherit.entitlements"
PKG_PATH="$DIST_DIR/$APP_NAME.pkg"

APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-}"

usage() {
  cat >&2 <<EOF
usage: $0 [--unsigned|--signed|--package|--upload]

Modes:
  --unsigned  Build a release .app and run local structural checks.
  --signed    Build and sign the .app for Mac App Store distribution.
  --package   Build, sign, and create a signed .pkg for App Store upload.
  --upload    Build, sign, package, and upload the .pkg to App Store Connect.

Optional environment:
  APP_VERSION=1.0
  APP_BUILD=$(date +%Y%m%d%H%M%S)
  TEAM_ID=$TEAM_ID
  APP_SIGN_IDENTITY="Apple Distribution: ..."
  INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: ..."
  PROVISIONING_PROFILE="/path/to/SubForge_Mac_App_Store.provisionprofile"
  APP_STORE_USER="apple-id@example.com"
  APP_STORE_PASSWORD="app-specific-password"
EOF
}

MODE="${1:---unsigned}"
case "$MODE" in
  --unsigned|--signed|--package|--upload) ;;
  *) usage; exit 2 ;;
esac

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

find_certificate_label() {
  local explicit="$1"
  shift
  if [ -n "$explicit" ]; then
    printf '%s\n' "$explicit"
    return 0
  fi

  local labels pattern match
  labels="$(security find-certificate -a -Z 2>/dev/null | sed -n 's/.*"labl"<blob>="\([^"]*\)".*/\1/p')"
  for pattern in "$@"; do
    match="$(printf '%s\n' "$labels" | grep -E "$pattern" | head -n 1)"
    if [ -n "$match" ]; then
      printf '%s\n' "$match"
      return 0
    fi
  done

  return 1
}

require_file() {
  if [ ! -e "$1" ]; then
    echo "missing required file: $1" >&2
    exit 1
  fi
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

  embed_provisioning_profile
  embed_whisper_runtime
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

embed_provisioning_profile() {
  local profile="$PROVISIONING_PROFILE"

  if [ -z "$profile" ]; then
    profile="$(find_provisioning_profile || true)"
  fi

  if [ -z "$profile" ]; then
    if [ "$MODE" = "--unsigned" ]; then
      return
    fi

    echo "missing Mac App Store provisioning profile for $BUNDLE_ID" >&2
    echo "Set PROVISIONING_PROFILE=/path/to/SubForge_Mac_App_Store.provisionprofile." >&2
    exit 1
  fi

  require_file "$profile"
  if ! provisioning_profile_matches_bundle "$profile"; then
    echo "provisioning profile does not match $TEAM_ID.$BUNDLE_ID: $profile" >&2
    exit 1
  fi

  echo "Using provisioning profile: $profile"
  cp "$profile" "$APP_CONTENTS/embedded.provisionprofile"
}

find_provisioning_profile() {
  local direct_candidates=(
    "$ROOT_DIR/Config/SubForge_Mac_App_Store.provisionprofile"
    "$ROOT_DIR/SubForge_Mac_App_Store.provisionprofile"
    "$HOME/Downloads/SubForge_Mac_App_Store.provisionprofile"
  )

  local profile
  for profile in "${direct_candidates[@]}"; do
    if [ -f "$profile" ] && provisioning_profile_matches_bundle "$profile"; then
      printf '%s\n' "$profile"
      return 0
    fi
  done

  local search_dirs=(
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    "$HOME/Library/MobileDevice/Provisioning Profiles"
  )

  local dir
  for dir in "${search_dirs[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r profile; do
      if provisioning_profile_matches_bundle "$profile"; then
        printf '%s\n' "$profile"
        return 0
      fi
    done < <(find "$dir" -type f \( -name "*.provisionprofile" -o -name "*.mobileprovision" \) 2>/dev/null)
  done

  return 1
}

provisioning_profile_matches_bundle() {
  local profile="$1"
  local temp_plist app_identifier
  temp_plist="$(mktemp)"
  if ! security cms -D -i "$profile" >"$temp_plist" 2>/dev/null; then
    rm -f "$temp_plist"
    return 1
  fi

  app_identifier="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$temp_plist" 2>/dev/null || true)"
  rm -f "$temp_plist"

  [ "$app_identifier" = "$TEAM_ID.$BUNDLE_ID" ]
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
  find "$ggml_prefix/libexec" -maxdepth 1 -name "libggml*.so" ! -name "libggml-metal.so" -exec cp {} "$APP_FRAMEWORKS/" \;

  require_file "$libomp_prefix/lib/libomp.dylib"
  cp "$libomp_prefix/lib/libomp.dylib" "$APP_FRAMEWORKS/libomp.dylib"
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

clean_bundle_metadata() {
  find "$APP_BUNDLE" -name "._*" -delete
  find "$APP_BUNDLE" -print0 | xargs -0 xattr -c 2>/dev/null || true
  dot_clean -m "$APP_BUNDLE" 2>/dev/null || true
}

sign_nested_code() {
  local identity="$1"

  if [ -d "$APP_FRAMEWORKS" ]; then
    find "$APP_FRAMEWORKS" -type f -print0 | while IFS= read -r -d '' mach_o; do
      file "$mach_o" | grep -q "Mach-O" || continue

      if [ "$(basename "$mach_o")" = "whisper-cli" ]; then
        local timestamp_arg="--timestamp"
        local options_arg="--options runtime"
        if [ "$identity" = "-" ]; then
          timestamp_arg="--timestamp=none"
          options_arg=""
        fi

        codesign --force "$timestamp_arg" ${options_arg:+--options runtime} \
          --entitlements "$INHERIT_ENTITLEMENTS" \
          --sign "$identity" "$mach_o"
      else
        local timestamp_arg="--timestamp"
        local options_arg="--options runtime"
        if [ "$identity" = "-" ]; then
          timestamp_arg="--timestamp=none"
          options_arg=""
        fi

        codesign --force "$timestamp_arg" ${options_arg:+--options runtime} \
          --sign "$identity" "$mach_o"
      fi
    done
  fi
}

sign_app() {
  local identity
  identity="$(find_codesigning_identity "$APP_SIGN_IDENTITY" \
    "3rd Party Mac Developer Application: .*($TEAM_ID)" \
    "Apple Distribution: .*($TEAM_ID)")" || {
      echo "missing Mac App Store app signing identity for team $TEAM_ID" >&2
      echo "Install a Mac App Distribution certificate, or set APP_SIGN_IDENTITY." >&2
      exit 1
    }

  sign_nested_code "$identity"
  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$identity" "$APP_BUNDLE"
}

sign_app_ad_hoc_for_testing() {
  sign_nested_code "-"
  codesign --force --timestamp=none \
    --entitlements "$DEBUG_ENTITLEMENTS" \
    --sign - "$APP_BUNDLE"
}

package_app() {
  local identity
  identity="$(find_certificate_label "$INSTALLER_SIGN_IDENTITY" \
    "3rd Party Mac Developer Installer: .*($TEAM_ID)" \
    "Mac Installer Distribution: .*($TEAM_ID)")" || {
      echo "missing Mac App Store installer signing identity for team $TEAM_ID" >&2
      echo "Note: installer certificates are not listed by 'security find-identity -p codesigning'." >&2
      echo "Install a Mac Installer Distribution certificate, or set INSTALLER_SIGN_IDENTITY." >&2
      exit 1
    }

  clean_bundle_metadata
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

  rm -f "$PKG_PATH"
  COPYFILE_DISABLE=1 productbuild \
    --component "$APP_BUNDLE" /Applications \
    --sign "$identity" \
    "$PKG_PATH"
}

upload_app() {
  require_file "$PKG_PATH"

  if [ -z "${APP_STORE_USER:-}" ] || [ -z "${APP_STORE_PASSWORD:-}" ]; then
    echo "missing APP_STORE_USER or APP_STORE_PASSWORD for App Store Connect upload" >&2
    exit 1
  fi

  xcrun altool --upload-app \
    -f "$PKG_PATH" \
    --type osx \
    -u "$APP_STORE_USER" \
    -p "$APP_STORE_PASSWORD"
}

verify_bundle() {
  require_file "$ENTITLEMENTS"
  require_file "$DEBUG_ENTITLEMENTS"
  require_file "$INHERIT_ENTITLEMENTS"
  plutil -lint "$INFO_PLIST" "$ENTITLEMENTS" "$DEBUG_ENTITLEMENTS" "$INHERIT_ENTITLEMENTS"

  if [ -f "$APP_RESOURCES/PrivacyInfo.xcprivacy" ]; then
    plutil -lint "$APP_RESOURCES/PrivacyInfo.xcprivacy"
  else
    echo "missing embedded PrivacyInfo.xcprivacy" >&2
    exit 1
  fi

  local external_deps
  external_deps="$(
    find "$APP_BUNDLE" -type f -print0 |
      xargs -0 otool -L 2>/dev/null |
      awk '/\/opt\/homebrew|\/usr\/local/ {print}'
  )"
  if [ -n "$external_deps" ]; then
    echo "found non-system absolute library dependencies:" >&2
    echo "$external_deps" >&2
    exit 1
  fi

  if [ "$MODE" != "--unsigned" ]; then
    if [ ! -f "$APP_CONTENTS/embedded.provisionprofile" ]; then
      echo "warning: missing Contents/embedded.provisionprofile; build may not be eligible for TestFlight" >&2
    fi
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    codesign -dvvv --entitlements :- "$APP_BUNDLE" >/dev/null
  fi
}

main() {
  build_app
  stage_bundle

  if [ "$MODE" = "--signed" ] || [ "$MODE" = "--package" ]; then
    sign_app
  else
    sign_app_ad_hoc_for_testing
  fi

  if [ "$MODE" = "--package" ] || [ "$MODE" = "--upload" ]; then
    package_app
  fi

  verify_bundle
  echo "App Store artifact prepared: $APP_BUNDLE"
  if [ "$MODE" = "--package" ] || [ "$MODE" = "--upload" ]; then
    echo "Package prepared: $PKG_PATH"
  fi

  if [ "$MODE" = "--upload" ]; then
    upload_app
  fi
}

main
