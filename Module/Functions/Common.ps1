# Core functions: logging, external processes, files, registry, signed-in users.

# Folder and key names that must never be offered as leftovers
$script:WTProtectedNames = @(
    'Microsoft', 'Microsoft Corporation', 'Windows', 'Common Files', 'Microsoft Shared', 'Microsoft.NET',
    'WindowsApps', 'ModifiableWindowsApps', 'WindowsPowerShell', 'Windows Defender', 'Windows NT', 'Windows Mail',
    'Windows Media Player', 'Windows Photo Viewer', 'Windows Portable Devices', 'Windows Sidebar',
    'Windows Security', 'Internet Explorer', 'Reference Assemblies', 'Packages', 'Programs', 'Temp', 'Tmp',
    'Installer', 'Package Cache', 'Desktop', 'Documents', 'Downloads', 'Start Menu', 'Intel', 'Intel Corporation',
    'NVIDIA', 'NVIDIA Corporation', 'AMD', 'Realtek', 'Dell', 'HP', 'Hewlett-Packard', 'Lenovo', 'Classes',
    'Policies', 'Clients', 'RegisteredApplications', 'Wow6432Node', 'ODBC', 'Khronos', 'Partner', 'Software',
    'Setup', 'Update', 'Updater', 'Uninstall', 'Driver', 'Drivers', 'Tools', 'Tool', 'Client', 'Agent',
    'Service', 'Services', 'App', 'Apps', 'Application', 'Applications', 'Data', 'Bin', 'Cache', 'Caches',
    'Config', 'Logs', 'Log', 'Default', 'User Data', 'Users', 'Public', 'CrashDumps', 'D3DSCache',
    'ConnectedDevicesPlatform', 'Comms', 'VirtualStore', 'History', 'Publishers', 'System', 'System32'
)

$script:WTProfileListKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

function Get-WTDataFolder {
    # Logs, registry backups and reports stay here after the toolkit is closed
    $root = Join-Path $env:ProgramData 'WinTechToolkit'
    foreach ($sub in 'Logs', 'Backup', 'Report', 'Temp') {
        $p = Join-Path $root $sub
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
    $root
}

function Write-WTLog {
    <#
    .SYNOPSIS
        Writes a log line. Inside the GUI the line goes to a queue read by the UI thread;
        from the console it is printed and saved to a file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][AllowEmptyString()][string]$Message,
        [ValidateSet('Info', 'OK', 'Warn', 'Error')][string]$Level = 'Info'
    )
    $tag = @{ Info = 'INFO'; OK = 'OK'; Warn = 'WARN'; Error = 'ERROR' }[$Level]
    $line = '{0} [{1,-5}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $tag, $Message

    if ($null -ne $global:WTQueue) { $global:WTQueue.Enqueue($line); return }

    $color = @{ Info = 'Gray'; OK = 'Green'; Warn = 'Yellow'; Error = 'Red' }[$Level]
    Write-Host $line -ForegroundColor $color
    if ($global:WTLogFile) {
        try { [IO.File]::AppendAllText($global:WTLogFile, $line + [Environment]::NewLine, [Text.Encoding]::UTF8) } catch { }
    }
}

