# SPDX-License-Identifier: GPL-2.0-only
"""Audit the explicit public source list before packaging or publication."""
import json
import hashlib
from pathlib import Path, PureWindowsPath
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# Reviewed PNG export contains only image/color/dimension chunks, no personal metadata.
PUBLIC_IMAGES = {'docs/images/prometheus-logo.png': '692e6cd4f436eed824084be568a2e5b2c131b83a7ee90af6656db845981e662f'}
PRIVATE_DIRECTORIES = ('research/profile/local/', 'assets/', 'local-tools/', 'firmware-inputs/',
                       'firmware-source/', 'dist/', '.git/', '__pycache__/')
PRIVATE_NAMES = {'profile-local.h', 'platform-config.h', 'generated.h', '.gui.lock', 'REPORT.TXT'}
BINARY_SUFFIXES = {'.efi', '.exe', '.dll', '.bin', '.obj', '.pdb', '.pyc', '.zip', '.key', '.pem', '.log'}
SECRET_PATTERNS = {
    'private key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'access token': re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})\b'),
    'OpenAI-style secret': re.compile(r'\bsk-(?:proj-)?[A-Za-z0-9_-]{40,}\b'),
}
HOME_PATH = re.compile(r'(?i)[A-Z]:[\\/]+Users[\\/]+([^\\/\s\x22\x27]+)')
PLACEHOLDER_USERS = {'private', 'secret', 'example', 'user', 'username', '<username>', 'public'}


def public_files(root=ROOT):
    names = json.loads((root / 'SOURCE-FILES.json').read_text(encoding='utf-8'))
    if not isinstance(names, list) or any(not isinstance(name, str) for name in names):
        raise ValueError('Source list must contain strings')
    if len(names) != len(set(names)):
        raise ValueError('Duplicate public source path')
    for name in names:
        path = Path(name)
        full = root / path
        if (path.is_absolute() or PureWindowsPath(name).is_absolute() or '..' in path.parts
                or ':' in name or '\\' in name or not full.resolve().is_relative_to(root.resolve())):
            raise ValueError('Unsafe public source path: ' + name)
        if (name.startswith(PRIVATE_DIRECTORIES) or path.name in PRIVATE_NAMES or path.name.startswith('.env')
                or path.suffix.lower() in BINARY_SUFFIXES
                or re.fullmatch(r'(?:DIAG|HLS|IMG)\d+\.[A-Za-z]+', path.name, re.I)):
            raise ValueError('Private/generated source entry: ' + name)
        if not full.is_file() or full.is_symlink():
            raise ValueError('Missing/indirect public source: ' + name)
        yield name, full


def audit(root=ROOT):
    files = list(public_files(root))
    findings = []
    for name, path in files:
        if name in PUBLIC_IMAGES:
            if hashlib.sha256(path.read_bytes()).hexdigest() != PUBLIC_IMAGES[name]:
                findings.append(name + ": image changed; review pixels and metadata before updating approved hash")
            continue
        try:
            text = path.read_text(encoding='utf-8-sig')
        except UnicodeError:
            findings.append(name + ': unexpected binary/non-UTF8 source')
            continue
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(text):
                findings.append(name + ': ' + label)
        if any(match.group(1).casefold() not in PLACEHOLDER_USERS for match in HOME_PATH.finditer(text)):
            findings.append(name + ': personal home-directory path')
    if findings:
        raise ValueError('\n'.join(findings))
    if (root / '.git').exists():
        tracked = set(subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().split('\0')) - {''}
        extra = tracked - {name for name, _ in files}
        if extra:
            raise ValueError('Tracked files outside the audited source list: ' + ', '.join(sorted(extra)))
    print(f'PASS public-source audit: {len(files)} files; no detected credentials, personal home paths or generated private files.')
    return files


if __name__ == '__main__':
    audit()
