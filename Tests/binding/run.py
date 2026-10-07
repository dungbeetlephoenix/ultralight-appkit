#!/usr/bin/env python3
"""Check production RunLoop binding semantics without UI, audio, or user data."""
import datetime, hashlib, json, os, pathlib, platform, subprocess, sys

base = pathlib.Path(__file__).resolve().parent
repo = pathlib.Path(sys.argv[1]).resolve()
flags = sys.argv[2:]
if flags[:1] == ['--']:
    flags = flags[1:]
out = base / 'runs' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
out.mkdir(parents=True)
source = repo / 'Sources/Ultralight/App/Binding.swift'
copied = out / 'Binding.swift'
copied.write_bytes(source.read_bytes())
binary = out / 'binding-gates'
cmd = ['xcrun', 'swiftc', '-parse-as-library', '-module-name', 'UltralightBindingGates',
       '-target', platform.machine() + '-apple-macosx14.0', '-Osize', '-whole-module-optimization',
       *flags, str(copied), str(base / 'BindingGates.swift'), '-o', str(binary)]
(out / 'manifest.json').write_text(json.dumps({
    'command': cmd, 'binding_sha256': hashlib.sha256(copied.read_bytes()).hexdigest()
}, indent=2) + '\n')
with (out / 'compile.log').open('w') as log:
    compiled = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
if compiled.returncode:
    print((out / 'compile.log').read_text())
    raise SystemExit(compiled.returncode)
if os.environ.get('ULTRALIGHT_AUDIT_STRIP') == '1':
    subprocess.run(['strip', '-rSTx', '-N', str(binary)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(binary)], check=True)
with (out / 'run.log').open('w') as log:
    result = subprocess.run([str(binary), str(out)], stdout=log, stderr=subprocess.STDOUT, timeout=20)
print((out / 'run.log').read_text())
print(json.dumps({'output': str(out), 'run_exit': result.returncode}))
raise SystemExit(result.returncode)
