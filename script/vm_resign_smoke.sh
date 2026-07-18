#!/usr/bin/env bash
# 在 macOS 虚拟机 guest 内执行：覆盖安装后的重签 + 短音频冒烟。
set -euo pipefail

APP="/Applications/SubForge.app"
SRC="/Volumes/My Shared Files/Home/Downloads/SubForge.app"

pkill -9 -x SubForge 2>/dev/null || true
pkill -9 -x llama-funasr-sensevoice 2>/dev/null || true
pkill -9 -x llama-funasr-vad 2>/dev/null || true
sleep 2

if [ -d "$SRC" ]; then
  rm -rf "$APP"
  /usr/bin/ditto "$SRC" "$APP"
  echo "copied from shared Downloads"
fi

test -d "$APP"
find "$APP" -exec xattr -c {} \; 2>/dev/null || true
chmod -R u+w "$APP/Contents/Frameworks" 2>/dev/null || true

INHERIT_ENT="/tmp/subforge_inherit.entitlements"
cat > "$INHERIT_ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.inherit</key>
  <true/>
</dict>
</plist>
PLIST

for name in llama-funasr-sensevoice llama-funasr-vad whisper-cli; do
  src="$APP/Contents/Frameworks/$name"
  [ -f "$src" ] || continue
  xattr -c "$src" 2>/dev/null || true
  codesign --force --sign - --entitlements "$INHERIT_ENT" "$src"
  echo "signed $name"
done

CLI="$APP/Contents/Frameworks/llama-funasr-sensevoice"
MODEL="$APP/Contents/Resources/funasr/sensevoice-small-q8.gguf"
VAD="$APP/Contents/Resources/funasr/fsmn-vad.gguf"
WAV=/tmp/subforge_vm_smoke.wav
/usr/bin/afconvert -f WAVE -d LEI16@16000 -c 1 "$APP/Contents/Resources/test_audio.m4a" "$WAV"
START=$(date +%s)
if "$CLI" -m "$MODEL" -a "$WAV" --vad "$VAD" >/tmp/sf_smoke_out.txt 2>/tmp/sf_smoke_err.txt; then
  END=$(date +%s)
  echo "SMOKE_OK elapsed=$((END-START))s: $(head -c 80 /tmp/sf_smoke_out.txt)"
else
  echo "SMOKE_FAIL status=$?"
  cat /tmp/sf_smoke_err.txt || true
  exit 1
fi

codesign -d --entitlements :- "$CLI" 2>&1 | head -20
open "$APP"
sleep 1
ps -ax -o pid,%cpu,etime,command | grep -E '[S]ubForge' || true
echo DEPLOY_OK
