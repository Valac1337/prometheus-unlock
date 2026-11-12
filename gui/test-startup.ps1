# SPDX-License-Identifier: GPL-2.0-only
# Simulated firmware/registry only. All files go into a temporary test directory.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/startup.ps1"
$realBootProof = ${function:Assert-StartupBootProof}
$repo = Split-Path $PSScriptRoot -Parent
$originalProgramData = $env:ProgramData
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('prometheus-startup-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $testRoot | Out-Null
$env:ProgramData = $testRoot
$script:entryId = '{11111111-1111-1111-1111-111111111111}'
$script:otherId = '{22222222-2222-2222-2222-222222222222}'
$script:checks = 0
function Assert($Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
    $script:checks++
}
function Assert-StartupAdministrator {}
function Confirm-SecureBootUEFI { return $script:secureBoot }
function Get-BitLockerVolume { [pscustomobject]@{ VolumeStatus = 0; ProtectionStatus = 0 } }
function Assert-StartupPackage {
    if ($script:badPackage) { throw 'Injected USB mismatch' }
    return @{ Partition = 'partition'; Disk = 'disk'; Efi = $script:efi; Child = 'child'; Profile = 'local' }
}
function Read-StartupPower { @{ Exists = $true; Value = $script:power } }
function Write-StartupPower($Plan) { $script:power = $Plan.Value }
function Assert-StartupBootProof {
    if (!$script:proof) { throw 'Injected missing successful boot proof' }
}
function Invoke-StartupBcd([string[]]$Arguments) {
    $script:calls++
    $operation = $Arguments[0]
    if ($operation -eq '/export') { return '' }
    if ($operation -eq '/copy') {
        $script:entries[$script:entryId] = @{ Description = $script:StartupName; Device = 'C'; Path = '\EFI\Microsoft\Boot\bootmgfw.efi' }
        if ($script:failCopy) { throw 'Injected copy response failure after creation' }
        return ''
    }
    if ($operation -eq '/delete') { $script:entries.Remove($Arguments[1]); return '' }
    if ($operation -eq '/set') {
        if ($Arguments[1] -eq '{fwbootmgr}') {
            $script:order = @($Arguments | Select-Object -Skip 3)
            if ($script:failOrder) { $script:failOrder = $false; throw 'Injected boot-order write failure' }
            return ''
        }
        $entry = $script:entries[$Arguments[1]]
        if ($Arguments[2] -eq 'device') { $entry.Device = $Arguments[3].Replace('partition=', '').TrimEnd(':') }
        if ($Arguments[2] -eq 'path') { $entry.Path = $Arguments[3] }
        return ''
    }
    if ($operation -eq '/enum') {
        if ($Arguments[1] -eq '{fwbootmgr}') {
            return 'displayorder ' + ($script:order -join "`r`n             ") + "`r`n" + $script:bootNext
        }
        if ($Arguments[1] -in @('all', 'firmware')) {
            return (@($script:entries.Keys | ForEach-Object { Invoke-StartupBcd @('/enum', $_) }) -join "`r`n")
        }
        $entry = $script:entries[$Arguments[1]]
        if (!$entry) { throw 'Entry missing' }
        return "identifier $($Arguments[1])`r`ndescription $($entry.Description)`r`ndevice partition=$($entry.Device):`r`npath $($entry.Path)`r`n"
    }
    throw 'Unexpected mock BCDEdit command'
}
function Reset-Case {
    $env:ProgramData = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $env:ProgramData | Out-Null
    $script:order = @('{bootmgr}', $script:otherId)
    $script:entries = @{
        '{bootmgr}' = @{ Description = 'Windows Boot Manager'; Device = 'C'; Path = '\EFI\Microsoft\Boot\bootmgfw.efi' }
        $script:otherId = @{ Description = 'Other boot'; Device = 'D'; Path = '\other.efi' }
    }
    $script:power = 1
    $script:proof = $true
    $script:badPackage = $false
    $script:secureBoot = $false
    $script:failCopy = $false
    $script:failOrder = $false
    $script:bootNext = ''
    $script:efi = 'efi'
    $script:calls = 0
}
function Run-Action($Action) {
    Invoke-PrometheusStartup -Action $Action -Repo $repo -Drive G -DiskIdentity disk | Out-Null
}
function Expect-Refusal($Action) {
    $refused = $false
    try { Run-Action $Action } catch { $refused = $true }
    Assert $refused "Expected refusal for $Action"
}
try {
    Reset-Case
    Run-Action RegisterStartup
    Assert ($script:order[0] -eq '{bootmgr}') 'Registration changed default boot'
    Assert ($script:order[-1] -eq $script:entryId) 'Test entry not appended'
    Assert ($script:power -eq 1) 'Registration changed power settings'
    Run-Action EnableStartup
    Assert ($script:order[0] -eq $script:entryId -and $script:order[1] -eq '{bootmgr}') 'Promotion order wrong'
    Assert ($script:order -contains $script:otherId) 'Unrelated entry lost'
    Assert ($script:power -eq 0) 'Fast Startup not disabled'
    Run-Action EnableStartup
    Assert ($script:order.Count -eq 3) 'Repeat promotion duplicated entry'
    $script:badPackage = $true
    Run-Action DisableStartup
    Assert ($script:order[0] -eq '{bootmgr}' -and $script:power -eq 1) 'Recovery without USB failed'
    Run-Action RemoveStartup
    Assert (!$script:entries.ContainsKey($script:entryId) -and $script:order.Count -eq 2) 'Owned entry removal failed'
    $script:badPackage = $false
    Run-Action RegisterStartup
    Assert ($script:entries.ContainsKey($script:entryId)) 'Registration after removal failed'
    $script:entries[$script:entryId].Description = 'Another tool owns this'
    Expect-Refusal RemoveStartup
    Assert ($script:entries.ContainsKey($script:entryId)) 'Changed unrelated entry was deleted'

    Reset-Case
    Run-Action RegisterStartup
    $script:proof = $false
    Expect-Refusal EnableStartup
    Assert ($script:order[0] -eq '{bootmgr}' -and $script:power -eq 1) 'Missing-proof refusal mutated settings'
    $script:proof = $true
    $script:efi = 'changed'
    Expect-Refusal EnableStartup
    Assert ($script:order[0] -eq '{bootmgr}') 'Changed build accepted'

    Reset-Case
    $script:failCopy = $true
    Expect-Refusal RegisterStartup
    Assert (!$script:entries.ContainsKey($script:entryId)) 'Failed copy left an owned entry'
    Assert ($script:order.Count -eq 2) 'Failed registration changed boot order'

    Reset-Case
    Run-Action RegisterStartup
    $script:failOrder = $true
    Expect-Refusal EnableStartup
    Assert ($script:order[0] -eq '{bootmgr}' -and $script:power -eq 1) 'Promotion rollback failed'
    $state = Get-Content (Join-Path $env:ProgramData 'PrometheusUnlock/usb-startup.json') -Raw | ConvertFrom-Json
    Assert ($state.Mode -eq 'registered') 'Rollback state incorrect'

    Reset-Case
    $script:bootNext = 'bootsequence {bootmgr}'
    Expect-Refusal RegisterStartup
    Assert (!$script:entries.ContainsKey($script:entryId)) 'Pending boot sequence accepted'
    Reset-Case
    $script:secureBoot = $true
    Expect-Refusal RegisterStartup
    Assert (!$script:entries.ContainsKey($script:entryId)) 'Secure Boot enabled accepted'
    Reset-Case
    Run-Action DisableStartup
    Assert ($script:order[0] -eq '{bootmgr}') 'Recovery without saved state failed'
    $corruptFolder = Join-Path $env:ProgramData 'PrometheusUnlock'
    'broken json' | Set-Content (Join-Path $corruptFolder 'usb-startup.json')
    Run-Action DisableStartup
    Assert ($script:order[0] -eq '{bootmgr}') 'Recovery with unreadable state failed'

    $refused = $false
    try { Get-StartupOrder 'displayorder {bootmgr} {bootmgr}' } catch { $refused = $true }
    Assert $refused 'Duplicate boot IDs accepted'
    $refused = $false
    try { Get-StartupOrder 'unrecognized localized output' } catch { $refused = $true }
    Assert $refused 'Unrecognized firmware output accepted'

    # Exercise the production proof parser with local files and a fake OS boot time.
    function Get-CimInstance { [pscustomobject]@{ LastBootUpTime = $script:bootTime } }
    New-PSDrive -Name PUProof -PSProvider FileSystem -Root $testRoot | Out-Null
    $proofDirectory = Join-Path $testRoot 'RTX3090-UNLOCK/AUTO000000'
    New-Item -ItemType Directory $proofDirectory -Force | Out-Null
    $proofFile = Join-Path $proofDirectory 'REPORT.TXT'
    $registered = [DateTime]::UtcNow.AddMinutes(-10)
    $proofState = [pscustomobject]@{ RegisteredUtc = $registered.ToString('o') }
    $script:bootTime = [DateTime]::UtcNow.AddMinutes(-5)
    $goodLog = "transaction result=0 containment=0 started=1 quiesced=1 fault=0 retained=0 maps=0 FLR=1`nFINAL status=0 stage=transaction attempted=1 driver_release=0 clean=1"
    $goodLog | Set-Content $proofFile
    & $realBootProof $proofState PUProof
    Assert $true 'Valid boot proof'
    (Get-Item $proofFile).LastWriteTimeUtc = $registered.AddMinutes(-1)
    $refused = $false
    try { & $realBootProof $proofState PUProof } catch { $refused = $true }
    Assert $refused 'Stale report accepted'
    ($goodLog -replace 'clean=1','clean=0') | Set-Content $proofFile
    $refused = $false
    try { & $realBootProof $proofState PUProof } catch { $refused = $true }
    Assert $refused 'Unclean report accepted'
    $goodLog | Set-Content $proofFile
    $script:bootTime = $registered.AddMinutes(-1)
    $refused = $false
    try { & $realBootProof $proofState PUProof } catch { $refused = $true }
    Assert $refused 'Missing Windows boot accepted'
    Remove-PSDrive PUProof
    "PASS $script:checks startup assertions. Firmware and registry simulated. Test files: $testRoot"
} finally {
    $env:ProgramData = $originalProgramData
}
