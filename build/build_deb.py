#!/usr/bin/env python3
"""
build_deb.py — 将编译好的 dylib 打包为 .deb
要求：build_dylib.py 已成功执行生成 dylib
"""

import os
import sys
import tarfile
import shutil
import subprocess

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BUILD_DIR = os.path.join(PROJECT_ROOT, 'build')
DIST_DIR = os.path.join(BUILD_DIR, 'dist')
LAYOUT_DIR = os.path.join(PROJECT_ROOT, 'layout')

DEB_NAME = 'com.ps.filesharetweak_1.0.0_iphoneos-arm64.deb'
DEB_PATH = os.path.join(BUILD_DIR, DEB_NAME)

CONTROL_DATA = '''Package: com.ps.filesharetweak
Name: FileShareTweak
Version: 1.0.0
Architecture: iphoneos-arm64
Priority: optional
Section: Tweaks
Author: PS <ps@localhost>
Maintainer: PS <ps@localhost>
Tag: purpose::extension
Description: 一键分享文件到目标App
 点击dylib自动打开TrollFools，点击ipa/tipa自动打开TrollStore，点击deb自动打开Sileo
'''

POSTINST_DATA = '''#!/bin/sh
# 安装后刷新
uicache_bin="/var/jb/usr/bin/uicache"
if [ -f "$uicache_bin" ]; then
    "$uicache_bin" -a >/dev/null 2>&1 || true
fi
if [ -f "/var/jb/usr/bin/sbreload" ]; then
    /var/jb/usr/bin/sbreload >/dev/null 2>&1 || true
elif command -v killall >/dev/null 2>&1; then
    killall -9 SpringBoard >/dev/null 2>&1 || true
fi
exit 0
'''

PRERM_DATA = '''#!/bin/sh
# 卸载前清理
rm -f /var/jb/var/mobile/Library/Preferences/com.ps.filesharetweak.plist >/dev/null 2>&1 || true
exit 0
'''


def create_ar_archive(output_path, file_paths):
    """
    使用 llvm-ar 创建 ar 归档（.deb 格式）
    """
    llvm_ar = r'C:\Program Files\LLVM\bin\llvm-ar.exe'
    if not os.path.exists(llvm_ar):
        print('  ERROR: llvm-ar 未找到')
        sys.exit(1)
    
    # 构建 ar 命令
    # 格式: llvm-ar rcS <output> <file1> <file2> <file3>
    cmd = [llvm_ar, 'rcS', output_path] + file_paths
    print(f'  $ {" ".join(cmd)}')
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f'  ERROR: {result.stderr}')
        sys.exit(result.returncode)


