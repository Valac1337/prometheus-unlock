# SPDX-License-Identifier: GPL-2.0-only
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/gui/prerequisites.ps1"
$python = Find-PrometheusPython
if (!$python) { Write-Error 'Python 3.14 with Tcl/Tk is required. Run Install Prometheus Unlock.cmd first.'; exit 1 }
& $python -I "$PSScriptRoot/gui/app.py"
exit $LASTEXITCODE
