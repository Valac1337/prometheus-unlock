# SPDX-License-Identifier: GPL-2.0-only
[CmdletBinding()]
param([switch]$CheckOnly, [switch]$InstallDependencies, [switch]$SkipDownloads, [switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/gui/prerequisites.ps1"

function Get-Prerequisites {
    [pscustomobject]@{
        Python = Find-PrometheusPython
        SevenZip = Find-PrometheusSevenZip
        Cpp = Find-PrometheusCpp
    }
}
try {
    if (![Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        throw 'Prometheus Unlock requires x64 Windows.'
    }
    $requirements = Get-Prerequisites
    Write-Host 'Prometheus Unlock setup' -ForegroundColor Cyan
    $requirements | Format-List
    $missing = @()
    if (!$requirements.Python) { $missing += 'Python.Python.3.14' }
    if (!$requirements.SevenZip) { $missing += '7zip.7zip' }
    if (!$requirements.Cpp) { $missing += 'Microsoft.VisualStudio.2022.BuildTools' }
    if ($CheckOnly) {
        if ($missing.Count) { Write-Host ('Missing packages: ' + ($missing -join ', ')); exit 1 }
        Write-Host 'Prerequisites found. The build tests will verify SDK and compiler compatibility.'
        exit 0
    }
    if ($missing.Count) {
        Write-Host ('Required packages: ' + ($missing -join ', '))
        Write-Host 'Visual Studio C++ Build Tools includes the recommended Windows SDK. Its download may be several GB.'
        if (!$InstallDependencies) {
            $answer = Read-Host 'Install these packages through Windows Package Manager? Type Y to continue'
            if ($answer -notmatch '^[Yy]$') { throw 'Setup stopped. See INSTALL.md for manual dependency installation.' }
        }
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (!$winget) { throw 'Windows Package Manager is unavailable. Install Microsoft App Installer or follow INSTALL.md, then rerun setup.' }
        foreach ($package in $missing) {
            $options = @('install', '--id', $package, '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements')
            if ($package -eq 'Microsoft.VisualStudio.2022.BuildTools') {
                $options += @('--override', '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended')
            }
            & $winget.Source @options
            if ($LASTEXITCODE -notin @(0, 3010)) { throw "Package installation stopped for $package (exit $LASTEXITCODE). Review the installer output." }
        }
        $requirements = Get-Prerequisites
        if (!$requirements.Python -or !$requirements.SevenZip -or !$requirements.Cpp) {
            throw 'A required component is still missing. Restart Windows if requested by an installer, then rerun setup. See INSTALL.md for repair steps.'
        }
    }
    if (!$SkipDownloads) {
        & $requirements.Python -I -u "$PSScriptRoot/gui/setup.py"
        if ($LASTEXITCODE -ne 0) { throw 'Build-input preparation failed. Review the output and rerun setup after resolving the cause.' }
    }
    Write-Host 'Setup finished. Open Launch Prometheus Unlock.cmd to use the GUI.' -ForegroundColor Green
    if (!$NoLaunch) { & "$PSScriptRoot/Launch.ps1" }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
