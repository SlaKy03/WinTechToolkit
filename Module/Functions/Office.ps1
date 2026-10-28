# Microsoft 365 / Office, Teams, Outlook and OneDrive.

$script:WTC2RConfig = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
$script:WTOfficeApps = 'WINWORD', 'EXCEL', 'POWERPNT', 'OUTLOOK', 'ONENOTE', 'MSACCESS', 'MSPUB', 'VISIO', 'WINPROJ', 'lync'

function Get-WTOfficeInfo {
    # Office Click-to-Run version, channel and language
    if (-not (Test-Path $script:WTC2RConfig)) {
        Write-WTLog 'Office Click-to-Run not found (Office missing or MSI installation).' -Level Warn
        return
    }
    $c = Get-ItemProperty $script:WTC2RConfig
    $channels = @{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current Channel'
        '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'Current Channel (Preview)'
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'Monthly Enterprise'
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'Semi-Annual Enterprise'
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'Semi-Annual Enterprise (Preview)'
        '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'Beta'
    }
    $url = "$($c.UpdateChannel)"
    if (-not $url) { $url = "$($c.CDNBaseUrl)" }
    $guid = ($url -split '/')[-1]
    $channel = $channels[$guid]
    if (-not $channel) { $channel = 'custom / managed' }
    $info = [pscustomobject]@{
        Version  = $c.VersionToReport
        Platform = $c.Platform
        Culture  = $c.ClientCulture
        Channel  = $channel
        Products = $c.ProductReleaseIds
    }
    Write-WTLog ("Office {0} - {1} - {2} - language {3}" -f $info.Version, $info.Platform, $info.Channel, $info.Culture) -Level OK
    Write-WTLog "Products: $($info.Products)"
    $info
}

function Repair-WTOffice {
    # Quick repair (offline, a few minutes) or online repair (full reinstall)
    param([ValidateSet('Quick', 'Full')][string]$Mode = 'Quick', [switch]$Simulate)
    $exe = Join-Path $env:CommonProgramFiles 'microsoft shared\ClickToRun\OfficeClickToRun.exe'
    if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path $script:WTC2RConfig)) {
        Write-WTLog 'Office Click-to-Run not found: for MSI installations use Apps & features > Repair.' -Level Error
        return
    }
    $c = Get-ItemProperty $script:WTC2RConfig
    $type = if ($Mode -eq 'Full') { 'FullRepair' } else { 'QuickRepair' }
    $arguments = "scenario=Repair platform=$($c.Platform) culture=$($c.ClientCulture) forceappshutdown=True RepairType=$type DisplayLevel=True"
    if ($Simulate) { Write-WTLog "[SIMULATION] Would run: OfficeClickToRun.exe $arguments"; return }
    Write-WTLog "Starting $(if ($Mode -eq 'Full') { 'online' } else { 'quick' }) Office repair: open applications will be closed."
    Start-Process -FilePath $exe -ArgumentList $arguments
    Write-WTLog 'Repair started: progress is shown in the Office window.' -Level OK
}

function Update-WTOffice {
    $exe = Join-Path $env:CommonProgramFiles 'microsoft shared\ClickToRun\OfficeC2RClient.exe'
    if (-not (Test-Path -LiteralPath $exe)) { Write-WTLog 'Office Click-to-Run not found.' -Level Error; return }
    Start-Process -FilePath $exe -ArgumentList '/update user displaylevel=true forceappshutdown=false'
    Write-WTLog 'Office update started (if apps are open, you will be asked to close them).' -Level OK
}

function Reset-WTTeamsCache {
    # Cache of the new Teams (MSTeams package) and of classic Teams
    param([Parameter(Mandatory)][string]$ProfilePath, [string]$UserName, [switch]$Simulate)
    if (-not $Simulate) { Stop-WTUserProcess -Name 'ms-teams', 'Teams', 'msteamsupdate' -UserName $UserName }
    $paths = @("$ProfilePath\AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams")
    foreach ($sub in 'Cache', 'blob_storage', 'databases', 'GPUCache', 'IndexedDB', 'Local Storage', 'tmp', 'Code Cache', 'Service Worker') {
        $paths += "$ProfilePath\AppData\Roaming\Microsoft\Teams\$sub"
    }
    $freed = [int64]0
    $found = $false
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $found = $true
        $freed += Clear-WTFolderContent -Path $p -Simulate:$Simulate
    }
    if (-not $found) { Write-WTLog "No Teams cache found in $ProfilePath." -Level Warn; return }
    Write-WTLog "Teams cache cleared: $(Format-WTSize $freed). Teams will reload its data on the next start." -Level OK
}

