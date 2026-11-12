# SPDX-License-Identifier: GPL-2.0-only
# USB boot automation. GPU unlock execution remains in the validated UEFI build.
$script:StartupName = 'Prometheus Unlock USB - EXPERIMENTAL'
$script:StartupPath = '\EFI\BOOT\BOOTX64.EFI'

function Assert-StartupAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Relaunch Prometheus Unlock as administrator for boot-setting changes.' }
}

function Invoke-StartupBcd([string[]]$Arguments) {
    $text = @(& "$env:SystemRoot\System32\bcdedit.exe" @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('BCDEdit failed: ' + ($text -join "`n")) }
    return $text -join "`r`n"
}

function Get-StartupOrder([string]$Text) {
    $match = [regex]::Match($Text, '(?ms)^displayorder\s+(.*?)(?=\r?\n\S|\z)')
    $ids = @([regex]::Matches($match.Groups[1].Value, '\{(?:bootmgr|[0-9a-fA-F-]{36})\}') | ForEach-Object Value)
    if (!$match.Success -or $ids -notcontains '{bootmgr}' -or @($ids | Select-Object -Unique).Count -ne $ids.Count) {
        throw 'Cannot parse firmware boot order. This automation currently requires English BCDEdit output.'
    }
    return $ids
}

function Get-StartupIds([string]$Text) {
    @([regex]::Matches($Text, '(?mi)^identifier\s+(\{[0-9a-f-]{36}\})') | ForEach-Object { $_.Groups[1].Value })
}

function Read-StartupPower {
    $key = Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    $exists = $key.GetValueNames() -contains 'HiberbootEnabled'
    if ($exists -and $key.GetValueKind('HiberbootEnabled') -ne 'DWord') { throw 'Unexpected Fast Startup registry type.' }
    @{ Exists = $exists; Value = $(if ($exists) { [int]$key.GetValue('HiberbootEnabled') } else { $null }) }
}

function Write-StartupPower($Plan) {
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    if ($Plan.Exists) {
        New-ItemProperty $path -Name HiberbootEnabled -PropertyType DWord -Value ([int]$Plan.Value) -Force | Out-Null
    } elseif ((Get-Item $path).GetValueNames() -contains 'HiberbootEnabled') {
        Remove-ItemProperty $path -Name HiberbootEnabled
    }
    $actual = Read-StartupPower
    if ($actual.Exists -ne $Plan.Exists -or ($actual.Exists -and $actual.Value -ne $Plan.Value)) { throw 'Fast Startup verification failed.' }
}

function Save-StartupState([string]$Path, $State) {
    $temporary = $Path + '.pending'
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
    if (Test-Path -LiteralPath $Path) {
        [IO.File]::Replace($temporary, $Path, $Path + '.previous', $true)
    } else {
        [IO.File]::Move($temporary, $Path)
    }
}

