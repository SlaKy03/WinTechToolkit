# Printers: list, network connections, queues, unused drivers.

function Import-WTPrintModule {
    <#
    .SYNOPSIS
        Loads PrintManagement; $false if it cannot be loaded.
    .NOTES
        In the GUI runspaces the automatic loading sometimes fails ("Get-Printer found in the
        module PrintManagement, but the module could not be loaded"), e.g. while an antivirus
        scans the module or other runspaces load modules at the same time: a few more tries.
    #>
    if (Get-Module PrintManagement) { return $true }
    for ($i = 1; $i -le 3; $i++) {
        try { Import-Module PrintManagement -ErrorAction Stop -WarningAction SilentlyContinue; return $true }
        catch { Start-Sleep -Milliseconds (300 * $i) }
    }
    $false
}

function Get-WTPrinterFromCim {
    # Same objects as Get-WTPrinterFromSpooler, read from Win32_Printer when PrintManagement does not load
    $jobs = @(Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue)
    foreach ($p in Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Sort-Object Name) {
        # PrinterStatus: 4 printing, 7 offline (1 = "other" is common on network queues and is
        # not an error). DetectedErrorState: 4 no paper, 6 no toner, 7 door open, 8 jammed,
        # 9 offline, 10 service requested
        $e = [int]$p.DetectedErrorState
        $key = if ($p.WorkOffline -or $p.PrinterStatus -eq 7 -or $e -eq 9) { 'Offline' }
        elseif ($e -eq 4) { 'PaperOut' }
        elseif ($e -eq 8) { 'PaperJam' }
        elseif ($e -in 6, 7, 10) { 'Error' }
        elseif ($p.PrinterStatus -eq 4) { 'Printing' }
        else { 'Normal' }
        $st = @{ Normal = 'Ready'; Offline = 'Offline'; Error = 'Error'; Printing = 'Printing'; PaperOut = 'Out of paper'; PaperJam = 'Paper jam' }[$key]
        [pscustomobject]@{
            Name = $p.Name; IsConnection = [bool]$p.Network; Driver = $p.DriverName; Port = $p.PortName
            Shared = Format-WTBool $p.Shared; Status = $st; StatusText = (T $st)
            Jobs = @($jobs | Where-Object { "$($_.Name)".StartsWith("$($p.Name),") }).Count
        }
    }
}

function Get-WTPrinterFromSpooler {
    # Printers seen by the account the toolkit runs as (Get-Printer, or WMI as a fallback)
    if (-not (Import-WTPrintModule)) {
        Write-WTLog 'The PrintManagement module could not be loaded: printers read from WMI.'
        return Get-WTPrinterFromCim
    }
    $status = @{ Normal = 'Ready'; Offline = 'Offline'; Error = 'Error'; PaperOut = 'Out of paper'; PaperJam = 'Paper jam'; Paused = 'Paused'; Busy = 'Busy'; Printing = 'Printing' }
    # In the GUI runspaces the Printer type data is not always applied and PrinterStatus comes
    # back as the raw code of the enum (0 = Normal...)
    $codes = @{ 0 = 'Normal'; 1 = 'Paused'; 2 = 'Error'; 4 = 'PaperJam'; 5 = 'PaperOut'; 7 = 'Offline'; 9 = 'Busy'; 10 = 'Printing' }
    foreach ($p in Get-Printer -ErrorAction SilentlyContinue | Sort-Object Name) {
        $key = "$($p.PrinterStatus)"
        if ($key -match '^\d+$' -and $codes.ContainsKey([int]$key)) { $key = $codes[[int]$key] }
        $st = $status[$key]
        if (-not $st) { $st = $key }
        [pscustomobject]@{
            Name = $p.Name; IsConnection = "$($p.Type)" -eq 'Connection'; Driver = $p.DriverName; Port = $p.PortName
            Shared = Format-WTBool $p.Shared; Status = $st; StatusText = (T $st)
            Jobs = @(Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue).Count
        }
    }
}

function Get-WTUserPrinterConnection {
    <#
    .SYNOPSIS
        Network printers (\\server\queue) connected by the users whose registry is loaded
        (signed-in users), read from HKEY_USERS\<SID>\Printers\Connections.
    .NOTES
        A connection belongs to one user: when the toolkit runs with another administrator
        account, Get-Printer does not list the connections of the signed-in user.
    #>
    foreach ($h in Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue) {
        $sid = $h.PSChildName
        if ($sid -notmatch '^S-1-(5-21|12-1)-[\d-]+$') { continue }
        $user = Resolve-WTSidName $sid
        if (-not $user) { $user = $sid }
        foreach ($c in Get-ChildItem "Registry::HKEY_USERS\$sid\Printers\Connections" -ErrorAction SilentlyContinue) {
            # ",,server,queue" (the queue name may contain commas)
            $parts = $c.PSChildName.Split(',')
            if ($parts.Count -lt 4 -or -not $parts[2]) { continue }
            [pscustomobject]@{ Name = '\\{0}\{1}' -f $parts[2], ($parts[3..($parts.Count - 1)] -join ','); UserName = $user; SID = $sid }
        }
    }
}

function Get-WTPrinter {
    <#
    .SYNOPSIS
        Printers of the computer plus the network connections of every signed-in user.
    .OUTPUTS
        Status: Ready, Offline, Error... (row colours); StatusText: shown in the table;
        UserName: owner of a network connection (empty for the printers of the computer).
    #>
    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    $short = { param($n) $n -replace "^$([regex]::Escape($env:COMPUTERNAME))\\", '' }
    $list = New-Object Collections.Generic.List[object]
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in Get-WTPrinterFromSpooler) {
        $owner = if ($p.IsConnection) { $me.Name } else { '' }
        [void]$seen.Add("$($p.Name)|$owner")
        $list.Add([pscustomobject]@{
                Name = $p.Name; Type = $(if ($p.IsConnection) { T 'Network connection' } else { T 'Local' })
                UserName = $owner; UserText = $(if ($owner) { & $short $owner } else { T 'All users' })
                Driver = $p.Driver; Port = $p.Port; Shared = $p.Shared; Status = $p.Status; StatusText = $p.StatusText; Jobs = $p.Jobs
            })
    }
    foreach ($c in Get-WTUserPrinterConnection) {
        if (-not $seen.Add("$($c.Name)|$($c.UserName)")) { continue }
        # status, driver and queue are only visible in the user's session
        $list.Add([pscustomobject]@{
                Name = $c.Name; Type = (T 'Network connection'); UserName = $c.UserName; UserText = (& $short $c.UserName)
                Driver = ''; Port = ''; Shared = ''; Status = 'UserSession'; StatusText = (T 'In the user session'); Jobs = ''
            })
    }
    $list | Sort-Object Name, UserText
}

