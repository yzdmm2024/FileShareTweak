#!/usr/bin/env bash
# build_dylib.sh — 纯 Windows 原生交叉编译 FileShareTweak.dylib
# 工具链：LLVM/clang + lld + iOS 16.5 SDK（来自 win-ios-dylib-crossbuild skill）
# 不依赖 WSL / Theos / macOS
set -e

# ========== 路径配置 ==========
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
SRC="$BUILD/src"
SDK="$BUILD/sdk/iPhoneOS16.5.sdk"
INC="$BUILD/include"
LLVM="/c/Program Files/LLVM"
CLANG="$LLVM/bin/clang"
TOOLCHAIN="$HOME/.workbuddy/skills/win-ios-dylib-crossbuild"

# winpath：POSIX -> Windows 原生路径（Git Bash）
winpath() { cygpath -w "$1" 2>/dev/null || echo "$1"; }

echo "========================================="
echo "  FileShareTweak dylib 构建脚本"
echo "========================================="

# ========== 检查工具链 ==========
echo "==> 检查工具链"
[ -x "$CLANG" ] || { echo "ERROR: clang 未找到 ($CLANG)"; exit 1; }
[ -d "$SDK" ] || { echo "ERROR: SDK 未找到 ($SDK)，请解压 iPhoneOS16.5.sdk.tar.xz 到此目录"; exit 1; }
[ -f "$TOOLCHAIN/scripts/logos2objc.py" ] || { echo "ERROR: logos2objc.py 未找到"; exit 1; }

# ========== 准备源码目录 ==========
echo "==> 同步源码到 build/src"
mkdir -p "$SRC"
cp "$ROOT/Tweak.xm" "$SRC/Tweak.xm"

# 复制工具链文件
cp "$TOOLCHAIN/scripts/logos2objc.py" "$BUILD/logos2objc.py"
cp "$TOOLCHAIN/build/include/substrate.h" "$INC/substrate.h"

# ========== Logos 预处理 ==========
echo "==> Logos 预处理 Tweak.xm -> Tweak.m"
python3 "$(winpath "$BUILD/logos2objc.py")" "$(winpath "$SRC/Tweak.xm")" "$(winpath "$SRC/Tweak.m")"

# 检查预处理结果
if [ ! -f "$SRC/Tweak.m" ]; then
    echo "ERROR: Logos 预处理失败"
    exit 1
fi
echo "  Tweak.m 生成成功"

# ========== 编译 ==========
SDK_W="$(winpath "$SDK")"
SRC_W="$(winpath "$SRC")"
INC_W="$(winpath "$INC")"
OUT_DYLIB_W="$(winpath "$BUILD/FileShareTweak.dylib")"

CFLAGS=(
    -target arm64-apple-ios16.5
    -isysroot "$SDK_W"
    -fobjc-arc
    -fobjc-exceptions
    -O2
    -fvisibility=hidden
    -fno-modules
    -Wno-implicit-function-declaration
    -Wno-objc-method-access
    -Wno-format
    -Wno-deprecated-declarations
    -Wno-arc-performSelector-leaks
    -D__IPHONE_OS_VERSION_MIN_REQUIRED=160500
    -I"$SRC_W" -I"$INC_W"
)

echo "==> 编译 Tweak.m -> Tweak.o"
"$CLANG" -c "${CFLAGS[@]}" -o "$(winpath "$BUILD/Tweak.o")" "$(winpath "$SRC/Tweak.m")"

# ========== 链接为动态库 ==========
echo "==> 链接 FileShareTweak.dylib"
"$CLANG" -dynamiclib \
    -target arm64-apple-ios16.5 \
    -isysroot "$SDK_W" \
    -fuse-ld=lld \
    -Wl,-platform_version,ios,16.5,16.5 \
    -Wl,-install_name,@rpath/FileShareTweak.dylib \
    -Wl,-undefined,dynamic_lookup \
    -O2 \
    -o "$OUT_DYLIB_W" \
    "$(winpath "$BUILD/Tweak.o")"

# ========== 签名 ==========
echo "==> 用 ldid 签名"
LDID="$TOOLCHAIN/ldid.exe"
if [ -f "$LDID" ]; then
    "$LDID" -S "$OUT_DYLIB_W"
    echo "  签名完成"
else
    echo "  WARNING: ldid 未找到，跳过签名"
fi

# ========== 校验产物 ==========
echo "==> 产物信息"
ls -la "$BUILD/FileShareTweak.dylib"

# 复制到 layout 目录
echo "==> 复制到 layout 目录"
cp "$BUILD/FileShareTweak.dylib" "$ROOT/layout/var/jb/Library/MobileSubstrate/DynamicLibraries/"
cp "$ROOT/Tweak.plist" "$ROOT/layout/var/jb/Library/MobileSubstrate/DynamicLibraries/FileShareTweak.plist"

echo ""
echo "========================================="
echo "  ✅ 构建成功！"
echo "  产物: $BUILD/FileShareTweak.dylib"
echo "========================================="