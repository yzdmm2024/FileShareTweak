#!/usr/bin/env bash
# setup_sdk.sh — 下载并解压 iOS 16.5 SDK，用于本地交叉编译
# 需要：Git Bash 环境，网络连接
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
SDK_DIR="$BUILD/sdk"
SDK_TAR="$BUILD/iPhoneOS16.5.sdk.tar.xz"
SDK_EXTRACTED="$SDK_DIR/iPhoneOS16.5.sdk"

echo "========================================="
echo "  iOS 16.5 SDK 下载/解压脚本"
echo "========================================="

# 检查 SDK 是否已存在
if [ -d "$SDK_EXTRACTED" ] && [ -f "$SDK_EXTRACTED/usr/lib/libobjc.tbd" ]; then
    echo "  SDK 已存在: $SDK_EXTRACTED"
    echo "  如需重新下载，请删除该目录后重试"
    exit 0
fi

mkdir -p "$SDK_DIR"

# 检查 tar 文件是否存在
if [ ! -f "$SDK_TAR" ]; then
    echo "==> 下载 iPhoneOS16.5.sdk.tar.xz"
    echo "  从 GitHub theos/sdks 下载..."
    
    # 尝试多种下载方式
    if command -v curl &>/dev/null; then
        curl -L -o "$SDK_TAR" "https://github.com/theos/sdks/releases/download/master/iPhoneOS16.5.sdk.tar.xz" || {
            echo "  curl 下载失败，尝试 gh CLI..."
        }
    fi
    
    if [ ! -f "$SDK_TAR" ] && command -v gh &>/dev/null; then
        gh release download master -R theos/sdks -p "iPhoneOS16.5.sdk.tar.xz" -D "$BUILD" || {
            echo "  gh 下载失败，请手动下载 SDK"
            echo "  下载地址: https://github.com/theos/sdks/releases"
            echo "  下载后放到: $SDK_TAR"
            exit 1
        }
    fi
    
    if [ ! -f "$SDK_TAR" ]; then
        echo "  ERROR: 无法下载 SDK，请手动下载"
        echo "  1. 访问 https://github.com/theos/sdks/releases/tag/master"
        echo "  2. 下载 iPhoneOS16.5.sdk.tar.xz"
        echo "  3. 放到 $SDK_TAR"
        echo "  4. 重新运行此脚本"
        exit 1
    fi
fi

# 解压 SDK
echo "==> 解压 SDK 到 $SDK_DIR"
if command -v python3 &>/dev/null; then
    python3 -c "
import tarfile, sys
print('  正在解压，请稍候...')
with tarfile.open(r'$SDK_TAR', 'r:xz') as tar:
    tar.extractall(path=r'$SDK_DIR')
print('  解压完成')
" || {
    echo "  python3 解压失败，尝试 tar 命令"
    tar -xf "$SDK_TAR" -C "$SDK_DIR"
}
else
    tar -xf "$SDK_TAR" -C "$SDK_DIR"
fi

# 验证
if [ -d "$SDK_EXTRACTED" ]; then
    echo "  SDK 解压成功: $SDK_EXTRACTED"
    ls -la "$SDK_EXTRACTED" | head -5
else
    echo "  ERROR: SDK 解压失败"
    exit 1
fi

echo ""
echo "========================================="
echo "  SDK 设置完成！"
echo "  路径: $SDK_EXTRACTED"
echo "========================================="