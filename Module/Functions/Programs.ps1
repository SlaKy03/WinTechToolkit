# Program list, uninstall and search/removal of leftovers.

function Get-WTInstalledProgram {
    <# Installed programs (HKLM 64/32 bit + HKCU of users whose hive is loaded). #>
    $sources = New-Object Collections.Generic.List[object]
    $sources.Add(@{ Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Computer (64-bit)' })
    $sources.Add(@{ Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Computer (32-bit)' })
    foreach ($h in Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue) {
        if ($h.PSChildName -notmatch '^S-1-(5-21|12-1)-[\d-]+$') { continue }
        $n = Resolve-WTSidName $h.PSChildName
        if (-not $n) { $n = $h.PSChildName }
        $sources.Add(@{ Key = "HKEY_USERS\$($h.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Uninstall"; Scope = "User $n" })
    }

    $list = New-Object Collections.Generic.List[object]
    foreach ($s in $sources) {
        if (-not (Test-Path -LiteralPath "Registry::$($s.Key)")) { continue }
        foreach ($k in Get-ChildItem -LiteralPath "Registry::$($s.Key)" -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p -or -not $p.DisplayName) { continue }
            if ($p.SystemComponent -eq 1 -or $p.ParentKeyName -or $p.ReleaseType -match 'Update|Hotfix') { continue }

            $code = $null
            if ($k.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') { $code = $k.PSChildName }
            elseif ($p.UninstallString -match 'msiexec' -and $p.UninstallString -match '(\{[0-9A-Fa-f-]{36}\})') { $code = $Matches[1] }
            $isMsi = ($p.WindowsInstaller -eq 1) -or ($p.UninstallString -match 'msiexec')

            $date = ''; $dateSort = ''
            # yyyyMMdd by convention, but some installers write other formats (or invalid dates)
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParseExact("$($p.InstallDate)".Trim(), [string[]]@('yyyyMMdd', 'yyyy-MM-dd', 'M/d/yyyy', 'MM/dd/yyyy'),
                    [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                $date = $parsed.ToString('yyyy-MM-dd')
                $dateSort = $parsed.ToString('yyyyMMdd')
            }
            $size = [int64]0
            if ($p.EstimatedSize) { $size = [int64]$p.EstimatedSize * 1KB }
            $loc = "$($p.InstallLocation)".Trim().Trim('"').TrimEnd('\')

            $list.Add([pscustomobject]@{
                    DisplayName          = $p.DisplayName.Trim()
                    Version              = $p.DisplayVersion
                    Publisher            = $p.Publisher
                    InstallDate          = $date
                    InstallDateSort      = $dateSort
                    SizeBytes            = $size
                    SizeText             = $(if ($size) { Format-WTSize $size } else { '' })
                    InstallerType        = $(if ($isMsi) { 'MSI' } else { 'EXE' })
                    Scope                = $s.Scope
                    InstallLocation      = $loc
                    UninstallString      = $p.UninstallString
                    QuietUninstallString = $p.QuietUninstallString
                    ProductCode          = $code
                    RegistryKey          = "$($s.Key)\$($k.PSChildName)"
                })
        }
    }
    $list | Sort-Object DisplayName
}

function Split-WTCommandLine {
    <# Splits the executable and the arguments of an UninstallString (also without quotes). #>
    param([string]$CommandLine)
    $cl = $CommandLine.Trim()
    if ($cl -match '^"([^"]+)"\s*(.*)$') { return @($Matches[1], $Matches[2]) }
    if ($cl -match '^(.+?\.exe)\s*(.*)$') { return @($Matches[1], $Matches[2]) }
    @($cl, '')
}

function Get-WTSilentSwitch {
    <# Recognizes Inno Setup and NSIS uninstallers and returns the silent switch. #>
    param([string]$ExePath)
    $leaf = Split-Path $ExePath -Leaf
    if ($leaf -match '^unins\d{3}\.exe$') { return '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
    if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) { return $null }
    $fi = Get-Item -LiteralPath $ExePath
    if ($fi.Length -gt 30MB) { return $null }
    $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($ExePath))
    if ($text.Contains('Nullsoft')) { return '/S' }
    if ($text.Contains('Inno Setup')) { return '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
    $null
}

function Uninstall-WTProgram {
    <#
    .SYNOPSIS
        Uninstalls a program (object from Get-WTInstalledProgram).
        MSI: msiexec /x with log; EXE: QuietUninstallString or detected switch (Inno/NSIS).
    #>
    param([Parameter(Mandatory)]$Program, [switch]$Silent, [switch]$Simulate)
    $name = $Program.DisplayName
    Write-WTLog "Uninstalling: $name $($Program.Version)"
    $fail = [pscustomobject]@{ Program = $name; ExitCode = -1; Success = $false }

    if ($Program.ProductCode -and $Program.InstallerType -eq 'MSI') {
        $logFile = Join-Path (Get-WTDataFolder) ('Logs\msi_uninstall_{0}_{1:yyyyMMdd_HHmmss}.log' -f ($name -replace '[^\w\-]', '_'), (Get-Date))
        $exe = "$env:windir\System32\msiexec.exe"
        $arguments = "/x $($Program.ProductCode) /norestart /l*v `"$logFile`""
        if ($Silent) { $arguments += ' /qn' }
    } else {
        $cmd = $Program.UninstallString
        $usedQuiet = $false
        if ($Silent -and $Program.QuietUninstallString) { $cmd = $Program.QuietUninstallString; $usedQuiet = $true }
        if (-not $cmd) { Write-WTLog 'No uninstall string: use "Find leftovers" to remove the entry.' -Level Error; return $fail }
        $parts = Split-WTCommandLine ([Environment]::ExpandEnvironmentVariables($cmd))
        $exe = $parts[0]
        $arguments = $parts[1]
        if ($Silent -and -not $usedQuiet) {
            $sw = Get-WTSilentSwitch -ExePath $exe
            if ($sw) {
                if ($arguments -notmatch [regex]::Escape($sw.Split(' ')[0])) { $arguments = "$arguments $sw".Trim() }
                Write-WTLog "Silent switch detected: $sw"
            } else {
                Write-WTLog 'Silent switch not recognized: the interactive uninstaller will be started.' -Level Warn
            }
        }
        if ([IO.Path]::IsPathRooted($exe) -and -not (Test-Path -LiteralPath $exe)) {
            Write-WTLog "Uninstaller not found ($exe): orphan entry, use 'Find leftovers'." -Level Error
            return $fail
        }
    }

    if ($Simulate) {
        Write-WTLog "[SIMULATION] Would run: `"$exe`" $arguments"
        return [pscustomobject]@{ Program = $name; ExitCode = 0; Success = $true }
    }

    Write-WTLog "Running: `"$exe`" $arguments"
    try {
        $sp = @{ FilePath = $exe; PassThru = $true; ErrorAction = 'Stop' }
        if ($arguments) { $sp.ArgumentList = $arguments }
        $proc = Start-Process @sp
        $null = $proc.Handle           # needed to read ExitCode at the end
        $proc.WaitForExit()
        $code = $proc.ExitCode
    } catch {
        Write-WTLog "Start failed: $($_.Exception.Message)" -Level Error
        return $fail
    }

    # Some uninstallers (NSIS, Inno) copy themselves to %TEMP% and exit immediately:
    # wait for the registry entry to disappear while uninstall helper processes are running.
    $regPath = "Registry::$($Program.RegistryKey)"
    $exeBase = [IO.Path]::GetFileNameWithoutExtension($exe)
    $deadline = (Get-Date).AddMinutes(10)
    while ((Test-Path -LiteralPath $regPath) -and (Get-Date) -lt $deadline) {
        $helpers = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -match '^(Au_|Un_A|Un_|unins\d{3}|_iu14D2N|uninst|uninstall)' -or $_.ProcessName -eq $exeBase
        }
        if (-not $helpers) { Start-Sleep -Seconds 3; break }
        Start-Sleep -Seconds 2
    }
    $stillThere = Test-Path -LiteralPath $regPath

    switch ($code) {
        0 { }
        3010 { Write-WTLog 'A restart is required to complete the uninstall.' -Level Warn }
        1641 { Write-WTLog 'The uninstaller started a restart.' -Level Warn }
        1605 { Write-WTLog 'Product not installed (orphan entry).' -Level Warn }
        1602 { Write-WTLog 'Uninstall cancelled by the user.' -Level Warn }
        1618 { Write-WTLog 'Another installation is in progress: try again later.' -Level Error }
        default { Write-WTLog "Exit code: $code" -Level Warn }
    }
    if ($stillThere) {
        Write-WTLog 'The uninstall entry is still present (uninstall not completed or leftover entry).' -Level Warn
    } else {
        Write-WTLog "$name uninstalled." -Level OK
    }
    [pscustomobject]@{ Program = $name; ExitCode = $code; Success = -not $stillThere }
}

function Get-WTCleanPublisher {
    param([string]$Publisher)
    $p = "$Publisher".Trim()
    for ($i = 0; $i -lt 3; $i++) {
        $p = ($p -replace '(?i)[,.]?\s+(Inc|LLC|Ltd|Limited|Corporation|Corp|GmbH|S\.?p\.?A|S\.?r\.?l|Co|AG|SA|SAS|B\.?V|Pty|Software|Technologies|Systems|Foundation|International)\.?$', '').Trim()
    }
    $p
}

function Get-WTPublisherVariants {
    <# Possible names of the publisher folder/key (never Microsoft/Windows or generic names). #>
    param([string]$Publisher)
    if ([string]::IsNullOrWhiteSpace($Publisher)) { return @() }
    @(@($Publisher.Trim(), (Get-WTCleanPublisher $Publisher)) |
        Where-Object { $_.Length -ge 3 -and -not (Test-WTProtectedName $_) } | Select-Object -Unique)
}

function Get-WTNameVariants {
    <# Possible folder/key names of the program, stripped of version and architecture. #>
    param([string]$DisplayName, [string]$Publisher)
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { return @() }
    $n = $DisplayName
    $n = $n -replace '\s*\([^)]*\)', ''
    $n = $n -replace '\s*\[[^\]]*\]', ''
    $n = $n -replace '(?i)\s+\d+\s+Update\s+\d+.*$', ''
    $n = $n -replace '(?i)\s+v?\d+([.,]\d+)+.*$', ''
    $n = $n -replace '(?i)\s+(x64|x86|amd64|64-bit|32-bit|64 bit|32 bit|it-it|en-us)\b.*$', ''
    $n = $n -replace '\s+-\s+.*$', ''
    $n = ($n -replace '\s{2,}', ' ').Trim(' ', '-', ',', '.')

    $cands = New-Object Collections.Generic.List[string]
    $cands.Add($n)
    if ($Publisher) {
        foreach ($pub in @($Publisher.Trim(), (Get-WTCleanPublisher $Publisher))) {
            if ($pub -and $n.StartsWith("$pub ", [StringComparison]::OrdinalIgnoreCase)) { $cands.Add($n.Substring($pub.Length).Trim()) }
        }
    }
    foreach ($c in @($cands)) {
        $ns = $c -replace '\s', ''
        if ($ns -ne $c) { $cands.Add($ns) }
    }
    @($cands | Where-Object { $_ -and $_.Length -ge 3 -and $_ -notmatch '^\d+$' -and -not (Test-WTProtectedName $_) } | Select-Object -Unique)
}

function Convert-WTGuidToPacked {
    <# {12345678-ABCD-...} -> the "packed" format used by Windows Installer in the registry. #>
    param([string]$Guid)
    $g = $Guid.Trim('{', '}').Replace('-', '')
    if ($g.Length -ne 32) { return $null }
    $out = (-join $g.Substring(0, 8)[7..0]) + (-join $g.Substring(8, 4)[3..0]) + (-join $g.Substring(12, 4)[3..0])
    for ($i = 16; $i -lt 32; $i += 2) { $out += "$($g[$i + 1])$($g[$i])" }
    $out
}

function Find-WTProgramResidue {
    <#
    .SYNOPSIS
        Looks for the leftovers of a program: folders (Program Files, ProgramData, every
        user's AppData), shortcuts, registry keys, services, scheduled tasks.
        Deletes nothing: returns a list to review.
    .NOTES
        Folders in use by other installed programs and generic/system names are
        excluded automatically.
    #>
    param([Parameter(Mandatory)]$Program)
    $name = $Program.DisplayName
    Write-WTLog "Searching for leftovers of: $name"

    $profiles = @(Get-WTProfileFolders)
    $installed = @(Get-WTInstalledProgram)
    $others = @($installed | Where-Object { $_.RegistryKey -ne $Program.RegistryKey })
    if ($Program.RegistryKey -and ($installed | Where-Object { $_.RegistryKey -eq $Program.RegistryKey })) {
        Write-WTLog 'The program still appears as installed: the results include the files of the program itself.' -Level Warn
    }

    # Paths and names still used by other programs
    $otherLocations = New-Object Collections.Generic.List[string]
    $otherNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($o in $others) {
        if ($o.InstallLocation -and $o.InstallLocation.Length -gt 3) { $otherLocations.Add($o.InstallLocation) }
        foreach ($v in (Get-WTNameVariants -DisplayName $o.DisplayName -Publisher $o.Publisher)) { [void]$otherNames.Add($v) }
    }

    $variants = @()
    foreach ($v in (Get-WTNameVariants -DisplayName $name -Publisher $Program.Publisher)) {
        if ($otherNames.Contains($v)) { Write-WTLog "  Name '$v' excluded: also used by another installed program." }
        else { $variants += $v }
    }
    $pubVariants = @(Get-WTPublisherVariants -Publisher $Program.Publisher)
    Write-WTLog ('  Names searched: {0}' -f $(if ($variants) { $variants -join ' | ' } else { '(none)' }))
    if ($pubVariants) { Write-WTLog ('  Publisher: {0}' -f ($pubVariants -join ' | ')) }

    $found = New-Object Collections.Generic.List[object]
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    function Add-Residue([string]$Type, [string]$Path, [string]$Reason) {
        if ($seen.Add("$Type|$Path")) {
            $found.Add([pscustomobject]@{ Type = $Type; Path = $Path; Reason = $Reason; Program = $name; SizeBytes = [int64]0; SizeText = '' })
        }
    }
    function Test-FolderCandidate([string]$Path) {
        if (Test-WTProtectedPath -Path $Path -ProfileFolders $profiles) { return $false }
        foreach ($o in $otherLocations) { if (Test-WTPathRelated $Path $o) { return $false } }
        $true
    }
    function Get-RootLabel([string]$Root) {
        foreach ($pr in $profiles) { if ($Root.StartsWith($pr + '\', [StringComparison]::OrdinalIgnoreCase)) { return "user data $(Split-Path $pr -Leaf)" } }
        Split-Path $Root -Leaf
    }

    # --- 1. Install folder and uninstaller folder -----------------------------------
    $loc = $Program.InstallLocation
    if ($loc -and (Test-Path -LiteralPath $loc -PathType Container) -and (Test-FolderCandidate $loc)) {
        Add-Residue 'Folder' $loc 'Install folder (InstallLocation)'
    }

    $roots = New-Object Collections.Generic.List[string]
    foreach ($r in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)) { if ($r -and -not $roots.Contains($r)) { $roots.Add($r) } }
    foreach ($pr in $profiles) {
        foreach ($sub in '\AppData\Local\Programs', '\AppData\Roaming', '\AppData\Local', '\AppData\LocalLow') { $roots.Add($pr + $sub) }
    }

    if ($Program.UninstallString) {
        $exe = (Split-WTCommandLine ([Environment]::ExpandEnvironmentVariables($Program.UninstallString)))[0]
        if ([IO.Path]::IsPathRooted($exe) -and $exe -notmatch 'msiexec') {
            $exeDir = Split-Path $exe -Parent
            if ($exeDir -and (Test-Path -LiteralPath $exeDir)) {
                $parent = Split-Path $exeDir -Parent
                if (($roots -contains $parent -or $variants -contains (Split-Path $exeDir -Leaf)) -and (Test-FolderCandidate $exeDir)) {
                    Add-Residue 'Folder' $exeDir 'Uninstaller folder'
                }
            }
        }
    }

    # --- 2. Folders named after the program / the publisher -------------------------
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $label = Get-RootLabel $root
        foreach ($v in $variants) {
            $c = Join-Path $root $v
            if ((Test-Path -LiteralPath $c -PathType Container) -and (Test-FolderCandidate $c)) { Add-Residue 'Folder' $c "Name '$v' ($label)" }
        }
        foreach ($pv in $pubVariants) {
            $pd = Join-Path $root $pv
            if (-not (Test-Path -LiteralPath $pd -PathType Container)) { continue }
            foreach ($v in $variants) {
                $c = Join-Path $pd $v
                if ((Test-Path -LiteralPath $c -PathType Container) -and (Test-FolderCandidate $c)) { Add-Residue 'Folder' $c "Publisher's folder '$v' ($label)" }
            }
            # publisher folder only if it would be left empty
            $children = @(Get-ChildItem -LiteralPath $pd -Force -ErrorAction SilentlyContinue)
            $leftover = @($children | Where-Object { -not $seen.Contains("Folder|$($_.FullName)") })
            if ($leftover.Count -eq 0 -and (Test-FolderCandidate $pd)) { Add-Residue 'Folder' $pd "Publisher folder, empty after cleanup ($label)" }
        }
    }

    # --- 3. Shortcuts (Start menu and desktop) --------------------------------------
    $dirs = @($found | Where-Object { $_.Type -eq 'Folder' } | ForEach-Object { $_.Path })
    $startMenus = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs") + @($profiles | ForEach-Object { "$_\AppData\Roaming\Microsoft\Windows\Start Menu\Programs" })
    $desktops = @("$env:PUBLIC\Desktop") + @($profiles | ForEach-Object { "$_\Desktop" })
    $lnkFiles = New-Object Collections.Generic.List[object]
    foreach ($sm in $startMenus) {
        if (-not (Test-Path -LiteralPath $sm)) { continue }
        foreach ($v in ($variants + $pubVariants)) {
            $c = Join-Path $sm $v
            if (Test-Path -LiteralPath $c -PathType Container) {
                $inside = @(Get-ChildItem -LiteralPath $c -Recurse -Force -File -ErrorAction SilentlyContinue)
                if ($variants -contains $v -or -not ($inside | Where-Object { $_.Extension -ne '.lnk' -and $_.Name -ne 'desktop.ini' })) {
                    Add-Residue 'Folder' $c 'Start menu folder'
                }
            }
        }
        foreach ($f in Get-ChildItem -LiteralPath $sm -Recurse -Force -Filter '*.lnk' -ErrorAction SilentlyContinue) { $lnkFiles.Add($f) }
    }
    foreach ($d in $desktops) {
        foreach ($f in Get-ChildItem -LiteralPath $d -Force -Filter '*.lnk' -ErrorAction SilentlyContinue) { $lnkFiles.Add($f) }
    }
    if ($lnkFiles.Count) {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($f in $lnkFiles) {
            $target = ''
            try { $target = $shell.CreateShortcut($f.FullName).TargetPath } catch { }
            $match = $variants -contains $f.BaseName
            if (-not $match -and $target) {
                foreach ($dd in $dirs) { if (Test-WTPathRelated $target $dd) { $match = $true; break } }
            }
            if ($match) { Add-Residue 'Shortcut' $f.FullName "Shortcut to: $target" }
        }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }

    # --- 4. Registry ------------------------------------------------------------------
    $regRoots = @('HKEY_LOCAL_MACHINE\SOFTWARE', 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node')
    foreach ($h in Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue) {
        if ($h.PSChildName -match '^S-1-(5-21|12-1)-[\d-]+$') { $regRoots += "HKEY_USERS\$($h.PSChildName)\Software" }
    }
    foreach ($rr in $regRoots) {
        foreach ($v in $variants) {
            $k = "$rr\$v"
            if (Test-Path -LiteralPath "Registry::$k") { Add-Residue 'Registry' $k "Key '$v'" }
        }
        foreach ($pv in $pubVariants) {
            $pk = "$rr\$pv"
            if (-not (Test-Path -LiteralPath "Registry::$pk")) { continue }
            foreach ($v in $variants) {
                $k = "$pk\$v"
                if (Test-Path -LiteralPath "Registry::$k") { Add-Residue 'Registry' $k "Publisher's key '$v'" }
            }
            $item = Get-Item -LiteralPath "Registry::$pk" -ErrorAction SilentlyContinue
            if ($item -and $item.ValueCount -eq 0) {
                $left = @($item.GetSubKeyNames() | Where-Object { -not $seen.Contains("Registry|$pk\$_") })
                if ($left.Count -eq 0) { Add-Residue 'Registry' $pk 'Publisher key, empty after cleanup' }
            }
        }
    }
    if ($Program.RegistryKey -and (Test-Path -LiteralPath "Registry::$($Program.RegistryKey)")) {
        Add-Residue 'Registry' $Program.RegistryKey 'Uninstall entry (Apps & features)'
    }
    if ($Program.ProductCode) {
        $packed = Convert-WTGuidToPacked $Program.ProductCode
        if ($packed) {
            foreach ($k in @(
                    "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\$packed",
                    "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Features\$packed",
                    "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$packed")) {
                if (Test-Path -LiteralPath "Registry::$k") { Add-Residue 'Registry' $k 'Windows Installer (MSI) registration' }
            }
        }
    }

    # --- 5. Services and scheduled tasks ----------------------------------------------
    $dirs = @($found | Where-Object { $_.Type -eq 'Folder' } | ForEach-Object { $_.Path })
    $cmp = [StringComparison]::OrdinalIgnoreCase
    foreach ($svc in Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) {
        $pn = "$($svc.PathName)"
        if ($pn -match 'svchost\.exe') { continue }
        $match = $false
        foreach ($d in $dirs) { if ($pn.IndexOf($d + '\', $cmp) -ge 0) { $match = $true; break } }
        if (-not $match -and ($variants -contains $svc.Name -or $variants -contains $svc.DisplayName) -and $pn.IndexOf($env:windir, $cmp) -lt 0) { $match = $true }
        if ($match) { Add-Residue 'Service' $svc.Name "Service '$($svc.DisplayName)' - $pn" }
    }
    try { $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }) } catch { $tasks = @() }
    foreach ($t in $tasks) {
        $exec = [Environment]::ExpandEnvironmentVariables(((@($t.Actions) | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' '))
        $match = $false
        foreach ($d in $dirs) { if ($exec.IndexOf($d + '\', $cmp) -ge 0) { $match = $true; break } }
        if (-not $match) {
            foreach ($v in $variants) {
                if ($v.Length -ge 4 -and ($t.TaskName.IndexOf($v, $cmp) -ge 0 -or $t.TaskName.IndexOf(($v -replace '\s', ''), $cmp) -ge 0)) { $match = $true; break }
            }
        }
        if ($match) { Add-Residue 'Scheduled task' "$($t.TaskPath)$($t.TaskName)" "Runs: $exec" }
    }

    # --- Sizes and summary --------------------------------------------------------------
    foreach ($r in $found) {
        if ($r.Type -eq 'Folder') { $r.SizeBytes = Get-WTFolderSize -Path $r.Path; $r.SizeText = Format-WTSize $r.SizeBytes }
    }
    if ($found.Count) {
        $tot = ($found | Measure-Object SizeBytes -Sum).Sum
        Write-WTLog "Found $($found.Count) leftovers for $name ($(Format-WTSize $tot)). Review them before deleting." -Level Warn
    } else {
        Write-WTLog "No leftovers found for $name." -Level OK
    }
    $found
}

function Remove-WTResidue {
    <#
    .SYNOPSIS
        Removes the selected leftovers (objects from Find-WTProgramResidue), in this order:
        services, tasks, shortcuts, folders, registry (with .reg backup).
    .OUTPUTS
        The leftovers that could not be removed.
    #>
    param([Parameter(Mandatory)][object[]]$InputObject, [switch]$Simulate)
    $order = @{ 'Service' = 1; 'Scheduled task' = 2; 'Shortcut' = 3; 'Folder' = 4; 'Registry' = 5 }
    $sorted = $InputObject | Sort-Object @{ Expression = { $order[$_.Type] } }, @{ Expression = { $_.Path.Length }; Descending = $true }
    $failed = New-Object Collections.Generic.List[object]
    $cmp = [StringComparison]::OrdinalIgnoreCase

    foreach ($r in $sorted) {
        $ok = $true
        switch ($r.Type) {
            'Service' {
                if ($Simulate) { Write-WTLog "[SIMULATION] Would stop and delete service $($r.Path)"; break }
                Stop-Service -Name $r.Path -Force -ErrorAction SilentlyContinue
                & sc.exe delete "$($r.Path)" 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-WTLog "Service deleted: $($r.Path)" -Level OK }
                elseif ($LASTEXITCODE -eq 1072) { Write-WTLog "Service $($r.Path) marked for deletion (completed at restart)." -Level Warn }
                else { Write-WTLog "Could not delete service $($r.Path) (code $LASTEXITCODE)." -Level Error; $ok = $false }
            }
            'Scheduled task' {
                $i = $r.Path.LastIndexOf('\')
                $tp = $r.Path.Substring(0, $i + 1); $tn = $r.Path.Substring($i + 1)
                if ($Simulate) { Write-WTLog "[SIMULATION] Would delete task $($r.Path)"; break }
                try {
                    Unregister-ScheduledTask -TaskName $tn -TaskPath $tp -Confirm:$false -ErrorAction Stop
                    Write-WTLog "Task deleted: $($r.Path)" -Level OK
                } catch { Write-WTLog "Could not delete task $($r.Path): $($_.Exception.Message)" -Level Error; $ok = $false }
            }
            'Shortcut' {
                if ($Simulate) { Write-WTLog "[SIMULATION] Would delete shortcut $($r.Path)"; break }
                try {
                    Remove-Item -LiteralPath $r.Path -Force -ErrorAction Stop
                    Write-WTLog "Shortcut deleted: $($r.Path)" -Level OK
                } catch { if (Test-Path -LiteralPath $r.Path) { Write-WTLog "Could not delete $($r.Path)" -Level Error; $ok = $false } }
            }
            'Folder' {
                if (-not $Simulate) {
                    foreach ($proc in Get-Process -ErrorAction SilentlyContinue) {
                        if ($proc.Path -and $proc.Path.StartsWith($r.Path + '\', $cmp)) {
                            Write-WTLog "Closing process in use: $($proc.ProcessName) (PID $($proc.Id))" -Level Warn
                            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                        }
                    }
                    Start-Sleep -Milliseconds 500
                }
                $ok = Remove-WTFolder -Path $r.Path -Simulate:$Simulate
            }
            'Registry' { $ok = Remove-WTRegistryKey -Key $r.Path -Simulate:$Simulate }
        }
        if ($Simulate -or -not $ok) { $failed.Add($r) }
    }
    if (-not $Simulate) {
        $done = @($sorted).Count - $failed.Count
        Write-WTLog "Leftovers removed: $done, not removed: $($failed.Count)." -Level $(if ($failed.Count) { 'Warn' } else { 'OK' })
    }
    $failed
}
