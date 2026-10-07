#!/usr/bin/env python3
"""Compile and run silent app source gates. All data stays in a fresh temporary directory.
Usage: run-gates.py SOURCE_ROOT [--baseline] [--strip-n] [SWIFTC EXTRA FLAGS...]
This copies ConfigStore.swift into scratch and redirects only its app-support lookup.
No production source is edited; no audio engine is started and no playback occurs.
"""
from pathlib import Path
import os, platform, shutil, subprocess, sys, tempfile
root = Path(sys.argv[1]).resolve()
flags = sys.argv[2:]
baseline = "--baseline" in flags
if baseline: flags.remove("--baseline")
strip_n = "--strip-n" in flags
if strip_n: flags.remove("--strip-n")
harness = Path(__file__).with_name('QualityGates.swift')
with tempfile.TemporaryDirectory(prefix='ultralight-gates-') as directory:
    scratch = Path(directory)
    source = scratch / 'source'
    shutil.copytree(root / 'Sources/Ultralight', source)
    engine_file = source / 'Audio/AudioEngine.swift'
    engine_file.write_text(engine_file.read_text() + """
// Scratch-only gate access to the real private callback, without starting playback.
extension AudioEngine {
    func gateSpectrum(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        var output: [Float]?
        onSpectrumData = { output = $0 }
        processSpectrum(buffer: buffer)
        onSpectrumData = nil
        return output
    }
    var gateEQUnitBypassed: Bool { eq.bypass }
}
""")
    config = (source / 'Storage/ConfigStore.swift').read_text()
    original = 'FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!'
    assert config.count(original) == 1, 'ConfigStore lookup changed; review gate isolation before running.'
    config = config.replace(original, 'URL(fileURLWithPath: ProcessInfo.processInfo.environment["ULTRALIGHT_GATE_ROOT"]!)')
    isolated = scratch / 'ConfigStore.swift'
    isolated.write_text(config)
    sources = sorted(str(p) for p in source.rglob('*.swift') if p.name not in ('main.swift', 'ConfigStore.swift'))
    exe = scratch / 'gates'
    result = subprocess.run(['xcrun', 'swiftc', '-target', f'{platform.machine()}-apple-macosx14.0', '-Osize', '-whole-module-optimization', '-Xlinker', '-dead_strip', '-Xlinker', '-x', '-parse-as-library', *flags, *sources, str(isolated), str(harness), '-o', str(exe)])
    if result.returncode:
        sys.exit(result.returncode)
    if strip_n:
        subprocess.run(['strip', '-rSTx', '-N', str(exe)], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', '--signature-size', '8', '--timestamp=none', str(exe)], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(exe)], check=True)
    env = dict(os.environ, ULTRALIGHT_GATE_ROOT=str(scratch), ULTRALIGHT_GATE_BASELINE="1" if baseline else "0")
    result = subprocess.run([str(exe)], env=env)
    sys.exit(result.returncode)
