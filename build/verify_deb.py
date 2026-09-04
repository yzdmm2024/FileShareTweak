#!/usr/bin/env python3
"""Verify the deb package created with llvm-ar"""
import os
import tarfile
import io

deb = r'C:\Users\Administrator\AppData\Roaming\TRAE SOLO CN\ModularData\ai-agent\work-mode-projects\6a9a22d3dfbd0e7da291e0fc\FileShareTweak\build\com.ps.filesharetweak_1.0.0_iphoneos-arm64.deb'

with open(deb, 'rb') as f:
    raw = f.read()

print('AR magic:', raw[:8])
print('Total size:', len(raw), 'bytes')

pos = 8
entry = 0
while pos < len(raw) - 60:
    name = raw[pos:pos+16].decode('ascii', errors='replace').strip()
    size = raw[pos+48:pos+58].decode('ascii', errors='replace').strip()
    fmag = raw[pos+58:pos+60].decode('ascii', errors='replace')
    print(f'Entry {entry}: name="{name}" size={size} fmag={repr(fmag)}')
    try:
        data_size = int(size)
    except:
        break
    pos += 60 + data_size
    if data_size % 2 == 1:
        pos += 1
    entry += 1
print(f'Total entries: {entry}')

# Verify the debian-binary content
with open(deb, 'rb') as f:
    f.read(8)  # ar magic
    f.read(60)  # header
    db = f.read(4).decode('ascii')
print(f'debian-binary: "{db}"')
print()

# Verify tar contents
with open(deb, 'rb') as f:
    f.read(8)
    f.read(60)  # debian-binary header
    f.read(4)   # debian-binary content
    if f.tell() % 2: f.read(1)
    f.read(60)  # control.tar.gz header
    ctrl_data = f.read(761)
    if f.tell() % 2: f.read(1)
    f.read(60)  # data.tar.gz header
    data_data = f.read(5274)

print('=== control.tar.gz ===')
with tarfile.open(fileobj=io.BytesIO(ctrl_data), mode='r:gz') as tar:
    for m in tar.getmembers():
        print(f'  {m.name} mode={oct(m.mode)}')

print('=== data.tar.gz ===')
with tarfile.open(fileobj=io.BytesIO(data_data), mode='r:gz') as tar:
    for m in tar.getmembers():
        print(f'  {m.name} mode={oct(m.mode)}')

print()
print('Deb package verification PASSED')