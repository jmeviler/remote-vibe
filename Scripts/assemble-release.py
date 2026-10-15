#!/usr/bin/env python3
"""Combine verified per-chip artifacts without overwriting checksum manifests."""
import hashlib
from pathlib import Path
import plistlib
import sys

directory = Path(sys.argv[1])
version = plistlib.loads(Path('Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
combined = {}
for chip in ('AppleSilicon', 'Intel'):
    expected = {f'Remote-Vibe-{version}-{kind}-{chip}.zip' for kind in ('Mac', 'App')}
    entries = {}
    for line in (directory / f'SHA256SUMS-{chip}.txt').read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        if name not in expected or name in entries:
            raise SystemExit(f'Unexpected or duplicate {chip} download: {name}')
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
            raise SystemExit(f'Checksum mismatch: {name}')
        entries[name] = digest
    if entries.keys() != expected:
        raise SystemExit(f'Missing {chip} downloads: {expected - entries.keys()}')
    combined.update(entries)
if {p.name for p in directory.glob('*.zip')} != combined.keys():
    raise SystemExit('Unexpected ZIP in release artifacts')
(directory / 'SHA256SUMS.txt').write_text(''.join(
    f'{digest}  {name}\n' for name, digest in sorted(combined.items())))
print('Verified all four downloads; wrote combined SHA256SUMS.txt.')
