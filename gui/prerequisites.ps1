# SPDX-License-Identifier: GPL-2.0-only
function Find-PrometheusPython {
    # Missing interpreters and older Python versions are expected during discovery.
    $ErrorActionPreference = 'Continue'
    $candidates = @()
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        $found = & uv python find 3.14 2>$null
        if ($LASTEXITCODE -eq 0) { $candidates += [string]$found }
    }
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $found = & py -3.14 -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0) { $candidates += [string]$found }
    }
    foreach ($key in @('HKCU:\Software\Python\PythonCore\3.14\InstallPath', 'HKLM:\Software\Python\PythonCore\3.14\InstallPath')) {
        if (Test-Path $key) {
            $installPath = (Get-Item $key).GetValue('')
            if ($installPath) { $candidates += Join-Path $installPath 'python.exe' }
        }
    }
    $candidates += @("$env:LOCALAPPDATA\Programs\Python\Python314\python.exe", "$env:ProgramFiles\Python314\python.exe")
    $command = Get-Command python -ErrorAction SilentlyContinue
    if ($command -and $command.Source -notlike '*\WindowsApps\*') { $candidates += $command.Source }
    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (!(Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        & $candidate -I -c 'import sys, tkinter; from compression import zstd; assert sys.version_info >= (3,14)' 2>$null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    return $null
}

function Find-PrometheusCpp {
    $where = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $where) {
        $result = & $where -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'VC\Auxiliary\Build\vcvars64.bat'
        return $result | Select-Object -First 1
    }
    return $null
}

function Find-PrometheusSevenZip {
    $command = Get-Command 7z -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $path = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
    if (Test-Path -LiteralPath $path) { return $path }
    return $null
}
