#!/usr/bin/env python3
"""Audit actual AppState notification semantics with silent deterministic services."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def validate_inventory(repo):
    for source in (repo / 'Sources').rglob('*.swift'):
        if source.relative_to(repo).as_posix() == 'Sources/Ultralight/App/AppState.swift':
            continue
        text = source.read_text()
        if re.search(r'^\s*@Published\b', text, re.MULTILINE) or re.search(
                r'\b(?:class|struct|extension)\s+\w+[^{}]*:\s*[^{}]*\bObservableObject\b', text):
            raise ValueError('A new observable type requires its own complete notification audit: ' + str(source))


def validate_coverage(source, harness, flags):
    fields = re.findall(r'@Published\s+var\s+(\w+)', source)
    covered = re.findall(r'exercise\("(\w+)"', harness)
    if len(fields) != source.count('@Published') or len(set(fields)) != len(fields):
        raise ValueError('Published declaration syntax changed; review observation coverage.')
    if sorted(fields) != sorted(covered):
        raise ValueError('Every Published property must have exactly one exhaustive observation fixture: '
                         'fields=' + str(fields) + ', fixtures=' + str(covered))
    if '-disable-reflection-metadata' in flags or 'let objectWillChange' in source:
        if source.count('let objectWillChange = ObservableObjectPublisher()') != 1:
            raise ValueError('Metadata-free AppState requires one stable explicit object publisher.')
        declarations = [line for line in source.splitlines() if '@Published' in line]
        if any(line.count('willSet { objectWillChange.send() }') != 1 for line in declarations):
            raise ValueError('Every Published declaration must send objectWillChange exactly once in willSet.')
        if source.count('objectWillChange.send()') != len(fields):
            raise ValueError('Unexpected duplicate/manual object notifications outside Published observers.')
    return fields


def main():
    argv = sys.argv[1:]
    flags = []
    if '--' in argv:
        at = argv.index('--'); flags, argv = argv[at + 1:], argv[:at]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args(argv)
    repo = args.repo.resolve()
    sys.path.insert(0, str(repo / 'Scripts'))
    from build_config import FLAGS, TARGET
    if not flags:
        flags = FLAGS
    out = args.output or HERE / 'runs' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    out.mkdir(parents=True, exist_ok=True)
    state = repo / 'Sources/Ultralight/App/AppState.swift'
    harness = HERE / 'ObservationAudit.swift'
    validate_inventory(repo)
    fields = validate_coverage(state.read_text(), harness.read_text(), flags)
    shared = (repo / 'Tests/state/StateAudit.swift').read_text()
    marker = '@main @MainActor struct StateAudit {'
    if shared.count(marker) != 1 or shared.count('StateAudit.check') != 2:
        raise ValueError('State service doubles changed; review silent observation isolation.')
    doubles = shared.split(marker)[0].replace('StateAudit.check', 'ObservationAudit.check')
    (out / 'ServiceDoubles.swift').write_text(doubles)
    inputs = [repo / ('Sources/Ultralight/' + p) for p in
              ['App/AppState.swift', 'Models/Track.swift', 'Models/EQProfile.swift', 'Models/AnalysisResult.swift']]
    copied = []
    for source in inputs:
        copy = out / source.name; copy.write_bytes(source.read_bytes()); copied.append(str(copy))
    binary = out / 'observation-audit'
    command = ['xcrun', 'swiftc', '-parse-as-library', '-module-name', 'UltralightObservationAudit',
               '-target', TARGET, *flags, *copied, str(out / 'ServiceDoubles.swift'), str(harness), '-o', str(binary)]
    (out / 'manifest.json').write_text(json.dumps({'fields': fields, 'flags': flags, 'command': command,
        'source_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs + [harness]}}, indent=2))
    with (out / 'compile.log').open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((out / 'compile.log').read_text()); return result.returncode
    subprocess.run(['strip', '-rSTx', '-N', str(binary)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', '--signature-size', '8', '--timestamp=none', str(binary)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(binary)], check=True)
    result = subprocess.run([str(binary), str(out / 'results.json')], capture_output=True, text=True, timeout=30)
    (out / 'run.log').write_text(result.stdout + result.stderr)
    print(result.stdout)
    print(json.dumps({'output': str(out), 'run_exit': result.returncode}))
    return result.returncode


if __name__ == '__main__':
    sys.exit(main())
