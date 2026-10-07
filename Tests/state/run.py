#!/usr/bin/env python3
import datetime, hashlib, json, os, pathlib, platform, subprocess, sys
base = pathlib.Path(__file__).resolve().parent
repo = pathlib.Path(sys.argv[1]).resolve()
out = base / 'runs' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
out.mkdir(parents=True)
inputs = [repo / ('Sources/Ultralight/' + p) for p in ['App/AppState.swift','Models/Track.swift','Models/EQProfile.swift','Models/AnalysisResult.swift']]
binding = repo / 'Sources/Ultralight/App/Binding.swift'
if binding.exists(): inputs.append(binding)
copies = []
for source in inputs:
    dest = out / source.name; dest.write_bytes(source.read_bytes()); copies.append(str(dest))
flags = sys.argv[2:]
if flags[:1] == ['--']: flags = flags[1:]
cmd = ['xcrun','swiftc','-parse-as-library','-module-name','UltralightStateAudit','-target',platform.machine()+'-apple-macosx14.0','-Osize','-whole-module-optimization'] + flags + copies + [str(base/'StateAudit.swift'),'-o',str(out/'state-audit')]
(out/'manifest.json').write_text(json.dumps({'command':cmd,'hashes':{str(s):hashlib.sha256(s.read_bytes()).hexdigest() for s in inputs}},indent=2))
with (out/'compile.log').open('w') as log: compiled=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
if compiled.returncode: print((out/'compile.log').read_text()); print(out); sys.exit(compiled.returncode)
if os.environ.get('ULTRALIGHT_AUDIT_STRIP') == '1':
    subprocess.run(['strip', '-rSTx', '-N', str(out / 'state-audit')], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(out / 'state-audit')], check=True)
with (out/'run.log').open('w') as log: result=subprocess.run([str(out/'state-audit'),str(out)],stdout=log,stderr=subprocess.STDOUT,timeout=30)
print((out/'run.log').read_text()); print(json.dumps({'output':str(out),'run_exit':result.returncode}));sys.exit(result.returncode)
