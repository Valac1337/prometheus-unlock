# SPDX-License-Identifier: GPL-2.0-only
"""Package compiled Windows launchers with the audited public source payload."""
import hashlib
import importlib.util
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_check', ROOT / 'gui/release_check.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

def main():
    files = dict(checker.audit(ROOT))
    for name in ('PrometheusUnlock.exe', 'Setup.exe'):
        path = ROOT / 'dist/desktop-bin' / name
        if not path.is_file() or path.read_bytes()[:2] != b'MZ':
            raise ValueError('Build the desktop launchers first: ' + name)
        files[name] = path
    files['START-HERE.txt'] = ROOT / 'WINDOWS-DOWNLOAD.txt'
    output = ROOT / 'dist/Prometheus-Unlock-Windows-x64.zip'
    pending = output.with_suffix('.zip.pending')
    with zipfile.ZipFile(pending, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, path in sorted(files.items()):
            archive.write(path, 'Prometheus Unlock/' + name)
    with zipfile.ZipFile(pending) as archive:
        if archive.testzip():
            raise ValueError('Windows archive integrity check failed')
    pending.replace(output)
    checksums = []
    for path in (output, ROOT / 'dist/Prometheus-Unlock-source.zip'):
        checksums.append(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name)
    (ROOT / 'dist/SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n', encoding='ascii')
    print(output)

if __name__ == '__main__':
    main()
