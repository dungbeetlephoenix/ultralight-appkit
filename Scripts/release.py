#!/usr/bin/env python3
"""Build, strip, sign, and measure the native app. No installation or network access."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
from build_config import FLAGS, ROOT, TARGET, source_hashes



def run(*command):
    return subprocess.run(command, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'artifacts/release')
    parser.add_argument('--dmg', choices=['UDZO', 'UDBZ', 'ULFO'])
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    run(sys.executable, str(ROOT / 'Scripts/check.py'))
    verified = json.loads((ROOT / 'artifacts/gates/results.json').read_text())
    checked_sources = verified['source_sha256']
    if not verified['passed'] or source_hashes() != checked_sources:
        raise SystemExit('Source changed after quality gates; rerun the release build.')
    app = output / 'Ultralight.app'
    contents = app / 'Contents'
    (contents / 'MacOS').mkdir(parents=True, exist_ok=True)
    binary = contents / 'MacOS/Ultralight'
    # A single compiler invocation lets LLVM optimize the entire dependency-free
    # executable together. SwiftPM's multiple object outputs produce a larger app.
    run('xcrun', 'swiftc', '-module-name', 'Ultralight', '-target', TARGET, *FLAGS,
        *[str(p) for p in sorted((ROOT / 'Sources').rglob('*.swift'))], '-o', str(binary))
    if source_hashes() != checked_sources:
        raise SystemExit('Source changed after quality gates; rerun the release build.')
    # Binary plists are native to macOS and avoid shipping XML whitespace.
    info = dict(CFBundleName='Ultralight', CFBundleIdentifier='com.ultralight.player',
                CFBundleExecutable='Ultralight', CFBundlePackageType='APPL',
                CFBundleVersion='2.1', CFBundleShortVersionString='2.1',
                LSMinimumSystemVersion='14.0', NSHighResolutionCapable=True,
                LSUIElement=False, NSSupportsAutomaticTermination=False)
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
    run('strip', '-rSTx', '-N', str(binary))
    run('codesign', '--force', '--sign', '-', '--timestamp=none', str(app))
    run('codesign', '--verify', '--strict', str(app))
    files = sorted(p for p in app.rglob('*') if p.is_file())
    report = {
        'binary_bytes': binary.stat().st_size,
        'app_bytes': sum(p.stat().st_size for p in files),
        'architecture': run('lipo', '-archs', str(binary)),
        'toolchain': run('swift', '--version'),
        'git_head': run('git', 'rev-parse', 'HEAD'),
        'source_sha256': checked_sources,
        'flags': FLAGS,
        'files': {str(p.relative_to(app)): {'bytes': p.stat().st_size,
                   'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files},
        'signature': 'ad-hoc; not Developer ID signed or notarized',
    }
    if report['binary_bytes'] > 272000 or report['app_bytes'] > 275000:
        raise SystemExit('Release exceeds the 272,000-byte binary / 275,000-byte app budgets.')
    if args.dmg:
        dmg = output / 'Ultralight.dmg'
        command = ['hdiutil', 'create', '-ov', '-volname', 'Ultralight', '-srcfolder',
                   str(app), '-format', args.dmg]
        if args.dmg == 'UDZO':
            command += ['-imagekey', 'zlib-level=9']
        run(*command, str(dmg))
        run('hdiutil', 'verify', str(dmg))
        report['dmg_bytes'] = dmg.stat().st_size
        report['dmg_format'] = args.dmg
        report['dmg_sha256'] = hashlib.sha256(dmg.read_bytes()).hexdigest()
        if report['dmg_bytes'] > 120000:
            raise SystemExit('Release exceeds the 120,000-byte download budget.')
    (output / 'size.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k not in ('source_sha256', 'files')}, indent=2))
    print(app)


if __name__ == '__main__':
    main()
