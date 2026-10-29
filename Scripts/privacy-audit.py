#!/usr/bin/env python3
"""Scan explicitly selected publication files. Findings report locations, never values."""
import pathlib
import re
import sys
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
files = [root / x for x in ['Package.swift', 'README.md', 'LICENSE', '.gitignore', 'install.sh', 'RELEASE_NOTES.md']]
for directory in ['Sources', 'Tests', 'Scripts', '.github']:
    files.extend(p for p in (root / directory).rglob('*') if p.is_file())
files.extend([root / 'docs/privacy.md', root / 'docs/releasing.md'])
patterns = {
    'absolute-home-path': rb'/(?:Users|home)/[A-Za-z0-9_.-]+/',
    'api-secret': rb'\b(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})',
    'private-key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'jwt': rb'\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}',
    'private-email': rb'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
}
allowed_emails = {
    b'private@example.test', # Synthetic test fixture only.
    b'88670321+HyeonjinBack@users.noreply.github.com', # Public GitHub noreply identity.
}
failures = []
def inspect(name, data):
    for kind, pattern in patterns.items():
        for match in re.finditer(pattern, data):
            if kind == 'private-email' and match.group() in allowed_emails:
                continue
            failures.append((name, kind))

for path in files:
    if not path.exists():
        failures.append((str(path.relative_to(root)), 'missing-publication-file')); continue
    inspect(str(path.relative_to(root)), path.read_bytes())

archive = root / 'dist/release/AgentUsage-macos-arm64.zip'
if archive.exists():
    with zipfile.ZipFile(archive) as z:
        for name in z.namelist():
            if any(x in pathlib.PurePosixPath(name).parts for x in ['.DS_Store', '__MACOSX', 'auth.json', '.credentials.json']):
                failures.append((name, 'private-artifact'))
            inspect(name, z.read(name))
if failures:
    for name, kind in sorted(set(failures)):
        print(f'FAIL {kind}: {name}')
    sys.exit(1)
print(f'PASS: {len(files)} source/document files' + (' and release archive' if archive.exists() else ''))