def main():
    print('=' * 50)
    print('  FileShareTweak .deb 打包脚本')
    print('=' * 50)

    # 检查 dylib
    dylib_path = os.path.join(BUILD_DIR, 'FileShareTweak.dylib')
    if not os.path.exists(dylib_path):
        print('  ERROR: 请先运行 build_dylib.py 编译 dylib')
        print(f'  未找到: {dylib_path}')
        sys.exit(1)

    print(f'\n==> 准备打包目录: {DIST_DIR}')
    if os.path.exists(DIST_DIR):
        shutil.rmtree(DIST_DIR)
    
    # 创建目录结构
    debian_dir = os.path.join(DIST_DIR, 'DEBIAN')
    os.makedirs(debian_dir, exist_ok=True)
    
    # 写 control 文件
    control_path = os.path.join(debian_dir, 'control')
    with open(control_path, 'w', encoding='utf-8') as f:
        f.write(CONTROL_DATA)
    print(f'  control: {control_path}')
    
    # 写 postinst
    postinst_path = os.path.join(debian_dir, 'postinst')
    with open(postinst_path, 'w', encoding='utf-8') as f:
        f.write(POSTINST_DATA)
    os.chmod(postinst_path, 0o755)
    print(f'  postinst: {postinst_path}')
    
    # 写 prerm
    prerm_path = os.path.join(debian_dir, 'prerm')
    with open(prerm_path, 'w', encoding='utf-8') as f:
        f.write(PRERM_DATA)
    os.chmod(prerm_path, 0o755)
    print(f'  prerm: {prerm_path}')
    
    # 复制文件到 dist 目录
    # 文件结构: var/jb/Library/... 
    target_dylib = os.path.join(DIST_DIR, 'var', 'jb', 'Library',
                                'MobileSubstrate', 'DynamicLibraries', 'FileShareTweak.dylib')
    os.makedirs(os.path.dirname(target_dylib), exist_ok=True)
    shutil.copy2(dylib_path, target_dylib)
    print(f'  dylib: {target_dylib}')
    
    # plist
    target_plist = os.path.join(DIST_DIR, 'var', 'jb', 'Library',
                                'MobileSubstrate', 'DynamicLibraries', 'FileShareTweak.plist')
    shutil.copy2(os.path.join(PROJECT_ROOT, 'Tweak.plist'), target_plist)
    print(f'  plist: {target_plist}')
    
    # 偏好设置 Bundle
    bundle_src = os.path.join(LAYOUT_DIR, 'var', 'jb', 'Library',
                               'PreferenceBundles', 'FileShareTweakSettings.bundle')
    bundle_dst = os.path.join(DIST_DIR, 'var', 'jb', 'Library',
                               'PreferenceBundles', 'FileShareTweakSettings.bundle')
    if os.path.exists(bundle_src):
        shutil.copytree(bundle_src, bundle_dst)
        print(f'  bundle: {bundle_dst}')
    
    # 创建 debian-binary
    debian_binary_path = os.path.join(DIST_DIR, 'debian-binary')
    with open(debian_binary_path, 'wb') as f:
        f.write(b'2.0\n')
    
    # 创建 control.tar.gz（显式设置权限）
    print('\n==> 创建 control.tar.gz')
    control_tar_path = os.path.join(DIST_DIR, 'control.tar.gz')
    with tarfile.open(control_tar_path, 'w:gz') as tar:
        # 逐文件添加并设置权限
        for root, dirs, files in os.walk(debian_dir):
            for f in files:
                fpath = os.path.join(root, f)
                arcname = os.path.relpath(fpath, DIST_DIR).replace('\\', '/')
                tinfo = tar.gettarinfo(fpath, arcname)
                if f in ('postinst', 'prerm', 'extrainst_'):
                    tinfo.mode = 0o755  # 脚本可执行
                else:
                    tinfo.mode = 0o644  # 普通文件
                with open(fpath, 'rb') as fh:
                    tar.addfile(tinfo, fh)
            for d in dirs:
                dpath = os.path.join(root, d)
                arcname = os.path.relpath(dpath, DIST_DIR).replace('\\', '/')
                tinfo = tar.gettarinfo(dpath, arcname)
                tinfo.mode = 0o755
                tar.addfile(tinfo)
    print(f'  control.tar.gz: {os.path.getsize(control_tar_path)} bytes')
    
    # 创建 data.tar.gz（显式设置权限）
    print('==> 创建 data.tar.gz')
    data_tar_path = os.path.join(DIST_DIR, 'data.tar.gz')
    with tarfile.open(data_tar_path, 'w:gz') as tar:
        var_dir = os.path.join(DIST_DIR, 'var')
        if os.path.exists(var_dir):
            for root, dirs, files in os.walk(var_dir):
                for f in files:
                    fpath = os.path.join(root, f)
                    arcname = os.path.relpath(fpath, DIST_DIR).replace('\\', '/')
                    tinfo = tar.gettarinfo(fpath, arcname)
                    if f.endswith('.dylib'):
                        tinfo.mode = 0o755  # dylib 可执行
                    else:
                        tinfo.mode = 0o644  # plist 普通文件
                    with open(fpath, 'rb') as fh:
                        tar.addfile(tinfo, fh)
                for d in dirs:
                    dpath = os.path.join(root, d)
                    arcname = os.path.relpath(dpath, DIST_DIR).replace('\\', '/')
                    tinfo = tar.gettarinfo(dpath, arcname)
                    tinfo.mode = 0o755
                    tar.addfile(tinfo)
    print(f'  data.tar.gz: {os.path.getsize(data_tar_path)} bytes')
    
    # 打包为 .deb (ar 格式，使用 llvm-ar)
    print(f'\n==> 打包 .deb: {DEB_PATH}')
    create_ar_archive(DEB_PATH, [
        debian_binary_path,
        control_tar_path,
        data_tar_path,
    ])
    
    # 校验
    deb_size = os.path.getsize(DEB_PATH)
    print(f'\n  .deb 大小: {deb_size} bytes')
    
    print('\n' + '=' * 50)
    print('  ✅ 打包成功！')
    print(f'  .deb: {DEB_PATH}')
    print('=' * 50)
    print()
    print('  安装到手机:')
    print(f'  scp {DEB_PATH} root@<设备IP>:/var/mobile/')
    print('  ssh root@<设备IP> "dpkg -i /var/mobile/com.ps.filesharetweak_1.0.0_iphoneos-arm64.deb"')
    print()


if __name__ == '__main__':
    main()