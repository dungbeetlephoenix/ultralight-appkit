#!/usr/bin/env python3
"""Export a small public record of a completed release, without local paths."""
import argparse
import hashlib
import json
import pathlib
import re
from build_config import ROOT, source_hashes
from release import files_in


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', type=pathlib.Path, default=ROOT / 'artifacts/release')
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'docs/evidence/release.json')
    args = parser.parse_args()
    report = json.loads((args.release / 'size.json').read_text())
    gates = json.loads((args.release / 'gates/results.json').read_text())
    if not gates['passed'] or report['source_sha256'] != source_hashes():
        raise SystemExit('Evidence requires a passing release from the current source.')
    if gates['source_sha256'] != report['source_sha256']:
        raise SystemExit('Gate and release inputs differ.')
    inventory = files_in(args.release / 'Ultralight.app')
    if inventory != report['files']:
        raise SystemExit('Release app inventory or file content changed.')
    if sum(item['bytes'] for item in inventory.values()) != report['app_bytes']:
        raise SystemExit('Release app size differs from its report.')
    if inventory['Contents/MacOS/Ultralight']['bytes'] != report['binary_bytes']:
        raise SystemExit('Release executable size differs from its report.')
    if 'dmg_sha256' in report:
        data = (args.release / 'Ultralight.dmg').read_bytes()
        if len(data) != report['dmg_bytes'] or hashlib.sha256(data).hexdigest() != report['dmg_sha256']:
            raise SystemExit('Release disk image changed.')
    # Explicit fields keep credentials, scratch directories, and command paths
    # out of this public summary even if future release reports grow new fields.
    keys = ('version', 'git_head', 'toolchain', 'architecture', 'binary_bytes', 'app_bytes',
            'dmg_bytes', 'dmg_format', 'dmg_sha256', 'signature', 'signature_gate',
            'source_sha256', 'flags', 'files', 'signature_cms_reserve_bytes', 'environment', 'dmg_gate')
    output = {key: report[key] for key in keys if key in report}
    output['gates'] = {'passed': gates['passed'], 'source_stable': gates['source_stable'],
                       'suites': gates['suites']}
    output['assertion_summaries'] = {}
    for suite in gates['suites']:
        log = args.release / 'gates' / (suite + '.log')
        if log.exists():
            output['assertion_summaries'][suite] = [line for line in log.read_text().splitlines()
                if re.match(r'^(RESULT|GEOMETRY|LIFECYCLE|FINISHING|ACCESSIBILITY)\b', line)]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + '\n')
    print(args.output)


if __name__ == '__main__':
    main()
