# Event log analysis: BSODs, crashes, shutdowns, disk, hardware, updates, network/domain, failed logons, reliability.

# Most common stop codes (BugCheck), key = hex without leading zeros
$script:WTBugChecks = @{
    'A' = 'IRQL_NOT_LESS_OR_EQUAL'; '19' = 'BAD_POOL_HEADER'; '1A' = 'MEMORY_MANAGEMENT'; '1E' = 'KMODE_EXCEPTION_NOT_HANDLED'
    '24' = 'NTFS_FILE_SYSTEM'; '3B' = 'SYSTEM_SERVICE_EXCEPTION'; '4E' = 'PFN_LIST_CORRUPT'; '50' = 'PAGE_FAULT_IN_NONPAGED_AREA'
    '7A' = 'KERNEL_DATA_INPAGE_ERROR'; '7B' = 'INACCESSIBLE_BOOT_DEVICE'; '7E' = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED'
    '7F' = 'UNEXPECTED_KERNEL_MODE_TRAP'; '9C' = 'MACHINE_CHECK_EXCEPTION'; '9F' = 'DRIVER_POWER_STATE_FAILURE'
    'A0' = 'INTERNAL_POWER_ERROR'; 'BE' = 'ATTEMPTED_WRITE_TO_READONLY_MEMORY'; 'C2' = 'BAD_POOL_CALLER'
    'C4' = 'DRIVER_VERIFIER_DETECTED_VIOLATION'; 'C5' = 'DRIVER_CORRUPTED_EXPOOL'; 'D1' = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL'
    'ED' = 'UNMOUNTABLE_BOOT_VOLUME'; 'EF' = 'CRITICAL_PROCESS_DIED'; 'F4' = 'CRITICAL_OBJECT_TERMINATION'
    'FC' = 'ATTEMPTED_EXECUTE_OF_NOEXECUTE_MEMORY'; '101' = 'CLOCK_WATCHDOG_TIMEOUT'; '109' = 'CRITICAL_STRUCTURE_CORRUPTION'
    '10D' = 'WDF_VIOLATION'; '10E' = 'VIDEO_MEMORY_MANAGEMENT_INTERNAL'; '116' = 'VIDEO_TDR_FAILURE'
    '117' = 'VIDEO_TDR_TIMEOUT_DETECTED'; '119' = 'VIDEO_SCHEDULER_INTERNAL_ERROR'; '124' = 'WHEA_UNCORRECTABLE_ERROR'
    '133' = 'DPC_WATCHDOG_VIOLATION'; '139' = 'KERNEL_SECURITY_CHECK_FAILURE'; '13A' = 'KERNEL_MODE_HEAP_CORRUPTION'
    '141' = 'VIDEO_ENGINE_TIMEOUT_DETECTED'; '154' = 'UNEXPECTED_STORE_EXCEPTION'; '1C8' = 'MANUALLY_INITIATED_POWER_BUTTON_HOLD'
    'C000021A' = 'STATUS_SYSTEM_PROCESS_TERMINATED'
}

function Get-WTBugCheckHints {
    # Built on every call: the hints are in the interface language
    @(
        @{ Codes = '1A', '50', '4E', '19', 'C2', '13A', 'C5'; Hint = (T 'possible RAM or driver problem: run Windows Memory Diagnostic (mdsched) and update the drivers.') }
        @{ Codes = '116', '117', '119', '10E', '141'; Hint = (T 'video/GPU driver: update or cleanly reinstall the graphics driver, check GPU temperatures and power supply.') }
        @{ Codes = 'A', 'D1', '3B', '7E', '1E', 'C4', '10D', 'FC', 'BE', '139', '109'; Hint = (T 'faulty driver: analyze the minidump (WinDbg or BlueScreenView) to find the responsible .sys file, update drivers and BIOS.') }
        @{ Codes = '9F', 'A0'; Hint = (T 'power management: update the drivers (network, chipset, USB) and the BIOS, check sleep and hibernation.') }
        @{ Codes = '124', '9C', '101', '7F'; Hint = (T 'hardware error (CPU, RAM, motherboard, power supply or overheating): check the WHEA events and temperatures, and update the BIOS.') }
        @{ Codes = '7A', '24', '7B', 'ED', '154', 'F4'; Hint = (T 'disk/storage: check the SMART status, run CHKDSK, update SSD firmware and controller drivers.') }
        @{ Codes = '133'; Hint = (T 'often storage drivers (iaStor, stornvme) or SSD firmware: update chipset/storage drivers and the BIOS.') }
        @{ Codes = 'EF', 'C000021A'; Hint = (T 'critical process terminated: run DISM + SFC, check the antivirus and recently installed updates.') }
        @{ Codes = '1C8'; Hint = (T 'shutdown forced manually by holding the power button.') }
    )
}

