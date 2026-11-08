# Disk cleanup and Windows Update reset.

function Get-WTCleanTargetName {
    # Name of a cleanup item in the interface language ($null if unknown)
    param([string]$Target)
    switch ($Target) {
        'WinTemp' { T 'Windows temporary files' }
        'UserTemp' { T 'Temporary files of all users' }
        'WUCache' { T 'Windows Update download cache' }
        'DeliveryOpt' { T 'Delivery Optimization cache' }
        'RecycleBin' { T 'Recycle Bin (all users and volumes)' }
        'CrashDumps' { T 'Crash dumps and error reports (WER)' }
        'BrowserCache' { T 'Browser cache (Edge, Chrome, Firefox)' }
        'ComponentStore' { T 'WinSxS component store (DISM)' }
    }
}

function Get-WTCleanupPaths {
    param([Parameter(Mandatory)][string]$Target)
    $profiles = @(Get-WTProfileFolders)
    switch ($Target) {
        'WinTemp' { "$env:windir\Temp" }
        'UserTemp' { $profiles | ForEach-Object { "$_\AppData\Local\Temp" } }
        'WUCache' { "$env:windir\SoftwareDistribution\Download" }
        'DeliveryOpt' {
            "$env:windir\SoftwareDistribution\DeliveryOptimization"
            "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
        }
        'RecycleBin' {
            foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
                $rb = "$($d.DeviceID)\`$Recycle.Bin"
                if (Test-Path -LiteralPath $rb) { Get-ChildItem -LiteralPath $rb -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } }
            }
        }
        'CrashDumps' {
            "$env:windir\MEMORY.DMP"
            "$env:windir\Minidump"
            "$env:windir\LiveKernelReports"
            "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"
            "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
            "$env:ProgramData\Microsoft\Windows\WER\Temp"
            foreach ($p in $profiles) {
                "$p\AppData\Local\CrashDumps"
                "$p\AppData\Local\Microsoft\Windows\WER\ReportArchive"
                "$p\AppData\Local\Microsoft\Windows\WER\ReportQueue"
            }
        }
        'BrowserCache' {
            foreach ($p in $profiles) {
                foreach ($b in "$p\AppData\Local\Microsoft\Edge\User Data", "$p\AppData\Local\Google\Chrome\User Data") {
                    if (-not (Test-Path -LiteralPath $b)) { continue }
                    foreach ($bp in Get-ChildItem -LiteralPath $b -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }) {
                        foreach ($c in 'Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage') { "$($bp.FullName)\$c" }
                    }
                }
                $ff = "$p\AppData\Local\Mozilla\Firefox\Profiles"
                if (Test-Path -LiteralPath $ff) {
                    Get-ChildItem -LiteralPath $ff -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FullName)\cache2" }
                }
            }
        }
    }
}

function Invoke-WTCleanup {
    <#
    .SYNOPSIS
        Analyzes (-AnalyzeOnly) or performs the cleanup of the given items.
    .PARAMETER Targets
        WinTemp, UserTemp, WUCache, DeliveryOpt, RecycleBin, CrashDumps, BrowserCache, ComponentStore
    #>
    param([Parameter(Mandatory)][string[]]$Targets, [switch]$AnalyzeOnly, [switch]$Simulate)
    $freeBefore = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace
    $total = [int64]0
    $verb = if ($AnalyzeOnly -or $Simulate) { T 'recoverable' } else { T 'freed' }

    foreach ($t in $Targets) {
        $label = Get-WTCleanTargetName $t
        if (-not $label) { Write-WTLog (T 'Unknown item: {0}' $t) -Level Warn; continue }
        Write-WTLog "--- $label"

        if ($t -eq 'ComponentStore') {
            if ($AnalyzeOnly) { Invoke-WTProcess -FilePath 'dism.exe' -Arguments '/Online /Cleanup-Image /AnalyzeComponentStore' | Out-Null }
            elseif ($Simulate) { Write-WTLog '[SIMULATION] Would run DISM /StartComponentCleanup' }
            else { Invoke-WTProcess -FilePath 'dism.exe' -Arguments '/Online /Cleanup-Image /StartComponentCleanup' | Out-Null }
            [pscustomobject]@{ Target = $t; Bytes = [int64]-1 }
            continue
        }

        $paths = @(Get-WTCleanupPaths -Target $t | Where-Object { Test-Path -LiteralPath $_ })
        $stopped = @()
        if (-not $AnalyzeOnly -and -not $Simulate) {
            if ($t -eq 'BrowserCache' -and (Get-Process msedge, chrome, firefox -ErrorAction SilentlyContinue)) {
                Write-WTLog 'Browsers are open: files in use will not be deleted.' -Level Warn
            }
            if ($t -eq 'WUCache') {
                foreach ($s in 'wuauserv', 'bits', 'dosvc') {
                    $svc = Get-Service $s -ErrorAction SilentlyContinue
                    if ($svc -and $svc.Status -eq 'Running') { Stop-Service $s -Force -ErrorAction SilentlyContinue; $stopped += $s }
                }
            }
            if ($t -eq 'DeliveryOpt') { try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { } }
        }

        $sum = [int64]0
        foreach ($p in $paths) {
            if ($AnalyzeOnly) { $sum += Get-WTFolderSize -Path $p }
            else { $sum += Clear-WTFolderContent -Path $p -Simulate:$Simulate }
        }
        foreach ($s in $stopped) { Start-Service $s -ErrorAction SilentlyContinue }
        Write-WTLog ('{0}: {1} {2}' -f $label, (Format-WTSize $sum), $verb) -Level OK
        [pscustomobject]@{ Target = $t; Bytes = $sum }
        $total += $sum
    }

    Write-WTLog (T 'TOTAL: {0} {1}' (Format-WTSize $total) $verb) -Level OK
    if (-not $AnalyzeOnly -and -not $Simulate) {
        $freeAfter = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace
        Write-WTLog (T 'Free space on {0}: {1} -> {2}' $env:SystemDrive (Format-WTSize $freeBefore) (Format-WTSize $freeAfter))
    }
}

function Reset-WTWindowsUpdate {
    <# Resets the Windows Update components: stops the services, renames SoftwareDistribution and catroot2. #>
    param([switch]$Simulate)
    $services = 'wuauserv', 'bits', 'cryptsvc', 'msiserver'
    $folders = "$env:windir\SoftwareDistribution", "$env:windir\System32\catroot2"
    if ($Simulate) {
        Write-WTLog (T '[SIMULATION] Would stop {0}, rename {1} to .old and restart the services.' ($services -join ', ') ($folders -join ', '))
        return
    }
    foreach ($s in $services) {
        Write-WTLog (T 'Stopping service {0}...' $s)
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    }
    foreach ($f in $folders) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $old = "$f.old"
        if (Test-Path -LiteralPath $old) { Remove-WTFolder -Path $old | Out-Null }
        try {
            Rename-Item -LiteralPath $f -NewName (Split-Path $old -Leaf) -ErrorAction Stop
            Write-WTLog (T 'Renamed: {0} -> {1}' $f $old) -Level OK
        } catch {
            Write-WTLog (T 'Could not rename {0}: {1}' $f $_.Exception.Message) -Level Error
        }
    }
    foreach ($s in 'cryptsvc', 'bits', 'wuauserv') {
        Start-Service -Name $s -ErrorAction SilentlyContinue
        Write-WTLog (T 'Starting service {0}' $s)
    }
    Write-WTLog 'Windows Update reset complete. Restart and search for updates again.' -Level OK
}
