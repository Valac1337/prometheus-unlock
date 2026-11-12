# SPDX-License-Identifier: GPL-2.0-only
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('input_setup', HERE / 'setup.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class Response(io.BytesIO):
    url = 'https://example.invalid/test'


class InputDownloadTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.path = self.root / 'input'
        self.digest = hashlib.sha256(b'valid').hexdigest()

    def tearDown(self):
        self.directory.cleanup()

    def test_verified_cache_avoids_network(self):
        self.path.write_bytes(b'valid')
        with patch.object(setup.urllib.request, 'urlopen', side_effect=AssertionError('Network used')):
            setup.download(Response.url, self.path, self.digest)

    def test_bad_download_does_not_replace_cache(self):
        self.path.write_bytes(b'old')
        with patch.object(setup.urllib.request, 'urlopen', return_value=Response(b'bad')):
            with self.assertRaises(ValueError):
                setup.download(Response.url, self.path, self.digest)
        self.assertEqual(self.path.read_bytes(), b'old')
        self.assertEqual(list(self.root.glob('*.partial')), [])

    def test_corrupt_cache_is_repaired(self):
        self.path.write_bytes(b'bad')
        with patch.object(setup.urllib.request, 'urlopen', return_value=Response(b'valid')):
            setup.download(Response.url, self.path, self.digest)
        self.assertEqual(self.path.read_bytes(), b'valid')

    def test_insecure_redirect_refused(self):
        response = Response(b'valid')
        response.url = 'http://example.invalid/test'
        with patch.object(setup.urllib.request, 'urlopen', return_value=response):
            with self.assertRaises(ValueError):
                setup.download(Response.url, self.path, self.digest)
        self.assertFalse(self.path.exists())


class CatalogTests(unittest.TestCase):
    def test_additional_catalog_entries_cannot_grant_automatic_support(self):
        catalog = json.loads((HERE / 'gpu-catalog.json').read_text())
        rows = catalog['additional_entries']
        self.assertGreaterEqual(len(rows), 20)
        self.assertEqual(len({row['model'] for row in rows}), len(rows))
        for row in rows:
            self.assertNotEqual(row['status'], 'Automatic candidate')
            self.assertTrue(row['detail'])


class PublicAuditTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('release_check', HERE / 'release_check.py')
        self.checker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.checker)
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def source_list(self, names):
        (self.root / 'SOURCE-FILES.json').write_text(json.dumps(names))

    def test_rejects_private_capture_and_traversal(self):
        for name in ('research/profile/local/capture.txt', '../outside.txt', 'DIAG0001.TXT'):
            with self.subTest(name=name):
                self.source_list([name])
                with self.assertRaises(ValueError):
                    list(self.checker.public_files(self.root))

    def test_rejects_credentials_and_personal_paths(self):
        self.source_list(['note.txt'])
        for content in ('ghp_' + 'A' * 36, 'C:' + '/Users/' + 'real-person/file.txt'):
            with self.subTest(content_type=content[:4]):
                (self.root / 'note.txt').write_text(content)
                with self.assertRaises(ValueError):
                    self.checker.audit(self.root)

    def test_allows_public_text(self):
        self.source_list(['note.txt'])
        (self.root / 'note.txt').write_text('Public installation instructions')
        self.assertEqual(len(self.checker.audit(self.root)), 1)


if __name__ == '__main__':
    unittest.main()