function Reset-WTOutlookCache {
    # Renames the .ost files: Outlook downloads them again from the server on the next start
    param([Parameter(Mandatory)][string]$ProfilePath, [string]$UserName, [switch]$Simulate)
    $dir = "$ProfilePath\AppData\Local\Microsoft\Outlook"
    $osts = @(Get-ChildItem -LiteralPath $dir -Filter '*.ost' -Force -ErrorAction SilentlyContinue)
    if (-not $osts.Count) { Write-WTLog "No .ost file found in $dir." -Level Warn; return }
    if (-not $Simulate) { Stop-WTUserProcess -Name 'OUTLOOK' -UserName $UserName }
    foreach ($f in $osts) {
        $new = '{0}.old_{1:yyyyMMdd_HHmm}' -f $f.Name, (Get-Date)
        if ($Simulate) { Write-WTLog "[SIMULATION] Would rename $($f.FullName) ($(Format-WTSize $f.Length))"; continue }
        try {
            Rename-Item -LiteralPath $f.FullName -NewName $new -ErrorAction Stop
            Write-WTLog "Renamed $($f.Name) -> $new ($(Format-WTSize $f.Length))" -Level OK
        } catch { Write-WTLog "Could not rename $($f.Name): $($_.Exception.Message)" -Level Error }
    }
    Write-WTLog "On the next start Outlook will download the mailbox again: with large mailboxes this can take time. Delete the .old files after checking."
}

function Start-WTOutlookMode {
    # Starts Outlook in the user's session in safe mode or with the navigation pane reset
    param([Parameter(Mandatory)][string]$UserName, [ValidateSet('Safe', 'ResetNavPane')][string]$Mode = 'Safe')
    $switch = if ($Mode -eq 'Safe') { '/safe' } else { '/resetnavpane' }
    Stop-WTUserProcess -Name 'OUTLOOK' -UserName $UserName
    $out = Invoke-WTUserContext -UserName $UserName -TimeoutSec 30 -Script "Start-Process outlook.exe -ArgumentList '$switch'; 'Outlook started with $switch'"
    foreach ($l in $out) { Write-WTLog "  $l" }
}

function Reset-WTOfficeSignIn {
    <#
    .SYNOPSIS
        Resets the Microsoft 365 sign-in and activation state for the user:
        Identity/Licensing keys, identity cache and saved Office credentials.
        Fixes the classic "sign-in required over and over" and "unlicensed product".
    #>
    param([Parameter(Mandatory)][string]$UserName, [switch]$Simulate)
    if ($Simulate) { Write-WTLog "[SIMULATION] Would close the Office apps and reset the Microsoft 365 sign-in and license for $UserName"; return }
    Stop-WTUserProcess -Name $script:WTOfficeApps -UserName $UserName
    $script = @"
foreach (`$k in 'HKCU:\Software\Microsoft\Office\16.0\Common\Identity', 'HKCU:\Software\Microsoft\Office\16.0\Common\Licensing', 'HKCU:\Software\Microsoft\Office\16.0\Registration') {
    if (Test-Path `$k) { Remove-Item `$k -Recurse -Force -ErrorAction SilentlyContinue; "Removed key `$k" }
}
foreach (`$d in "`$env:LOCALAPPDATA\Microsoft\Office\16.0\Licensing", "`$env:LOCALAPPDATA\Microsoft\IdentityCache", "`$env:LOCALAPPDATA\Microsoft\OneAuth") {
    if (Test-Path `$d) { Remove-Item `$d -Recurse -Force -ErrorAction SilentlyContinue; "Removed folder `$d" }
}
$(Get-WTCredentialHelperSource)
foreach (`$c in [WTCred]::List()) {
    `$f = `$c.Split('|')
    if (`$f[1] -match 'MicrosoftOffice|msteams|OneAuth|Microsoft_OC|SSO_POP') {
        if ([WTCred]::Delete(`$f[1], [int]`$f[0])) { "Credential removed: `$(`$f[1])" }
    }
}
"@
    $out = Invoke-WTUserContext -UserName $UserName -Script $script
    foreach ($l in $out) { Write-WTLog "  $l" }
    Write-WTLog 'Microsoft 365 sign-in reset: the user will have to sign in again when opening Office.' -Level OK
}

function Reset-WTOneDrive {
    # onedrive.exe /reset in the user's session, then restart of the client
    param([Parameter(Mandatory)][string]$UserName, [switch]$Simulate)
    if ($Simulate) { Write-WTLog "[SIMULATION] Would run onedrive.exe /reset for $UserName"; return }
    $script = @'
$exe = @("$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe", "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe", "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { 'OneDrive not found'; return }
Start-Process $exe -ArgumentList '/reset'
'Reset sent, waiting for the client to close...'
Start-Sleep -Seconds 15
if (-not (Get-Process OneDrive -ErrorAction SilentlyContinue)) { Start-Process $exe; 'OneDrive restarted' } else { 'OneDrive restarted by itself' }
'Sync will start again from scratch (local files are not deleted).'
'@
    $out = Invoke-WTUserContext -UserName $UserName -Script $script -TimeoutSec 90
    foreach ($l in $out) { Write-WTLog "  $l" }
}
