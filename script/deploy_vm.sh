#!/usr/bin/env bash
# 构建 SubForge，打 tarball 投递到 Parallels macOS 虚拟机，
# guest 内清隔离属性、按「无沙箱主程序 + 普通 adhoc 嵌套 CLI」重签，并冒烟。
#
# 重要（信号 5 / SIGTRAP）：
#   - 主程序若带 sandbox，子进程必须 sandbox+inherit
#   - 主程序若无 sandbox（站外/VM 测试常见），子进程带 inherit 会 Trace/BPT trap: 5
#   - 只更新 MacOS 二进制却用 `codesign --sign -` 裸签，会把主程序 sandbox 签没，
#     却留下 inherit 的 CLI → App 内一跑 FunASR 就信号 5
# 因此 VM 分发包统一：主程序 developer-id 风格（无 sandbox）+ CLI 普通 adhoc。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SubForge.app"
TGZ_NAME="SubForge-vm.tgz"
VM_NAME="${PRLAPP_VM:-macOS}"

cd "$ROOT_DIR"
echo "=== build ==="
./script/build_and_run.sh >/tmp/subforge_build.log 2>&1 || {
  tail -40 /tmp/subforge_build.log
  exit 1
}
pkill -x SubForge 2>/dev/null || true

echo "=== stage chunked tarball to Downloads ==="
rm -f "$HOME/Downloads/$TGZ_NAME" "$HOME/Downloads/${TGZ_NAME}.part"* "$HOME/Downloads/SubForge-vm.sha256" 2>/dev/null || true
rm -f "$HOME/Downloads"/SubForge-vm.tgz.part* 2>/dev/null || true
tar -C "$ROOT_DIR/dist" -czf "$HOME/Downloads/$TGZ_NAME" "$APP_NAME"
shasum -a 256 "$HOME/Downloads/$TGZ_NAME" | tee "$HOME/Downloads/SubForge-vm.sha256"
split -b 40m "$HOME/Downloads/$TGZ_NAME" "$HOME/Downloads/${TGZ_NAME}.part"
ls -lh "$HOME/Downloads"/${TGZ_NAME}.part* 2>/dev/null || ls -lh "$HOME/Downloads"/SubForge-vm.tgz.part*
sync

echo "=== guest install + resign + smoke ==="
prlctl exec "$VM_NAME" --current-user bash <<'EOF'
set -e
APP="/Applications/SubForge.app"
DIR="/Volumes/My Shared Files/Home/Downloads"
EXPECTED="$(awk '{print $1}' "$DIR/SubForge-vm.sha256")"

pkill -9 -x SubForge 2>/dev/null || true
pkill -9 -x llama-funasr-sensevoice 2>/dev/null || true
pkill -9 -x llama-funasr-vad 2>/dev/null || true
sleep 2

for i in $(seq 1 30); do
  n=$(ls "$DIR"/SubForge-vm.tgz.part* 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 2 ] && break
  sleep 1
done
cat "$DIR"/SubForge-vm.tgz.part* > /tmp/SubForge-vm.tgz
GOT="$(shasum -a 256 /tmp/SubForge-vm.tgz | awk '{print $1}')"
echo "checksum expected=$EXPECTED got=$GOT"
[ "$EXPECTED" = "$GOT" ]

rm -rf /tmp/SubForge.app "$APP"
tar -xzf /tmp/SubForge-vm.tgz -C /tmp
mv /tmp/SubForge.app "$APP"
echo "installed $(du -sh "$APP" | awk '{print $1}')"

find "$APP" -exec xattr -c {} \; 2>/dev/null || true
chmod -R u+w "$APP/Contents" 2>/dev/null || true

# 主程序：无 sandbox（与 developer-id 站外包一致）
MAIN_ENT="/tmp/subforge_main.entitlements"
cat > "$MAIN_ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
  <key>com.apple.security.automation.apple-events</key>
  <true/>
</dict>
</plist>
PLIST

# 嵌套 CLI / dylib：普通 adhoc，不要 inherit
for name in llama-funasr-sensevoice llama-funasr-vad whisper-cli; do
  src="$APP/Contents/Frameworks/$name"
  [ -f "$src" ] || continue
  codesign --force --sign - "$src"
  echo "plain_signed $name"
done
find "$APP/Contents/Frameworks" -type f \( -name '*.dylib' -o -name '*.so' \) -print0 \
  | while IFS= read -r -d '' f; do
      codesign --force --sign - "$f" 2>/dev/null || true
    done

codesign --force --sign - --entitlements "$MAIN_ENT" "$APP/Contents/MacOS/SubForge"
codesign --force --sign - --entitlements "$MAIN_ENT" "$APP"

CLI="$APP/Contents/Frameworks/llama-funasr-sensevoice"
MODEL="$APP/Contents/Resources/funasr/sensevoice-small-q8.gguf"
VAD="$APP/Contents/Resources/funasr/fsmn-vad.gguf"
WAV=/tmp/subforge_vm_smoke.wav
/usr/bin/afconvert -f WAVE -d LEI16@16000 -c 1 "$APP/Contents/Resources/test_audio.m4a" "$WAV"
if "$CLI" -m "$MODEL" -a "$WAV" --vad "$VAD" >/tmp/sf_smoke_out.txt 2>/tmp/sf_smoke_err.txt; then
  echo "SMOKE_OK: $(head -c 80 /tmp/sf_smoke_out.txt)"
else
  echo "SMOKE_FAIL status=$?"
  cat /tmp/sf_smoke_err.txt || true
  exit 1
fi

open "$APP"
sleep 2
ps -ax -o pid,%cpu,etime,command | grep -E '[S]ubForge' || true
echo DEPLOY_OK
EOF
