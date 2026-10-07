#!/usr/bin/env python3
"""Render the original icon, then losslessly compress its PNG streams."""
import pathlib
import struct
import subprocess
import tempfile
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def chunk(kind, data):
    return (struct.pack('>I', len(data)) + kind + data
            + struct.pack('>I', zlib.crc32(kind + data)))


def compress_png(data):
    cursor, chunks, pixels = 8, [], b''
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    while cursor < len(data):
        size = struct.unpack_from('>I', data, cursor)[0]
        kind, payload = data[cursor + 4:cursor + 8], data[cursor + 8:cursor + 8 + size]
        if kind == b'IDAT':
            pixels += payload
        else:
            chunks.append((kind, payload))
        cursor += size + 12
    decoded = zlib.decompress(pixels)
    encoded = zlib.compress(decoded, 9)
    assert zlib.decompress(encoded) == decoded
    return (data[:8] + b''.join(chunk(k, v) for k, v in chunks if k != b'IEND')
            + chunk(b'IDAT', encoded) + chunk(b'IEND', b''))


def main():
    with tempfile.TemporaryDirectory(prefix='ultralight-icon-') as directory:
        raw = pathlib.Path(directory) / 'AppIcon.icns'
        subprocess.run(['xcrun', 'swift', str(ROOT / 'Scripts/icon.swift'), str(raw)], check=True)
        data = raw.read_bytes()
    cursor, body = 8, b''
    while cursor < len(data):
        kind, size = struct.unpack_from('>4sI', data, cursor)
        png = compress_png(data[cursor + 8:cursor + size])
        body += kind + struct.pack('>I', len(png) + 8) + png
        cursor += size
    output = ROOT / 'Resources/AppIcon.icns'
    output.parent.mkdir(exist_ok=True)
    output.write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
    print(f'{output.stat().st_size} bytes: {output}')


if __name__ == '__main__':
    main()
