# SPDX-License-Identifier: GPL-2.0-only
"""Windows GUI for the source-bound GPU unlock workflow. Python 3.14+."""
import json
import msvcrt
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import messagebox, simpledialog, ttk

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent
GPU_NAMES = {'220410de': 'RTX 3090', '220310de': 'RTX 3090 Ti',
             '248710de': 'RTX 3060 12GB (GA104)', '250410de': 'RTX 3060 12GB (GA106)',
             '24c910de': 'RTX 3060 Ti 8GB', '248410de': 'RTX 3070 8GB',
             '220a10de': 'RTX 3080 12GB'}

def support_rows():
    envelope = json.loads((ROOT / 'research/profile/proven.json').read_text())
    rows = [dict(model=GPU_NAMES.get(pci, pci), pci=pci[:4].upper(), family=chip['family'],
                 status='Automatic candidate', detail='Exact PCI ID admitted by the bundled generator. Firmware, display layout, two captures and host tests must also pass.')
            for chip in envelope['chips'] for pci in chip['pci_memory']]
    catalog = json.loads((HERE / 'gpu-catalog.json').read_text(encoding='utf-8'))
    rows.extend(catalog['additional_entries'])
    return rows

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title('Prometheus Unlock')
        self.geometry('1080x800')
        self.minsize(900, 700)
        self.events = queue.Queue()
        self.busy = False
        self.drives = []
        self.buttons = []
        self.protocol('WM_DELETE_WINDOW', self.close)
        style = ttk.Style(self)
        style.theme_use('clam')
        style.configure('.', font=('Segoe UI', 10))
        style.configure('Title.TLabel', font=('Segoe UI', 23, 'bold'))
        style.configure('TButton', padding=(12, 8))
        outer = ttk.Frame(self, padding=22)
        outer.pack(fill='both', expand=True)
        ttk.Label(outer, text='Prometheus Unlock', style='Title.TLabel').pack(anchor='w')
        ttk.Label(outer, text='Build a USB unlock for your own hardware', padding=(0, 5, 0, 15)).pack(anchor='w')
        tabs = ttk.Notebook(outer)
        tabs.pack(fill='both', expand=True)
        workflow = ttk.Frame(tabs, padding=16)
        support = ttk.Frame(tabs, padding=16)
        guide = ttk.Frame(tabs, padding=16)
        startup = ttk.Frame(tabs, padding=16)
        tabs.add(workflow, text='Prepare and build')
        tabs.add(support, text='GPU compatibility')
        tabs.add(guide, text='Step-by-step guide')
        tabs.add(startup, text='Automatic startup')
        ttk.Label(startup, text='Reapply the unlock at startup', font=('Segoe UI', 17, 'bold')).pack(anchor='w')
        ttk.Label(startup, text='USB stays connected. The firmware runs your validated unlock before Windows on a cold boot. Use the same tested monitor layout. Restart, sleep and GPU resets can clear the unlock.', wraplength=880).pack(anchor='w', pady=14)
        ttk.Label(startup, text='Select the USB in Prepare and build. Run this GUI as administrator for boot changes. Register a test entry first, fully shut down and boot that named entry, then return here after Windows starts successfully.', wraplength=880).pack(anchor='w', pady=10)
        for label, action in [('Show startup settings', 'StartupStatus'), ('Register test boot entry…', 'RegisterStartup'), ('Enable automatic USB startup…', 'EnableStartup'), ('Restore Windows first…', 'DisableStartup'), ('Remove test boot entry…', 'RemoveStartup')]:
            self.button(startup, label, lambda a=action: self.startup_action(a)).pack(anchor='w', pady=7)
        ttk.Label(startup, text='If a boot stays black, fully power off, remove the USB and select Windows Boot Manager. Restore Windows first also works when the USB is absent. Logs and saved recovery settings are kept in ProgramData\\PrometheusUnlock.', wraplength=880).pack(anchor='w', pady=20)
        ttk.Label(startup, text='This option automates the existing USB route. Internal-drive installation and three-monitor boot support require separate hardware validation. Results appear in Prepare and build.', wraplength=880).pack(anchor='w')
        self.status = tk.StringVar(value='Refresh hardware to begin. Existing USB contents stay in place until you choose an action.')
        ttk.Label(workflow, textvariable=self.status, wraplength=920).pack(anchor='w', pady=(0, 12))
        row = ttk.Frame(workflow)
        row.pack(fill='x')
        ttk.Label(row, text='USB drive').pack(side='left', padx=(0, 10))
        self.drive = ttk.Combobox(row, state='readonly', width=65)
        self.drive.pack(side='left', fill='x', expand=True)
        self.button(row, 'Refresh hardware', self.inventory).pack(side='left', padx=8)
        actions = ttk.Frame(workflow)
        actions.pack(fill='x', pady=14)
        steps = [
            ('1  Download build inputs', self.setup),
            ('2  Format USB…', self.format_usb),
            ('3  Prepare capture USB…', lambda: self.action('Probe')),
            ('4  Check two captures', self.check),
            ('5  Validate and build', lambda: self.action('Build')),
            ('6  Write unlock to USB…', lambda: self.action('Stage')),
            ('Read latest boot result', self.read_logs),
        ]
        for index, (label, command) in enumerate(steps):
            self.button(actions, label, command).grid(row=index // 3, column=index % 3, padx=4, pady=4, sticky='ew')
        for column in range(3):
            actions.columnconfigure(column, weight=1)
        self.progress = ttk.Progressbar(workflow, mode='indeterminate')
        self.progress.pack(fill='x', pady=(0, 8))
        self.output = tk.Text(workflow, wrap='word', bg='#142029', fg='#e3edf4', font=('Consolas', 10), height=18, state='disabled')
        self.output.pack(fill='both', expand=True)
        self.output_scroll = ttk.Scrollbar(self.output, command=self.output.yview)
        self.output_scroll.pack(side='right', fill='y')
        self.output.configure(yscrollcommand=self.output_scroll.set)
        ttk.Label(support, text='GPU compatibility catalog', font=('Segoe UI', 16, 'bold')).pack(anchor='w')
        ttk.Label(support, text='Automatic candidates come directly from the Windows generator. Select a row for its exact limits. Catalog entries with other statuses cannot be enabled through this GUI.', wraplength=900).pack(anchor='w', pady=12)
        self.catalog = support_rows()
        search_row = ttk.Frame(support)
        search_row.pack(fill='x', pady=(0, 10))
        ttk.Label(search_row, text='Find GPU').pack(side='left', padx=(0, 8))
        self.gpu_search = tk.StringVar()
        ttk.Entry(search_row, textvariable=self.gpu_search).pack(side='left', fill='x', expand=True)
        self.gpu_filter = ttk.Combobox(search_row, state='readonly', values=['All statuses', 'Automatic candidate', 'Fixed upstream profile', 'Linux source only', 'Outside automatic route', 'Unsupported'], width=26)
        self.gpu_filter.set('All statuses')
        self.gpu_filter.pack(side='left', padx=8)
        self.gpu_table = ttk.Treeview(support, columns=('gpu', 'pci', 'chip', 'status'), show='headings', height=13)
        for name, label, width in [('gpu', 'GPU', 260), ('pci', 'Device ID', 95), ('chip', 'Family', 100), ('status', 'Windows workflow', 210)]:
            self.gpu_table.heading(name, text=label)
            self.gpu_table.column(name, width=width)
        self.gpu_table.pack(fill='both', expand=True)
        self.gpu_detail = tk.StringVar(value='Select a GPU to see compatibility details.')
        ttk.Label(support, textvariable=self.gpu_detail, wraplength=900).pack(anchor='w', pady=12)
        self.gpu_search.trace_add('write', self.filter_gpus)
        self.gpu_filter.bind('<<ComboboxSelected>>', self.filter_gpus)
        self.gpu_table.bind('<<TreeviewSelect>>', self.select_gpu)
        self.filter_gpus()
        self.button(support, 'Open full port compatibility guide', lambda: os.startfile(ROOT / 'docs/COMPATIBILITY.en.md')).pack(anchor='w')
        instructions = tk.Text(guide, wrap='word', font=('Segoe UI', 11), padx=12, pady=12)
        instructions.insert('1.0', (HERE / 'HOW-TO.txt').read_text(encoding='utf-8'))
        instructions.configure(state='disabled')
        instructions.pack(fill='both', expand=True)
        self.after(100, self.poll)
        self.inventory()

    def button(self, parent, text, command):
        button = ttk.Button(parent, text=text, command=command)
        self.buttons.append(button)
        return button

    def filter_gpus(self, *_):
        self.gpu_table.delete(*self.gpu_table.get_children())
        query = self.gpu_search.get().casefold()
        status = self.gpu_filter.get()
        for index, row in enumerate(self.catalog):
            if query not in (row['model'] + ' ' + row.get('pci', '') + ' ' + row['family']).casefold():
                continue
            if status != 'All statuses' and row['status'] != status:
                continue
            self.gpu_table.insert('', 'end', iid=str(index), values=(row['model'], row.get('pci', '—'), row['family'], row['status']))

    def select_gpu(self, *_):
        selection = self.gpu_table.selection()
        if selection:
            self.gpu_detail.set(self.catalog[int(selection[0])]['detail'])

    def log(self, text):
        self.output.configure(state='normal')
        self.output.insert('end', text + '\n')
        self.output.see('end')
        self.output.configure(state='disabled')

    def ps(self, action, *arguments):
        return [str(Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'),
                '-NoProfile', '-File', str(HERE / 'backend.ps1'), '-Action', action, *arguments]

    def run(self, command, kind='operation'):
        if self.busy:
            return
        self.busy = True
        for button in self.buttons:
            button.configure(state='disabled')
        self.drive.configure(state='disabled')
        self.progress.start()
        self.status.set('Working. Build and firmware replay can take several minutes.')
        def worker():
            lines = []
            try:
                with subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      text=True, encoding='utf-8', errors='replace',
                                      creationflags=subprocess.CREATE_NO_WINDOW) as process:
                    for line in process.stdout:
                        lines.append(line)
                        if kind != 'inventory':
                            self.events.put(('line', line.rstrip()))
                    code = process.wait()
                self.events.put(('done', kind, code, ''.join(lines)))
            except Exception as error:
                self.events.put(('done', kind, 1, str(error)))
        threading.Thread(target=worker, daemon=True).start()

    def poll(self):
        while not self.events.empty():
            event = self.events.get()
            if event[0] == 'line':
                self.log(event[1])
                continue
            _, kind, code, output = event
            self.busy = False
            self.progress.stop()
            for button in self.buttons:
                button.configure(state='normal')
            self.drive.configure(state='readonly')
            self.status.set('Completed. Read the result below.' if code == 0 else 'Stopped. Review the error below before continuing.')
            if kind == 'inventory' and code == 0:
                try:
                    report = json.loads(output.lstrip('\ufeff'))
                    self.drives = report['Usb']
                    self.drive['values'] = [f"{d['Drive']}:  {d['Name']}  {d['Size'] / 1e9:.1f} GB  {d['FileSystem']}" for d in self.drives]
                    self.drive.set('')
                    if self.drives:
                        self.drive.current(0)
                    for gpu in report['Gpus']:
                        self.log(f"GPU: {gpu['Name']} — driver {gpu['DriverVersion']}")
                    for board in report['Board']:
                        self.log(f"Motherboard: {board['Manufacturer']} {board['Product']}")
                    self.log('Secure Boot: ' + report['SecureBoot'])
                    self.log('Windows encryption: ' + report['Encryption'])
                    self.log(f"Found {len(self.drives)} USB volumes. Verify the selected drive before any write action.")
                except (ValueError, KeyError) as error:
                    self.log(f'Could not parse hardware inventory: {error}\n{output}')
            elif code != 0:
                self.log(output[-3000:])
        self.after(100, self.poll)

    def selected(self):
        index = self.drive.current()
        if index < 0 or index >= len(self.drives):
            messagebox.showerror('Choose a USB', 'Refresh hardware and select a USB drive.')
            return None
        return self.drives[index]

    def inventory(self):
        self.run(self.ps('Inventory'), 'inventory')

    def setup(self):
        self.run([sys.executable, '-I', '-u', str(HERE / 'setup.py')])

    def startup_action(self, action):
        if action in ('StartupStatus', 'DisableStartup', 'RemoveStartup'):
            if action == 'DisableStartup' and not messagebox.askokcancel('Restore normal startup',
                    'Put Windows Boot Manager first and restore the saved Fast Startup setting? This works without the USB.'):
                return
            if action == 'RemoveStartup' and not messagebox.askokcancel('Remove test boot entry',
                    'Restore Windows-first boot and remove the entry owned by Prometheus Unlock? This allows registering a new build. Recovery state is archived.'):
                return
            self.run(self.ps(action))
            return
        drive = self.selected()
        if not drive:
            return
        prompt = ('Add a test entry at the end of the firmware boot menu? After registration, fully shut down and select Prometheus Unlock USB - EXPERIMENTAL once.'
                  if action == 'RegisterStartup' else
                  'Confirm that you booted the registered test entry and Windows returned successfully with the same monitor layout. Enable it first in the firmware boot order and disable Windows Fast Startup? Keep the USB connected. Hardware reliability across restarts and sleep is unverified.')
        if messagebox.askokcancel('Automatic USB startup', prompt):
            self.run(self.ps(action, '-Drive', drive['Drive'], '-DiskIdentity', drive['Identity']))

    def format_usb(self):
        drive = self.selected()
        if not drive:
            return
        confirmation = simpledialog.askstring('Erase selected USB volume',
            f"Erase every file on {drive['Drive']}: ({drive['Name']}, {drive['Size'] / 1e9:.1f} GB)?\nType ERASE {drive['Drive']} to confirm.")
        if confirmation == 'ERASE ' + drive['Drive']:
            self.run(self.ps('Format', '-Drive', drive['Drive'], '-DiskIdentity', drive['Identity']))

    def action(self, action):
        drive = self.selected()
        if not drive:
            return
        if action == 'Probe' and not messagebox.askokcancel('Prepare capture USB',
                'This replaces the USB boot program with the read-only capture tool and archives existing captures. Use this when starting a fresh pair of captures. Continue?'):
            return
        if action == 'Stage' and not messagebox.askokcancel('Install experimental unlock on USB',
                'The next USB boot will attempt GPU register writes and may leave a black screen. Host tests cannot guarantee hardware safety. Use the captured monitor setup. On failure, fully power off, remove USB and boot Windows normally. Continue?'):
            return
        self.run(self.ps(action, '-Drive', drive['Drive'], '-DiskIdentity', drive['Identity'], '-Python', sys.executable))

    def check(self):
        drive = self.selected()
        if drive:
            self.run([sys.executable, '-I', str(ROOT / 'research/profile/check-compatibility.py'),
                      drive['Drive'] + ':\\RTX3090-UNLOCK'])

    def read_logs(self):
        drive = self.selected()
        if not drive:
            return
        folder = Path(drive['Drive'] + ':\\RTX3090-UNLOCK')
        reports = sorted(folder.glob('AUTO*/REPORT.TXT'))
        wrappers = sorted(folder.glob('HLS*.TXT'))
        if not reports:
            self.log('No unlock report found. Capture files are checked with Check two captures.')
            return
        for path in [reports[-1], *wrappers[-1:]]:
            self.log(str(path))
            self.log('\n'.join(path.read_text(errors='replace').splitlines()[-20:]))
        self.log('These are saved boot logs. Confirm Windows returned during that boot; a historical log cannot establish current unlock status.')

    def close(self):
        if self.busy:
            messagebox.showinfo('Operation running', 'Wait for the current operation to finish before closing.')
            return
        self.destroy()

    def report_callback_exception(self, exception_type, value, traceback):
        messagebox.showerror('Operation could not complete', str(value))

if __name__ == '__main__':
    if sys.version_info < (3, 14):
        raise SystemExit('Python 3.14 or newer is required. See gui/README.md.')
    # One GUI per source tree prevents overlapping profile generation and USB writes.
    lock = (HERE / '.gui.lock').open('a+b')
    lock.seek(0)
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        raise SystemExit('This source tree already has a running GUI.')
    App().mainloop()