function Test-WTAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WTOemEncoding {
    # dism, chkdsk, netsh & co. write in the OEM code page (850 on Western European systems)
    [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
}

function Invoke-WTProcess {
    <#
    .SYNOPSIS
        Runs a console program and reports its output to the log line by line.
        Progress lines ("45%") are reduced to one every 10%.
    .OUTPUTS
        Object with ExitCode and Output (lines).
    #>
    param(
        [Parameter(Mandatory, Position = 0)][string]$FilePath,
        [Parameter(Position = 1)][string]$Arguments = '',
        [Text.Encoding]$Encoding,
        [switch]$NoLog
    )
    if (-not $Encoding) { $Encoding = Get-WTOemEncoding }

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true      # stdin closed: a prompt gets EOF instead of hanging
    $psi.StandardOutputEncoding = $Encoding
    $psi.StandardErrorEncoding = $Encoding

    $output = New-Object Collections.Generic.List[string]
    try {
        $proc = [Diagnostics.Process]::Start($psi)
    } catch {
        Write-WTLog "Unable to start $FilePath : $($_.Exception.Message)" -Level Error
        return [pscustomobject]@{ ExitCode = -1; Output = @() }
    }
    $proc.StandardInput.Close()
    $errTask = $proc.StandardError.ReadToEndAsync()

    $lastBucket = -1
    while ($null -ne ($line = $proc.StandardOutput.ReadLine())) {
        $line = (($line -replace "`0", '') -replace '\s{2,}', ' ').Trim()
        if (-not $line) { continue }
        $output.Add($line)
        if ($NoLog) { continue }
        if ($line -match '(\d{1,3})(?:[.,]\d+)?\s?%') {
            $bucket = [math]::Floor([int]$Matches[1] / 10)
            if ($bucket -eq $lastBucket) { continue }
            $lastBucket = $bucket
        }
        Write-WTLog "  $line"
    }
    $proc.WaitForExit()

    $err = $errTask.Result
    if ($err -and -not $NoLog) {
        foreach ($l in ($err -split "`r?`n")) { if ($l.Trim()) { Write-WTLog "  $($l.Trim())" -Level Warn } }
    }
    [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = $output.ToArray() }
}

function Format-WTSize {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    '{0:N0} B' -f $Bytes
}

function Format-WTBool {
    param($Value)
    if ($Value) { 'Yes' } else { 'No' }
}

function Get-WTFolderSize {
    # Size in bytes of a folder or file. Does not follow junctions.
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try { return [int64](Get-Item -LiteralPath $Path -Force).Length } catch { return [int64]0 }
    }
    $total = [int64]0
    $stack = New-Object Collections.Generic.Stack[string]
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try {
            $di = New-Object IO.DirectoryInfo $dir
            foreach ($f in $di.EnumerateFiles()) { $total += $f.Length }
            foreach ($d in $di.EnumerateDirectories()) {
                if (-not ($d.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stack.Push($d.FullName) }
            }
        } catch { }
    }
    $total
}

