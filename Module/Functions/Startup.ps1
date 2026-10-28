# Startup programs and scheduled tasks.
# Enabling uses the StartupApproved keys, like Task Manager: nothing is deleted.

function Get-WTCommandTarget {
    # Executable of a command line (or target of a .lnk), with variables expanded
    param([string]$Command)
    if (-not $Command) { return $null }
    $exe = (Split-WTCommandLine ([Environment]::ExpandEnvironmentVariables($Command)))[0]
    if ($exe -like '*.lnk' -and (Test-Path -LiteralPath $exe)) {
        try { $exe = (New-Object -ComObject WScript.Shell).CreateShortcut($exe).TargetPath } catch { }
    }
    $exe
}

function Get-WTStartupItem {
    $items = New-Object Collections.Generic.List[object]
    $approvedBase = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'

    function Add-Item($Name, $Command, $Location, $ApprovedKey) {
        $enabled = $true
        if ($ApprovedKey) {
            $k = Get-Item -LiteralPath "Registry::$ApprovedKey" -ErrorAction SilentlyContinue
            $v = if ($k) { $k.GetValue($Name) } else { $null }
            if ($v -is [byte[]] -and $v.Length -gt 0) { $enabled = ($v[0] % 2) -eq 0 }   # odd byte = disabled
        }
        $target = Get-WTCommandTarget $Command
        $company = ''
        if ($target -and (Test-Path -LiteralPath $target -PathType Leaf)) {
            try { $company = (Get-Item -LiteralPath $target).VersionInfo.CompanyName } catch { }
        }
        $items.Add([pscustomobject]@{
                Name        = $Name
                Command     = $Command
                Target      = $target
                Publisher   = $company
                Location    = $Location
                Enabled     = $enabled
                EnabledText = $(if ($ApprovedKey) { Format-WTBool $enabled } else { 'n/a' })
                ApprovedKey = $ApprovedKey
            })
    }

    $sources = @(
        @{ Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Label = 'Registry (all users)'; Approved = "HKEY_LOCAL_MACHINE\$approvedBase\Run" },
        @{ Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Label = 'Registry 32-bit (all users)'; Approved = "HKEY_LOCAL_MACHINE\$approvedBase\Run32" }
    )
    foreach ($h in Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue) {
        if ($h.PSChildName -notmatch '^S-1-(5-21|12-1)-[\d-]+$') { continue }
        $n = Resolve-WTSidName $h.PSChildName
        if (-not $n) { $n = $h.PSChildName }
        $sources += @{ Key = "HKEY_USERS\$($h.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Run"; Label = "Registry ($n)"; Approved = "HKEY_USERS\$($h.PSChildName)\$approvedBase\Run" }
    }
    foreach ($s in $sources) {
        $item = Get-Item -LiteralPath "Registry::$($s.Key)" -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        foreach ($v in $item.GetValueNames()) {
            if (-not $v) { continue }
            Add-Item $v ([string]$item.GetValue($v)) $s.Label $s.Approved
        }
    }

    # Startup folders
    $common = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    foreach ($f in Get-ChildItem -LiteralPath $common -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }) {
        Add-Item $f.Name $f.FullName 'Startup folder (all users)' "HKEY_LOCAL_MACHINE\$approvedBase\StartupFolder"
    }
    foreach ($key in Get-ChildItem $script:WTProfileListKey -ErrorAction SilentlyContinue) {
        $sid = $key.PSChildName
        if ($sid -notmatch '^S-1-(5-21|12-1)-[\d-]+$') { continue }
        $ip = (Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $ip) { continue }
        $dir = Join-Path ([Environment]::ExpandEnvironmentVariables($ip)) 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
        $approved = if (Test-Path "Registry::HKEY_USERS\$sid") { "HKEY_USERS\$sid\$approvedBase\StartupFolder" } else { $null }
        foreach ($f in Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }) {
            Add-Item $f.Name $f.FullName "Startup folder ($(Split-Path $ip -Leaf))" $approved
        }
    }
    $items | Sort-Object Location, Name
}

function Set-WTStartupItem {
    # Enables or disables like Task Manager (byte 02 = enabled, 03 + date = disabled)
    param([Parameter(Mandatory)][object[]]$InputObject, [Parameter(Mandatory)][bool]$Enabled, [switch]$Simulate)
    foreach ($i in $InputObject) {
        if (-not $i.ApprovedKey) { Write-WTLog "$($i.Name): profile not loaded, cannot be changed now." -Level Warn; continue }
        $verb = if ($Enabled) { 'Would enable' } else { 'Would disable' }
        if ($Simulate) { Write-WTLog "[SIMULATION] $verb $($i.Name)"; continue }
        $path = "Registry::$($i.ApprovedKey)"
        if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
        if ($Enabled) { $bytes = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) }
        else { $bytes = [byte[]](3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTime()) }
        New-ItemProperty -LiteralPath $path -Name $i.Name -Value $bytes -PropertyType Binary -Force | Out-Null
        Write-WTLog ('{0} {1}' -f $i.Name, $(if ($Enabled) { 'enabled' } else { 'disabled' })) -Level OK
    }
}

function Get-WTScheduledTaskList {
    param([switch]$IncludeMicrosoft)
    $states = @{ Ready = 'Ready'; Disabled = 'Disabled'; Running = 'Running'; Queued = 'Queued' }
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        ($IncludeMicrosoft -or $_.TaskPath -notlike '\Microsoft\*') -and $_.TaskPath -ne '\WinTechToolkit\'
    }
    foreach ($t in $tasks) {
        $info = $t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        $exec = (@($t.Actions) | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join ' ; '
        $last = if ($info -and $info.LastRunTime -and $info.LastRunTime.Year -gt 2000) { $info.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { '' }
        $st = $states["$($t.State)"]
        if (-not $st) { $st = "$($t.State)" }
        [pscustomobject]@{
            Name       = $t.TaskName
            Path       = $t.TaskPath
            State      = $st
            Enabled    = $t.State -ne 'Disabled'
            RunAs      = $t.Principal.UserId
            Action     = $exec
            LastRun    = $last
            LastResult = $(if ($info -and $last) { '0x{0:X}' -f $info.LastTaskResult } else { '' })
            Author     = $t.Author
        }
    }
}

function Set-WTScheduledTaskState {
    param([Parameter(Mandatory)][object[]]$InputObject, [Parameter(Mandatory)][bool]$Enabled, [switch]$Simulate)
    foreach ($t in $InputObject) {
        if ($Simulate) { Write-WTLog ("[SIMULATION] {0} task {1}{2}" -f $(if ($Enabled) { 'Would enable' } else { 'Would disable' }), $t.Path, $t.Name); continue }
        try {
            if ($Enabled) { Enable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null }
            else { Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null }
            Write-WTLog ('Task {0}{1} {2}' -f $t.Path, $t.Name, $(if ($Enabled) { 'enabled' } else { 'disabled' })) -Level OK
        } catch { Write-WTLog "Could not change $($t.Name): $($_.Exception.Message)" -Level Error }
    }
}
