#!/usr/bin/env python3
"""Run all release gates, using isolated data and no audible output."""
import json
import os
import subprocess
import sys
from build_config import FLAGS, ROOT, SIGNATURE_CMS_RESERVE_BYTES, source_hashes


def main():
    output = ROOT / 'artifacts/gates'
    output.mkdir(parents=True, exist_ok=True)
    snapshot = source_hashes()
    jobs = [
        ('audio', ['Tests/audio/run-gates.py', str(ROOT), '--strip-n', *FLAGS]),
        ('ui', ['Tests/ui/run.py', str(ROOT), '--label', 'release', '--', *FLAGS]),
        ('playback', ['Tests/playback/run.py', str(ROOT), '--label', 'release', '--', *FLAGS]),
        ('continuity', ['Tests/playback/continuity.py', str(ROOT), '--', *FLAGS]),
        ('state', ['Tests/state/run.py', str(ROOT), '--', *FLAGS]),
        ('binding', ['Tests/binding/run.py', str(ROOT), '--', *FLAGS]),
        ('drop', ['Tests/drop/run.py', str(ROOT), '--', *FLAGS]),
        ('allocation', ['Tests/allocation/run.py', str(ROOT)]),
    ]
    statuses = {}
    env = dict(os.environ, ULTRALIGHT_AUDIT_STRIP='1')
    for name, command in jobs:
        print('Checking ' + name + '…', flush=True)
        with (output / (name + '.log')).open('w') as log:
            result = subprocess.run([sys.executable, *command], cwd=ROOT, env=env,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=180)
        statuses[name] = result.returncode
        if name == 'ui' and not result.returncode:
            latest = json.loads((output / 'ui.log').read_text().strip().splitlines()[-1])['output']
            with (output / 'ui-comparison.log').open('w') as log:
                compared = subprocess.run([sys.executable, 'Tests/ui/compare.py',
                    'Tests/ui/baseline', latest], cwd=ROOT, stdout=log,
                    stderr=subprocess.STDOUT, timeout=30)
            statuses[name] = compared.returncode
        if statuses[name]:
            print((output / (name + '.log')).read_text())
            if name == 'ui':
                print((output / 'ui-comparison.log').read_text())
            break
    stable = snapshot == source_hashes()
    passed = len(statuses) == len(jobs) and not any(statuses.values()) and stable
    report = {'passed': passed, 'source_stable': stable, 'suites': statuses,
              'source_sha256': snapshot, 'flags': FLAGS, 'strip_n': True,
              'signature_cms_reserve_bytes': SIGNATURE_CMS_RESERVE_BYTES}
    (output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    if not passed:
        raise SystemExit('Release gates failed or source changed during verification.')
    print('All release gates passed.')
    return report


if __name__ == '__main__':
    main()
