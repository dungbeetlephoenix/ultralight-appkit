#!/usr/bin/env python3
"""Exercise production DropView and AppState with an isolated native pasteboard.

Usage: run.py REPO [-- RELEASE_FLAGS...]. Audio, scanner, and stores reuse the
existing state audit's service doubles; no user configuration or audio is used.
"""
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys

base = pathlib.Path(__file__).resolve().parent
repo = pathlib.Path(sys.argv[1]).resolve()
sys.path.insert(0, str(repo / 'Scripts'))
from build_config import FLAGS, TARGET, SIGNATURE_CMS_RESERVE_BYTES

flags = sys.argv[2:]
if flags[:1] == ['--']:
    flags = flags[1:]
if not flags:
    flags = FLAGS
out = base / 'runs' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
out.mkdir(parents=True)
window = repo / 'Sources/Ultralight/Views/MainWindow.swift'
state_audit = repo / 'Tests/state/StateAudit.swift'
source = window.read_text()
start, end = 'final class DropView: NSView {', '// NSColor hex convenience'
if source.count(start) != 1 or source.count(end) != 1 or source.index(start) >= source.index(end):
    raise SystemExit('Cannot extract production DropView: expected unique class and following section markers.')
drop_source = source[source.index(start):source.index(end)]
if not drop_source.rstrip().endswith('}'):
    raise SystemExit('Cannot extract production DropView: class boundary changed.')
(out / 'DropView.swift').write_text('import AppKit\n' + drop_source)
shared = state_audit.read_text()
marker = '@main @MainActor struct StateAudit {'
if shared.count(marker) != 1:
    raise SystemExit('Cannot extract shared service doubles: StateAudit main marker changed.')
doubles = shared.split(marker)[0]
save = 'static func save(_ config: Config) {}'
if doubles.count(save) != 1 or doubles.count('StateAudit.check') != 2:
    raise SystemExit('Cannot instrument shared service doubles: ConfigStore or failure-reporting markers changed.')
doubles = doubles.replace(save, 'static var saved: [[String]] = []\n    static func save(_ config: Config) { saved.append(config.folders) }')
doubles = doubles.replace('StateAudit.check', 'DragAudit.check')
(out / 'ServiceDoubles.swift').write_text(doubles)
inputs = [repo / ('Sources/Ultralight/' + p) for p in [
    'App/AppState.swift', 'App/Binding.swift', 'Models/Track.swift',
    'Models/EQProfile.swift', 'Models/AnalysisResult.swift']]
copies = []
for source in inputs:
    copy = out / source.name
    copy.write_bytes(source.read_bytes())
    copies.append(str(copy))
binary = out / 'drop-audit'
cmd = ['xcrun', 'swiftc', '-parse-as-library', '-module-name', 'Ultralight',
       '-target', TARGET, *flags, *copies, str(out / 'DropView.swift'),
       str(out / 'ServiceDoubles.swift'), str(base / 'DragAudit.swift'), '-o', str(binary)]
tracked = inputs + [window, state_audit, base / 'DragAudit.swift', pathlib.Path(__file__).resolve()]
(out / 'manifest.json').write_text(json.dumps({
    'command': cmd, 'flags': flags,
    'source_hashes': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in tracked},
    'isolation': 'Unique named native pasteboards, temporary fixture files, existing state service doubles; production DropView and AppState are unchanged.'
}, indent=2) + '\n')
with (out / 'compile.log').open('w') as log:
    compiled = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
if compiled.returncode:
    print((out / 'compile.log').read_text())
    print(out)
    raise SystemExit(compiled.returncode)
subprocess.run(['strip', '-rSTx', '-N', str(binary)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none',
                '--signature-size', str(SIGNATURE_CMS_RESERVE_BYTES), str(binary)], check=True)
with (out / 'run.log').open('w') as log:
    result = subprocess.run([str(binary), str(out)], stdout=log, stderr=subprocess.STDOUT, timeout=30)
print((out / 'run.log').read_text())
print(json.dumps({'output': str(out), 'run_exit': result.returncode}))
raise SystemExit(result.returncode)
