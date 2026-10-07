#!/usr/bin/env python3
"""Build once; run the identical signed native smoke harness on another macOS."""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Scripts'))
from build_config import FLAGS, TARGET, source_hashes


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(output):
    checked_sources = source_hashes()
    output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='ultralight-compat-build-') as directory:
        config = ROOT / 'Sources/Ultralight/Storage/ConfigStore.swift'
        original = config.read_text()
        needle = 'FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!'
        if original.count(needle) != 1:
            raise SystemExit('ConfigStore changed; review compatibility data isolation.')
        isolated = pathlib.Path(directory) / 'ConfigStore.swift'
        isolated.write_text(original.replace(needle, 'URL(fileURLWithPath: ProcessInfo.processInfo.environment["ULTRALIGHT_COMPAT_DATA"]!)'))
        sources = [p for p in sorted((ROOT / 'Sources').rglob('*.swift')) if p != config and p.name != 'main.swift']
        command = ['xcrun', 'swiftc', '-module-name', 'Ultralight', '-parse-as-library', '-target', TARGET, *FLAGS,
                   *map(str, sources), str(isolated), str(ROOT / 'Tests/compatibility/Smoke.swift'), '-o', str(output / 'smoke')]
        subprocess.run(command, check=True)
    subprocess.run(['strip', '-rSTx', '-N', str(output / 'smoke')], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', '--signature-size', '8', str(output / 'smoke')], check=True)
    shutil.copy2(ROOT / 'Resources/AppIcon.icns', output / 'AppIcon.icns')
    if source_hashes() != checked_sources:
        raise SystemExit('Source changed while building the compatibility fixture.')
    manifest = {'source_sha256': checked_sources, 'flags': FLAGS,
                'compiler': subprocess.check_output(['xcrun', 'swift', '--version'], text=True).strip(),
                'built_on': platform.mac_ver()[0], 'architecture': platform.machine(),
                'files': {p.name: digest(p) for p in output.iterdir() if p.is_file()}}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


def run(bundle, output, expected_os):
    version = platform.mac_ver()[0]
    if expected_os and version.split('.')[0] != expected_os:
        raise SystemExit(f'Expected macOS {expected_os}; found {version}.')
    manifest = json.loads((bundle / 'manifest.json').read_text())
    for name, expected in manifest['files'].items():
        if digest(bundle / name) != expected:
            raise SystemExit('Compatibility bundle content changed: ' + name)
    subprocess.run(['codesign', '--verify', '--strict', str(bundle / 'smoke')], check=True)
    output.mkdir(parents=True, exist_ok=False)
    environment = dict(os.environ, ULTRALIGHT_COMPAT_DATA=str(output))
    with (output / 'run.log').open('w') as log:
        result = subprocess.run([str(bundle / 'smoke'), str(bundle / 'AppIcon.icns')], env=environment,
                                stdout=log, stderr=subprocess.STDOUT, timeout=60)
    print((output / 'run.log').read_text())
    checks_path = output / 'results.json'
    checks = json.loads(checks_path.read_text()) if checks_path.is_file() else {}
    passed = result.returncode == 0 and checks.get('passed') is True and bool(checks.get('checks'))
    passed = passed and all(item.get('pass') is True for item in checks.get('checks', []))
    report = {'passed': passed, 'exit_code': result.returncode,
              'macos': version, 'architecture': platform.machine(), 'bundle_sha256': digest(bundle / 'manifest.json')}
    (output / 'runtime.json').write_text(json.dumps(report, indent=2) + '\n')
    if not passed:
        raise SystemExit('Native compatibility smoke failed. See run.log.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['build', 'run'])
    parser.add_argument('--bundle', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path)
    parser.add_argument('--expect-os')
    args = parser.parse_args()
    if args.action == 'build':
        build(args.bundle.resolve())
    elif args.output:
        run(args.bundle.resolve(), args.output.resolve(), args.expect_os)
    else:
        parser.error('run requires --output')


if __name__ == '__main__':
    main()