function Get-WTProfilesDirectory {
    $v = (Get-ItemProperty $script:WTProfileListKey -ErrorAction SilentlyContinue).ProfilesDirectory
    if ($v) { [Environment]::ExpandEnvironmentVariables($v).TrimEnd('\') } else { "$env:SystemDrive\Users" }
}

function Get-WTProfileFolders {
    # Folders of real profiles (local, domain, Entra ID) present on disk
    $list = New-Object Collections.Generic.List[string]
    foreach ($key in Get-ChildItem $script:WTProfileListKey -ErrorAction SilentlyContinue) {
        if ($key.PSChildName -notmatch '^S-1-(5-21|12-1)-[\d-]+$') { continue }
        $p = (Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $p) { continue }
        $p = [Environment]::ExpandEnvironmentVariables($p).TrimEnd('\')
        if ((Test-Path -LiteralPath $p) -and -not $list.Contains($p)) { $list.Add($p) }
    }
    $list.ToArray()
}

function Get-WTCriticalPaths {
    # Paths that no delete function may touch
    @(
        $env:windir, "$env:windir\System32", "$env:windir\SysWOW64", $env:ProgramFiles, ${env:ProgramFiles(x86)},
        $env:ProgramW6432, $env:ProgramData, "$env:ProgramFiles\Common Files", "${env:ProgramFiles(x86)}\Common Files",
        (Get-WTProfilesDirectory), $env:PUBLIC, "$env:SystemDrive\Users", "$env:SystemDrive\Program Files",
        "$env:SystemDrive\ProgramData", "$env:SystemDrive\Windows"
    ) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
}

function Test-WTPathRelated {
    # $true if the two paths are the same or one contains the other
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return $false }
    $a = $A.TrimEnd('\'); $b = $B.TrimEnd('\')
    $cmp = [StringComparison]::OrdinalIgnoreCase
    $a.Equals($b, $cmp) -or $a.StartsWith($b + '\', $cmp) -or $b.StartsWith($a + '\', $cmp)
}

function Test-WTProtectedName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }
    ($script:WTProtectedNames -contains $Name.Trim()) -or ($Name -match '^(Microsoft|Windows)\b')
}

function Test-WTProtectedPath {
    # $true for system paths or roots that must never be offered as a leftover
    param([string]$Path, [string[]]$ProfileFolders)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    $p = $Path.TrimEnd('\')
    if ($p.Length -le 3) { return $true }
    if ((Get-WTCriticalPaths) -contains $p) { return $true }
    if ($p.StartsWith($env:windir + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if (Test-WTProtectedName (Split-Path $p -Leaf)) { return $true }
    if (-not $ProfileFolders) { $ProfileFolders = Get-WTProfileFolders }
    foreach ($pr in $ProfileFolders) {
        foreach ($sub in '', '\AppData', '\AppData\Roaming', '\AppData\Local', '\AppData\LocalLow', '\AppData\Local\Programs', '\Desktop', '\Documents', '\Downloads') {
            if ($p -eq ($pr + $sub)) { return $true }
        }
    }
    $false
}

function Remove-WTFolder {
    <#
    .SYNOPSIS
        Deletes a folder even with denied permissions or long paths: first rd (which does not
        follow junctions), then ownership to Administrators and robocopy /MIR in backup mode.
    #>
    param([Parameter(Mandatory)][string]$Path, [switch]$Simulate)
    $p = $Path.TrimEnd('\')
    if ($p.Length -le 3 -or (Get-WTCriticalPaths) -contains $p) {
        Write-WTLog "Protected path, deletion refused: $p" -Level Error
        return $false
    }
    if (-not (Test-Path -LiteralPath $p)) { return $true }
    if ($Simulate) {
        Write-WTLog "[SIMULATION] Would delete folder: $p"
        return $true
    }

    $item = Get-Item -LiteralPath $p -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        try { [IO.Directory]::Delete($p, $false) } catch { }   # removes only the link
    } else {
        & cmd.exe /c rd /s /q "$p" 2>&1 | Out-Null
        if (Test-Path -LiteralPath $p) {
            & icacls.exe "$p" /setowner '*S-1-5-32-544' /T /C /L /Q 2>&1 | Out-Null
            & icacls.exe "$p" /grant '*S-1-5-32-544:F' /T /C /L /Q 2>&1 | Out-Null
            $empty = Join-Path $env:TEMP ('wt_empty_' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $empty -Force | Out-Null
            & robocopy.exe "$empty" "$p" /MIR /B /XJ /R:0 /W:0 /NFL /NDL /NJH /NJS /NP 2>&1 | Out-Null
            Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue
            & cmd.exe /c rd /s /q "$p" 2>&1 | Out-Null
        }
    }
    if (Test-Path -LiteralPath $p) {
        Write-WTLog "Could not delete completely: $p (files in use? try again after a restart)" -Level Warn
        return $false
    }
    Write-WTLog "Folder deleted: $p" -Level OK
    $true
}

function Remove-WTTreeBestEffort {
    # Empties a folder skipping files in use, without following junctions
    param([IO.DirectoryInfo]$Directory)
    try { $items = $Directory.GetFileSystemInfos() } catch { return }
    foreach ($i in $items) {
        if ($i -is [IO.DirectoryInfo]) {
            if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { try { $i.Delete() } catch { } }
            else {
                Remove-WTTreeBestEffort -Directory $i
                try { $i.Delete() } catch { }
            }
        } else {
            try { if ($i.IsReadOnly) { $i.IsReadOnly = $false }; $i.Delete() } catch { }
        }
    }
}

function Clear-WTFolderContent {
    # Empties a folder (or deletes a file) and returns the bytes freed
    param([Parameter(Mandatory)][string]$Path, [switch]$Simulate)
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $before = Get-WTFolderSize -Path $Path
    if ($Simulate) {
        if ($before -gt 0) { Write-WTLog "[SIMULATION] Would empty $Path ($(Format-WTSize $before))" }
        return $before
    }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop; return $before } catch { return [int64]0 }
    }
    Remove-WTTreeBestEffort -Directory (New-Object IO.DirectoryInfo $Path)
    $after = Get-WTFolderSize -Path $Path
    [int64]($before - $after)
}

function Backup-WTRegistryKey {
    # Exports the key (HKEY_LOCAL_MACHINE\... format) to a .reg file in Backup\<date>
    param([Parameter(Mandatory)][string]$Key)
    $dir = Join-Path (Get-WTDataFolder) ('Backup\' + (Get-Date -Format 'yyyyMMdd'))
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $name = $Key -replace '[\\/:*?"<>|\s]', '_'
    if ($name.Length -gt 120) { $name = $name.Substring($name.Length - 120) }
    $file = Join-Path $dir ('{0}_{1}.reg' -f (Get-Date -Format 'HHmmss_fff'), $name)
    & reg.exe export "$Key" "$file" /y 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $file } else { $null }
}

function Remove-WTRegistryKey {
    # .reg backup, then deletion of the key
    param([Parameter(Mandatory)][string]$Key, [switch]$Simulate)
    $psPath = "Registry::$Key"
    if (-not (Test-Path -LiteralPath $psPath)) { return $true }
    if ($Simulate) { Write-WTLog "[SIMULATION] Would delete key: $Key"; return $true }
    $bak = Backup-WTRegistryKey -Key $Key
    try {
        Remove-Item -LiteralPath $psPath -Recurse -Force -ErrorAction Stop
        Write-WTLog "Key deleted: $Key$(if ($bak) { " (backup: $(Split-Path $bak -Leaf))" })" -Level OK
        $true
    } catch {
        Write-WTLog "Could not delete key $Key : $($_.Exception.Message)" -Level Error
        $false
    }
}

function Resolve-WTSidName {
    param([string]$Sid)
    try { (New-Object Security.Principal.SecurityIdentifier $Sid).Translate([Security.Principal.NTAccount]).Value } catch { $null }
}

function Get-WTLoggedOnUser {
    # Users with an open session (owners of explorer.exe), more than one on RDP
    $found = [ordered]@{}
    foreach ($p in Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue) {
        $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction SilentlyContinue
        if (-not $o -or -not $o.User) { continue }
        $name = "$($o.Domain)\$($o.User)"
        if ($found.Contains($name)) { continue }
        $sid = $null
        try { $sid = (New-Object Security.Principal.NTAccount $name).Translate([Security.Principal.SecurityIdentifier]).Value } catch { }
        $path = $null
        if ($sid) {
            $ip = (Get-ItemProperty "$script:WTProfileListKey\$sid" -ErrorAction SilentlyContinue).ProfileImagePath
            if ($ip) { $path = [Environment]::ExpandEnvironmentVariables($ip) }
        }
        $found[$name] = [pscustomobject]@{ UserName = $name; SID = $sid; ProfilePath = $path; SessionId = $p.SessionId }
    }
    $found.Values
}

function Get-WTUserTargets {
    # Profiles the toolkit can act on: signed-in users first, then the others
    $logged = @(Get-WTLoggedOnUser)
    $list = New-Object Collections.Generic.List[object]
    foreach ($u in $logged) {
        $list.Add([pscustomobject]@{ UserName = $u.UserName; SID = $u.SID; ProfilePath = $u.ProfilePath; LoggedOn = $true })
    }
    foreach ($key in Get-ChildItem $script:WTProfileListKey -ErrorAction SilentlyContinue) {
        $sid = $key.PSChildName
        if ($sid -notmatch '^S-1-(5-21|12-1)-[\d-]+$') { continue }
        if ($logged | Where-Object { $_.SID -eq $sid }) { continue }
        $ip = (Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $ip) { continue }
        $ip = [Environment]::ExpandEnvironmentVariables($ip)
        if (-not (Test-Path -LiteralPath $ip)) { continue }
        $name = Resolve-WTSidName $sid
        if (-not $name) { $name = Split-Path $ip -Leaf }
        $list.Add([pscustomobject]@{ UserName = $name; SID = $sid; ProfilePath = $ip; LoggedOn = $false })
    }
    $list.ToArray()
}

function Invoke-WTUserContext {
    <#
    .SYNOPSIS
        Runs a PowerShell script in a signed-in user's session, through a temporary
        scheduled task, and returns its output.
    .DESCRIPTION
        Needed for everything that lives in the user's context and cannot be reached from
        another administrator account: Credential Manager, Kerberos tickets, HKCU, OneDrive.
        The task and the temporary files are removed when done.
    #>
    param(
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][string]$Script,
        [int]$TimeoutSec = 120
    )
    $tmp = Join-Path (Get-WTDataFolder) 'Temp'
    $id = 'WTK_' + [guid]::NewGuid().ToString('N').Substring(0, 12)
    $ps1 = Join-Path $tmp "$id.ps1"
    $out = Join-Path $tmp "$id.txt"
    $taskPath = '\WinTechToolkit\'

    $body = "`$ErrorActionPreference = 'Continue'`r`n& {`r`n$Script`r`n} *>&1 | Out-File -LiteralPath '$out' -Encoding UTF8 -Width 400"
    Set-Content -LiteralPath $ps1 -Value $body -Encoding UTF8
    New-Item -ItemType File -Path $out -Force | Out-Null
    & icacls.exe "$out" /grant "${UserName}:M" /Q 2>&1 | Out-Null

    try {
        $action = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`""
        $principal = New-ScheduledTaskPrincipal -UserId $UserName -LogonType Interactive -RunLevel Limited
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds ($TimeoutSec + 30))
        Register-ScheduledTask -TaskName $id -TaskPath $taskPath -Action $action -Principal $principal -Settings $set -Force -ErrorAction Stop | Out-Null
        $started = Get-Date
        Start-ScheduledTask -TaskName $id -TaskPath $taskPath -ErrorAction Stop

        # 267011 = never run, 267009 = running
        $deadline = $started.AddSeconds($TimeoutSec)
        do {
            Start-Sleep -Milliseconds 500
            $info = Get-ScheduledTaskInfo -TaskName $id -TaskPath $taskPath -ErrorAction SilentlyContinue
            $done = $info -and $info.LastTaskResult -ne 267011 -and $info.LastTaskResult -ne 267009
        } until ($done -or (Get-Date) -gt $deadline)
        if (-not $done) { Write-WTLog "Timeout: the script in ${UserName}'s session did not finish within $TimeoutSec seconds." -Level Warn }

        if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out -Encoding UTF8 | Where-Object { $_ -ne '' } }
    } catch {
        Write-WTLog "Execution in ${UserName}'s session failed: $($_.Exception.Message)" -Level Error
    } finally {
        Unregister-ScheduledTask -TaskName $id -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $ps1, $out -Force -ErrorAction SilentlyContinue
        try {
            $svc = New-Object -ComObject Schedule.Service
            $svc.Connect()
            $folder = $svc.GetFolder($taskPath.TrimEnd('\'))
            if ($folder.GetTasks(1).Count -eq 0) { $svc.GetFolder('\').DeleteFolder('WinTechToolkit', 0) }
        } catch { }
    }
}

function Stop-WTUserProcess {
    # Closes the given processes, only the user's own if a user is specified
    param([Parameter(Mandatory)][string[]]$Name, [string]$UserName)
    $procs = @(Get-Process -Name $Name -IncludeUserName -ErrorAction SilentlyContinue)
    if ($UserName) { $procs = @($procs | Where-Object { $_.UserName -eq $UserName }) }
    foreach ($p in $procs) {
        Write-WTLog "Closing $($p.ProcessName) (PID $($p.Id))"
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    if ($procs.Count) { Start-Sleep -Seconds 2 }
}
