#!/usr/bin/env bash
# build_deb.sh — 将编译好的 dylib 打包为 .deb
# 要求：build_dylib.sh 已成功执行
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DEB_DIR="$BUILD/DEBIAN"
DIST_DIR="$BUILD/dist"

echo "========================================="
echo "  FileShareTweak .deb 打包脚本"
echo "========================================="

# 检查 dylib 是否存在
DYLIB="$BUILD/FileShareTweak.dylib"
if [ ! -f "$DYLIB" ]; then
    echo "ERROR: 请先运行 build_dylib.sh 编译 dylib"
    exit 1
fi

# 准备 deb 目录结构
echo "==> 准备 deb 打包目录"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/DEBIAN"
mkdir -p "$DIST_DIR/var/jb/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$DIST_DIR/var/jb/Library/PreferenceBundles/FileShareTweakSettings.bundle"

# 复制控制文件
echo "==> 复制 control"
cp "$ROOT/control" "$DIST_DIR/DEBIAN/control"

# 复制 dylib 和 plist
echo "==> 复制 dylib 和 plist"
cp "$DYLIB" "$DIST_DIR/var/jb/Library/MobileSubstrate/DynamicLibraries/FileShareTweak.dylib"
cp "$ROOT/Tweak.plist" "$DIST_DIR/var/jb/Library/MobileSubstrate/DynamicLibraries/FileShareTweak.plist"

# 复制偏好设置 Bundle
echo "==> 复制偏好设置 Bundle"
cp "$ROOT/layout/var/jb/Library/PreferenceBundles/FileShareTweakSettings.bundle/Info.plist" \
   "$DIST_DIR/var/jb/Library/PreferenceBundles/FileShareTweakSettings.bundle/"
cp "$ROOT/layout/var/jb/Library/PreferenceBundles/FileShareTweakSettings.bundle/Root.plist" \
   "$DIST_DIR/var/jb/Library/PreferenceBundles/FileShareTweakSettings.bundle/"

# 创建 postinst 脚本（安装后刷新）
echo "==> 创建 postinst"
cat > "$DIST_DIR/DEBIAN/postinst" << 'POSTINST'
#!/bin/bash
# 安装后：注销 SpringBoard 让设置面板生效
if [ -f /var/jb/usr/bin/uicache ]; then
    /var/jb/usr/bin/uicache -a
fi
# 重启 backboardd 或 SpringBoard 使 tweak 生效
if [ -f /var/jb/usr/bin/sbreload ]; then
    /var/jb/usr/bin/sbreload
elif command -v killall &>/dev/null; then
    killall -9 SpringBoard 2>/dev/null || true
fi
POSTINST
chmod 755 "$DIST_DIR/DEBIAN/postinst"

# 创建 prerm 脚本（卸载前清理）
echo "==> 创建 prerm"
cat > "$DIST_DIR/DEBIAN/prerm" << 'PRERM'
#!/bin/bash
# 卸载前清理
rm -f /var/jb/var/mobile/Library/Preferences/com.ps.filesharetweak.plist
PRERM
chmod 755 "$DIST_DIR/DEBIAN/prerm"

# 打包 .deb
echo "==> 打包 .deb"
DEB_NAME="com.ps.filesharetweak_1.0.0_iphoneos-arm64.deb"
# 使用 ar 打包（Git Bash 下可用）
cd "$DIST_DIR"
if command -v dpkg-deb &>/dev/null; then
    dpkg-deb -b . "$BUILD/$DEB_NAME"
else
    # 手动 ar 打包
    # 先创建 debian-binary
    echo "2.0" > "$DIST_DIR/debian-binary"
    # 创建控制文件 tar.gz
    tar czf "$DIST_DIR/control.tar.gz" -C "$DIST_DIR" DEBIAN/control DEBIAN/postinst DEBIAN/prerm 2>/dev/null || \
    tar czf "$DIST_DIR/control.tar.gz" -C "$DIST_DIR" DEBIAN/control DEBIAN/postinst 2>/dev/null || \
    tar czf "$DIST_DIR/control.tar.gz" -C "$DIST_DIR" DEBIAN/control
    # 创建数据文件 tar.gz
    tar czf "$DIST_DIR/data.tar.gz" -C "$DIST_DIR" var/ 2>/dev/null || true
    # 打包 ar
    if command -v ar &>/dev/null; then
        ar rcs "$BUILD/$DEB_NAME" "$DIST_DIR/debian-binary" "$DIST_DIR/control.tar.gz" "$DIST_DIR/data.tar.gz"
    else
        echo "ERROR: 没有 dpkg-deb 或 ar，无法打包 deb"
        echo "请手动打包：将 $DIST_DIR/var/ 下的文件复制到设备"
        exit 1
    fi
fi

echo ""
echo "========================================="
echo "  ✅ 打包成功！"
echo "  .deb: $BUILD/$DEB_NAME"
echo "========================================="
ls -la "$BUILD/$DEB_NAME"