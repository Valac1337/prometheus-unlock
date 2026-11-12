# SPDX-License-Identifier: GPL-2.0-only
"""Exercise GUI startup commands without launching a backend or altering boot settings."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('prometheus_gui', Path(__file__).with_name('app.py'))
gui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gui)


class StartupUiTests(unittest.TestCase):
    def setUp(self):
        with patch.object(gui.App, 'inventory'):
            self.app = gui.App()
        self.app.withdraw()
        self.app.drives = [{'Drive': 'G', 'Identity': 'expected-usb'}]
        self.app.drive['values'] = ['G: Test USB']
        self.app.drive.current(0)
        self.calls = []
        self.app.run = lambda command: self.calls.append(command)

    def tearDown(self):
        self.app.destroy()

    def test_confirmation_cancel_prevents_registration(self):
        with patch.object(gui.messagebox, 'askokcancel', return_value=False):
            self.app.startup_action('RegisterStartup')
        self.assertEqual(self.calls, [])

    def test_enable_binds_selected_disk_identity(self):
        with patch.object(gui.messagebox, 'askokcancel', return_value=True):
            self.app.startup_action('EnableStartup')
        command = self.calls[0]
        self.assertEqual(command[command.index('-Action') + 1], 'EnableStartup')
        self.assertEqual(command[command.index('-Drive') + 1], 'G')
        self.assertEqual(command[command.index('-DiskIdentity') + 1], 'expected-usb')

    def test_recovery_available_without_usb(self):
        self.app.drives = []
        self.app.drive.set('')
        with patch.object(gui.messagebox, 'askokcancel', return_value=True):
            self.app.startup_action('DisableStartup')
        self.assertIn('DisableStartup', self.calls[0])
        self.assertNotIn('-Drive', self.calls[0])

    def test_status_available_without_usb(self):
        self.app.drives = []
        self.app.drive.set('')
        self.app.startup_action('StartupStatus')
        self.assertIn('StartupStatus', self.calls[0])

    def test_catalog_filter_keeps_support_levels_separate(self):
        self.app.gpu_filter.set('Automatic candidate')
        self.app.filter_gpus()
        envelope = gui.json.loads((gui.ROOT / 'research/profile/proven.json').read_text())
        expected = sum(len(chip['pci_memory']) for chip in envelope['chips'])
        self.assertEqual(len(self.app.gpu_table.get_children()), expected)
        self.app.gpu_filter.set('All statuses')
        self.app.gpu_search.set('4090')
        rows = self.app.gpu_table.get_children()
        self.assertEqual(len(rows), 2)
        for row in rows:
            self.assertEqual(self.app.gpu_table.item(row, 'values')[-1], 'Linux source only')


if __name__ == '__main__':
    unittest.main()