function Get-WTEventCategory {
    <#
    .SYNOPSIS
        An event category: name in the interface language and queries (log + provider/ID/levels,
        XPath filter). Without -Category, the list of the categories.
    #>
    param([string]$Category)
    $all = [ordered]@{
        Bsod      = @{ Name = (T 'Blue screens (BSOD)'); Queries = @(
                @{ Log = 'System'; Providers = 'Microsoft-Windows-WER-SystemErrorReporting', 'BugCheck'; Ids = 1001 }) }
        Shutdown  = @{ Name = (T 'Shutdowns and restarts'); Queries = @(
                @{ Log = 'System'; Providers = 'Microsoft-Windows-Kernel-Power'; Ids = 41 },
                @{ Log = 'System'; Providers = 'EventLog'; Ids = 6005, 6006, 6008 },
                @{ Log = 'System'; Providers = 'User32'; Ids = 1074 }) }
        AppCrash  = @{ Name = (T 'Application crashes'); Queries = @(
                @{ Log = 'Application'; Providers = 'Application Error'; Ids = 1000 },
                @{ Log = 'Application'; Providers = '.NET Runtime'; Ids = 1026 }) }
        AppHang   = @{ Name = (T 'Application hangs'); Queries = @(
                @{ Log = 'Application'; Providers = 'Application Hang'; Ids = 1002 }) }
        Disk      = @{ Name = (T 'Disk and file system'); Queries = @(
                @{ Log = 'System'; Providers = 'disk', 'Ntfs', 'Microsoft-Windows-Ntfs', 'volmgr', 'storahci', 'stornvme', 'iaStorA', 'iaStorAC', 'iaStorAVC', 'Microsoft-Windows-StorPort', 'Microsoft-Windows-Disk'; Levels = 1, 2, 3 }) }
        Hardware  = @{ Name = (T 'Hardware and drivers'); Queries = @(
                @{ Log = 'System'; Providers = 'Microsoft-Windows-WHEA-Logger'; Levels = 1, 2, 3 },
                @{ Log = 'System'; Providers = 'Display'; Ids = 4101 },
                @{ Log = 'System'; Providers = 'Microsoft-Windows-Kernel-PnP'; Ids = 219, 411 },
                @{ Log = 'System'; Providers = 'Microsoft-Windows-Resource-Exhaustion-Detector'; Ids = 2004 }) }
        Updates   = @{ Name = 'Windows Update'; Queries = @(
                @{ Log = 'System'; Providers = 'Microsoft-Windows-WindowsUpdateClient'; Levels = 1, 2 },
                @{ Log = 'Setup'; Levels = 1, 2 }) }
        Services  = @{ Name = (T 'Services'); Queries = @(
                @{ Log = 'System'; Providers = 'Service Control Manager'; Levels = 1, 2 }) }
        Network   = @{ Name = (T 'Network and domain'); Queries = @(
                @{ Log = 'System'; Providers = 'NETLOGON', 'Microsoft-Windows-GroupPolicy', 'Microsoft-Windows-Dhcp-Client', 'Microsoft-Windows-Time-Service'; Levels = 1, 2 },
                @{ Log = 'System'; Providers = 'Microsoft-Windows-DNS-Client'; Ids = 1014 },
                @{ Log = 'System'; Providers = 'Tcpip'; Ids = 4199 }) }
        Logon     = @{ Name = (T 'Failed sign-ins'); Queries = @(
                @{ Log = 'Security'; Providers = 'Microsoft-Windows-Security-Auditing'; Ids = 4625, 4740 }) }
        Install   = @{ Name = (T 'Software installations'); Queries = @(
                @{ Log = 'Application'; Providers = 'MsiInstaller'; Ids = 1033, 1034, 11707, 11708, 11724 },
                @{ Log = 'System'; Providers = 'Microsoft-Windows-WindowsUpdateClient'; Ids = 19 }) }
        AllErrors = @{ Name = (T 'All errors'); Queries = @(
                @{ Log = 'System'; Levels = 1, 2 },
                @{ Log = 'Application'; Levels = 1, 2 }) }
    }
    if ($Category) { $all[$Category] } else { $all }
}

function Get-WTLevelText {
    # Event level in the interface language (Level stays Critical/Error/Warning/Info for the checks)
    param([string]$Level)
    switch ($Level) { 'Critical' { T 'Critical' } 'Error' { T 'Error' } 'Warning' { T 'Warning' } default { T 'Info' } }
}

