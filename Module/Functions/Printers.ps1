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
    # Same objects as Get-WTPrinter, read from Win32_Printer when PrintManagement does not load
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
            Name       = $p.Name
            Type       = $(if ($p.Network) { T 'Network connection' } else { T 'Local' })
            Driver     = $p.DriverName
            Port       = $p.PortName
            Shared     = Format-WTBool $p.Shared
            Status     = $st
            StatusText = (T $st)
            Jobs       = @($jobs | Where-Object { "$($_.Name)".StartsWith("$($p.Name),") }).Count
        }
    }
}

function Get-WTPrinter {
    # Status: Ready, Offline, Error... (row colours), StatusText: shown in the table
    if (-not (Import-WTPrintModule)) {
        Write-WTLog 'The PrintManagement module could not be loaded: printers read from WMI.'
        return Get-WTPrinterFromCim
    }
    $status = @{ Normal = 'Ready'; Offline = 'Offline'; Error = 'Error'; PaperOut = 'Out of paper'; PaperJam = 'Paper jam'; Paused = 'Paused'; Busy = 'Busy'; Printing = 'Printing' }
    $statusText = @{
        Normal = (T 'Ready'); Offline = (T 'Offline'); Error = (T 'Error'); PaperOut = (T 'Out of paper'); PaperJam = (T 'Paper jam')
        Paused = (T 'Paused'); Busy = (T 'Busy'); Printing = (T 'Printing')
    }
    # In the GUI runspaces the Printer type data is not always applied and PrinterStatus comes
    # back as the raw code of the enum (0 = Normal...)
    $codes = @{ 0 = 'Normal'; 1 = 'Paused'; 2 = 'Error'; 4 = 'PaperJam'; 5 = 'PaperOut'; 7 = 'Offline'; 9 = 'Busy'; 10 = 'Printing' }
    foreach ($p in Get-Printer -ErrorAction SilentlyContinue | Sort-Object Name) {
        $key = "$($p.PrinterStatus)"
        if ($key -match '^\d+$' -and $codes.ContainsKey([int]$key)) { $key = $codes[[int]$key] }
        $st = $status[$key]
        if (-not $st) { $st = $key }
        $stText = $statusText[$key]
        if (-not $stText) { $stText = $st }
        [pscustomobject]@{
            Name       = $p.Name
            Type       = $(if ($p.Type -eq 'Connection') { T 'Network connection' } else { T 'Local' })
            Driver     = $p.DriverName
            Port       = $p.PortName
            Shared     = Format-WTBool $p.Shared
            Status     = $st
            StatusText = $stText
            Jobs       = @(Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue).Count
        }
    }
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
    param([Parameter(Mandatory)][string[]]$Name, [switch]$Simulate)
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
