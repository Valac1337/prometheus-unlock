# SPDX-License-Identifier: GPL-2.0-only
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("prometheus desktop ' & " + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
Expand-Archive -LiteralPath "$repo/dist/Prometheus-Unlock-Windows-x64.zip" -DestinationPath $testRoot
$payload = Join-Path $testRoot 'Prometheus Unlock'
foreach ($name in @('Setup','PrometheusUnlock')) {
    foreach ($option in @('--check','--smoke-test')) {
        $process = Start-Process -FilePath "$payload/$name.exe" -ArgumentList $option -PassThru
        if (!$process.WaitForExit(60000)) { $process.Kill(); throw "Timed out: $name $option" }
        if ($process.ExitCode -ne 0) { throw "Failed: $name $option (exit $($process.ExitCode))" }
    }
}
$isolated = Join-Path $testRoot 'isolated'
New-Item -ItemType Directory -Path $isolated | Out-Null
Copy-Item -LiteralPath "$payload/PrometheusUnlock.exe" -Destination $isolated
$process = Start-Process -FilePath "$isolated/PrometheusUnlock.exe" -ArgumentList '--check' -PassThru
if (!$process.WaitForExit(10000)) { $process.Kill(); throw 'Missing-payload test timed out' }
if ($process.ExitCode -ne 1) { throw 'Isolated EXE must reject missing support files' }
Write-Output 'PASS: both EXEs validated and opened the real GUI from the extracted Windows ZIP, including a path with spaces, an apostrophe and ampersand. Missing-payload rejection passed. Hardware scanning and backend actions disabled for smoke tests.'