function New-WTEventXPath {
    <# Builds an XPath filter (does not fail if a provider does not exist on the PC). #>
    param([string[]]$Providers, [int[]]$Ids, [int[]]$Levels, [int]$Days = 7)
    $parts = @()
    if ($Providers) { $parts += 'Provider[' + (($Providers | ForEach-Object { "@Name='$_'" }) -join ' or ') + ']' }
    if ($Ids) { $parts += '(' + (($Ids | ForEach-Object { "EventID=$_" }) -join ' or ') + ')' }
    if ($Levels) { $parts += '(' + (($Levels | ForEach-Object { "Level=$_" }) -join ' or ') + ')' }
    $parts += 'TimeCreated[timediff(@SystemTime) <= {0}]' -f ([int64]$Days * 86400000)
    '*[System[' + ($parts -join ' and ') + ']]'
}

function Measure-WTEvents {
    <# Counts the events matching the filter (maximum 1000). #>
    param([string]$Log, [string[]]$Providers, [int[]]$Ids, [int[]]$Levels, [int]$Days = 7)
    $xp = New-WTEventXPath -Providers $Providers -Ids $Ids -Levels $Levels -Days $Days
    try { @(Get-WinEvent -LogName $Log -FilterXPath $xp -MaxEvents 1000 -ErrorAction Stop).Count } catch { 0 }
}

function Get-WTBugCheckInfo {
    <# Name and suggestion for a BugCheck code (e.g. 0x00000116 or 0x1000007e). #>
    param([Parameter(Mandatory)][string]$Hex)
    $h = ($Hex.ToUpper() -replace '^0X', '').PadLeft(8, '0')
    if ($h.Length -eq 8 -and $h[0] -eq '1') { $h = '0' + $h.Substring(1) }   # 0x1000007E = 0x7E with 64-bit parameters
    $key = $h.TrimStart('0')
    if (-not $key) { $key = '0' }
    $name = $script:WTBugChecks[$key]
    if (-not $name) { $name = T 'code not in list' }
    $hint = (Get-WTBugCheckHints | Where-Object { $_.Codes -contains $key } | Select-Object -First 1).Hint
    [pscustomobject]@{ Code = '0x' + $key.PadLeft(8, '0'); Name = $name; Hint = $hint }
}

function Get-WTEventData {
    <# Event data: by index ("0","1"...) and, when present, by name. #>
    param($Record)
    $d = @{}
    $i = 0
    foreach ($p in $Record.Properties) { $d["$i"] = $p.Value; $i++ }
    try {
        $xml = [xml]$Record.ToXml()
        foreach ($n in @($xml.Event.EventData.Data)) {
            if ($n -is [Xml.XmlElement]) {
                $name = $n.GetAttribute('Name')
                if ($name) { $d[$name] = $n.InnerText }
            }
        }
    } catch { }
    $d
}

function Get-WTExceptionName {
    param([string]$Code)
    switch -Regex ("$Code".ToLower()) {
        'c0000005' { return T 'access violation' }
        'c0000409' { return T 'stack buffer overrun' }
        'e0434352' { return T 'unhandled .NET exception' }
        'c0000374' { return T 'heap corruption' }
        '80000003' { return 'breakpoint' }
        'c00000fd' { return 'stack overflow' }
        'c0000135' { return T 'DLL not found' }
        'c0000602' { return 'fail fast' }
        'c0000006' { return T 'in-page I/O error' }
        'c000001d' { return T 'illegal instruction' }
    }
    ''
}

function Get-WTLogonFailureReason {
    param([string]$Code)
    switch ("$Code".ToLower()) {
        '0xc000006a' { return T 'wrong password' }
        '0xc0000064' { return T 'user does not exist' }
        '0xc000006d' { return T 'wrong user name or password' }
        '0xc0000234' { return T 'account locked out' }
        '0xc0000072' { return T 'account disabled' }
        '0xc000006f' { return T 'outside allowed hours' }
        '0xc0000070' { return T 'workstation not allowed' }
        '0xc0000071' { return T 'password expired' }
        '0xc0000193' { return T 'account expired' }
        '0xc0000224' { return T 'password change required' }
        '0xc000015b' { return T 'logon type not granted' }
        '0xc0000133' { return T 'clock not synchronized with the DC' }
    }
    T 'code {0}' $Code
}

function Get-WTLogonTypeName {
    param($Type)
    switch ("$Type") {
        '2' { return T 'interactive' }
        '3' { return T 'network' }
        '4' { return 'batch' }
        '5' { return T 'service' }
        '7' { return T 'unlock' }
        '8' { return T 'network (clear text)' }
        '10' { return T 'Remote Desktop' }
        '11' { return T 'cached credentials' }
    }
    "$Type"
}

