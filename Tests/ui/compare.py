#!/usr/bin/env python3
"""Compare UI audit runs. Exit 1 for assertion/layout/observation differences; 2 for renders requiring review."""
import hashlib, json, pathlib, sys

baseline, candidate = [pathlib.Path(p) for p in sys.argv[1:3]]
before, after = [json.loads((p / 'results.json').read_text()) for p in (baseline, candidate)]
failures = [item['name'] for item in after['checks'] if not item['pass']]
same_checks = [(i['name'], i['pass']) for i in before['checks']] == [(i['name'], i['pass']) for i in after['checks']]
same_layout = before['layouts'] == after['layouts']
same_observations = before['observations'] == after['observations']
images = []
for source in sorted(baseline.glob('*.png')):
    other = candidate / source.name
    same = other.exists() and hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(other.read_bytes()).digest()
    images.append({'image': source.name, 'identical_png': same})
report = {'candidate_failed_assertions': failures, 'same_assertion_results': same_checks, 'same_layout': same_layout, 'same_observations': same_observations, 'renders': images}
print(json.dumps(report, indent=2))
if failures or not same_checks or not same_layout or not same_observations:
    sys.exit(1)
if not all(i['identical_png'] for i in images):
    sys.exit(2)
