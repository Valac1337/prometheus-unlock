# SPDX-License-Identifier: GPL-2.0-only
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw 'Windows .NET Framework 4.x C# compiler is required.' }
$output = Join-Path $repo 'dist\desktop-bin'
$sourceFile = Join-Path $PSScriptRoot 'desktop-launcher.cs'
New-Item -ItemType Directory -Path $output -Force | Out-Null
foreach ($name in @('PrometheusUnlock','Setup')) {
    $options = @('/nologo','/target:winexe','/platform:x64','/optimize+','/debug-','/reference:System.Windows.Forms.dll',("/out:" + (Join-Path $output ($name + ".exe"))))
    if ($name -eq 'Setup') { $options += '/define:SETUP' }
    & $compiler @options $sourceFile
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $name" }
}
Write-Output 'Built x64 .NET Framework launchers. These unsigned EXEs require the complete source payload.'