function Get-WTEventSummary {
    <#
    .SYNOPSIS
        Readable interpretation of the main events. $Info (optional hashtable) receives App and
        Module of crashes and hangs, and NoBsod for the unexpected shutdowns without a blue
        screen: the diagnosis uses them instead of parsing the translated text.
    #>
    param($Record, [string]$Message, [hashtable]$Info = @{})
    $lines = @(($Message -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $first = "$($lines | Select-Object -First 1)"
    # "Service X terminated with the error:" - the useful part is on the next line
    if ($first.EndsWith(':') -and $lines.Count -gt 1) { $first = "$first $($lines[1])" }
    if ($first.Length -gt 220) { $first = $first.Substring(0, 220) + '...' }
    $p = $Record.ProviderName
    $id = $Record.Id

    if ($id -eq 1001 -and $p -match 'WER-SystemErrorReporting|BugCheck') {
        if ($Message -match '0x[0-9A-Fa-f]{8}') {
            $b = Get-WTBugCheckInfo $Matches[0]
            $s = "BSOD $($b.Code) $($b.Name)"
            if ($Message -match '([A-Za-z]:\\\S+?\.dmp)') { $s += " - dump: $($Matches[1])" }
            return $s
        }
        return T 'Blue screen - {0}' $first
    }
    if ($p -eq 'Microsoft-Windows-Kernel-Power' -and $id -eq 41) {
        $d = Get-WTEventData $Record
        $code = $d['BugcheckCode']
        if ($null -eq $code) { $code = $d['0'] }
        if ($code -and [int64]$code -ne 0) {
            $b = Get-WTBugCheckInfo ('{0:X}' -f [int64]$code)
            return T 'Restart after BSOD {0} {1}' $b.Code $b.Name
        }
        $Info.NoBsod = $true
        return T 'Unexpected shutdown without a BSOD: power loss, power button held, total freeze or flat battery'
    }
    if ($p -eq 'EventLog') {
        if ($id -eq 6005) { return T 'System startup' }
        if ($id -eq 6006) { return T 'Clean system shutdown' }
        if ($id -eq 6008) { return T 'Unexpected shutdown: {0}' $first }
    }
    if ($p -eq 'User32' -and $id -eq 1074) {
        $d = Get-WTEventData $Record
        $proc = Split-Path ("$($d['0'])" -replace '\s*\(.*$', '') -Leaf
        return T '{0} requested by {1} through {2} - {3}' $d['4'] $d['6'] $proc $d['2']
    }
    if ($p -eq 'Application Error' -and $id -eq 1000) {
        $d = Get-WTEventData $Record
        $ex = "$($d['6'])" -replace '^0x', ''
        $exName = Get-WTExceptionName $ex
        $Info.App = "$($d['0'])"; $Info.Module = "$($d['3'])"
        $s = T 'Crash of {0} {1} - module {2} {3} - exception 0x{4}' $d['0'] $d['1'] $d['3'] $d['4'] $ex
        if ($exName) { $s += " ($exName)" }
        return $s
    }
    if ($p -eq 'Application Hang' -and $id -eq 1002) {
        $d = Get-WTEventData $Record
        $Info.App = "$($d['0'])"
        return T 'Hang (not responding) of {0} {1}' $d['0'] $d['1']
    }
    if ($p -eq '.NET Runtime' -and $id -eq 1026) {
        $app = if ($Message -match 'Application:\s*(.+)') { $Matches[1].Trim() } else { '?' }
        $exc = if ($Message -match 'Exception Info:\s*(.+)') { $Matches[1].Trim() } else { $first }
        $Info.App = $app
        return T 'Crash of .NET app {0} - {1}' $app $exc
    }
    if ($p -eq 'Microsoft-Windows-Security-Auditing' -and $id -eq 4625) {
        $d = Get-WTEventData $Record
        $sub = "$($d['SubStatus'])"
        if (-not $sub -or $sub -eq '0x0') { $sub = "$($d['Status'])" }
        return T 'Failed sign-in: {0}\{1} - {2} - type {3} - from {4} {5}' $d['TargetDomainName'] $d['TargetUserName'] `
            (Get-WTLogonFailureReason $sub) (Get-WTLogonTypeName $d['LogonType']) $d['WorkstationName'] $d['IpAddress']
    }
    if ($p -eq 'Microsoft-Windows-Security-Auditing' -and $id -eq 4740) {
        $d = Get-WTEventData $Record
        return T 'Account locked out: {0} (source: {1})' $d['TargetUserName'] $d['TargetDomainName']
    }
    if ($p -eq 'Display' -and $id -eq 4101) { return T 'Video driver stopped responding and recovered (TDR): {0}' $first }
    if ($p -eq 'Microsoft-Windows-Resource-Exhaustion-Detector') { return T 'Low virtual memory: {0}' $first }
    if ($p -eq 'Tcpip' -and $id -eq 4199) { return T 'IP address conflict: {0}' $first }
    $first
}

function ConvertTo-WTEventRow {
    param($Record, [string]$Category)
    $msg = ''
    try { $msg = $Record.Message } catch { }
    if (-not $msg) { $msg = (T '(description not available)') + ' ' + ((@($Record.Properties) | ForEach-Object { "$($_.Value)" }) -join ' | ') }
    $level = switch ($Record.Level) { 1 { 'Critical' } 2 { 'Error' } 3 { 'Warning' } default { 'Info' } }
    if ($Record.LogName -eq 'Security' -and ($Record.Id -eq 4625 -or $Record.Id -eq 4740)) { $level = 'Warning' }
    $info = @{ App = ''; Module = ''; NoBsod = $false }
    $summary = Get-WTEventSummary -Record $Record -Message $msg -Info $info
    [pscustomobject]@{
        Time      = $Record.TimeCreated
        TimeText  = $Record.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
        Level     = $level
        LevelText = Get-WTLevelText $level
        Category  = $Category
        Source    = $Record.ProviderName
        Id        = $Record.Id
        Log       = $Record.LogName
        Summary   = $summary
        Message   = $msg
        App       = $info.App
        Module    = $info.Module
        NoBsod    = $info.NoBsod
    }
}

function Get-WTEvents {
    <#
    .SYNOPSIS
        Events of a category (Bsod, Shutdown, AppCrash, AppHang, Disk, Hardware,
        Updates, Services, Network, Logon, Install, AllErrors) with interpretation.
    #>
    param([Parameter(Mandatory)][string]$Category, [int]$Days = 7, [int]$MaxPerQuery = 300, [switch]$Quiet)
    $cat = Get-WTEventCategory $Category
    if (-not $cat) { throw "Unknown category: $Category" }
    $rows = New-Object Collections.Generic.List[object]
    foreach ($q in $cat.Queries) {
        $xp = New-WTEventXPath -Providers $q.Providers -Ids $q.Ids -Levels $q.Levels -Days $Days
        try {
            $events = @(Get-WinEvent -LogName $q.Log -FilterXPath $xp -MaxEvents $MaxPerQuery -ErrorAction Stop)
        } catch {
            if ($_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound') { Write-WTLog (T 'Log {0}: {1}' $q.Log $_.Exception.Message) -Level Warn }
            continue
        }
        foreach ($e in $events) { $rows.Add((ConvertTo-WTEventRow -Record $e -Category $cat.Name)) }
    }
    if (-not $Quiet) {
        Write-WTLog (T '{0}: {1} events in the last {2} days.' $cat.Name $rows.Count $Days) -Level $(if ($rows.Count) { 'Warn' } else { 'OK' })
    }
    $rows | Sort-Object Time -Descending
}

function Get-WTStabilityIndex {
    <# Latest stability index (1-10) from Reliability Monitor. #>
    try {
        $m = Get-CimInstance -ClassName Win32_ReliabilityStabilityMetrics -ErrorAction Stop | Sort-Object TimeGenerated -Descending | Select-Object -First 1
        if ($m) { [double]$m.SystemStabilityIndex }
    } catch { }
}

function Get-WTReliabilityHistory {
    <# Reliability Monitor history (crashes, Windows errors, installations). #>
    param([int]$Days = 30)
    $since = [Management.ManagementDateTimeConverter]::ToDmtfDateTime((Get-Date).AddDays(-$Days))
    try {
        $recs = @(Get-CimInstance -ClassName Win32_ReliabilityRecords -Filter "TimeGenerated >= '$since'" -ErrorAction Stop)
    } catch {
        Write-WTLog (T 'Reliability history not available: {0}' $_.Exception.Message) -Level Warn
        return
    }
    $si = Get-WTStabilityIndex
    if ($null -ne $si) { Write-WTLog (T 'Current stability index: {0:N1} / 10' $si) -Level $(if ($si -lt 5) { 'Warn' } else { 'OK' }) }
    Write-WTLog (T 'Reliability history: {0} records in the last {1} days.' $recs.Count $Days)
    $category = T 'Reliability history'
    $rows = foreach ($r in $recs) {
        $level = 'Info'
        if ($r.SourceName -match 'Application Error|Application Hang|EventLog') { $level = 'Error' }
        if ($r.SourceName -match 'WER-SystemErrorReporting') { $level = 'Critical' }
        if ($r.SourceName -match 'WindowsUpdateClient' -and $r.EventIdentifier -eq 20) { $level = 'Error' }
        $first = @(("$($r.Message)" -split "`r?`n") | Where-Object { $_.Trim() }) | Select-Object -First 1
        [pscustomobject]@{
            Time      = $r.TimeGenerated
            TimeText  = $r.TimeGenerated.ToString('yyyy-MM-dd HH:mm:ss')
            Level     = $level
            LevelText = Get-WTLevelText $level
            Category  = $category
            Source    = $r.SourceName
            Id        = $r.EventIdentifier
            Log       = $r.LogFile
            Summary   = $(if ($r.ProductName) { "$($r.ProductName): $first" } else { "$first" })
            Message   = $r.Message
        }
    }
    $rows | Sort-Object Time -Descending
}

function Get-WTProblemReport {
    <#
    .SYNOPSIS
        Automatic diagnosis: collects BSODs, unexpected shutdowns, crashes, hangs and
        disk/hardware/update/service/network errors and returns a report with suggestions.
    .OUTPUTS
        [pscustomobject] with Report (text) and Rows (relevant events).
    #>
    param([int]$Days = 7)
    Write-WTLog (T 'Analyzing the event logs of the last {0} days...' $Days)
    $rows = New-Object Collections.Generic.List[object]
    $R = New-Object Collections.Generic.List[string]
    $hints = New-Object Collections.Generic.List[string]
    function Add-Hint([string]$Text) { if (-not $hints.Contains($Text)) { $hints.Add($Text) } }
    function Add-Rows($Items) { foreach ($i in $Items) { $rows.Add($i) } }
    function Get-Top($Items, [scriptblock]$Key, [int]$N = 3) {
        (@($Items | Group-Object -Property $Key | Sort-Object Count -Descending | Select-Object -First $N |
                ForEach-Object { "$($_.Name) ($($_.Count))" })) -join ', '
    }
    # crashed or hung application, from the event data (the summary is translated)
    $appOf = { if ($_.App) { $_.App } else { $_.Source } }

    $os = Get-CimInstance Win32_OperatingSystem
    $up = (Get-Date) - $os.LastBootUpTime
    $R.Add((T 'PROBLEM DIAGNOSIS - {0} - last {1} days (generated {2:yyyy-MM-dd HH:mm})' $env:COMPUTERNAME $Days (Get-Date)))
    $R.Add(('=' * 90))
    $R.Add((T 'Last boot: {0:yyyy-MM-dd HH:mm} - up for {1}' $os.LastBootUpTime (Format-WTUptime $up)))
    $pending = @(Test-WTPendingReboot)
    if (Test-WTRebootRequired $pending) {
        $R.Add((T 'Restart pending: {0}' (Format-WTRebootReasons $pending)))
        Add-Hint (T 'A restart is pending (updates or installations): restart before investigating further.')
    } elseif ($pending.Count) {
        $R.Add((T 'Restart pending: no (only file renames queued by installers)'))
    }
    if ($up.Days -ge 14) { Add-Hint (T 'The PC has been up for {0} days: a full restart solves many problems and applies updates.' $up.Days) }
    $si = Get-WTStabilityIndex
    if ($null -ne $si) { $R.Add((T 'Stability index (Reliability Monitor): {0:N1} / 10' $si)) }
    $R.Add('')

    # --- Blue screens ---
    $bsod = @(Get-WTEvents -Category Bsod -Days $Days -Quiet)
    Add-Rows $bsod
    if ($bsod.Count) {
        $R.Add((T '[!] BLUE SCREENS (BSOD): {0}' $bsod.Count))
        foreach ($e in ($bsod | Select-Object -First 10)) { $R.Add("      $($e.TimeText)   $($e.Summary)") }
        foreach ($e in $bsod) {
            if ($e.Message -match '0x[0-9A-Fa-f]{8}') {
                $b = Get-WTBugCheckInfo $Matches[0]
                if ($b.Hint) { Add-Hint "BSOD $($b.Name): $($b.Hint)" }
            }
        }
    } else { $R.Add((T '[OK] No blue screens')) }

    # --- Unexpected shutdowns ---
    $sd = @(Get-WTEvents -Category Shutdown -Days $Days -Quiet | Where-Object { $_.Id -eq 41 -or $_.Id -eq 6008 })
    Add-Rows $sd
    $kp = @($sd | Where-Object { $_.Id -eq 41 })
    if ($sd.Count) {
        $R.Add((T '[!] UNEXPECTED SHUTDOWNS: {0} Kernel-Power 41, {1} unclean shutdowns (6008)' $kp.Count (@($sd | Where-Object { $_.Id -eq 6008 }).Count)))
        foreach ($e in ($kp | Select-Object -First 5)) { $R.Add("      $($e.TimeText)   $($e.Summary)") }
        $noBsod = @($kp | Where-Object { $_.NoBsod }).Count
        if ($noBsod) { Add-Hint (T '{0} shutdowns without a blue screen: check the power supply (PSU, power strip, battery), the power button, overheating or total system freezes.' $noBsod) }
    } else { $R.Add((T '[OK] No unexpected shutdowns')) }

    # --- Application crashes ---
    $ac = @(Get-WTEvents -Category AppCrash -Days $Days -Quiet)
    Add-Rows $ac
    if ($ac.Count) {
        $R.Add((T '[!] APPLICATION CRASHES: {0} - most frequent: {1}' $ac.Count (Get-Top $ac $appOf 5)))
        $mods = @($ac | Where-Object { $_.Module })
        if ($mods.Count) { $R.Add((T '      Modules involved: {0}' (Get-Top $mods { $_.Module } 5))) }
        if (@($mods | Where-Object { $_.Module -match '^(nvwgf|nvd3d|nvoglv|atiu|amdxx|aticfx|igd|igxe|ig\d)' }).Count) {
            Add-Hint (T 'Some crashes involve graphics driver modules: update or reinstall the video driver.')
        }
        $topApp = $ac | Group-Object $appOf | Sort-Object Count -Descending | Select-Object -First 1
        if ($topApp.Count -ge 5) {
            $topMod = $topApp.Group | Where-Object { $_.Module } | Group-Object Module | Sort-Object Count -Descending | Select-Object -First 1
            $hint = if ($topMod) { T "{0} crashed {1} times (module {2}): update, repair or reinstall it (if it is a vendor utility, update the driver package from the vendor's website)." $topApp.Name $topApp.Count $topMod.Name }
            else { T "{0} crashed {1} times: update, repair or reinstall it (if it is a vendor utility, update the driver package from the vendor's website)." $topApp.Name $topApp.Count }
            Add-Hint $hint
        }
        Add-Hint (T 'Applications that keep crashing: update or repair them (Apps & features > Repair), disable add-ins, try a new user profile.')
    } else { $R.Add((T '[OK] No application crashes')) }

    # --- Application hangs ---
    $ah = @(Get-WTEvents -Category AppHang -Days $Days -Quiet)
    Add-Rows $ah
    if ($ah.Count) {
        $R.Add((T '[!] APPLICATION HANGS (NOT RESPONDING): {0} - most frequent: {1}' $ah.Count (Get-Top $ah $appOf 5)))
    } else { $R.Add((T '[OK] No application hangs')) }

    # --- Disk ---
    $dk = @(Get-WTEvents -Category Disk -Days $Days -Quiet)
    Add-Rows $dk
    $bad = @()
    try { $bad = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { (ConvertTo-WTStorageText $_.HealthStatus $script:WTHealthStates) -ne 'Healthy' }) } catch { }
    if ($dk.Count -or $bad.Count) {
        $R.Add((T '[!] DISK AND FILE SYSTEM: {0} events - sources: {1}' $dk.Count (Get-Top $dk { "$($_.Source) $($_.Id)" } 4)))
        foreach ($d in $bad) { $R.Add((T '      Disk {0}: status {1}' $d.FriendlyName (Get-WTStateText (ConvertTo-WTStorageText $d.HealthStatus $script:WTHealthStates)))) }
        Add-Hint (T "Disk errors: check 'Disk health (SMART)' in the Integrity section, run CHKDSK and back up the user's data; with repeated errors consider replacing the disk.")
    } else { $R.Add((T '[OK] No disk errors')) }

    # --- Hardware and drivers ---
    $hw = @(Get-WTEvents -Category Hardware -Days $Days -Quiet)
    Add-Rows $hw
    if ($hw.Count) {
        $whea = @($hw | Where-Object { $_.Source -eq 'Microsoft-Windows-WHEA-Logger' }).Count
        $tdr = @($hw | Where-Object { $_.Id -eq 4101 }).Count
        $pnp = @($hw | Where-Object { $_.Source -eq 'Microsoft-Windows-Kernel-PnP' }).Count
        $mem = @($hw | Where-Object { $_.Id -eq 2004 }).Count
        $R.Add((T '[!] HARDWARE AND DRIVERS: WHEA {0}, video driver recovered (TDR) {1}, drivers not loaded {2}, memory exhausted {3}' $whea $tdr $pnp $mem))
        if ($whea) { Add-Hint (T 'WHEA errors: hardware problem (CPU, RAM, PCIe, power or temperature). Update the BIOS and firmware, check the cooling and run the vendor diagnostics.') }
        if ($tdr) { Add-Hint (T 'The video driver stopped responding and was recovered: update the graphics driver.') }
        if ($pnp) { Add-Hint (T 'Some drivers failed to load: check Device Manager for devices with an exclamation mark.') }
        if ($mem) { Add-Hint (T 'Virtual memory exhausted: find the process consuming memory (the event details list the top processes) and check the paging file.') }
    } else { $R.Add((T '[OK] No hardware or driver errors')) }

    # --- Windows Update ---
    $wu = @(Get-WTEvents -Category Updates -Days $Days -Quiet)
    Add-Rows $wu
    if ($wu.Count) {
        $R.Add((T '[!] WINDOWS UPDATE: {0} errors' $wu.Count))
        foreach ($e in ($wu | Select-Object -First 3)) { $R.Add("      $($e.TimeText)   $($e.Summary)") }
        Add-Hint (T "Failed updates: run 'Reset components' (Windows Update section) and then DISM RestoreHealth + SFC.")
    } else { $R.Add((T '[OK] No Windows Update errors')) }

    # --- Services ---
    $sv = @(Get-WTEvents -Category Services -Days $Days -Quiet)
    Add-Rows $sv
    if ($sv.Count) {
        $R.Add((T '[!] SERVICES: {0} errors' $sv.Count))
        $R.Add((T '      Most frequent: {0}' (Get-Top $sv { $s = "$($_.Summary)"; if ($s.Length -gt 80) { $s.Substring(0, 80) } else { $s } } 3)))
    } else { $R.Add((T '[OK] No service errors')) }

    # --- Network and domain ---
    $nw = @(Get-WTEvents -Category Network -Days $Days -Quiet)
    Add-Rows $nw
    if ($nw.Count) {
        $R.Add((T '[!] NETWORK AND DOMAIN: {0} events - sources: {1}' $nw.Count (Get-Top $nw { "$($_.Source) $($_.Id)" } 4)))
        if (@($nw | Where-Object { $_.Source -eq 'NETLOGON' -and $_.Id -eq 5719 }).Count) { Add-Hint (T 'NETLOGON 5719: the domain controller was not reachable at startup (slow network, Wi-Fi, VLAN): check the connection.') }
        if (@($nw | Where-Object { $_.Source -eq 'NETLOGON' -and $_.Id -eq 3210 }).Count) { Add-Hint (T "NETLOGON 3210: trust relationship with the domain is broken: use 'Repair domain trust'.") }
        if (@($nw | Where-Object { $_.Id -eq 4199 }).Count) { Add-Hint (T 'IP address conflict: another device uses the same address; check DHCP/static IPs.') }
        if (@($nw | Where-Object { $_.Source -eq 'Microsoft-Windows-GroupPolicy' }).Count) { Add-Hint (T 'Group Policy errors: check the domain connection and DNS, then run gpupdate /force.') }
        if (@($nw | Where-Object { $_.Source -eq 'Microsoft-Windows-Time-Service' }).Count) { Add-Hint (T "Time synchronization problems: use 'Sync time' (a skew of more than 5 minutes breaks Kerberos).") }
    } else { $R.Add((T '[OK] No network or domain errors')) }

    # --- Dump files ---
    $R.Add('')
    $dumps = @(Get-ChildItem -LiteralPath "$env:windir\Minidump" -Filter '*.dmp' -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $full = Get-Item -LiteralPath "$env:windir\MEMORY.DMP" -Force -ErrorAction SilentlyContinue
    if ($dumps.Count -or $full) {
        $R.Add((T 'DUMP FILES (can be analyzed with WinDbg or BlueScreenView):'))
        foreach ($d in (@($dumps | Select-Object -First 10) + @($full | Where-Object { $_ }))) {
            $R.Add(('      {0:yyyy-MM-dd HH:mm}   {1}   {2}' -f $d.LastWriteTime, $d.FullName, (Format-WTSize $d.Length)))
        }
    } else { $R.Add((T 'No dump files present.')) }

    $R.Add('')
    $R.Add((T 'SUGGESTIONS'))
    $R.Add(('-' * 90))
    if ($hints.Count) { $i = 1; foreach ($h in $hints) { $R.Add(('{0}. {1}' -f $i, $h)); $i++ } }
    else { $R.Add((T 'No relevant problems in the analyzed period.')) }

    $problems = @($R | Where-Object { $_.StartsWith('[!]') }).Count
    Write-WTLog (T 'Diagnosis complete: {0} problem areas, {1} relevant events.' $problems $rows.Count) -Level $(if ($problems) { 'Warn' } else { 'OK' })
    [pscustomobject]@{ Report = ($R -join "`r`n"); Rows = @($rows | Sort-Object Time -Descending) }
}
