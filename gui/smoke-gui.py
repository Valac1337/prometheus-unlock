# SPDX-License-Identifier: GPL-2.0-only
"""Open and close the actual GUI without hardware discovery or backend actions."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('prometheus_gui_smoke', Path(__file__).with_name('app.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.App.inventory = lambda self: None
app = module.App()
app.title('Prometheus Unlock - launch test')
app.after(700, app.destroy)
app.mainloop()
