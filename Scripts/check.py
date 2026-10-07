#!/usr/bin/env python3
"""Run all release gates, using isolated data and no audible output."""
import argparse
import json
import os
import signal
import subprocess
import sys
from build_config import FLAGS, ROOT, SIGNATURE_CMS_RESERVE_BYTES, preflight, source_hashes


def jobs():
    return [
        ('tooling', ['-m', 'unittest', 'discover', '-s', 'Tests/tooling', '-v']),
        ('audio', ['Tests/audio/run-gates.py', str(ROOT), '--strip-n', *FLAGS]),
        ('ui', ['Tests/ui/run.py', str(ROOT), '--label', 'release', '--', *FLAGS]),
        ('playback', ['Tests/playback/run.py', str(ROOT), '--label', 'release', '--', *FLAGS]),
        ('continuity', ['Tests/playback/continuity.py', str(ROOT), '--', *FLAGS]),
        ('state', ['Tests/state/run.py', str(ROOT), '--', *FLAGS]),
        ('observation', ['Tests/observation/run.py', str(ROOT), '--', *FLAGS]),
        ('binding', ['Tests/binding/run.py', str(ROOT), '--', *FLAGS]),
        ('drop', ['Tests/drop/run.py', str(ROOT), '--', *FLAGS]),
        ('allocation', ['Tests/allocation/run.py', str(ROOT)]),
    ]


def write_report(output, report):
    temporary = output / 'results.json.tmp'
    temporary.write_text(json.dumps(report, indent=2) + '\n')
    temporary.replace(output / 'results.json')


def run_gate(command, log_path, env, timeout):
    with log_path.open('w') as log:
        try:
            with subprocess.Popen([sys.executable, *command], cwd=ROOT, env=env,
                                  stdout=log, stderr=subprocess.STDOUT, start_new_session=True) as process:
                try:
                    return process.wait(timeout=timeout)
                except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
                    # Kill only this gate's process group, including compiler/test
                    # children. Never leave an orphan test running after timeout.
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
                    if isinstance(error, KeyboardInterrupt):
                        raise
                    log.write('\nGate timed out after ' + str(timeout) + ' seconds.\n')
                    return 124
        except OSError as error:
            log.write('\nCould not start gate: ' + str(error) + '\n')
            return 127


def run_checks(output):
    output.mkdir(parents=True, exist_ok=True)
    scheduled = jobs()
    # Invalidate a previous successful report before preflight or compilation.
    report = {'passed': False, 'source_stable': False, 'suites': {}, 'source_sha256': {},
              'flags': FLAGS, 'strip_n': True, 'signature_cms_reserve_bytes': SIGNATURE_CMS_RESERVE_BYTES}
    write_report(output, report)
    for name in [*[name for name, _ in scheduled], 'ui-comparison', 'preflight']:
        (output / (name + '.log')).unlink(missing_ok=True)
    try:
        report['environment'] = preflight()
        report['source_sha256'] = source_hashes()
        env = dict(os.environ, ULTRALIGHT_AUDIT_STRIP='1')
        for name, command in scheduled:
            print('Checking ' + name + '…', flush=True)
            status = run_gate(command, output / (name + '.log'), env, 180)
            if name == 'ui' and status == 0:
                latest = json.loads((output / 'ui.log').read_text().strip().splitlines()[-1])['output']
                status = run_gate(['Tests/ui/compare.py', 'Tests/ui/baseline', latest],
                                  output / 'ui-comparison.log', env, 30)
            report['suites'][name] = status
            write_report(output, report)
            if status:
                for log_name in [name, 'ui-comparison'] if name == 'ui' else [name]:
                    log = output / (log_name + '.log')
                    if log.is_file():
                        print(log.read_text())
                break
        report['source_stable'] = report['source_sha256'] == source_hashes()
        report['passed'] = (len(report['suites']) == len(scheduled) and
                            not any(report['suites'].values()) and report['source_stable'])
    except (Exception, KeyboardInterrupt) as error:
        report['error'] = type(error).__name__ + ': ' + str(error)
        (output / 'preflight.log').write_text(report['error'] + '\n')
    finally:
        write_report(output, report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=lambda p: ROOT / p, default=ROOT / 'artifacts/gates')
    args = parser.parse_args()
    report = run_checks(args.output.resolve())
    if not report['passed']:
        raise SystemExit('Release gates failed: ' + report.get('error', 'see ' + str(args.output)))
    print('All release gates passed.')


if __name__ == '__main__':
    main()
