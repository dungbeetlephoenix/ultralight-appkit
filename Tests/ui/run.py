#!/usr/bin/env python3
"""Run isolated Ultralight AppKit checks. Usage: run.py REPO [--label NAME] [-- FLAGS...]."""
import argparse, datetime, hashlib, json, os, pathlib, platform, subprocess, sys

base = pathlib.Path(__file__).resolve().parent
argv = sys.argv[1:]
flags = []
if '--' in argv:
    i = argv.index('--')
    flags, argv = argv[i + 1:], argv[:i]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('repo', type=pathlib.Path)
parser.add_argument('--label', default='audit')
args = parser.parse_args(argv)
repo = args.repo.resolve()
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
out = base / 'runs' / (args.label + '-' + stamp)
out.mkdir(parents=True)
config = repo / 'Sources/Ultralight/Storage/ConfigStore.swift'
original = config.read_text()
needle = 'FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!'
if original.count(needle) != 1:
    raise SystemExit('Cannot safely isolate ConfigStore: expected data-directory expression changed.')
replacement = 'URL(fileURLWithPath: ProcessInfo.processInfo.environment["ULTRALIGHT_UI_AUDIT_DATA_ROOT"]!, isDirectory: true)'
isolated = out / 'ConfigStore.swift'
isolated.write_text(original.replace(needle, replacement))
sources = sorted((repo / 'Sources/Ultralight').rglob('*.swift'))
sources = [p for p in sources if p.name != 'main.swift' and p != config] + [isolated, base / 'UIAudit.swift']
default_flags = ['-Osize', '-whole-module-optimization', '-Xlinker', '-dead_strip', '-Xlinker', '-x']
effective_flags = default_flags + flags
binary = out / 'ui-audit'
cmd = ['xcrun', 'swiftc', '-module-name', 'Ultralight', '-parse-as-library', '-target', platform.machine() + '-apple-macosx14.0'] + effective_flags + [str(p) for p in sources] + ['-o', str(binary)]
manifest = {'repo': str(repo), 'flags': effective_flags, 'source_hashes': {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((repo / 'Sources/Ultralight').rglob('*.swift'))}, 'config_isolation': 'Only applicationSupportDirectory expression replaced in a temporary copy', 'output': str(out), 'command': cmd}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
with (out / 'compile.log').open('w') as log:
    compiled = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
if compiled.returncode:
    print((out / 'compile.log').read_text())
    print(json.dumps({'output': str(out), 'compile_exit': compiled.returncode}))
    raise SystemExit(compiled.returncode)
if os.environ.get('ULTRALIGHT_AUDIT_STRIP') == '1':
    subprocess.run(['strip', '-rSTx', '-N', str(binary)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(binary)], check=True)
env = os.environ.copy()
env['ULTRALIGHT_UI_AUDIT_DATA_ROOT'] = str(out / 'data')
env['ULTRALIGHT_UI_AUDIT_OUTPUT'] = str(out)
with (out / 'run.log').open('w') as log:
    result = subprocess.run([str(binary)], env=env, stdout=log, stderr=subprocess.STDOUT, timeout=45)
print((out / 'run.log').read_text())
print(json.dumps({'output': str(out), 'run_exit': result.returncode, 'results': str(out / 'results.json')}))
raise SystemExit(result.returncode)