function Add-WTNetworkPrinter {
    <#
    .SYNOPSIS
        Connects a shared printer (\\server\queue).
        Machine: connection for all users (printui /ga), appears at the next sign-in.
        User: only for the signed-in user, in their session.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Machine', 'User')][string]$Scope = 'Machine',
        [string]$UserName,
        [switch]$Simulate
    )
    if ($Path -notmatch '^\\\\[^\\]+\\.+') { Write-WTLog 'Invalid path: use the format \\server\printer' -Level Error; return }
    if ($Simulate) {
        if ($Scope -eq 'Machine') { Write-WTLog (T '[SIMULATION] Would connect {0} for all users' $Path) } else { Write-WTLog (T '[SIMULATION] Would connect {0} for {1}' $Path $UserName) }
        return
    }
    if ($Scope -eq 'Machine') {
        $r = Invoke-WTProcess -FilePath 'rundll32.exe' -Arguments "printui.dll,PrintUIEntry /ga /n`"$Path`""
        Restart-Service -Name Spooler -Force -ErrorAction SilentlyContinue
        if ($r.ExitCode -eq 0) { Write-WTLog (T 'Printer {0} connected for all users (visible at the next sign-in).' $Path) -Level OK }
        return
    }
    if (-not $UserName) { Write-WTLog 'No signed-in user.' -Level Error; return }
    $p = $Path -replace "'", "''"
    $out = Invoke-WTUserContext -UserName $UserName -Script "Add-Printer -ConnectionName '$p' -ErrorAction Stop; 'Printer connected'"
    foreach ($l in $out) { Write-WTLog "  $l" }
}

function Remove-WTPrinter {
    <#
    .SYNOPSIS
        Removes printers. -UserName: network connections of that user, removed in their session
        (a connection belongs to one user and cannot be removed from another account).
    #>
    param([Parameter(Mandatory)][string[]]$Name, [string]$UserName, [switch]$Simulate)
    if ($UserName -and $UserName -ne [Security.Principal.WindowsIdentity]::GetCurrent().Name) {
        foreach ($n in $Name) {
            if ($Simulate) { Write-WTLog (T "[SIMULATION] Would remove printer {0} in {1}'s session" $n $UserName); continue }
            $q = $n.Replace("'", "''")
            $out = @(Invoke-WTUserContext -UserName $UserName -Script "Remove-Printer -Name '$q' -ErrorAction Stop; 'WT-REMOVED'")
            if ($out -contains 'WT-REMOVED') { Write-WTLog (T 'Printer removed: {0}' "$n ($UserName)") -Level OK }
            else { Write-WTLog (T 'Could not remove {0}: {1}' $n (($out | Where-Object { $_ }) -join ' ')) -Level Error }
        }
        return
    }
    if (-not (Import-WTPrintModule)) { Write-WTLog 'The PrintManagement module could not be loaded: try again.' -Level Error; return }
    foreach ($n in $Name) {
        if ($Simulate) { Write-WTLog (T '[SIMULATION] Would remove printer {0}' $n); continue }
        if ($n -like '\\*') {
            # possible per-machine connection created with /ga
            Invoke-WTProcess -FilePath 'rundll32.exe' -Arguments "printui.dll,PrintUIEntry /gd /n`"$n`"" -NoLog | Out-Null
        }
        try {
            Remove-Printer -Name $n -ErrorAction Stop
            Write-WTLog (T 'Printer removed: {0}' $n) -Level OK
        } catch {
            if (Get-Printer -Name $n -ErrorAction SilentlyContinue) { Write-WTLog (T 'Could not remove {0}: {1}' $n $_.Exception.Message) -Level Error }
            else { Write-WTLog (T 'Printer removed: {0}' $n) -Level OK }
        }
    }
}

