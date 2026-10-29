#!/usr/bin/env python3
"""Build a clean release archive without Finder metadata or absolute file paths."""
import hashlib
import pathlib
import shutil
import stat
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
app = root / 'dist/AgentMeter.app'
output = root / 'dist/release'
output.mkdir(parents=True, exist_ok=True)
archive = output / 'AgentUsage-macos-arm64.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for path in sorted(app.rglob('*')):
        if path.is_dir() or path.name == '.DS_Store' or path.name.startswith('._'):
            continue
        if path.is_symlink():
            raise SystemExit('Unexpected symlink in release bundle')
        name = str(path.relative_to(app.parent))
        info = zipfile.ZipInfo(name)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.create_system = 3
        info.external_attr = (stat.S_IFREG | (path.stat().st_mode & 0o777)) << 16
        z.writestr(info, path.read_bytes())
shutil.copyfile(root / 'install.sh', output / 'install.sh')
lines = []
for path in [archive, output / 'install.sh']:
    lines.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n')
(output / 'SHA256SUMS').write_text(''.join(lines))
print('Release assets:', ', '.join(p.name for p in output.iterdir()))
