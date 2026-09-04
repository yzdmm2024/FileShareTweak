#!/usr/bin/env python3
"""
build_dylib.py — 纯 Windows 原生编译 FileShareTweak.dylib
使用 Python 调用 logos2objc.py + clang 编译链接
无需 Git Bash / WSL / Theos
"""

import os
import sys
import shutil
import subprocess
import glob

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BUILD_DIR = os.path.join(PROJECT_ROOT, 'build')
SRC_DIR = os.path.join(BUILD_DIR, 'src')
SDK_DIR = os.path.join(BUILD_DIR, 'sdk', 'iPhoneOS16.5.sdk')
INC_DIR = os.path.join(BUILD_DIR, 'include')
LLVM_DIR = r'C:\Program Files\LLVM'
CLANG = os.path.join(LLVM_DIR, 'bin', 'clang.exe')
LOGOS_PY = os.path.join(os.environ.get('USERPROFILE', ''),
    r'.workbuddy\skills\win-ios-dylib-crossbuild\scripts\logos2objc.py')
SUBSTRATE_H = os.path.join(os.environ.get('USERPROFILE', ''),
    r'.workbuddy\skills\win-ios-dylib-crossbuild\build\include\substrate.h')

def run(cmd, desc=''):
    """运行命令并打印输出"""
    print(f'==> {desc}')
    cmd_str = ' '.join(cmd)
    print(f'  $ {cmd_str}')
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.stdout:
        print(f'  {result.stdout.strip()}')
    if result.returncode != 0:
        print(f'  ERROR: {result.stderr.strip()}')
        sys.exit(result.returncode)
    return result

def main():
    print('=' * 50)
    print('  FileShareTweak dylib 构建脚本 (Python)')
    print('=' * 50)

    # 检查工具链
    print('\n==> 检查工具链')
    if not os.path.exists(CLANG):
        print(f'  ERROR: clang 未找到 ({CLANG})')
        sys.exit(1)
    print(f'  clang: OK')

    if not os.path.exists(SDK_DIR):
        print(f'  ERROR: SDK 未找到 ({SDK_DIR})')
        sys.exit(1)
    print(f'  SDK: {SDK_DIR}')

    if not os.path.exists(LOGOS_PY):
        print(f'  ERROR: logos2objc.py 未找到 ({LOGOS_PY})')
        sys.exit(1)
    print(f'  logos2objc.py: OK')

    # 准备源码目录
    print('\n==> 准备源码目录')
    os.makedirs(SRC_DIR, exist_ok=True)
    os.makedirs(INC_DIR, exist_ok=True)

    # 复制 Tweak.xm
    shutil.copy2(os.path.join(PROJECT_ROOT, 'Tweak.xm'), os.path.join(SRC_DIR, 'Tweak.xm'))
    print(f'  Tweak.xm -> {SRC_DIR}/Tweak.xm')

    # 复制 substrate.h
    shutil.copy2(SUBSTRATE_H, os.path.join(INC_DIR, 'substrate.h'))
    print(f'  substrate.h -> {INC_DIR}/substrate.h')

    # Logos 预处理
    print('\n==> Logos 预处理 Tweak.xm -> Tweak.m')
    tweak_xm = os.path.join(SRC_DIR, 'Tweak.xm')
    tweak_m = os.path.join(SRC_DIR, 'Tweak.m')
    run(['python3', LOGOS_PY, tweak_xm, tweak_m], 'logos2objc.py')
    if not os.path.exists(tweak_m):
        print('  ERROR: Tweak.m 生成失败')
        sys.exit(1)
    print('  Tweak.m 生成成功')

    # 编译
    print('\n==> 编译 Tweak.m -> Tweak.o')
    tweak_o = os.path.join(BUILD_DIR, 'Tweak.o')
    cflags = [
        '-target', 'arm64e-apple-ios16.5',
        '-isysroot', SDK_DIR,
        '-fobjc-arc',
        '-fobjc-exceptions',
        '-O2',
        '-fvisibility=hidden',
        '-fno-modules',
        '-Wno-implicit-function-declaration',
        '-Wno-objc-method-access',
        '-Wno-format',
        '-Wno-deprecated-declarations',
        '-Wno-arc-performSelector-leaks',
        '-D__IPHONE_OS_VERSION_MIN_REQUIRED=160500',
        f'-I{SRC_DIR}',
        f'-I{INC_DIR}',
        '-c', tweak_m,
        '-o', tweak_o,
    ]
    run([CLANG] + cflags, 'clang 编译')

    # 链接为动态库
    print('\n==> 链接 FileShareTweak.dylib')
    dylib_out = os.path.join(BUILD_DIR, 'FileShareTweak.dylib')
    link_flags = [
        '-dynamiclib',
        '-target', 'arm64e-apple-ios16.5',
        '-isysroot', SDK_DIR,
        '-fuse-ld=lld',
        '-Wl,-platform_version,ios,16.5,16.5',
        '-Wl,-install_name,@rpath/FileShareTweak.dylib',
        '-Wl,-undefined,dynamic_lookup',
        '-O2',
        '-o', dylib_out,
        tweak_o,
    ]
    run([CLANG] + link_flags, 'clang 链接')
    # 修正 ld.lld 把 arm64e cpusubtype 清零为 ARM64_ALL 的 bug
    # 否则 rootless(arm64e) 设备 dyld 不会按 PAC 处理，注入失败
    import struct as _st
    _bb = bytearray(open(dylib_out, "rb").read())
    if _st.unpack("<I", _bb[:4])[0] == 0xFEEDFACF:  # 瘦 Mach-O (arm64 LE)
        _st.pack_into("<I", _bb, 8, 0x00000002)  # CPU_SUBTYPE_ARM64E
        open(dylib_out, "wb").write(_bb)
        print("   cpusubtype 已修正为 ARM64E (0x2)")


    # 尝试签名
    print('\n==> 签名')
    ldid_path = os.path.join(os.path.dirname(LOGOS_PY), '..', 'ldid.exe')
    if os.path.exists(ldid_path):
        run([ldid_path, '-S', dylib_out], 'ldid')
        print('  签名完成')
    else:
        ldid_alt = os.path.join(os.path.dirname(LOGOS_PY), 'ldid.exe')
        if os.path.exists(ldid_alt):
            run([ldid_alt, '-S', dylib_out], 'ldid')
            print('  签名完成')
        else:
            print('  WARNING: ldid 未找到，跳过签名')
            print(f'  查找路径: {ldid_path}')

    # 复制到 layout 目录
    print('\n==> 复制到 layout 目录')
    layout_dylib = os.path.join(PROJECT_ROOT, 'layout', 'Library',
                                 'MobileSubstrate', 'DynamicLibraries', 'FileShareTweak.dylib')
    os.makedirs(os.path.dirname(layout_dylib), exist_ok=True)
    shutil.copy2(dylib_out, layout_dylib)
    layout_plist = os.path.join(PROJECT_ROOT, 'layout', 'Library',
                                 'MobileSubstrate', 'DynamicLibraries', 'FileShareTweak.plist')
    shutil.copy2(os.path.join(PROJECT_ROOT, 'Tweak.plist'), layout_plist)
    print(f'  dylib: {layout_dylib}')
    print(f'  plist: {layout_plist}')

    # 校验
    print('\n==> 产物信息')
    size = os.path.getsize(dylib_out)
    print(f'  FileShareTweak.dylib: {size} bytes')

    print('\n' + '=' * 50)
    print('  ✅ 构建成功！')
    print(f'  产物: {dylib_out}')
    print('=' * 50)


if __name__ == '__main__':
    main()