function Clear-WTPrintQueue {
    param([Parameter(Mandatory)][string[]]$Name)
    if (-not (Import-WTPrintModule)) { Write-WTLog 'The PrintManagement module could not be loaded: try again.' -Level Error; return }
    foreach ($n in $Name) {
        $jobs = @(Get-PrintJob -PrinterName $n -ErrorAction SilentlyContinue)
        $jobs | Remove-PrintJob -ErrorAction SilentlyContinue
        Write-WTLog (T 'Queue of {0} cleared ({1} jobs).' $n $jobs.Count) -Level OK
    }
}

function Invoke-WTPrinterTestPage {
    param([Parameter(Mandatory)][string]$Name)
    $wql = $Name -replace '\\', '\\' -replace "'", "\'"
    $p = Get-CimInstance Win32_Printer -Filter "Name='$wql'" -ErrorAction SilentlyContinue
    if (-not $p) { Write-WTLog (T 'Printer {0} not found.' $Name) -Level Error; return }
    $r = Invoke-CimMethod -InputObject $p -MethodName PrintTestPage
    if ($r.ReturnValue -eq 0) { Write-WTLog (T 'Test page sent to {0}.' $Name) -Level OK }
    else { Write-WTLog (T 'Could not send the test page (code {0}).' $r.ReturnValue) -Level Error }
}

function Remove-WTUnusedPrinterDriver {
    # Printer drivers not used by any printer (system Microsoft drivers excluded)
    param([switch]$Simulate)
    # without the printer list every driver would look unused
    if (-not (Import-WTPrintModule)) { Write-WTLog 'The PrintManagement module could not be loaded: try again.' -Level Error; return }
    try { $used = @(Get-Printer -ErrorAction Stop | ForEach-Object { $_.DriverName }) }
    catch { Write-WTLog (T 'Could not read the printers: {0}' $_.Exception.Message.Trim()) -Level Error; return }
    # Network connections of other users are not listed by Get-Printer, but their drivers are
    # installed on the computer: they are read in each user's session, otherwise nothing is removed
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($u in @(Get-WTUserPrinterConnection | Where-Object { $_.SID -ne $me } | Select-Object -ExpandProperty UserName -Unique)) {
        Write-WTLog (T "Reading the printer drivers used in {0}'s session..." $u)
        $out = @(Invoke-WTUserContext -UserName $u -Script "Get-Printer -ErrorAction Stop | ForEach-Object { 'WT-DRV:' + `$_.DriverName }; 'WT-DONE'")
        if ($out -notcontains 'WT-DONE') {
            Write-WTLog (T "Could not read the printers of {0}: no driver removed, so that their network printers keep working." $u) -Level Error
            return
        }
        $used += @($out | Where-Object { $_ -like 'WT-DRV:*' } | ForEach-Object { $_.Substring(7) })
    }
    $drivers = @(Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object {
            $used -notcontains $_.Name -and $_.Manufacturer -ne 'Microsoft' -and $_.Name -notmatch '^Microsoft|Remote Desktop Easy Print'
        })
    if (-not $drivers.Count) { Write-WTLog 'No unused printer drivers.' -Level OK; return }
    if (-not $Simulate) { Restart-Service -Name Spooler -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
    foreach ($d in $drivers) {
        if ($Simulate) { Write-WTLog (T '[SIMULATION] Would remove driver {0} ({1})' $d.Name $d.PrinterEnvironment); continue }
        try {
            Remove-PrinterDriver -Name $d.Name -PrinterEnvironment $d.PrinterEnvironment -RemoveFromDriverStore -ErrorAction Stop
            Write-WTLog (T 'Driver removed: {0}' $d.Name) -Level OK
        } catch {
            try {
                Remove-PrinterDriver -Name $d.Name -PrinterEnvironment $d.PrinterEnvironment -ErrorAction Stop
                Write-WTLog (T 'Driver removed (the package stays in the driver store): {0}' $d.Name) -Level OK
            } catch { Write-WTLog (T 'Could not remove {0}: {1}' $d.Name $_.Exception.Message) -Level Warn }
        }
    }
}
