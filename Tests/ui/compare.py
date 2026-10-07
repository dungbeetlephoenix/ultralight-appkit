#!/usr/bin/env python3
"""Compare all frozen UI fixtures. Exit 1 for invalid checks; 2 for changed renders."""
import hashlib
import json
import pathlib
import sys

EXPECTED_IMAGES = {'compact-600x400.png', 'default-900x600.png', 'eq-hidden.png'}


def compare(baseline, candidate):
    for label, directory in [('baseline', baseline), ('candidate', candidate)]:
        found = {p.name for p in directory.glob('*.png') if p.is_file()}
        if found != EXPECTED_IMAGES:
            raise ValueError(label + ' must contain exactly the three frozen renders; missing=' +
                             str(sorted(EXPECTED_IMAGES - found)) + ', unexpected=' +
                             str(sorted(found - EXPECTED_IMAGES)))
    before, after = [json.loads((p / 'results.json').read_text()) for p in (baseline, candidate)]
    failures = [item['name'] for item in after['checks'] if not item['pass']]
    same_checks = [(i['name'], i['pass']) for i in before['checks']] == [(i['name'], i['pass']) for i in after['checks']]
    same_layout = before['layouts'] == after['layouts']
    same_observations = before['observations'] == after['observations']
    images = [{'image': name, 'identical_png': hashlib.sha256((baseline / name).read_bytes()).digest() ==
              hashlib.sha256((candidate / name).read_bytes()).digest()} for name in sorted(EXPECTED_IMAGES)]
    report = {'candidate_failed_assertions': failures, 'same_assertion_results': same_checks,
              'same_layout': same_layout, 'same_observations': same_observations, 'renders': images}
    code = 1 if failures or not same_checks or not same_layout or not same_observations else (
        0 if all(i['identical_png'] for i in images) else 2)
    return report, code


def main():
    try:
        report, code = compare(*[pathlib.Path(p) for p in sys.argv[1:3]])
    except (OSError, ValueError, KeyError, TypeError) as error:
        report, code = {'error': str(error)}, 1
    print(json.dumps(report, indent=2))
    return code


if __name__ == '__main__':
    sys.exit(main())
