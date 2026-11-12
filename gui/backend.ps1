# SPDX-License-Identifier: GPL-2.0-only
[CmdletBinding()]
param(
    [ValidateSet('Inventory','Format','Probe','Build','Stage','StartupStatus','RegisterStartup','EnableStartup','DisableStartup','RemoveStartup')][string]$Action,
    [ValidatePattern('^[D-Z]$')][string]$Drive,
    [string]$DiskIdentity,
    [string]$Python
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if ($Action -in @('StartupStatus','RegisterStartup','EnableStartup','DisableStartup','RemoveStartup')) {
    . "$PSScriptRoot/startup.ps1"
    Invoke-PrometheusStartup -Action $Action -Repo $repo -Drive $Drive -DiskIdentity $DiskIdentity
    exit 0
}
function Get-Usb {
    $partition = Get-Partition -DriveLetter $Drive -ErrorAction Stop
    $disk = $partition | Get-Disk
    if ($disk.BusType -ne 'USB' -or $disk.IsBoot -or $disk.IsSystem -or $partition.IsBoot -or $partition.IsSystem -or $disk.UniqueId -cne $DiskIdentity) {
        throw 'The selected USB changed or is a protected disk. Refresh the drive list.'
    }
    return $partition
}
if ($Action -eq 'Inventory') {
    $usb = @(foreach ($disk in Get-Disk | Where-Object BusType -eq USB) {
        if ($disk.IsBoot -or $disk.IsSystem) { continue }
        foreach ($part in $disk | Get-Partition | Where-Object DriveLetter) {
            $vol = $part | Get-Volume
            [pscustomobject]@{ Drive = [string]$part.DriveLetter; Identity = $disk.UniqueId; Name = $disk.FriendlyName; Size = $vol.Size; FileSystem = $vol.FileSystem }
        }
    })
    $secureBoot = 'Unknown (requires administrator access)'
    try { $secureBoot = [string](Confirm-SecureBootUEFI) } catch {}
    $encryption = 'Unknown (check Manage BitLocker)'
    try { $encryption = [string](Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop).VolumeStatus } catch {}
    [pscustomobject]@{
        Usb = $usb
        Gpus = @(Get-CimInstance Win32_VideoController | Select-Object Name,PNPDeviceID,DriverVersion)
        Board = @(Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer,Product)
        SecureBoot = $secureBoot
        Encryption = $encryption
    } | ConvertTo-Json -Depth 5
    exit 0
}
$partition = Get-Usb
$startupStatePath = Join-Path $env:ProgramData 'PrometheusUnlock/usb-startup.json'
if ($Action -in @('Format','Probe','Stage') -and (Test-Path -LiteralPath $startupStatePath)) {
    $startupState = Get-Content -LiteralPath $startupStatePath -Raw | ConvertFrom-Json
    if ($startupState.Package.Disk -ceq $DiskIdentity -and $startupState.Mode -in @('automatic','enabling')) {
        throw 'Restore Windows first in the Automatic startup tab before changing this boot USB.'
    }
}
foreach ($relative in @('EFI', 'EFI\BOOT', 'EFI\WindowsGPUUnlock', 'RTX3090-UNLOCK', 'RTX3090-UNLOCK\ASSETS', 'RTX3090-UNLOCK\backup')) {
    $target = "$($Drive):\$relative"
    if ((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'A USB destination is a reparse point. Choose ordinary directories on the USB.'
    }
}
if ($Action -eq 'Format') {
    if ($partition.Size -gt 32GB) { throw 'Choose a USB partition of 32 GB or less for FAT32 formatting.' }
    Format-Volume -DriveLetter $Drive -FileSystem FAT32 -NewFileSystemLabel 'GPU-CAPTURE' -Force -Confirm:$false | Out-Null
    if ((Get-Volume -DriveLetter $Drive).FileSystem -ne 'FAT32') { throw 'FAT32 verification failed.' }
    'USB formatted and verified as FAT32.'
    exit 0
}
if ((Get-Volume -DriveLetter $Drive).FileSystem -ne 'FAT32') { throw 'The selected USB must be FAT32.' }
$esp = @(Get-Partition | Where-Object IsSystem)
if ($esp.Count -ne 1 -or !$esp[0].Guid) { throw 'Could not identify one Windows EFI system partition.' }
$clang = Join-Path $repo 'local-tools/llvm20/bin/clang.exe'
$link = Join-Path $repo 'local-tools/llvm20/bin/lld-link.exe'
$assets = Join-Path $repo 'assets'
if ($Action -eq 'Probe') {
    # Build explicitly as observation-only, even when this USB has older captures.
    & "$repo/research/profile/build-probe.ps1" -WindowsEspGuid $esp[0].Guid -Clang $clang -LldLink $link -Python $Python
    if (!$?) { throw 'Probe build failed.' }
    . "$repo/research/profile/probe-manifest.ps1"
    $probe = "$repo/internal-boot/boot/build/probe-generic"
    $manifest = Get-Content "$probe/manifest.json" -Raw | ConvertFrom-Json
    Assert-GuGenericProbeManifest $repo $manifest "$probe/BOOTX64.EFI"
    $captureRoot = "$($Drive):\RTX3090-UNLOCK"
    $archive = Join-Path $captureRoot ('archive-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $archive -Force | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $captureRoot -File) {
        if ($file.Name -match '^(DIAG\d\d\.TXT|IMG\d\d\.BIN|PROM\.BIN)$') {
            Copy-Item -LiteralPath $file.FullName -Destination $archive
            if ((Get-FileHash $file.FullName).Hash -ne (Get-FileHash (Join-Path $archive $file.Name)).Hash) { throw 'Archive verification failed.' }
            Remove-Item -LiteralPath $file.FullName
        }
    }
    $boot = "$($Drive):\EFI\BOOT\BOOTX64.EFI"
    if (Test-Path -LiteralPath $boot) { Copy-Item -LiteralPath $boot -Destination (Join-Path $archive 'BOOTX64.EFI') }
    New-Item -ItemType Directory -Path (Split-Path $boot) -Force | Out-Null
    Copy-Item -LiteralPath "$probe/BOOTX64.EFI" -Destination $boot -Force
    Assert-GuGenericProbeManifest $repo $manifest $boot
    'CAPTURE USB READY. Perform two separate full shutdowns and USB boots. Keep the display connections identical.'
    exit 0
}
if ($Action -eq 'Build') {
    & $Python -I "$repo/research/profile/check-compatibility.py" "$($Drive):\RTX3090-UNLOCK"
    if ($LASTEXITCODE -ne 0) { throw 'Capture compatibility checks did not pass.' }
    & "$repo/research/profile/new-machine.ps1" -Drive $Drive -WindowsEspGuid $esp[0].Guid -Assets $assets -Clang $clang -LldLink $link -Python $Python
    if (!$?) { throw 'Profile, test or build step failed.' }
    exit 0
}
& "$repo/research/headless/stage-usb.ps1" -Drive $Drive -Assets $assets
if (!$?) { throw 'USB staging failed.' }
