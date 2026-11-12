# SPDX-License-Identifier: GPL-2.0-only
"""Download build inputs locally and verify all generated firmware assets."""
import hashlib
import importlib.util
import json
import msvcrt
import os
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
from compression import zstd
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VENDOR = Path(__file__).parent / 'vendor'

def load(name):
    spec = importlib.util.spec_from_file_location(name, VENDOR / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def download(url, path, expected=None):
    if not path.exists() or (expected and sha(path) != expected):
        print('Downloading ' + path.name, flush=True)
        temporary = None
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'Prometheus-Unlock'})
            with urllib.request.urlopen(request, timeout=60) as response:
                if not response.url.startswith('https://'):
                    raise ValueError('HTTPS redirect required')
                with tempfile.NamedTemporaryFile(dir=path.parent, suffix='.partial', delete=False) as output:
                    temporary = Path(output.name)
                    shutil.copyfileobj(response, output)
                    output.flush()
                    os.fsync(output.fileno())
            if expected and sha(temporary) != expected:
                raise ValueError('Downloaded hash mismatch in ' + path.name)
            temporary.replace(path)
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)
    if expected and sha(path) != expected:
        raise ValueError('Hash mismatch in ' + str(path))

def prepare():
    tools = ROOT / 'local-tools'
    inputs = ROOT / 'firmware-inputs'
    assets = ROOT / 'assets'
    for folder in (tools, inputs, assets):
        folder.mkdir(exist_ok=True)
    clang = tools / 'llvm20/bin/clang.exe'
    linker = tools / 'llvm20/bin/lld-link.exe'
    ready_path = tools / 'llvm20/ready.json'
    ready = {}
    if ready_path.exists():
        try:
            ready = json.loads(ready_path.read_text())
        except (ValueError, OSError):
            pass
    complete = all(path.is_file() and ready.get(path.name) == sha(path) for path in (clang, linker))
    if not complete:
        seven = shutil.which('7z') or r'C:\Program Files\7-Zip\7z.exe'
        if not Path(seven).is_file():
            raise RuntimeError('Install 7-Zip from https://www.7-zip.org/ then retry setup.')
        package = tools / 'LLVM-20.1.8-win64.exe'
        download('https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/' + package.name,
                 package, '3197846a2b19063687dd56e93e34cd941e3548d907f23a6131571321bdf9fe7b')
        subprocess.run([seven, 'x', str(package), '-o' + str(tools / 'llvm20'), '-y', '-bso0'], check=True)
        ready_path.write_text(json.dumps({path.name: sha(path) for path in (clang, linker)}), encoding='utf-8')
    subprocess.run([str(clang), '--version'], check=True)
    manifest = json.loads((VENDOR / 'artifacts-610.43.03.json').read_text())
    source = manifest['source_artifacts'][0]
    source_archive = inputs / source['filename']
    download(source['url'], source_archive, source['sha256'])
    source_dir = inputs / 'source'
    source_dir.mkdir(exist_ok=True)
    with tarfile.open(source_archive) as archive:
        archive.extractall(source_dir, filter='data')
    load('extract_boot_assets').extract_assets(source_dir / 'NVIDIA-kernel-module-source-610.43.03', assets)
    installer = inputs / 'NVIDIA-Linux-x86_64-610.43.03-no-compat32.run'
    download('https://download.nvidia.com/XFree86/Linux-x86_64/610.43.03/' + installer.name, installer)
    extract = load('extract_gsp')
    with installer.open('rb') as stream:
        stream.seek(extract.payload_offset(installer))
        with zstd.ZstdFile(stream, 'rb') as decompressed:
            with tarfile.open(fileobj=decompressed, mode='r|') as archive:
                members = extract.read_members(archive, ('firmware/gsp_ga10x.bin', 'LICENSE'))
    generated = {'gsp_ga10x.bin': members['firmware/gsp_ga10x.bin'],
                 'v67-ga102-610.43.03.bin': load('generate_v67').build_payload()}
    for entry in json.loads((ROOT / 'unlock/assets.json').read_text()):
        name = entry['Name']
        data = generated[name] if name in generated else (assets / name).read_bytes()
        if len(data) != entry['Bytes'] or hashlib.sha256(data).hexdigest() != entry['Sha256']:
            raise ValueError('Firmware verification failed for ' + name)
    for name, data in generated.items():
        (assets / name).write_bytes(data)
    (assets / 'NVIDIA-LICENSE').write_bytes(members['LICENSE'])
    print('Compiler and linker ready. All five firmware assets verified. Continue with capture preparation; host tests also require MSVC and a Windows SDK.', flush=True)

def main():
    tools = ROOT / 'local-tools'
    tools.mkdir(exist_ok=True)
    with (tools / 'setup.lock').open('a+b') as lock:
        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise RuntimeError('Another build-input setup is running in this project.') from None
        prepare()

if __name__ == '__main__':
    main()