function Assert-StartupPackage([string]$Repo, [string]$Drive, [string]$Identity) {
    $part = Get-Partition -DriveLetter $Drive -ErrorAction Stop
    $disk = $part | Get-Disk
    $volume = $part | Get-Volume
    if ($disk.BusType -ne 'USB' -or $disk.UniqueId -cne $Identity -or $disk.IsBoot -or $disk.IsSystem -or
        $part.IsSystem -or $volume.FileSystem -ne 'FAT32' -or !$part.Guid) { throw 'The selected FAT32 USB identity changed.' }
    . "$Repo/internal-boot/unlock/local-profile.ps1"
    $manifest = Get-Content "$Repo/internal-boot/boot/build/headless/usb-manifest.json" -Raw | ConvertFrom-Json
    Assert-GuUsbManifest $Repo $manifest
    $root = "$($Drive):\"
    $files = @(
        @{ Path = 'EFI\BOOT\BOOTX64.EFI'; Hash = $manifest.EfiSha256 },
        @{ Path = 'EFI\WindowsGPUUnlock\UNLOCK-HEADLESS.EFI'; Hash = $manifest.ChildSha256 }
    )
    foreach ($asset in Get-Content "$Repo/unlock/assets.json" -Raw | ConvertFrom-Json) {
        $files += @{ Path = 'RTX3090-UNLOCK\ASSETS\' + $asset.Name; Hash = $asset.Sha256 }
    }
    foreach ($file in $files) {
        if ((Get-FileHash -LiteralPath (Join-Path $root $file.Path)).Hash -ine $file.Hash) { throw ('USB file changed: ' + $file.Path) }
    }
    @{ Partition = [string]$part.Guid; Disk = $Identity; Efi = $manifest.EfiSha256; Child = $manifest.ChildSha256; Profile = $manifest.HardwareProfile }
}

function Assert-StartupEntry([string]$Id, [string]$Drive) {
    $text = Invoke-StartupBcd @('/enum', $Id)
    if ($text -notmatch ('(?mi)^device\s+partition=' + [regex]::Escape($Drive) + ':\s*$') -or
        $text -notmatch ('(?mi)^path\s+' + [regex]::Escape($script:StartupPath) + '\s*$') -or
        $text -notmatch ('(?m)^description\s+' + [regex]::Escape($script:StartupName) + '\s*$')) {
        throw 'Registered boot entry differs from the expected USB loader.'
    }
}

function Set-StartupOrder([string[]]$Ids) {
    $null = Invoke-StartupBcd (@('/set', '{fwbootmgr}', 'displayorder') + $Ids)
    $actual = @(Get-StartupOrder (Invoke-StartupBcd @('/enum', '{fwbootmgr}')))
    if (($actual -join ',') -cne ($Ids -join ',')) { throw 'Firmware boot-order readback failed.' }
}

function Assert-StartupBootProof($State, [string]$Drive) {
    $report = Get-ChildItem "$($Drive):\RTX3090-UNLOCK\AUTO*\REPORT.TXT" -File | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    if (!$report -or $report.LastWriteTimeUtc -lt ([DateTime]::Parse($State.RegisteredUtc).ToUniversalTime())) {
        throw 'Perform a full-shutdown test of the registered entry first. A new successful log is required.'
    }
    $text = Get-Content -LiteralPath $report.FullName -Raw
    if ($text -notmatch '(?m)^FINAL status=0 stage=transaction attempted=1 driver_release=0 clean=1\s*$' -or
        $text -notmatch '(?m)^transaction result=0 containment=0 started=1 quiesced=1 fault=0 retained=0 maps=0 FLR=1\s*$') {
        throw 'Latest unlock report lacks successful transaction and clean cleanup.'
    }
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime()
    if ($boot -lt ([DateTime]::Parse($State.RegisteredUtc).ToUniversalTime())) { throw 'Windows has not booted since test registration.' }
}

function Invoke-PrometheusStartup {
    param([ValidateSet('StartupStatus','RegisterStartup','EnableStartup','DisableStartup','RemoveStartup')][string]$Action,
          [string]$Repo, [string]$Drive, [string]$DiskIdentity)
    $directory = Join-Path $env:ProgramData 'PrometheusUnlock'
    $statePath = Join-Path $directory 'usb-startup.json'
    $state = $null
    if ($Action -eq 'StartupStatus') {
        if (Test-Path -LiteralPath $statePath) { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
        if ($state) { $state | ConvertTo-Json -Depth 8 } else { 'Automatic USB startup has not been registered.' }
        Invoke-StartupBcd @('/enum', '{fwbootmgr}')
        return
    }
    Assert-StartupAdministrator
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $lock = [IO.File]::Open((Join-Path $directory 'startup.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        # Reload after taking the cross-process lock.
        if (Test-Path -LiteralPath $statePath) {
            try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
            catch {
                if ($Action -ne 'DisableStartup') { throw }
                Write-Warning 'Saved startup state is unreadable. Restoring Windows-first boot only; previous Fast Startup setting is unavailable.'
            }
        }
        $firmware = Invoke-StartupBcd @('/enum', '{fwbootmgr}')
        $order = @(Get-StartupOrder $firmware)
        if ($firmware -match '(?mi)^bootsequence\s+') { throw 'A one-time firmware boot is pending. Finish it before changing automatic startup.' }
        $backup = Join-Path $directory ('backups\' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        $null = Invoke-StartupBcd @('/export', (Join-Path $backup 'BCD-export'))
        Invoke-StartupBcd @('/enum', 'firmware') | Set-Content (Join-Path $backup 'firmware-before.txt')
        if ($Action -in @('DisableStartup','RemoveStartup')) {
            # Recovery is independent of USB presence, build inputs and profile validity.
            $removeId = $null
            if ($Action -eq 'RemoveStartup') {
                if (!$state -or $state.Entry -notmatch '^\{[0-9a-fA-F-]{36}\}$') { throw 'A saved owned entry is required for removal. Restore Windows first remains available.' }
                $removeId = $state.Entry
                $ids = @(Get-StartupIds (Invoke-StartupBcd @('/enum', 'all')))
                if ($ids -contains $removeId) {
                    $entry = Invoke-StartupBcd @('/enum', $removeId)
                    if ($entry -notmatch ('(?m)^description\s+' + [regex]::Escape($script:StartupName) + '\s*$') -or
                        $entry -notmatch ('(?mi)^path\s+' + [regex]::Escape($script:StartupPath) + '\s*$')) {
                        throw 'The saved entry was changed by another tool. Restore Windows first and review it manually.'
                    }
                }
            }
            $restored = @('{bootmgr}') + @($order | Where-Object { $_ -ne '{bootmgr}' -and $_ -ne $removeId })
            Set-StartupOrder $restored
            if ($state -and $state.PowerBefore) { Write-StartupPower $state.PowerBefore }
            if ($Action -eq 'RemoveStartup') {
                if ($ids -contains $removeId) { $null = Invoke-StartupBcd @('/delete', $removeId) }
                if (@(Get-StartupIds (Invoke-StartupBcd @('/enum', 'all'))) -contains $removeId) { throw 'Boot-entry deletion readback failed.' }
                Copy-Item -LiteralPath $statePath -Destination (Join-Path $backup 'removed-state.json')
                Remove-Item -LiteralPath $statePath
                'Owned test entry removed. Windows is first. You can register a new validated build.'
                return
            }
            if ($state) { $state.Mode = 'windows-first'; Save-StartupState $statePath $state }
            'Windows Boot Manager is first. Saved Fast Startup setting restored when available.'
            return
        }
        if (Confirm-SecureBootUEFI) { throw 'The experimental USB loader requires Secure Boot off.' }
        $encrypted = Get-BitLockerVolume -MountPoint $env:SystemDrive
        if ([int]$encrypted.VolumeStatus -ne 0 -or [int]$encrypted.ProtectionStatus -ne 0) { throw 'The Windows system drive must be fully decrypted with protection off.' }
        $package = Assert-StartupPackage $Repo $Drive $DiskIdentity
        . "$Repo/internal-boot/install/automatic-policy.ps1"
        if ($Action -eq 'RegisterStartup') {
            if ($state) { throw 'Startup state already exists. Use its test entry, or Restore Windows first and review the saved state before replacing the build.' }
            $all = Invoke-StartupBcd @('/enum', 'all')
            if ($all -match [regex]::Escape($script:StartupName)) { throw 'An existing Prometheus entry lacks registration state. Review it before creating another.' }
            $before = @(Get-StartupIds $all)
            $manager = Invoke-StartupBcd @('/enum', '{bootmgr}')
            if ((Invoke-StartupBcd @('/enum', '{fwbootmgr}')) -cne $firmware) { throw 'Firmware boot order changed during validation. Retry after reviewing settings.' }
            $state = [pscustomobject]@{ Mode = 'registering'; Entry = $null; Package = $package; OrderBefore = $order;
                RegisteredUtc = [DateTime]::UtcNow.ToString('o'); PowerBefore = $null; Backup = $backup }
            Save-StartupState $statePath $state
            try {
                try { $null = Invoke-StartupBcd @('/copy', '{bootmgr}', '/d', $script:StartupName) }
                finally {
                    $after = @{}
                    foreach ($id in Get-StartupIds (Invoke-StartupBcd @('/enum', 'all'))) {
                        if ($before -notcontains $id) { $after[$id] = Invoke-StartupBcd @('/enum', $id) }
                    }
                    $state.Entry = Resolve-NewBootCopy -BeforeIds $before -AfterEntries $after -Source $manager -Name $script:StartupName
                    Save-StartupState $statePath $state
                }
                $null = Invoke-StartupBcd @('/set', $state.Entry, 'device', ('partition=' + $Drive + ':'))
                $null = Invoke-StartupBcd @('/set', $state.Entry, 'path', $script:StartupPath)
                Assert-StartupEntry $state.Entry $Drive
                $null = Assert-StartupPackage $Repo $Drive $DiskIdentity
                Set-StartupOrder (@($order) + @($state.Entry))
                $state.Mode = 'registered'
                Save-StartupState $statePath $state
            } catch {
                $original = $_
                Set-StartupOrder $order
                if ($state.Entry) { $null = Invoke-StartupBcd @('/delete', $state.Entry) }
                $state.Mode = 'registration-failed'
                Save-StartupState $statePath $state
                throw $original
            }
            'Test entry registered at the end of the boot menu. Fully shut down, select Prometheus Unlock USB - EXPERIMENTAL, then return to enable automatic startup.'
            return
        }
        if (!$state -or $state.Mode -notin @('registered', 'windows-first', 'automatic') -or
            $state.Entry -notmatch '^\{[0-9a-fA-F-]{36}\}$' -or $order -notcontains $state.Entry) { throw 'Register and test this USB entry first.' }
        foreach ($key in @('Partition','Disk','Efi','Child','Profile')) {
            if ($package[$key] -cne $state.Package.$key) { throw 'USB or build changed since registration.' }
        }
        Assert-StartupEntry $state.Entry $Drive
        Assert-StartupBootProof $state $Drive
        if ($state.Mode -eq 'automatic') {
            if ($order[0] -ne $state.Entry -or (Read-StartupPower).Value -ne 0) { throw 'Automatic state differs from the saved settings. Restore Windows first before retrying.' }
            'Automatic USB startup is already enabled.'
            return
        }
        $power = Read-StartupPower
        if ((Invoke-StartupBcd @('/enum', '{fwbootmgr}')) -cne $firmware) { throw 'Firmware boot order changed during validation. Retry after reviewing settings.' }
        $priorMode = $state.Mode
        $state.PowerBefore = $power
        $state.Mode = 'enabling'
        Save-StartupState $statePath $state
        try {
            Write-StartupPower @{ Exists = $true; Value = 0 }
            $next = @($state.Entry, '{bootmgr}') + @($order | Where-Object { $_ -ne $state.Entry -and $_ -ne '{bootmgr}' })
            Set-StartupOrder $next
            Assert-StartupEntry $state.Entry $Drive
            $state.Mode = 'automatic'
            Save-StartupState $statePath $state
        } catch {
            $original = $_
            Invoke-RecoveryActions -Actions @({ Set-StartupOrder $order }, { Write-StartupPower $power })
            $state.Mode = $priorMode
            Save-StartupState $statePath $state
            throw $original
        }
        'Automatic USB startup enabled. Keep this USB connected and use the tested display layout. Full shutdown/startup reapplies the unlock; restart and sleep remain hardware-dependent.'
    } finally {
        $lock.Dispose()
    }
}
