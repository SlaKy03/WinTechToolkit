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
    function Add-Line($Label, $Value) { $L.Add(('{0,-24}: {1}' -f $Label, $Value)) }

    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $L.Add('=== COMPUTER ===')
    Add-Line 'Computer name' $env:COMPUTERNAME
    if ($cs.PartOfDomain) { Add-Line 'Domain' $cs.Domain } else { Add-Line 'Workgroup' $cs.Workgroup }
    Add-Line 'Signed-in user' $(if ($cs.UserName) { $cs.UserName } else { '(none)' })
    Add-Line 'Manufacturer' $cs.Manufacturer
    Add-Line 'Model' $cs.Model
    Add-Line 'Serial number' $bios.SerialNumber
    Add-Line 'BIOS' ('{0} dated {1:yyyy-MM-dd}' -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)

    $L.Add(''); $L.Add('=== OPERATING SYSTEM ===')
    Add-Line 'System' $os.Caption
    Add-Line 'Version' ('{0} (build {1}.{2})' -f $cv.DisplayVersion, $os.BuildNumber, $cv.UBR)
    Add-Line 'Architecture' $os.OSArchitecture
    Add-Line 'Installed on' $os.InstallDate.ToString('yyyy-MM-dd HH:mm')
    $up = (Get-Date) - $os.LastBootUpTime
    Add-Line 'Last boot' ('{0:yyyy-MM-dd HH:mm} (up for {1})' -f $os.LastBootUpTime, (Format-WTUptime $up))
    $pending = @(Test-WTPendingReboot)
    Add-Line 'Restart pending' $(if ($pending.Count) { 'YES - ' + ($pending -join ', ') } else { 'No' })
    # InstalledOn arrives as an "M/d/yyyy" string and is sometimes empty or in odd formats
    $hf = Get-CimInstance Win32_QuickFixEngineering -ErrorAction SilentlyContinue | ForEach-Object {
        $d = [datetime]::MinValue
        if ([datetime]::TryParse("$($_.InstalledOn)", [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) {
            [pscustomobject]@{ Id = $_.HotFixID; Date = $d }
        }
    } | Sort-Object Date -Descending | Select-Object -First 1
    if ($hf) { Add-Line 'Latest update' ('{0} dated {1:yyyy-MM-dd}' -f $hf.Id, $hf.Date) }

    $L.Add(''); $L.Add('=== HARDWARE ===')
    Add-Line 'CPU' $cpu.Name.Trim()
    Add-Line 'RAM' ('{0:N1} GB' -f ($cs.TotalPhysicalMemory / 1GB))
    foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
        $pct = if ($d.Size) { [math]::Round($d.FreeSpace / $d.Size * 100) } else { 0 }
        Add-Line "Volume $($d.DeviceID)" ('{0} free of {1} ({2}% free)' -f (Format-WTSize $d.FreeSpace), (Format-WTSize $d.Size), $pct)
    }
    foreach ($pd in Get-WTPhysicalDiskInfo) {
        Add-Line 'Physical disk' ('{0} - {1} - {2} - Status: {3}' -f $pd.Name, $pd.MediaType, $pd.SizeText, $pd.Health)
    }

    $L.Add(''); $L.Add('=== SECURITY ===')
    $sec = Get-WTSecurityState -Detailed
    Add-Line 'BitLocker' $(if ($null -ne $sec.BitLockerPercent) { "$($sec.BitLocker) ($($sec.BitLockerPercent)% encrypted)" } else { $sec.BitLocker })
    Add-Line 'TPM' $sec.Tpm
    Add-Line 'Secure Boot' $sec.SecureBoot
    try {
        $av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop
        Add-Line 'Antivirus' ((@($av.displayName) | Select-Object -Unique) -join ', ')
    } catch { }

    $L.Add(''); $L.Add('=== NETWORK ===')
    foreach ($n in Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE') {
        Add-Line 'Adapter' $n.Description
        Add-Line '  MAC' $n.MACAddress
        Add-Line '  IP' (@($n.IPAddress) -join ', ')
        Add-Line '  Gateway' (@($n.DefaultIPGateway) -join ', ')
        Add-Line '  DNS' (@($n.DNSServerSearchOrder) -join ', ')
        Add-Line '  DHCP' $(if ($n.DHCPEnabled) { "Yes ($($n.DHCPServer))" } else { 'No (static IP)' })
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
        PendingReboot = [bool]$pending.Count
        PendingText   = $pending -join ', '
        DiskFreeText  = Format-WTSize $disk.FreeSpace
        DiskTotalText = Format-WTSize $disk.Size
        DiskUsedPct   = $diskPct
        RamText       = '{0:N1} GB' -f ($ramTotal / 1GB)
        RamUsedPct    = [int][math]::Round((1 - $ramFree / $ramTotal) * 100)
        IP            = $(if ($net) { @($net.IPAddress | Where-Object { $_ -notmatch ':' })[0] } else { 'not connected' })
        Domain        = $(if ($cs.PartOfDomain) { $cs.Domain } else { "Workgroup $($cs.Workgroup)" })
        BitLocker     = $sec.BitLocker
        SecureBoot    = $sec.SecureBoot
        Tpm           = $sec.Tpm
        Bsod          = Measure-WTEvents -Log System -Providers 'Microsoft-Windows-WER-SystemErrorReporting', 'BugCheck' -Ids 1001 -Days 7
        Unexpected    = Measure-WTEvents -Log System -Providers 'Microsoft-Windows-Kernel-Power' -Ids 41 -Days 7
        AppCrash      = Measure-WTEvents -Log Application -Providers 'Application Error' -Ids 1000 -Days 7
    }
}

function Get-WTPhysicalDiskInfo {
    # Physical disks with the SMART counters exposed by Windows
    try { $disks = @(Get-PhysicalDisk -ErrorAction Stop) } catch { return }
    foreach ($d in $disks) {
        $c = $null
        try { $c = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
        [pscustomobject]@{
            Name        = $d.FriendlyName
            MediaType   = "$($d.MediaType)"
            BusType     = "$($d.BusType)"
            SizeText    = Format-WTSize $d.Size
            Health      = "$($d.HealthStatus)"
            Operational = (@($d.OperationalStatus) -join ', ')
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
        Write-WTLog ('{0} - {1} {2} - {3} - Status: {4} ({5})' -f $d.Name, $d.MediaType, $d.BusType, $d.SizeText, $d.Health, $d.Operational) -Level $lvl
        $parts = @()
        if ($d.Temperature) { $parts += "temperature $($d.Temperature) °C" }
        if ($null -ne $d.Wear) { $parts += "wear $($d.Wear)%" }
        if ($d.PowerOnHours) { $parts += "power-on hours $($d.PowerOnHours)" }
        if ($d.ReadErrors) { $parts += "uncorrected read errors $($d.ReadErrors)" }
        if ($d.WriteErrors) { $parts += "uncorrected write errors $($d.WriteErrors)" }
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
        Write-WTLog "Creating restore point '$Description'..."
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
        Write-WTLog 'Restore point created.' -Level OK
        $true
    } catch {
        Write-WTLog "Could not create the restore point: $($_.Exception.Message)" -Level Error
        Write-WTLog "Check that System Protection is on for $env:SystemDrive (Enable-ComputerRestore -Drive '$env:SystemDrive\')." -Level Warn
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
        Write-WTLog "Battery report created: $file" -Level OK
        $file
    } else {
        Write-WTLog 'Could not create the battery report.' -Level Error
    }
}
