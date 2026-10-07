#!/usr/bin/env python3
"""Verify the release seal and reject tampered copies without launching the app."""
import argparse
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


def immutable_method_lists(data, offset, length):
    end = offset + length
    lists = 0
    while offset < end:
        require(offset + 8 <= end, 'Truncated Objective-C method list.')
        flags, count = struct.unpack_from('<II', data, offset)
        require(flags == 0x8000000c, 'Packed method lists must use immutable relative entries.')
        offset += 8 + count * 12
        require(offset <= end, 'Objective-C method list exceeds its section.')
        lists += 1
        aligned = min(end, (offset + 7) & ~7)
        require(not any(data[offset:aligned]), 'Unexpected method-list alignment padding.')
        offset = aligned
    require(lists > 0, 'Missing Objective-C method lists.')
    return lists


def signing_policy(app, mode):
    display = subprocess.run(['codesign', '-d', '--verbose=4', str(app)],
                             capture_output=True, text=True, check=True)
    details = display.stdout + display.stderr
    if mode == 'adhoc':
        require('Signature=adhoc' in details, 'Expected native ad-hoc signing.')
    else:
        require('Authority=Developer ID Application:' in details,
                'Public signing requires a Developer ID Application identity.')
        require('runtime)' in details and 'Timestamp=' in details,
                'Developer ID release requires hardened runtime and a secure timestamp.')
        requirement = ('anchor apple generic and '
                       'certificate 1[field.1.2.840.113635.100.6.2.6] exists and '
                       'certificate leaf[field.1.2.840.113635.100.6.1.13] exists')
        trusted = subprocess.run(['codesign', '--verify', '--strict', '-R', requirement, str(app)],
                                 capture_output=True)
        require(trusted.returncode == 0, 'Signature is not an Apple-trusted Developer ID Application chain.')
    return {'mode': mode, 'hardened_runtime': 'runtime)' in details,
            'secure_timestamp': 'Timestamp=' in details}


def verify(app, mode='adhoc'):
    app = pathlib.Path(app).resolve()
    require(valid(app), 'Release signature is invalid.')
    policy = signing_policy(app, mode)
    executable = pathlib.Path('Contents/MacOS/Ultralight')
    data = (app / executable).read_bytes()
    require(len(data) <= 200000 and sum(p.stat().st_size for p in app.rglob('*') if p.is_file()) <= 200000,
            'Signed executable/app exceeds 200,000 bytes; certificate and notarization overhead count toward the same budget.')
    require(struct.unpack_from('<I', data)[0] == 0xfeedfacf, 'Expected thin 64-bit Mach-O.')
    cursor = 32
    text_offset = None
    signature = None
    segments = {}
    sections = {}
    uuid = False
    function_starts = False
    method_lists = 0
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, size = struct.unpack_from('<II', data, cursor)
        if command == 0x1d:  # LC_CODE_SIGNATURE
            offset, reserved = struct.unpack_from('<II', data, cursor + 8)
            magic, used = struct.unpack_from('>II', data, offset)
            require(magic == 0xfade0cc0 and used <= reserved, 'Invalid signature envelope.')
            if mode == 'adhoc':
                require(reserved - used < 16, 'Ad-hoc signature has unused certificate reservation.')
            signature = {'used_bytes': used, 'reserved_bytes': reserved}
        elif command == 0x19:  # LC_SEGMENT_64
            segment = data[cursor + 8:cursor + 24].split(b'\0')[0].decode()
            maximum, initial, count, flags = struct.unpack_from('<IIII', data, cursor + 56)
            require(not (maximum & 2 and maximum & 4), 'Segment permits writable executable memory.')
            segments[segment] = {'maximum': maximum, 'initial': initial, 'flags': flags}
            for index in range(count):
                section = cursor + 72 + index * 80
                name = data[section:section + 16].split(b'\0')[0].decode()
                sections[(segment, name)] = struct.unpack_from('<Q', data, section + 40)[0]
                if name == '__objc_methlist':
                    require(segment == '__DATA_CONST', 'Method lists must remain in protected constant data.')
                    method_lists = immutable_method_lists(data,
                        struct.unpack_from('<I', data, section + 48)[0], sections[(segment, name)])
                if name.startswith('__swift') or name == '__constg_swiftt':
                    require(segment == '__TEXT', 'Runtime-discovered Swift metadata moved out of TEXT.')
                if name == '__text':
                    require(segment == '__TEXT', 'Executable code moved out of TEXT.')
                    text_offset = struct.unpack_from('<I', data, section + 48)[0]
        elif command == 0x1b:  # LC_UUID
            uuid = any(data[cursor + 8:cursor + 24])
        elif command == 0x26:  # LC_FUNCTION_STARTS
            function_starts = struct.unpack_from('<I', data, cursor + 12)[0] > 0
        cursor += size
    require(text_offset is not None and signature is not None, 'Missing code or signature.')
    require(segments.get('__TEXT', {}).get('initial') == 5, 'TEXT must remain read/execute.')
    constant = segments.get('__DATA_CONST', {})
    require(constant.get('initial') == 3 and constant.get('flags', 0) & 0x10,
            'Constant data must retain dyld read-only-after-fixup protection.')
    for name in ('__text_const', '__cstring', '__objc_classname', '__objc_selrefs'):
        require(sections.get(('__DATA_CONST', name), 0) > 0, 'Missing protected literals: ' + name)
    require(method_lists > 0, 'Missing immutable method lists.')
    require(uuid and function_starts, 'UUID and function starts are required for diagnostics.')
    for name in ('__unwind_info', '__eh_frame'):
        require(sections.get(('__TEXT', name), 0) > 0, 'Missing unwind information: ' + name)
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
    return {'passed': True, 'clean_verified': True, 'tampered_rejected': rejected, 'signing_policy': policy,
            'signature': signature,
            'layout': {'segments': segments, 'swift_metadata_in_text': True,
                       'immutable_method_lists': method_lists,
                       'protected_literals': True, 'unwind_and_diagnostics_retained': True}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app')
    parser.add_argument('--mode', choices=['adhoc', 'developer-id'], default='adhoc')
    args = parser.parse_args()
    print(json.dumps(verify(args.app, args.mode), sort_keys=True))
