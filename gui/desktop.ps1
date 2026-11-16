# SPDX-License-Identifier: GPL-2.0-only
param([ValidateSet('Launch','Setup','SmokeTest')][string]$Mode = 'Launch')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
try {
    if ($Mode -eq 'Setup') {
        & "$repo/Install.ps1"
        exit $LASTEXITCODE
    }
    . "$PSScriptRoot/prerequisites.ps1"
    $python = Find-PrometheusPython
    if (!$python) {
        if ($Mode -eq 'SmokeTest') { exit 2 }
        Add-Type -AssemblyName System.Windows.Forms
        $answer = [System.Windows.Forms.MessageBox]::Show('Python 3.14 with Tcl/Tk is required. Open Setup.exe now to install the prerequisites?', 'Prometheus Unlock setup', 'YesNo', 'Information')
        if ($answer -eq 'Yes') {
            Start-Process -FilePath (Join-Path $repo 'Setup.exe')
        }
        exit 0
    }
    $script = if ($Mode -eq 'SmokeTest') { 'smoke-gui.py' } else { 'app.py' }
    & $python -I (Join-Path $PSScriptRoot $script)
    exit $LASTEXITCODE
} catch {
    Write-Error $_
    exit 1
}
