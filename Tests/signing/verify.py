#!/usr/bin/env python3
"""Verify the release seal and reject tampered copies without launching the app."""
import json
import pathlib
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile


def valid(app):
    return subprocess.run(['codesign', '--verify', '--strict', str(app)],
                          capture_output=True).returncode == 0


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def verify(app):
    app = pathlib.Path(app).resolve()
    require(valid(app), 'Release signature is invalid.')
    executable = pathlib.Path('Contents/MacOS/Ultralight')
    data = (app / executable).read_bytes()
    require(struct.unpack_from('<I', data)[0] == 0xfeedfacf, 'Expected thin 64-bit Mach-O.')
    cursor = 32
    text_offset = None
    signature = None
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, size = struct.unpack_from('<II', data, cursor)
        if command == 0x1d:  # LC_CODE_SIGNATURE
            offset, reserved = struct.unpack_from('<II', data, cursor + 8)
            magic, used = struct.unpack_from('>II', data, offset)
            require(magic == 0xfade0cc0 and used <= reserved, 'Invalid signature envelope.')
            require(reserved - used < 16, 'Ad-hoc signature has unused certificate reservation.')
            signature = {'used_bytes': used, 'reserved_bytes': reserved}
        elif command == 0x19:  # LC_SEGMENT_64
            for index in range(struct.unpack_from('<I', data, cursor + 64)[0]):
                section = cursor + 72 + index * 80
                if data[section:section + 16].split(b'\0')[0] == b'__text':
                    text_offset = struct.unpack_from('<I', data, section + 48)[0]
        cursor += size
    require(text_offset is not None and signature is not None, 'Missing code or signature.')
    rejected = {}
    with tempfile.TemporaryDirectory(prefix='ultralight-signature-gate-') as directory:
        for kind in ('code', 'plist'):
            copied = pathlib.Path(directory) / (kind + '.app')
            shutil.copytree(app, copied)
            if kind == 'code':
                modified = bytearray(data)
                modified[text_offset] ^= 1
                (copied / executable).write_bytes(modified)
            else:
                path = copied / 'Contents/Info.plist'
                info = plistlib.loads(path.read_bytes())
                info['CFBundleVersion'] = 'signature-gate-tamper'
                path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            rejected[kind] = not valid(copied)
    require(all(rejected.values()), 'Signature accepted modified content.')
    return {'passed': True, 'clean_verified': True, 'tampered_rejected': rejected,
            'signature': signature}


if __name__ == '__main__':
    print(json.dumps(verify(sys.argv[1]), sort_keys=True))
