# SPDX-License-Identifier: GPL-2.0-only
# Execute the real installer against fake prerequisites and package installs.
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('prometheus-installer-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory (Join-Path $root 'gui') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'Install.ps1') -Destination $root
@'
function Find-PrometheusPython { if (Test-Path "$PSScriptRoot/Python.Python.3.14") { 'fake-python' } }
function Find-PrometheusSevenZip { if (Test-Path "$PSScriptRoot/7zip.7zip") { 'fake-7zip' } }
function Find-PrometheusCpp { if (Test-Path "$PSScriptRoot/Microsoft.VisualStudio.2022.BuildTools") { 'fake-cpp' } }
function Get-Command {
    param([string]$Name, $ErrorAction)
    if ($Name -ne 'winget') { throw 'Unexpected command lookup' }
    [pscustomobject]@{ Source = "$PSScriptRoot/fake-winget.ps1" }
}
'@ | Set-Content (Join-Path $root 'gui/prerequisites.ps1')
@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
if (Test-Path "$PSScriptRoot/fail") { $global:LASTEXITCODE = 5; return }
$id = $Arguments[[array]::IndexOf($Arguments, '--id') + 1]
$Arguments | ConvertTo-Json | Set-Content "$PSScriptRoot/$id.arguments.json"
New-Item -ItemType File -Path "$PSScriptRoot/$id" -Force | Out-Null
$global:LASTEXITCODE = 0
'@ | Set-Content (Join-Path $root 'gui/fake-winget.ps1')
$powershell = "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe"
& $powershell -NoProfile -ExecutionPolicy Bypass -File "$root/Install.ps1" -CheckOnly | Out-Null
if ($LASTEXITCODE -ne 1) { throw 'Missing prerequisites should fail the check.' }
New-Item -ItemType File "$root/gui/fail" | Out-Null
& $powershell -NoProfile -ExecutionPolicy Bypass -File "$root/Install.ps1" -InstallDependencies -SkipDownloads -NoLaunch | Out-Null
if ($LASTEXITCODE -ne 1) { throw 'Package installation failure was ignored.' }
Remove-Item -LiteralPath "$root/gui/fail"
& $powershell -NoProfile -ExecutionPolicy Bypass -File "$root/Install.ps1" -InstallDependencies -SkipDownloads -NoLaunch | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Simulated dependency installation failed.' }
foreach ($id in @('Python.Python.3.14','7zip.7zip','Microsoft.VisualStudio.2022.BuildTools')) {
    $arguments = Get-Content "$root/gui/$id.arguments.json" -Raw | ConvertFrom-Json
    if ($arguments[0] -ne 'install' -or $arguments -notcontains '--exact' -or $arguments -notcontains $id) { throw 'Unexpected package arguments.' }
}
$cpp = Get-Content "$root/gui/Microsoft.VisualStudio.2022.BuildTools.arguments.json" -Raw | ConvertFrom-Json
if ($cpp -notcontains '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended') { throw 'C++ workload option was split or lost.' }
& $powershell -NoProfile -ExecutionPolicy Bypass -File "$root/Install.ps1" -CheckOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Installed prerequisites should pass.' }
'PASS installer check-only, package failure, missing-dependency installation, quoted C++ workload and repeat detection. Package installations simulated.'
