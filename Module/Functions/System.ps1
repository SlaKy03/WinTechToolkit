# System information, disk health, restore point, battery.

function Test-WTPendingReboot {
    # Reasons why Windows is waiting for a restart (empty = none)
    $reasons = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons += 'Component Based Servicing' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons += 'Windows Update' }
    $pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($pfro) { $reasons += 'Pending file renames' }
    $reasons
}

function Test-WTRebootRequired {
    # File renames are queued by many installers and can stay there for days: on their own
    # they are not a reason to restart before working on the PC
    param([string[]]$Reasons)
    [bool]@($Reasons | Where-Object { $_ -and $_ -ne 'Pending file renames' }).Count
}

function Format-WTRebootReasons {
    # The reasons of Test-WTPendingReboot as text in the interface language
    param([string[]]$Reasons)
    (@($Reasons | ForEach-Object { if ($_ -eq 'Pending file renames') { T 'Pending file renames' } else { $_ } })) -join ', '
}

function Get-WTStateText {
    # BitLocker, Secure Boot, TPM and disk health states (on, off, Healthy...) in the interface language
    param([string]$State)
    switch -Regex ($State) {
        '^on$' { return T 'on' }
        '^off$' { return T 'off' }
        '^unknown$' { return T 'unknown' }
        '^not supported$' { return T 'not supported' }
        '^encrypting$' { return T 'encrypting' }
        '^suspended$' { return T 'suspended' }
        '^absent$' { return T 'absent' }
        '^n/a$' { return T 'n/a' }
        '^n/a \(code (.*)\)$' { return T 'n/a (code {0})' $Matches[1] }
        '^(.+) on$' { return "$($Matches[1]) $(T 'on')" }
        '^(.+) off$' { return "$($Matches[1]) $(T 'off')" }
        '^Healthy$' { return T 'Healthy' }
        '^Warning$' { return T 'Warning' }
        '^Unhealthy$' { return T 'Unhealthy' }
    }
    $State
}

