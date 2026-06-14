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

# 复制 whisper-cli + 依赖库到 Frameworks
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
WHISPER_PREFIX="/opt/homebrew/opt/whisper-cpp"
GGML_PREFIX="/opt/homebrew/opt/ggml"

# 复制二进制和库
cp "$WHISPER_PREFIX/bin/whisper-cli" "$FRAMEWORKS_DIR/"
cp "$WHISPER_PREFIX/lib/libwhisper.1.8.6.dylib" "$FRAMEWORKS_DIR/"
cp "$GGML_PREFIX/lib/libggml.0.15.1.dylib" "$FRAMEWORKS_DIR/"
cp "$GGML_PREFIX/lib/libggml-base.0.15.1.dylib" "$FRAMEWORKS_DIR/"

# 创建符号链接
cd "$FRAMEWORKS_DIR"
ln -sf libwhisper.1.8.6.dylib libwhisper.1.dylib
ln -sf libwhisper.1.dylib libwhisper.dylib
ln -sf libggml.0.15.1.dylib libggml.0.dylib
ln -sf libggml.0.dylib libggml.dylib
ln -sf libggml-base.0.15.1.dylib libggml-base.0.dylib
ln -sf libggml-base.0.dylib libggml-base.dylib
cd "$PROJECT_DIR"

# 修复 rpath：让 whisper-cli 找到同目录的 dylib
install_name_tool -change "@rpath/libwhisper.1.dylib" "@executable_path/../Frameworks/libwhisper.1.dylib" "$FRAMEWORKS_DIR/whisper-cli"
install_name_tool -change "/opt/homebrew/opt/ggml/lib/libggml.0.dylib" "@executable_path/../Frameworks/libggml.0.dylib" "$FRAMEWORKS_DIR/whisper-cli"
install_name_tool -change "/opt/homebrew/opt/ggml/lib/libggml-base.0.dylib" "@executable_path/../Frameworks/libggml-base.0.dylib" "$FRAMEWORKS_DIR/whisper-cli"

# 修复 dylib 自身的依赖路径
install_name_tool -change "/opt/homebrew/opt/ggml/lib/libggml.0.dylib" "@executable_path/../Frameworks/libggml.0.dylib" "$FRAMEWORKS_DIR/libwhisper.1.8.6.dylib"
install_name_tool -change "/opt/homebrew/opt/ggml/lib/libggml-base.0.dylib" "@executable_path/../Frameworks/libggml-base.0.dylib" "$FRAMEWORKS_DIR/libwhisper.1.8.6.dylib"

# libggml 的 rpath 从 @loader_path/../lib 改为 @loader_path（同目录）
install_name_tool -rpath "@loader_path/../lib" "@loader_path" "$FRAMEWORKS_DIR/libggml.0.15.1.dylib"

# 清理旧 rpath，添加新的
install_name_tool -delete_rpath "/opt/homebrew/opt/ggml/lib" "$FRAMEWORKS_DIR/libggml.0.15.1.dylib" 2>/dev/null || true
install_name_tool -delete_rpath "/opt/homebrew/opt/whisper-cpp/lib" "$FRAMEWORKS_DIR/libwhisper.1.8.6.dylib" 2>/dev/null || true
install_name_tool -add_rpath "@loader_path" "$FRAMEWORKS_DIR/libwhisper.1.8.6.dylib" 2>/dev/null || true

# 签名所有 dylib 和二进制
codesign --force --sign - "$FRAMEWORKS_DIR/"*.dylib
codesign --force --sign - "$FRAMEWORKS_DIR/whisper-cli"

echo "🔏 签名..."
codesign --force --sign - \
    --entitlements "$PROJECT_DIR/SubForge.entitlements" \
    "$APP_BUNDLE"

echo "✅ 构建完成：$APP_BUNDLE"
echo "   运行: open '$APP_BUNDLE'"
