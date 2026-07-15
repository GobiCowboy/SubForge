#!/usr/bin/env bash
# 下载 FunASR llama.cpp macOS arm64 运行时到 vendor/funasr/
# 用法: script/download_funasr_runtime.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/vendor/funasr"
VERSION="${FUNASR_RUNTIME_VERSION:-runtime-llamacpp-v0.1.6}"
ASSET="funasr-llamacpp-macos-arm64.tar.gz"
BASE_URL="https://github.com/modelscope/FunASR/releases/download/${VERSION}"
MIRRORS=(
  "${BASE_URL}/${ASSET}"
  "https://ghfast.top/${BASE_URL}/${ASSET}"
)

mkdir -p "$OUT_DIR"
TMP_TGZ="$OUT_DIR/${ASSET}"
TMP_EXTRACT="$OUT_DIR/_extract_$$"

cleanup() {
  rm -rf "$TMP_EXTRACT"
}
trap cleanup EXIT

download_ok=0
for url in "${MIRRORS[@]}"; do
  echo "downloading $url"
  if curl -fL --connect-timeout 20 --max-time 300 -o "$TMP_TGZ" "$url"; then
    download_ok=1
    break
  fi
  rm -f "$TMP_TGZ"
done

if [ "$download_ok" -ne 1 ]; then
  echo "error: failed to download FunASR runtime from all mirrors" >&2
  exit 1
fi

mkdir -p "$TMP_EXTRACT"
tar -xzf "$TMP_TGZ" -C "$TMP_EXTRACT"

# 兼容不同解压目录结构，定位 llama-funasr-sensevoice
CLI_SRC="$(find "$TMP_EXTRACT" -type f -name 'llama-funasr-sensevoice' | head -n 1 || true)"
if [ -z "$CLI_SRC" ]; then
  echo "error: llama-funasr-sensevoice not found in archive" >&2
  find "$TMP_EXTRACT" -type f | head -50 >&2
  exit 1
fi

cp "$CLI_SRC" "$OUT_DIR/llama-funasr-sensevoice"
chmod +x "$OUT_DIR/llama-funasr-sensevoice"
rm -f "$TMP_TGZ"

# 一并拷贝同包内其他 funasr 工具（可选）
while IFS= read -r -d '' bin; do
  name="$(basename "$bin")"
  if [ "$name" = "llama-funasr-sensevoice" ]; then
    continue
  fi
  if [[ "$name" == llama-funasr-* ]]; then
    cp "$bin" "$OUT_DIR/$name"
    chmod +x "$OUT_DIR/$name"
  fi
done < <(find "$TMP_EXTRACT" -type f -name 'llama-funasr-*' -print0 2>/dev/null || true)

echo "installed -> $OUT_DIR/llama-funasr-sensevoice"
"$OUT_DIR/llama-funasr-sensevoice" 2>&1 | head -n 3 || true
echo "done. Models are downloaded from the SubForge settings UI (SenseVoice q8 + VAD)."