function Get-WTSecurityState {
    # BitLocker, Secure Boot and TPM without their cmdlets, which are slow.
    # Without privileges the BitLocker and TPM CIM namespaces take seconds just to answer "access denied".
    param([switch]$Detailed)
    $admin = Test-WTAdmin

    $bl = 'n/a'; $blPct = $null
    if ($admin) {
        try {
            $v = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume `
                -Filter "DriveLetter='$env:SystemDrive'" -ErrorAction Stop
            if ($v) {
                $bl = switch ([int]$v.ProtectionStatus) { 0 { 'off' } 1 { 'on' } default { 'unknown' } }
                if ($Detailed) {
                    $cs = Invoke-CimMethod -InputObject $v -MethodName GetConversionStatus -ErrorAction SilentlyContinue
                    if ($cs) { $blPct = $cs.EncryptionPercentage }
                }
            } else { $bl = 'not supported' }
        } catch { }
    } else {
        # without privileges: the same data File Explorer shows
        try {
            $state = (New-Object -ComObject Shell.Application).NameSpace($env:SystemDrive).Self.ExtendedProperty('System.Volume.BitLockerProtection')
            $bl = switch ([int]$state) { 1 { 'on' } 2 { 'off' } 3 { 'encrypting' } 5 { 'suspended' } default { "n/a (code $state)" } }
        } catch { }
    }

    $sb = 'not supported'
    $sbv = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue).UEFISecureBootEnabled
    if ($null -ne $sbv) { $sb = if ($sbv -eq 1) { 'on' } else { 'off' } }

    $tpm = 'n/a'
    if ($admin) { try {
        $t = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        if (-not $t) { $tpm = 'absent' }
        else {
            $ver = ("$($t.SpecVersion)" -split ',')[0].Trim()
            $tpm = if ($t.IsEnabled_InitialValue -and $t.IsActivated_InitialValue) { "$ver on" } else { "$ver off" }
        }
    } catch { } }

    [pscustomobject]@{ BitLocker = $bl; BitLockerPercent = $blPct; SecureBoot = $sb; Tpm = $tpm }
}

function Get-WTSystemInfo {
    # Text inventory of the computer, meant to be pasted into a ticket
    $L = New-Object Collections.Generic.List[string]
    # the label is translated (T)
    function Add-Line($Label, $Value) { $L.Add(('{0,-26}: {1}' -f (T $Label), $Value)) }

    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $L.Add((T '=== COMPUTER ==='))
    Add-Line 'Computer name' $env:COMPUTERNAME
    if ($cs.PartOfDomain) { Add-Line 'Domain' $cs.Domain } else { Add-Line 'Workgroup' $cs.Workgroup }
    Add-Line 'Signed-in user' $(if ($cs.UserName) { $cs.UserName } else { T '(none)' })
    Add-Line 'Manufacturer' $cs.Manufacturer
    Add-Line 'Model' $cs.Model
    Add-Line 'Serial number' $bios.SerialNumber
    Add-Line 'BIOS' (T '{0} dated {1:yyyy-MM-dd}' $bios.SMBIOSBIOSVersion $bios.ReleaseDate)

    $L.Add(''); $L.Add((T '=== OPERATING SYSTEM ==='))
    Add-Line 'System' $os.Caption
    Add-Line 'Version' ('{0} (build {1}.{2})' -f $cv.DisplayVersion, $os.BuildNumber, $cv.UBR)
    Add-Line 'Architecture' $os.OSArchitecture
    Add-Line 'Installed on' $os.InstallDate.ToString('yyyy-MM-dd HH:mm')
    $up = (Get-Date) - $os.LastBootUpTime
    Add-Line 'Last boot' (T '{0:yyyy-MM-dd HH:mm} (up for {1})' $os.LastBootUpTime (Format-WTUptime $up))
    $pending = @(Test-WTPendingReboot)
    Add-Line 'Restart pending' $(if (Test-WTRebootRequired $pending) { T 'YES - {0}' (Format-WTRebootReasons $pending) }
        elseif ($pending.Count) { T 'No (only file renames queued by installers)' } else { T 'No' })
    # InstalledOn arrives as an "M/d/yyyy" string and is sometimes empty or in odd formats
    $hf = Get-CimInstance Win32_QuickFixEngineering -ErrorAction SilentlyContinue | ForEach-Object {
        $d = [datetime]::MinValue
        if ([datetime]::TryParse("$($_.InstalledOn)", [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) {
            [pscustomobject]@{ Id = $_.HotFixID; Date = $d }
        }
    } | Sort-Object Date -Descending | Select-Object -First 1
    if ($hf) { Add-Line 'Latest update' (T '{0} dated {1:yyyy-MM-dd}' $hf.Id $hf.Date) }

    $L.Add(''); $L.Add('=== HARDWARE ===')
    Add-Line 'CPU' $cpu.Name.Trim()
    Add-Line 'RAM' ('{0:N1} GB' -f ($cs.TotalPhysicalMemory / 1GB))
    foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
        $pct = if ($d.Size) { [math]::Round($d.FreeSpace / $d.Size * 100) } else { 0 }
        $L.Add(('{0,-26}: {1}' -f (T 'Volume {0}' $d.DeviceID), (T '{0} free of {1} ({2}% free)' (Format-WTSize $d.FreeSpace) (Format-WTSize $d.Size) $pct)))
    }
    foreach ($pd in Get-WTPhysicalDiskInfo) {
        Add-Line 'Physical disk' ('{0} - {1} {2} - {3} - {4}' -f $pd.Name, $pd.MediaType, $pd.BusType, $pd.SizeText, (Get-WTStateText $pd.Health))
    }

    $L.Add(''); $L.Add((T '=== SECURITY ==='))
    $sec = Get-WTSecurityState -Detailed
    $bl = Get-WTStateText $sec.BitLocker
    Add-Line 'BitLocker' $(if ($null -ne $sec.BitLockerPercent) { T '{0} ({1}% encrypted)' $bl $sec.BitLockerPercent } else { $bl })
    Add-Line 'TPM' (Get-WTStateText $sec.Tpm)
    Add-Line 'Secure Boot' (Get-WTStateText $sec.SecureBoot)
    try {
        $av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop
        Add-Line 'Antivirus' ((@($av.displayName) | Select-Object -Unique) -join ', ')
    } catch { }

    $L.Add(''); $L.Add((T '=== NETWORK ==='))
    foreach ($n in Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE') {
        Add-Line 'Adapter' $n.Description
        Add-Line '  MAC' $n.MACAddress
        Add-Line '  IP' (@($n.IPAddress) -join ', ')
        Add-Line '  Gateway' (@($n.DefaultIPGateway) -join ', ')
        Add-Line '  DNS' (@($n.DNSServerSearchOrder) -join ', ')
        Add-Line '  DHCP' $(if ($n.DHCPEnabled) { T 'Yes ({0})' $n.DHCPServer } else { T 'No (static IP)' })
    }
    $L -join [Environment]::NewLine
}

function Get-WTSystemSummary {
    # Data for the Dashboard cards
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    $net = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' | Where-Object { $_.DefaultIPGateway } | Select-Object -First 1
    $up = (Get-Date) - $os.LastBootUpTime
    $pending = @(Test-WTPendingReboot)
    $sec = Get-WTSecurityState

    $ramTotal = [double]$os.TotalVisibleMemorySize * 1KB
    $ramFree = [double]$os.FreePhysicalMemory * 1KB
    $diskPct = if ($disk.Size) { [int][math]::Round(100 - $disk.FreeSpace / $disk.Size * 100) } else { 0 }

    [pscustomobject]@{
        Computer      = $env:COMPUTERNAME
        Model         = $(if ("$($cs.Model)".StartsWith("$($cs.Manufacturer)")) { "$($cs.Model)" } else { "$($cs.Manufacturer) $($cs.Model)".Trim() })
        Serial        = $bios.SerialNumber
        User          = $cs.UserName
        OS            = $os.Caption -replace '^Microsoft\s+', ''
        Version       = '{0} · build {1}.{2}' -f $cv.DisplayVersion, $os.BuildNumber, $cv.UBR
        Uptime        = Format-WTUptime $up
        UptimeDays    = $up.TotalDays
        LastBoot      = $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm')
        PendingReboot = Test-WTRebootRequired $pending
        PendingRenames = $pending -contains 'Pending file renames'
        PendingText   = Format-WTRebootReasons $pending
        DiskFreeText  = Format-WTSize $disk.FreeSpace
        DiskTotalText = Format-WTSize $disk.Size
        DiskUsedPct   = $diskPct
        RamText       = '{0:N1} GB' -f ($ramTotal / 1GB)
        RamUsedPct    = [int][math]::Round((1 - $ramFree / $ramTotal) * 100)
        IP            = $(if ($net) { @($net.IPAddress | Where-Object { $_ -notmatch ':' })[0] } else { T 'not connected' })
        Domain        = $(if ($cs.PartOfDomain) { $cs.Domain } else { T 'Workgroup {0}' $cs.Workgroup })
        DomainName    = $(if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup })
        BitLocker     = $sec.BitLocker
        SecureBoot    = $sec.SecureBoot
        Tpm           = $sec.Tpm
        Bsod          = Measure-WTEvents -Log System -Providers 'Microsoft-Windows-WER-SystemErrorReporting', 'BugCheck' -Ids 1001 -Days 7
        Unexpected    = Measure-WTEvents -Log System -Providers 'Microsoft-Windows-Kernel-Power' -Ids 41 -Days 7
        AppCrash      = Measure-WTEvents -Log Application -Providers 'Application Error' -Ids 1000 -Days 7
    }
}

function ConvertTo-WTStorageText {
    # In the GUI runspaces the Storage type data is not always applied and the MSFT_PhysicalDisk
    # properties come back as raw codes (e.g. MediaType 4, HealthStatus 0)
    param($Value, [hashtable]$Map)
    $s = "$Value"
    if ($s -match '^\d+$' -and $Map.ContainsKey([int]$s)) { return $Map[[int]$s] }
    $s
}

$script:WTMediaTypes = @{ 0 = 'Unspecified'; 3 = 'HDD'; 4 = 'SSD'; 5 = 'SCM' }
$script:WTHealthStates = @{ 0 = 'Healthy'; 1 = 'Warning'; 2 = 'Unhealthy'; 5 = 'Unknown' }
$script:WTBusTypes = @{
    0 = 'Unknown'; 1 = 'SCSI'; 2 = 'ATAPI'; 3 = 'ATA'; 4 = '1394'; 5 = 'SSA'; 6 = 'Fibre Channel'; 7 = 'USB'; 8 = 'RAID'
    9 = 'iSCSI'; 10 = 'SAS'; 11 = 'SATA'; 12 = 'SD'; 13 = 'MMC'; 14 = 'Virtual'; 15 = 'File Backed Virtual'
    16 = 'Storage Spaces'; 17 = 'NVMe'; 18 = 'SCM'; 19 = 'UFS'
}
$script:WTOperationalStates = @{
    0 = 'Unknown'; 1 = 'Other'; 2 = 'OK'; 3 = 'Degraded'; 4 = 'Stressed'; 5 = 'Predictive Failure'; 6 = 'Error'
    7 = 'Non-Recoverable Error'; 8 = 'Starting'; 9 = 'Stopping'; 10 = 'Stopped'; 11 = 'In Service'; 12 = 'No Contact'
    13 = 'Lost Communication'; 14 = 'Aborted'; 15 = 'Dormant'; 16 = 'Supporting Entity in Error'; 17 = 'Completed'
    18 = 'Power Mode'; 53264 = 'In Maintenance'; 53265 = 'Not Usable'; 53266 = 'Transient Error'; 53267 = 'Starting'
    53268 = 'Stopping'; 53269 = 'Failed Media'; 53270 = 'Split'; 53271 = 'Stale Metadata'; 53272 = 'IO Error'
    53273 = 'Unrecognized Metadata'
}

function Get-WTPhysicalDiskInfo {
    # Physical disks with the SMART counters exposed by Windows
    try { $disks = @(Get-PhysicalDisk -ErrorAction Stop) } catch { return }
    foreach ($d in $disks) {
        $c = $null
        try { $c = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
        [pscustomobject]@{
            Name        = $d.FriendlyName
            MediaType   = ConvertTo-WTStorageText $d.MediaType $script:WTMediaTypes
            BusType     = ConvertTo-WTStorageText $d.BusType $script:WTBusTypes
            SizeText    = Format-WTSize $d.Size
            Health      = ConvertTo-WTStorageText $d.HealthStatus $script:WTHealthStates
            Operational = (@($d.OperationalStatus | ForEach-Object { ConvertTo-WTStorageText $_ $script:WTOperationalStates }) -join ', ')
            Temperature = $(if ($c -and $c.Temperature) { $c.Temperature } else { $null })
            Wear        = $(if ($c) { $c.Wear } else { $null })
            PowerOnHours = $(if ($c) { $c.PowerOnHours } else { $null })
            ReadErrors  = $(if ($c) { $c.ReadErrorsUncorrected } else { $null })
            WriteErrors = $(if ($c) { $c.WriteErrorsUncorrected } else { $null })
        }
    }
}

function Get-WTDiskHealth {
    # Disk status written to the log (health, temperature, wear, errors)
    $disks = @(Get-WTPhysicalDiskInfo)
    if (-not $disks.Count) { Write-WTLog 'Could not read the physical disks.' -Level Error; return }
    foreach ($d in $disks) {
        $lvl = if ($d.Health -eq 'Healthy') { 'OK' } else { 'Error' }
        Write-WTLog (T '{0} - {1} {2} - {3} - Status: {4} ({5})' $d.Name $d.MediaType $d.BusType $d.SizeText (Get-WTStateText $d.Health) $d.Operational) -Level $lvl
        $parts = @()
        if ($d.Temperature) { $parts += T 'temperature {0} °C' $d.Temperature }
        if ($null -ne $d.Wear) { $parts += T 'wear {0}%' $d.Wear }
        if ($d.PowerOnHours) { $parts += T 'power-on hours {0}' $d.PowerOnHours }
        if ($d.ReadErrors) { $parts += T 'uncorrected read errors {0}' $d.ReadErrors }
        if ($d.WriteErrors) { $parts += T 'uncorrected write errors {0}' $d.WriteErrors }
        if ($parts) {
            $warn = ($d.Wear -ge 80) -or ($d.ReadErrors -gt 0) -or ($d.WriteErrors -gt 0)
            Write-WTLog "   $($parts -join ', ')" -Level $(if ($warn) { 'Warn' } else { 'Info' })
        } else {
            Write-WTLog '   SMART counters not available for this disk.'
        }
    }
}

function New-WTRestorePoint {
    # Creates a restore point bypassing the one-every-24-hours limit
    param([string]$Description = ('WinTech Toolkit - {0:yyyy-MM-dd HH:mm}' -f (Get-Date)))
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $old = (Get-ItemProperty $key -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    try {
        New-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -Value 0 -PropertyType DWord -Force | Out-Null
        Write-WTLog (T "Creating restore point '{0}'..." $Description)
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
        Write-WTLog 'Restore point created.' -Level OK
        $true
    } catch {
        Write-WTLog (T 'Could not create the restore point: {0}' $_.Exception.Message) -Level Error
        Write-WTLog (T "Check that System Protection is on for {0} (Enable-ComputerRestore -Drive '{0}\')." $env:SystemDrive) -Level Warn
        $false
    } finally {
        if ($null -eq $old) { Remove-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
        else { New-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -Value $old -PropertyType DWord -Force | Out-Null }
    }
}

function New-WTBatteryReport {
    # powercfg battery report; returns the path of the HTML file
    if (-not (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)) {
        Write-WTLog 'No battery detected on this computer.' -Level Warn
        return
    }
    $file = Join-Path (Get-WTDataFolder) ('Report\Battery_{0}_{1:yyyyMMdd_HHmm}.html' -f $env:COMPUTERNAME, (Get-Date))
    $r = Invoke-WTProcess -FilePath 'powercfg.exe' -Arguments "/batteryreport /output `"$file`""
    if ($r.ExitCode -eq 0 -and (Test-Path -LiteralPath $file)) {
        Write-WTLog (T 'Battery report created: {0}' $file) -Level OK
        $file
    } else {
        Write-WTLog 'Could not create the battery report.' -Level Error
    }
}
