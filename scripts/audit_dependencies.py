#!/usr/bin/env python3
"""Fail closed on OSV advisories or unavailable scans of committed Pub locks."""
import json
import pathlib
import re
import urllib.request

root = pathlib.Path(__file__).resolve().parents[1]
locks = [root / 'apps/standalone/pubspec.lock', *sorted((root / 'packages').glob('*/pubspec.lock'))]
pairs = set()
for lock in locks:
    text = lock.read_text()
    count = 0
    # Pub generates this fixed YAML layout; reject unknown hosted entry layouts.
    for match in re.finditer(r'^  ([a-zA-Z0-9_]+):\n(.*?)(?=^  [a-zA-Z0-9_]+:|\Z)', text, re.M | re.S):
        name, block = match.groups()
        if re.search(r'^    source: hosted\s*$', block, re.M):
            version = re.search(r'^    version: "([^"\n]+)"\s*$', block, re.M)
            if not version:
                raise SystemExit(f'Cannot read hosted version in {lock}: {name}')
            pairs.add((name, version[1]))
            count += 1
    if count != len(re.findall(r'^    source: hosted\s*$', text, re.M)):
        raise SystemExit(f'Incomplete hosted inventory from {lock}')
    if not count:
        raise SystemExit(f'No hosted dependencies read from {lock}')
pairs = sorted(pairs)
findings = []
for offset in range(0, len(pairs), 100):
    batch = pairs[offset:offset + 100]
    body = {'queries': [{'package': {'name': n, 'ecosystem': 'Pub'}, 'version': v} for n, v in batch]}
    request = urllib.request.Request('https://api.osv.dev/v1/querybatch',
                                    data=json.dumps(body).encode(),
                                    headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=45) as response:
        result = json.load(response)
    results = result['results']
    if len(results) != len(batch):
        raise SystemExit('OSV returned an incomplete scan')
    for pair, entry in zip(batch, results):
        if 'error' in entry:
            raise SystemExit(f'OSV could not scan {pair}')
        for advisory in entry.get('vulns', []):
            findings.append({'package': pair[0], 'version': pair[1], 'advisory': advisory['id']})
print(json.dumps({'scannedPackageVersions': len(pairs), 'findings': findings}, indent=2))
if findings:
    raise SystemExit(1)
