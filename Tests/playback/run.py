#!/usr/bin/env python3
import argparse, datetime, hashlib, json, math, os, pathlib, platform, struct, subprocess, sys, wave

base = pathlib.Path(__file__).resolve().parent
argv = sys.argv[1:]
flags = []
if '--' in argv:
    i = argv.index('--'); flags, argv = argv[i + 1:], argv[:i]
p = argparse.ArgumentParser()
p.add_argument('repo', type=pathlib.Path)
p.add_argument('--label', default='audit')
p.add_argument('--mode', choices=['realtime', 'offline'], default='realtime')
args = p.parse_args(argv)
repo = args.repo.resolve()
out = base / 'runs' / (args.label + '-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
out.mkdir(parents=True)
for name, rate, seconds, channels in [('long', 44100, 3, 2), ('a', 44100, .5, 2), ('b', 44100, .6, 2), ('c', 44100, .7, 2), ('different-rate', 48000, .8, 2), ('mono', 44100, .4, 1)]:
    with wave.open(str(out / (name + '.wav')), 'wb') as wav:
        wav.setparams((channels, 2, rate, 0, 'NONE', 'not compressed'))
        pcm = b''.join(struct.pack('<h', int(2500 * math.sin(2 * math.pi * 440 * i / rate))) * channels for i in range(int(rate * seconds)))
        wav.writeframes(pcm)
source = repo / 'Sources/Ultralight/Audio/AudioEngine.swift'
copied = out / 'AudioEngine.swift'
copied.write_text(source.read_text() + '\n' + (base / 'TestAccess.swift').read_text())
support = [str(p) for p in [repo / 'Sources/Ultralight/Audio/PowerSpectrum.swift'] if p.exists()]
cmd = ['xcrun', 'swiftc', '-parse-as-library', '-module-name', 'UltralightPlaybackAudit', '-target', platform.machine() + '-apple-macosx14.0', '-Osize', '-whole-module-optimization'] + flags + support + [str(copied), str(repo / 'Sources/Ultralight/Models/EQProfile.swift'), str(base / 'PlaybackAudit.swift'), '-o', str(out / 'playback-audit')]
(out / 'manifest.json').write_text(json.dumps({'repo': str(repo), 'audio_engine_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'command': cmd}, indent=2))
with (out / 'compile.log').open('w') as log:
    compile_result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
if compile_result.returncode:
    print((out / 'compile.log').read_text()); print(str(out)); sys.exit(compile_result.returncode)
if os.environ.get('ULTRALIGHT_AUDIT_STRIP') == '1':
    subprocess.run(['strip', '-rSTx', '-N', str(out / 'playback-audit')], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(out / 'playback-audit')], check=True)
env = os.environ.copy(); env['ULTRALIGHT_PLAYBACK_AUDIT_OUTPUT'] = str(out); env['ULTRALIGHT_PLAYBACK_AUDIT_MODE'] = args.mode
with (out / 'run.log').open('w') as log:
    result = subprocess.run([str(out / 'playback-audit')], env=env, stdout=log, stderr=subprocess.STDOUT, timeout=60)
print((out / 'run.log').read_text())
print(json.dumps({'output': str(out), 'run_exit': result.returncode}))
sys.exit(result.returncode)
