# DISM, SFC, CHKDSK, WMI repository.

function Invoke-WTDism {
    <#
    .SYNOPSIS
        DISM /Online /Cleanup-Image /CheckHealth | /ScanHealth | /RestoreHealth
    .PARAMETER Source
        Source for RestoreHealth, e.g. WIM:D:\sources\install.wim:1 (same build as the system).
    #>
    param(
        [ValidateSet('CheckHealth', 'ScanHealth', 'RestoreHealth')][string]$Mode = 'CheckHealth',
        [string]$Source,
        [switch]$LimitAccess
    )
    $arguments = "/Online /Cleanup-Image /$Mode"
    if ($Mode -eq 'RestoreHealth' -and $Source) {
        $arguments += " /Source:$Source"
        if ($LimitAccess) { $arguments += ' /LimitAccess' }
    }
    Write-WTLog (T 'Running: {0}' "dism.exe $arguments")
    $r = Invoke-WTProcess -FilePath "$env:windir\System32\dism.exe" -Arguments $arguments

    $hex = '0x{0:X8}' -f $r.ExitCode
    switch ($hex) {
        '0x00000000' { Write-WTLog (T 'DISM {0} completed.' $Mode) -Level OK }
        '0x800F081F' { Write-WTLog (T '{0} - Source files not found. Specify a source (ISO of the same build: WIM:D:\sources\install.wim:1) and enable /LimitAccess.' $hex) -Level Error }
        '0x800F0906' { Write-WTLog (T '{0} - Unable to download the files from Windows Update (network/proxy/WSUS). Use a local source.' $hex) -Level Error }
        '0x800F0907' { Write-WTLog (T '{0} - Download blocked by Group Policy (WSUS). Use a local source with /LimitAccess.' $hex) -Level Error }
        '0x800F0950' { Write-WTLog (T '{0} - Operation failed: check that the source matches the edition and build.' $hex) -Level Error }
        '0x00000057' { Write-WTLog (T '{0} - Invalid parameter (check the source format).' $hex) -Level Error }
        default      { Write-WTLog (T 'DISM finished with code {0}. Details in {1}' $hex "$env:windir\Logs\DISM\dism.log") -Level Error }
    }
    $r
}

