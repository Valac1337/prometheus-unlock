# Contributing

Prometheus Unlock is an experimental Windows GUI and setup layer around the credited upstream GPU unlock implementation. Keep changes scoped and preserve upstream attribution.

## Validate a change

Use Python 3.14 on Windows. Run the following commands from the project root.

```powershell
python -m unittest discover -s gui -p "test_*.py" -v
python -m unittest discover -s tools -p "test_*.py" -v
python -m unittest discover -s research/profile -p "test_*.py" -v
powershell -NoProfile -File gui/test-startup.ps1
powershell -NoProfile -File gui/test-installer.ps1
python gui/release_check.py
python gui/package.py
```

The Windows CI workflow runs these checks. PowerShell startup tests simulate BCDEdit and registry behavior. Installer tests simulate package installation. The GUI tests never execute a boot-setting mutation.

## GPU changes

The GUI reads automatic admission from `research/profile/proven.json`. Additional catalog rows in `gui/gpu-catalog.json` are informational and cannot grant automatic support. Any actual admission change needs firmware and topology evidence, corresponding upstream/runtime changes, host replay, and supervised hardware qualification. Include the exact tested source revision and clearly describe what remains untested.

## Public files and privacy

Add intended public files to `SOURCE-FILES.json`. Keep captures, raw logs, PROM/VBIOS dumps, firmware assets, compiled EFI programs, local profiles, recovery keys, local account paths and partition identifiers out of commits and attachments. The release checker audits the source list and rejects tracked files outside it.

Review every diff before committing. Automated scanning catches common patterns and generated artifacts but cannot identify every type of sensitive information. Existing upstream author credits and synthetic privacy-test fixtures are retained intentionally.

Use the bug-report template for GUI/install problems and the compatibility template for reviewed hardware metadata. Share minimal sanitized summaries. Preserve detailed diagnostic files privately.
