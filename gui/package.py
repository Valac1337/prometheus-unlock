# SPDX-License-Identifier: GPL-2.0-only
"""Package public source and GUI without local firmware, profiles or captures."""
from pathlib import Path
import json
import zipfile
import importlib.util

ROOT = Path(__file__).resolve().parents[1]

def main():
    spec = importlib.util.spec_from_file_location('release_check', ROOT / 'gui/release_check.py')
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    checker.audit(ROOT)
    names = json.loads((ROOT / 'SOURCE-FILES.json').read_text(encoding='utf-8'))
    files = {Path(name) for name in names}
    if len(files) != len(names):
        raise ValueError('Duplicate source-manifest entry')
    forbidden = ('research/profile/local/', 'assets/', 'local-tools/', 'firmware-inputs/', 'firmware-source/')
    for path in files:
        name = path.as_posix()
        if (path.is_absolute() or '..' in path.parts or ':' in name
                or not (ROOT / path).resolve().is_relative_to(ROOT.resolve())
                or (ROOT / path).is_symlink()):
            raise ValueError('Unsafe source path: ' + name)
        if (name.startswith(forbidden) or name.endswith(('profile-local.h', 'platform-config.h', 'generated.h'))
                or path.suffix.lower() in ('.efi', '.exe', '.dll', '.bin', '.obj', '.pdb')):
            raise ValueError('Private/generated file found in package inputs: ' + name)
    output = ROOT / 'dist/Prometheus-Unlock-source.zip'
    output.parent.mkdir(exist_ok=True)
    pending = output.with_suffix('.zip.pending')
    with zipfile.ZipFile(pending, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(files):
            archive.write(ROOT / path, 'Prometheus Unlock/' + path.as_posix())
    with zipfile.ZipFile(pending) as archive:
        if archive.testzip() is not None:
            raise ValueError('Release archive integrity verification failed')
    pending.replace(output)
    print(output)

if __name__ == '__main__':
    main()