function Read-WTCbsLog {
    <# Reads the [SR] lines of CBS.log (even if the file is in use), optionally from a given date. #>
    param([datetime]$Since = [datetime]::MinValue)
    $path = "$env:windir\Logs\CBS\CBS.log"
    if (-not (Test-Path -LiteralPath $path)) { return }
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
        $sr = New-Object IO.StreamReader($fs)
        while ($null -ne ($line = $sr.ReadLine())) {
            if ($line.IndexOf('[SR]') -lt 0) { continue }
            if ($Since -gt [datetime]::MinValue -and $line.Length -ge 19) {
                $ts = [datetime]::MinValue
                if ([datetime]::TryParseExact($line.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', $null, 'None', [ref]$ts) -and $ts -lt $Since) { continue }
            }
            $line
        }
    } finally { $fs.Dispose() }
}

function Invoke-WTSfc {
    <# SFC /scannow with a summary of repaired/unrepaired files read from CBS.log. #>
    $start = (Get-Date).AddSeconds(-5)
    Write-WTLog 'Starting SFC /scannow (may take 10-30 minutes)...'
    # sfc writes UTF-16 when its output is redirected
    $r = Invoke-WTProcess -FilePath "$env:windir\System32\sfc.exe" -Arguments '/scannow' -Encoding ([Text.Encoding]::Unicode)

    $sr = @(Read-WTCbsLog -Since $start)
    $repaired = @($sr | Where-Object { $_ -match 'Repairing corrupted file|Repaired file' }).Count
    $failed = @($sr | Where-Object { $_ -match 'Cannot repair member file|Could not reproject corrupted file' }).Count
    if ($failed -gt 0) {
        Write-WTLog (T "SFC: {0} files could NOT be repaired. Run DISM RestoreHealth and then repeat SFC (see 'SFC details')." $failed) -Level Error
    } elseif ($repaired -gt 0) {
        Write-WTLog (T 'SFC: {0} files repaired. Restart and repeat SFC to confirm.' $repaired) -Level Warn
    } else {
        Write-WTLog 'SFC: no repairs recorded in CBS.log.' -Level OK
    }
    [pscustomobject]@{ ExitCode = $r.ExitCode; Repaired = $repaired; Failed = $failed }
}

function Invoke-WTFullRepair {
    <# Recommended sequence: DISM RestoreHealth followed by SFC /scannow. #>
    param([string]$Source, [switch]$LimitAccess)
    Write-WTLog 'Step 1/2: DISM RestoreHealth'
    $d = Invoke-WTDism -Mode RestoreHealth -Source $Source -LimitAccess:$LimitAccess
    if ($d.ExitCode -ne 0) { Write-WTLog 'DISM failed: running SFC anyway, but it may not repair every file.' -Level Warn }
    Write-WTLog 'Step 2/2: SFC /scannow'
    $s = Invoke-WTSfc
    if ($d.ExitCode -eq 0 -and $s.Failed -eq 0) { Write-WTLog 'Full repair finished without errors.' -Level OK }
}

function Export-WTSfcDetails {
    <# Exports all [SR] lines of CBS.log to a text file and returns its path. #>
    $file = Join-Path (Get-WTDataFolder) ('Report\SFC_details_{0}_{1:yyyyMMdd_HHmm}.txt' -f $env:COMPUTERNAME, (Get-Date))
    $lines = @(Read-WTCbsLog)
    if (-not $lines.Count) {
        Write-WTLog 'No [SR] lines found in CBS.log (SFC not run recently or log rotated).' -Level Warn
        return
    }
    Set-Content -LiteralPath $file -Value $lines -Encoding UTF8
    Write-WTLog (T 'Exported {0} [SR] lines to {1}' $lines.Count $file) -Level OK
    $file
}

function Invoke-WTChkdsk {
    <#
    .SYNOPSIS
        Scan = online CHKDSK (/scan, no restart).
        Schedule = marks the volume "dirty" so CHKDSK /F runs at the next restart
        (works regardless of the system language).
    #>
    param(
        [string]$Drive = $env:SystemDrive,
        [ValidateSet('Scan', 'Schedule')][string]$Mode = 'Scan',
        [switch]$Simulate
    )
    if ($Mode -eq 'Scan') {
        Write-WTLog (T 'Running: {0}' "chkdsk $Drive /scan")
        $r = Invoke-WTProcess -FilePath 'chkdsk.exe' -Arguments "$Drive /scan"
        switch ($r.ExitCode) {
            0 { Write-WTLog 'CHKDSK: no errors found.' -Level OK }
            1 { Write-WTLog 'CHKDSK: errors found and fixed.' -Level Warn }
            2 { Write-WTLog 'CHKDSK: disk cleanup performed, no serious errors.' -Level OK }
            default { Write-WTLog (T 'CHKDSK: uncorrected errors (code {0}). Schedule CHKDSK at restart.' $r.ExitCode) -Level Error }
        }
        return
    }
    if ($Simulate) { Write-WTLog (T '[SIMULATION] Would schedule CHKDSK /F on {0} at the next restart.' $Drive); return }
    $r = Invoke-WTProcess -FilePath 'fsutil.exe' -Arguments "dirty set $Drive"
    if ($r.ExitCode -eq 0) {
        Write-WTLog (T 'CHKDSK /F will run on {0} at the next restart.' $Drive) -Level OK
        Write-WTLog (T 'To cancel before the restart: chkntfs /x {0} (then chkntfs /d to restore the default).' $Drive)
    } else {
        Write-WTLog 'Could not schedule CHKDSK.' -Level Error
    }
}

function Repair-WTWmi {
    <# Verify = checks the WMI repository; Salvage = verifies and rebuilds it if inconsistent. #>
    param([ValidateSet('Verify', 'Salvage')][string]$Mode = 'Verify', [switch]$Simulate)
    if ($Mode -eq 'Verify') {
        $r = Invoke-WTProcess -FilePath 'winmgmt.exe' -Arguments '/verifyrepository'
    } else {
        if ($Simulate) { Write-WTLog '[SIMULATION] Would run winmgmt /salvagerepository'; return }
        $r = Invoke-WTProcess -FilePath 'winmgmt.exe' -Arguments '/salvagerepository'
    }
    if ($r.ExitCode -eq 0) { Write-WTLog (T 'WMI {0} completed.' $Mode) -Level OK }
    else { Write-WTLog (T 'WMI {0} finished with code {1}.' $Mode $r.ExitCode) -Level Error }
}
