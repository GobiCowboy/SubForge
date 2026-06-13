#!/bin/bash
# SubForge 构建 + 打包脚本
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SubForge"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "🔨 编译中..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

echo "📦 打包 .app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/"
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 复制测试音频到 Resources
if [ -f "$PROJECT_DIR/test_audio.m4a" ]; then
    cp "$PROJECT_DIR/test_audio.m4a" "$APP_BUNDLE/Contents/Resources/"
fi

echo "🔏 签名..."
codesign --force --sign - \
    --entitlements "$PROJECT_DIR/SubForge.entitlements" \
    "$APP_BUNDLE"

echo "✅ 构建完成：$APP_BUNDLE"
echo "   运行: open '$APP_BUNDLE'"
