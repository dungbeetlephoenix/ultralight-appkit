#!/usr/bin/env python3
"""Two prequeued tracks, true offline render at volume 1; never connects to hardware playback."""
import datetime, hashlib, json, os, pathlib, platform, struct, subprocess, sys, wave
base = pathlib.Path(__file__).resolve().parent
repo = pathlib.Path(sys.argv[1]).resolve()
flags = sys.argv[2:]
if flags[:1] == ['--']: flags = flags[1:]
out = base / 'runs' / ('continuity-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
out.mkdir(parents=True)
for name, frames, value in [('positive', 22050, 8192), ('negative', 26460, -8192)]:
    with wave.open(str(out / (name + '.wav')), 'wb') as wav:
        wav.setparams((2, 2, 44100, 0, 'NONE', 'not compressed'))
        wav.writeframes(struct.pack('<hh', value, value) * frames)
source = repo / 'Sources/Ultralight/Audio/AudioEngine.swift'
copied = out / 'AudioEngine.swift'
copied.write_text(source.read_text() + '\n' + (base / 'ContinuityAccess.swift').read_text())
support = [str(p) for p in [repo / 'Sources/Ultralight/Audio/PowerSpectrum.swift'] if p.exists()]
cmd = ['xcrun', 'swiftc', '-parse-as-library', '-module-name', 'UltralightContinuityAudit', '-target', platform.machine() + '-apple-macosx14.0', '-Osize', '-whole-module-optimization'] + flags + support + [str(copied), str(repo / 'Sources/Ultralight/Models/EQProfile.swift'), str(base / 'ContinuityAudit.swift'), '-o', str(out / 'continuity-audit')]
(out / 'manifest.json').write_text(json.dumps({'repo': str(repo), 'audio_engine_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'command': cmd}, indent=2))
with (out / 'compile.log').open('w') as log: compiled = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
if compiled.returncode:
    print((out / 'compile.log').read_text()); print(out); sys.exit(compiled.returncode)
if os.environ.get('ULTRALIGHT_AUDIT_STRIP') == '1':
    subprocess.run(['strip', '-rSTx', '-N', str(out / 'continuity-audit')], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(out / 'continuity-audit')], check=True)
env = os.environ.copy(); env['ULTRALIGHT_PLAYBACK_AUDIT_OUTPUT'] = str(out)
with (out / 'run.log').open('w') as log: result = subprocess.run([str(out / 'continuity-audit')], env=env, stdout=log, stderr=subprocess.STDOUT, timeout=30)
print((out / 'run.log').read_text()); print(json.dumps({'output': str(out), 'run_exit': result.returncode}))
sys.exit(result.returncode)
