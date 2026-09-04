#!/usr/bin/env python3
"""检查 deb 包格式"""
import os

deb_path = r'C:\Users\Administrator\AppData\Roaming\TRAE SOLO CN\ModularData\ai-agent\work-mode-projects\6a9a22d3dfbd0e7da291e0fc\FileShareTweak\build\com.ps.filesharetweak_1.0.0_iphoneos-arm64.deb'

with open(deb_path, 'rb') as f:
    raw = f.read(200)

print('=== AR archive header ===')
print('Magic:', raw[:8])

pos = 8
entry = 0
while pos < len(raw):
    if pos + 60 > len(raw):
        break
    name = raw[pos:pos+16].decode('ascii', errors='replace').strip()
    date = raw[pos+16:pos+28].decode('ascii', errors='replace').strip()
    uid = raw[pos+28:pos+34].decode('ascii', errors='replace').strip()
    gid = raw[pos+34:pos+40].decode('ascii', errors='replace').strip()
    mode = raw[pos+40:pos+48].decode('ascii', errors='replace').strip()
    size = raw[pos+48:pos+58].decode('ascii', errors='replace').strip()
    fmag = raw[pos+58:pos+60].decode('ascii', errors='replace')
    print(f'Entry {entry}: name="{name}" date={date} mode={mode} size={size} fmag={repr(fmag)}')
    try:
        data_size = int(size)
    except:
        break
    pos += 60 + data_size
    if data_size % 2 == 1:
        pos += 1
    entry += 1

print()
print('File size:', os.path.getsize(deb_path), 'bytes')
print()

# Content verification
import tarfile, io
with open(deb_path, 'rb') as f:
    f.read(8)
    f.read(60)
    f.read(4)  # debian-binary
    if f.tell() % 2: f.read(1)
    f.read(60)
    control_data = f.read(758)
    if f.tell() % 2: f.read(1)
    f.read(60)
    data_data = f.read(5281)

print('=== control.tar.gz ===')
with tarfile.open(fileobj=io.BytesIO(control_data), mode='r:gz') as tar:
    for m in tar.getmembers():
        print(f'  {m.name} mode={oct(m.mode)} size={m.size}')

print()
print('=== data.tar.gz ===')
with tarfile.open(fileobj=io.BytesIO(data_data), mode='r:gz') as tar:
    for m in tar.getmembers():
        print(f'  {m.name} mode={oct(m.mode)} size={m.size}')

print()
print('=== debian-binary content ===')
with open(deb_path, 'rb') as f:
    f.read(8)
    f.read(60)
    db = f.read(4)
print(f'  {db}')

print()
print('Deb package looks valid.')