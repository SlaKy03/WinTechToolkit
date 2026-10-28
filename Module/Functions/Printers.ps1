# Printers: list, network connections, queues, unused drivers.

function Get-WTPrinter {
    $status = @{ Normal = 'Ready'; Offline = 'Offline'; Error = 'Error'; PaperOut = 'Out of paper'; PaperJam = 'Paper jam'; Paused = 'Paused'; Busy = 'Busy'; Printing = 'Printing' }
    foreach ($p in Get-Printer -ErrorAction SilentlyContinue | Sort-Object Name) {
        $st = $status["$($p.PrinterStatus)"]
        if (-not $st) { $st = "$($p.PrinterStatus)" }
        [pscustomobject]@{
            Name   = $p.Name
            Type   = $(if ($p.Type -eq 'Connection') { 'Network connection' } else { 'Local' })
            Driver = $p.DriverName
            Port   = $p.PortName
            Shared = Format-WTBool $p.Shared
            Status = $st
            Jobs   = @(Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue).Count
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
    if ($Path -notmatch '^\\\\[^\\]+\\.+') { Write-WTLog "Invalid path: use the format \\server\printer" -Level Error; return }
    if ($Simulate) { Write-WTLog "[SIMULATION] Would connect $Path ($Scope)"; return }
    if ($Scope -eq 'Machine') {
        $r = Invoke-WTProcess -FilePath 'rundll32.exe' -Arguments "printui.dll,PrintUIEntry /ga /n`"$Path`""
        Restart-Service -Name Spooler -Force -ErrorAction SilentlyContinue
        if ($r.ExitCode -eq 0) { Write-WTLog "Printer $Path connected for all users (visible at the next sign-in)." -Level OK }
        return
    }
    if (-not $UserName) { Write-WTLog 'No signed-in user.' -Level Error; return }
    $p = $Path -replace "'", "''"
    $out = Invoke-WTUserContext -UserName $UserName -Script "Add-Printer -ConnectionName '$p' -ErrorAction Stop; 'Printer connected'"
    foreach ($l in $out) { Write-WTLog "  $l" }
}

function Remove-WTPrinter {
    param([Parameter(Mandatory)][string[]]$Name, [switch]$Simulate)
    foreach ($n in $Name) {
        if ($Simulate) { Write-WTLog "[SIMULATION] Would remove printer $n"; continue }
        if ($n -like '\\*') {
            # possible per-machine connection created with /ga
            Invoke-WTProcess -FilePath 'rundll32.exe' -Arguments "printui.dll,PrintUIEntry /gd /n`"$n`"" -NoLog | Out-Null
        }
        try {
            Remove-Printer -Name $n -ErrorAction Stop
            Write-WTLog "Printer removed: $n" -Level OK
        } catch {
            if (Get-Printer -Name $n -ErrorAction SilentlyContinue) { Write-WTLog "Could not remove $n : $($_.Exception.Message)" -Level Error }
            else { Write-WTLog "Printer removed: $n" -Level OK }
        }
    }
}

function Clear-WTPrintQueue {
    param([Parameter(Mandatory)][string[]]$Name)
    foreach ($n in $Name) {
        $jobs = @(Get-PrintJob -PrinterName $n -ErrorAction SilentlyContinue)
        $jobs | Remove-PrintJob -ErrorAction SilentlyContinue
        Write-WTLog "Queue of $n cleared ($($jobs.Count) jobs)." -Level OK
    }
}

function Invoke-WTPrinterTestPage {
    param([Parameter(Mandatory)][string]$Name)
    $wql = $Name -replace '\\', '\\' -replace "'", "\'"
    $p = Get-CimInstance Win32_Printer -Filter "Name='$wql'" -ErrorAction SilentlyContinue
    if (-not $p) { Write-WTLog "Printer $Name not found." -Level Error; return }
    $r = Invoke-CimMethod -InputObject $p -MethodName PrintTestPage
    if ($r.ReturnValue -eq 0) { Write-WTLog "Test page sent to $Name." -Level OK }
    else { Write-WTLog "Could not send the test page (code $($r.ReturnValue))." -Level Error }
}

function Remove-WTUnusedPrinterDriver {
    # Printer drivers not used by any printer (system Microsoft drivers excluded)
    param([switch]$Simulate)
    $used = @(Get-Printer -ErrorAction SilentlyContinue | ForEach-Object { $_.DriverName })
    $drivers = @(Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object {
            $used -notcontains $_.Name -and $_.Manufacturer -ne 'Microsoft' -and $_.Name -notmatch '^Microsoft|Remote Desktop Easy Print'
        })
    if (-not $drivers.Count) { Write-WTLog 'No unused printer drivers.' -Level OK; return }
    if (-not $Simulate) { Restart-Service -Name Spooler -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
    foreach ($d in $drivers) {
        if ($Simulate) { Write-WTLog "[SIMULATION] Would remove driver $($d.Name) ($($d.PrinterEnvironment))"; continue }
        try {
            Remove-PrinterDriver -Name $d.Name -PrinterEnvironment $d.PrinterEnvironment -RemoveFromDriverStore -ErrorAction Stop
            Write-WTLog "Driver removed: $($d.Name)" -Level OK
        } catch {
            try {
                Remove-PrinterDriver -Name $d.Name -PrinterEnvironment $d.PrinterEnvironment -ErrorAction Stop
                Write-WTLog "Driver removed (the package stays in the driver store): $($d.Name)" -Level OK
            } catch { Write-WTLog "Could not remove $($d.Name): $($_.Exception.Message)" -Level Warn }
        }
    }
}
