# Screenshots for the README and the guide, with made-up data: no real computer, domain, user or
# program list ends up in the images. The UI starts off-screen, the real loads are disabled and
# every page shown is filled with sample data, translated like the interface.
#   powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\Build\New-Screenshots.ps1
# Without -Language it runs once per language (en, it): docs\images\<language>\*.png
param([string]$Language, [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\images'))
$root = Split-Path $PSScriptRoot -Parent
if (-not $Language) {
    foreach ($l in 'en', 'it') {
        & "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File $PSCommandPath -Language $l -OutDir $OutDir
    }
    return
}
$out = Join-Path $OutDir $Language
New-Item -ItemType Directory -Path $out -Force | Out-Null

$main = [IO.File]::ReadAllText((Join-Path $root 'WinTechToolkit.ps1'))
$main = $main.Replace('if (-not ($isAdmin -and $isSTA -and $isDesktop -and -not $is32on64)) {', 'if ($false) {')
$main = $main.Replace('Get-WTLanguage $settings.Language', "Get-WTLanguage '$Language'")
$main = $main.Replace('$PSScriptRoot', "'$root'").Replace('$MyInvocation.MyCommand.Path', "'$root\WinTechToolkit.ps1'")
# settings of the PC (window size, theme) are neither read nor written
$main = $main.Replace('if (Test-Path -LiteralPath $settingsFile) {', 'if ($false) {')
$main = $main.Replace('try { $settings | ConvertTo-Json', 'try { return; $settings | ConvertTo-Json')

$hook = @'
$window.WindowState = 'Normal'; $window.Width = 1440; $window.Height = 900
$window.Left = -6000; $window.Top = 0; $window.ShowInTaskbar = $false
Set-WTSidebar $true
# no real data: the loads of the pages do nothing, the pages are filled below
function Start-WTTask { }
$script:NoCloseConfirm = $true

function Save-Shot([string]$Name) {
    $window.UpdateLayout()
    $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$window.ActualWidth), ([int]$window.ActualHeight), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($window)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create((Join-Path '__OUT__' $Name)); $enc.Save($fs); $fs.Close()
}

# sample texts that do not exist in the interface
function L([string]$En, [string]$It) { if ($global:WTLanguage -eq 'it') { $It } else { $En } }

function Set-DemoCommon {
    $ui.TxtHeaderInfo.Text = 'PC-DEMO01 · contoso.local · ' + (T 'signed in: {0}' 'CONTOSO\mario.rossi')
    $line = { param($Time, $Level, $Text) [pscustomobject]@{ Line = '{0} [{1,-5}] {2}' -f $Time, $Level, $Text; Level = $Level } }
    $drop = $null; while ($global:WTQueue.TryDequeue([ref]$drop)) { }
    $script:LogItems.Clear()
    foreach ($l in @(
            (& $line '09:14:02' 'INFO' (T '{0} {1} - session started by {2} on {3}' $app.Name $app.Version 'CONTOSO\it.admin' 'PC-DEMO01')),
            (& $line '09:14:03' 'INFO' (T 'Analyzing the event logs of the last {0} days...' 7)),
            (& $line '09:14:05' 'OK' (T 'History: {0} entries, {1} failed.' 12 0)),
            (& $line '09:14:09' 'WARN' (T 'Diagnosis complete: {0} problem areas, {1} relevant events.' 2 9)),
            (& $line '09:15:41' 'INFO' (T 'Uninstalling: {0}' 'Contoso VPN Client 4.2')),
            (& $line '09:16:10' 'OK' (T '{0} uninstalled.' 'Contoso VPN Client')),
            (& $line '09:16:12' 'OK' (T 'Leftovers removed: {0}, not removed: {1}.' 6 0))
        )) { $script:LogItems.Add($l) }
}

function Set-DemoDashboard {
    Set-WTDash 'Pc' 'PC-DEMO01' 'Latitude 7440 · S/N 4XK2J93'
    Set-WTDash 'Os' 'Windows 11 Pro 24H2' 'build 26100.4061'
    Set-WTDash 'Up' '3 d 4 h' (T 'Last boot {0}' '2026-11-03 08:12')
    Set-WTDash 'Stab' (T 'No abnormal shutdowns') (T '{0} application crashes' 2) 'Ok'
    Set-WTDash 'Disk' (T '{0} free' '182 GB') (T 'of {0} · {1}% used' '476 GB' 62)
    $ui.DashDiskBar.Value = 62
    Set-WTDash 'Ram' '16 GB' (T '{0}% in use' 41)
    $ui.DashRamBar.Value = 41
    Set-WTDash 'Net' '10.20.30.45' 'contoso.local'
    Set-WTDash 'Sec' "BitLocker $(Get-WTStateText 'on')" "Secure Boot $(Get-WTStateText 'on') · TPM $(Get-WTStateText 'on')"
}

function Set-DemoPrograms {
    $p = { param($Name, $Version, $Publisher, $Date, $Size, $Type, $Scope)
        [pscustomobject]@{ DisplayName = $Name; Version = $Version; Publisher = $Publisher; InstallDate = $Date; InstallDateSort = $Date -replace '-', ''
            SizeBytes = [int64]($Size * 1MB); SizeText = (Format-WTSize ([int64]($Size * 1MB))); InstallerType = $Type; Scope = $Scope
            InstallLocation = ''; UninstallString = ''; QuietUninstallString = ''; ProductCode = $null; RegistryKey = '' } }
    $pc = T 'Computer (64-bit)'; $pc32 = T 'Computer (32-bit)'; $usr = T 'User {0}' 'CONTOSO\mario.rossi'
    $script:AllPrograms = @(
        (& $p '7-Zip 24.08 (x64)' '24.08' 'Igor Pavlov' '2026-09-12' 5.6 'EXE' $pc),
        (& $p 'Adobe Acrobat Reader (64-bit)' '25.001.20432' 'Adobe' '2026-10-20' 820 'EXE' $pc),
        (& $p 'Contoso VPN Client' '4.2.1' 'Contoso Ltd.' '2026-06-02' 96 'MSI' $pc),
        (& $p 'Google Chrome' '131.0.6778.86' 'Google LLC' '2026-11-02' 512 'MSI' $pc),
        (& $p 'Microsoft 365 Apps for business - it-it' '16.0.18129.20158' 'Microsoft Corporation' '2026-10-28' 3020 'EXE' $pc),
        (& $p 'Microsoft Edge' '131.0.2903.70' 'Microsoft Corporation' '2026-11-04' 690 'EXE' $pc32),
        (& $p 'Microsoft Teams' '24295.605.3225.8804' 'Microsoft Corporation' '2026-10-30' 410 'EXE' $usr),
        (& $p 'Mozilla Firefox (x64 it)' '132.0.2' 'Mozilla' '2026-10-31' 245 'EXE' $pc),
        (& $p 'Notepad++ (64-bit x64)' '8.7.1' 'Notepad++ Team' '2026-09-18' 15 'EXE' $pc),
        (& $p 'PDF24 Creator' '11.21.0' 'geek software GmbH' '2026-08-21' 380 'MSI' $pc),
        (& $p 'Visual Studio Code' '1.95.3' 'Microsoft Corporation' '2026-11-01' 395 'EXE' $usr),
        (& $p 'VLC media player' '3.0.21' 'VideoLAN' '2026-07-14' 162 'EXE' $pc),
        (& $p 'Zoom Workplace (64-bit)' '6.2.11' 'Zoom Video Communications, Inc.' '2026-10-13' 530 'MSI' $pc)
    )
    $ui.TxtProgFilter.Text = ''
    Update-WTProgramFilter
    $ui.GridPrograms.SelectedIndex = 2
    $script:ResidueTimer.Stop()
    $r = { param($Type, $Path, $Size, $Reason)
        [pscustomobject]@{ Type = $Type; TypeText = (T $Type); Path = $Path; Reason = $Reason; Program = 'Contoso VPN Client'
            SizeBytes = [int64]($Size * 1KB); SizeText = $(if ($Size) { Format-WTSize ([int64]($Size * 1KB)) } else { '' }) } }
    Show-WTResidues -Preview @(
        (& $r 'Folder' 'C:\Program Files\Contoso\VPN Client' 98304 (T 'Install folder (InstallLocation)')),
        (& $r 'Folder' 'C:\ProgramData\Contoso\VPN Client' 2140 (T "Name '{0}' ({1})" 'VPN Client' 'ProgramData')),
        (& $r 'Folder' 'C:\Users\mario.rossi\AppData\Roaming\Contoso VPN' 312 (T "Name '{0}' ({1})" 'Contoso VPN' (T 'user data {0}' 'mario.rossi'))),
        (& $r 'Shortcut' 'C:\Users\Public\Desktop\Contoso VPN.lnk' 0 (T 'Shortcut to: {0}' 'C:\Program Files\Contoso\VPN Client\vpnui.exe')),
        (& $r 'Service' 'ContosoVpnSvc' 0 (T "Service '{0}' - {1}" 'Contoso VPN Service' '"C:\Program Files\Contoso\VPN Client\vpnsvc.exe"')),
        (& $r 'Registry' 'HKEY_LOCAL_MACHINE\SOFTWARE\Contoso\VPN Client' 0 (T "Publisher's key '{0}'" 'VPN Client'))
    )
}

function Set-DemoEvents {
    Set-WTActiveEventCategory 'Diagnosis'
    $e = { param($Time, $Level, $Cat, $Source, $Id, $Summary)
        [pscustomobject]@{ TimeText = $Time; Level = $Level; LevelText = (T $Level); Category = (T $Cat); Source = $Source; Id = $Id; Summary = $Summary; Message = $Summary; Log = 'System' } }
    $rows = @(
        (& $e '2026-11-05 16:42' 'Error' 'App crashes' 'Application Error' 1000 (T 'Crash of {0} {1} - module {2} {3} - exception 0x{4}' 'OUTLOOK.EXE' '16.0.18129.20158' 'mso98win32client.dll' '16.0.18129.20030' 'c0000005')),
        (& $e '2026-11-05 11:03' 'Error' 'App crashes' 'Application Error' 1000 (T 'Crash of {0} {1} - module {2} {3} - exception 0x{4}' 'OUTLOOK.EXE' '16.0.18129.20158' 'mso98win32client.dll' '16.0.18129.20030' 'c0000005')),
        (& $e '2026-11-04 09:27' 'Warning' 'Disk' 'disk' 153 (L 'Disk 1: an I/O operation was retried' 'Disco 1: un''operazione di I/O è stata ripetuta')),
        (& $e '2026-11-04 09:26' 'Warning' 'Disk' 'disk' 153 (L 'Disk 1: an I/O operation was retried' 'Disco 1: un''operazione di I/O è stata ripetuta')),
        (& $e '2026-11-03 08:15' 'Error' 'Windows Update' 'Microsoft-Windows-WindowsUpdateClient' 20 (L 'Installation of KB5046617 failed (0x800f0922)' 'Installazione di KB5046617 non riuscita (0x800f0922)')),
        (& $e '2026-11-02 18:31' 'Warning' 'Network and domain' 'Microsoft-Windows-Time-Service' 129 (L 'The time could not be synchronized with the domain controller' 'Impossibile sincronizzare l''ora con il controller di dominio'))
    )
    Show-WTEvents $rows
    $R = @(
        (T 'PROBLEM DIAGNOSIS - {0} - last {1} days (generated {2:yyyy-MM-dd HH:mm})' 'PC-DEMO01' 7 ([datetime]'2026-11-06 09:14')),
        ('=' * 90),
        (T 'Last boot: {0:yyyy-MM-dd HH:mm} - up for {1}' ([datetime]'2026-11-03 08:12') '3 d 1 h'),
        (T 'Stability index (Reliability Monitor): {0:N1} / 10' 8.7),
        '',
        (T '[OK] No blue screens'),
        (T '[OK] No unexpected shutdowns'),
        (T '[!] APPLICATION CRASHES: {0} - most frequent: {1}' 2 'OUTLOOK.EXE (2)'),
        (T '      Modules involved: {0}' 'mso98win32client.dll (2)'),
        (T '[OK] No application hangs'),
        (T '[!] DISK AND FILE SYSTEM: {0} events - sources: {1}' 2 'disk 153 (2)'),
        (T '[OK] No hardware or driver errors'),
        (T '[OK] No service errors'),
        '',
        (T 'SUGGESTIONS'),
        ('1. ' + (T 'Applications that keep crashing: update or repair them (Apps & features > Repair), disable add-ins, try a new user profile.')),
        ('2. ' + (T "Disk errors: check 'Disk health (SMART)' in the Integrity section, run CHKDSK and back up the user's data; with repeated errors consider replacing the disk."))
    )
    $ui.TxtEventDetail.Text = $R -join "`r`n"
}

function Set-DemoProfiles {
    $o = { param($Type, $User, $Last, $Days, $Size, $Loaded, $Status, $Path, $Protect, $Sid)
        [pscustomobject]@{ Type = $Type; TypeText = (T $Type); UserName = $User; LastUseText = $Last; DaysUnused = $Days; SizeBytes = [int64]($Size * 1GB)
            SizeText = (Format-WTSize ([int64]($Size * 1GB))); Loaded = $Loaded; LoadedText = (Format-WTBool $Loaded); Status = $Status; Path = $Path
            ProtectReason = $Protect; Protected = [bool]$Protect; SID = $Sid } }
    $rows = @(
        (& $o 'Profile' 'CONTOSO\mario.rossi' '2026-11-06 08:55' 0 18.4 $true 'OK' 'C:\Users\mario.rossi' (T 'Profile loaded (user signed in)') 'S-1-5-21-3623811015-3361044348-30300820-1104'),
        (& $o 'Profile' 'CONTOSO\it.admin' '2026-11-06 09:13' 0 1.2 $true 'OK' 'C:\Users\it.admin' (T 'Account running the toolkit') 'S-1-5-21-3623811015-3361044348-30300820-1013'),
        (& $o 'Profile' 'CONTOSO\giulia.bianchi' '2026-05-14 17:20' 176 9.7 $false 'OK' 'C:\Users\giulia.bianchi' '' 'S-1-5-21-3623811015-3361044348-30300820-1188'),
        (& $o 'Profile' 'CONTOSO\luca.verdi' '2026-02-03 12:41' 276 23.1 $false 'OK' 'C:\Users\luca.verdi' '' 'S-1-5-21-3623811015-3361044348-30300820-1201'),
        (& $o 'Profile' 'CONTOSO\stage01' '2025-12-19 10:02' 322 4.3 $false (T 'Temporary profile (TEMP)') 'C:\Users\TEMP' '' 'S-1-5-21-3623811015-3361044348-30300820-1310'),
        (& $o 'Orphan folder' 'anna.neri' '2025-09-30 15:44' 402 6.8 $false (T 'Not registered in ProfileList') 'C:\Users\anna.neri' '' '')
    )
    $ui.GridProfiles.ItemsSource = $rows
    $ui.TxtProfCount.Text = T '{0} items · {1} on disk' $rows.Count (Format-WTSize ([int64](63.5 * 1GB)))
}

function Set-DemoPrinters {
    $p = { param($Name, $Status, $Jobs, $Type, $User, $Driver, $Port, $Shared)
        [pscustomobject]@{ Name = $Name; Status = $Status; StatusText = (T $Status); Jobs = $Jobs; Type = (T $Type); UserText = $User; UserName = $User
            Driver = $Driver; Port = $Port; Shared = (Format-WTBool $Shared) } }
    $rows = @(
        (& $p '\\print01.contoso.local\Floor2-Color' 'Ready' 0 'Network connection' 'mario.rossi' 'Kyocera TASKalfa 2554ci KX' 'IP_10.20.40.21' $true),
        (& $p '\\print01.contoso.local\Reception-BW' 'Offline' 3 'Network connection' 'mario.rossi' 'HP Universal Printing PCL 6' 'IP_10.20.40.35' $true),
        (& $p 'HP LaserJet M404 (USB)' 'Ready' 0 'Local' (T 'All users') 'HP LaserJet Pro M404-M405 PCL-6 (V4)' 'USB001' $false),
        (& $p 'Microsoft Print to PDF' 'Ready' 0 'Local' (T 'All users') 'Microsoft Print To PDF' 'PORTPROMPT:' $false)
    )
    $ui.GridPrinters.ItemsSource = $rows
    $ui.TxtPrinterCount.Text = T '{0} printers' $rows.Count
}

$script:Shots = @(
    @{ Name = 'dashboard.png'; Theme = 'Dark'; Page = 'Dashboard'; Fill = { Set-DemoDashboard } },
    @{ Name = 'programs.png'; Theme = 'Dark'; Page = 'Programs'; NoLog = $true; Fill = { Set-DemoPrograms } },
    @{ Name = 'events.png'; Theme = 'Dark'; Page = 'Events'; NoLog = $true; Fill = { Set-DemoEvents } },
    @{ Name = 'profiles.png'; Theme = 'Light'; Page = 'Profiles'; Fill = { Set-DemoProfiles } },
    @{ Name = 'printers.png'; Theme = 'Light'; Page = 'Printers'; Fill = { Set-DemoPrinters } }
)
$script:ShotStep = 0
$shotTimer = New-Object System.Windows.Threading.DispatcherTimer
$shotTimer.Interval = [TimeSpan]::FromMilliseconds(1200)
$shotTimer.Add_Tick({
    # an error must not open the crash message (the run is unattended): written to a file, window closed
    try {
        $i = [int][Math]::Floor($script:ShotStep / 2)
        if ($i -ge $script:Shots.Count) { $shotTimer.Stop(); $window.Close(); return }
        $s = $script:Shots[$i]
        if ($script:ShotStep % 2 -eq 0) {
            Set-WTTheme $s.Theme
            Set-WTLogVisible (-not $s.NoLog)
            Select-WTPageById $s.Page
            Set-DemoCommon
            . $s.Fill
        } else {
            Set-DemoCommon
            Save-Shot $s.Name
        }
        $script:ShotStep++
    } catch {
        $shotTimer.Stop()
        "$($_.Exception.Message)`r`n$($_.InvocationInfo.PositionMessage)" | Set-Content -LiteralPath (Join-Path '__OUT__' 'error.txt')
        $window.Close()
    }
})
$shotTimer.Start()
'@
$hook = $hook.Replace('__OUT__', $out)
$main = $main.Replace('$timer.Start()', "`$timer.Start()`r`n$hook")
. ([scriptblock]::Create($main))
"Screenshots ($Language): $out"
