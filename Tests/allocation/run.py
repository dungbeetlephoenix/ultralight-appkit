#!/usr/bin/env python3
"""Count FFT/live-callback allocations without starting audio or loading user data."""
from pathlib import Path
import subprocess, sys, tempfile
ROOT = Path(sys.argv[1]).resolve()
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'Scripts'))
from build_config import FLAGS, TARGET
with tempfile.TemporaryDirectory(prefix='ultralight-allocation-gate-') as directory:
    scratch = Path(directory)
    engine = scratch / 'AudioEngine.swift'
    engine.write_text((ROOT / 'Sources/Ultralight/Audio/AudioEngine.swift').read_text() + '''
// Gate-only same-file access to the real callback. Does not start AVAudioEngine.
extension AudioEngine {
    func allocationSpectrum(_ buffer: AVAudioPCMBuffer) { processSpectrum(buffer: buffer) }
}
''')
    library = scratch / 'libCount.dylib'
    subprocess.run(['xcrun', 'clang', '-dynamiclib', '-mmacosx-version-min=14.0',
                    str(HERE / 'Count.c'), '-install_name', '@rpath/libCount.dylib', '-o', str(library)], check=True)
    binary = scratch / 'AllocationAudit'
    subprocess.run(['xcrun', 'swiftc', '-target', TARGET, *FLAGS,
                    '-L', str(scratch), '-lCount', '-Xlinker', '-rpath', '-Xlinker', str(scratch),
                    str(ROOT / 'Sources/Ultralight/Audio/PowerSpectrum.swift'),
                    str(ROOT / 'Sources/Ultralight/Models/EQProfile.swift'),
                    str(engine), str(HERE / 'AllocationAudit.swift'), '-o', str(binary)], check=True)
    subprocess.run(['strip', '-rSTx', '-N', str(binary)], check=True)
    for file in [library, binary]:
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(file)], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(file)], check=True)
    result = subprocess.run([str(binary)], cwd=scratch)
    raise SystemExit(result.returncode)
