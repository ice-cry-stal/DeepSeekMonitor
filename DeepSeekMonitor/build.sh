#!/bin/bash
# ==========================================================
# DeepSeek Monitor 一键编译脚本
# 无需 Xcode，只需安装 Command Line Tools
# 使用方法: 打开「终端」，粘贴下面这行回车：
#   bash build.sh
# ==========================================================

set -e

APP_NAME="DeepSeekMonitor"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
INFO_PLIST="$PROJECT_DIR/Info.plist"

echo "========================================="
echo "  DeepSeek Monitor 一键编译"
echo "========================================="
echo ""

# 1) 检查 swift 是否可用
if ! command -v swift &> /dev/null; then
    echo "❌ 未找到 swift 编译器。"
    echo ""
    echo "请先安装 Command Line Tools:"
    echo "  打开「终端」，运行:"
    echo ""
    echo "    xcode-select --install"
    echo ""
    echo "等待安装完成后，重新运行:"
    echo "    bash build.sh"
    echo ""
    exit 1
fi

echo "✅ 发现 Swift 编译器: $(swift --version | head -1)"
echo ""

# 2) 清理旧缓存和调试文件
echo "🧹 清理旧编译缓存..."
rm -rf "$BUILD_DIR"
echo ""

# 3) 编译 Release 版本
echo "📦 正在编译..."
cd "$PROJECT_DIR"
swift build -c release --disable-sandbox 2>&1

# 适配不同 Swift 版本的构建路径
EXECUTABLE=""
for candidate in \
    "$BUILD_DIR/release/$APP_NAME" \
    "$BUILD_DIR/arm64-apple-macosx/release/$APP_NAME" \
    "$BUILD_DIR/x86_64-apple-macosx/release/$APP_NAME"; do
    if [ -f "$candidate" ]; then
        EXECUTABLE="$candidate"
        break
    fi
done

if [ -z "$EXECUTABLE" ]; then
    echo "❌ 编译失败，未找到可执行文件"
    echo "   尝试搜索 .build 目录:"
    find "$BUILD_DIR" -name "$APP_NAME" -type f 2>/dev/null || true
    exit 1
fi

echo "✅ 编译成功!"
echo ""

# 3) 创建 .app  bundle
echo "📁 正在打包应用..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制可执行文件
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 复制 Info.plist
if [ -f "$INFO_PLIST" ]; then
    cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
    echo "✅ Info.plist 已复制"
fi

# 4) 签名（ad-hoc，不需开发者账号）
echo "🔏 正在签名..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null

echo "✅ 打包完成!"
echo ""

# 5) 打开应用
echo "🚀 正在启动 DeepSeek Monitor..."
open "$APP_BUNDLE"

echo ""
echo "========================================="
echo "  ✅ 完成！应用已启动，查看菜单栏顶部"
echo "     应用位置: $APP_BUNDLE"
echo "========================================="
echo ""
echo "💡 以后再次启动，双击 DeepSeekMonitor.app 即可"
echo "💡 如果想开机自启，拖到「系统设置 → 通用 → 登录项」"
echo ""
