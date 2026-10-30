# List, delete and repair user profiles.

function ConvertTo-WTFileTime {
    <# Combines two registry DWORDs (High/Low) into a date. #>
    param($High, $Low)
    if ($null -eq $High -or $null -eq $Low) { return $null }
    # DWORDs can arrive as negative Int32 or as values > Int32: normalize to unsigned 32 bit
    $h = [uint64]([int64]$High -band 4294967295)
    $l = [uint64]([int64]$Low -band 4294967295)
    $ft = ($h -shl 32) -bor $l
    if ($ft -eq 0) { return $null }
    try { [DateTime]::FromFileTime([int64]$ft) } catch { $null }
}

function New-WTProfileObject {
    param($Type, $UserName, $Sid, $KeyName, $Path, $LastUse, $Loaded, $Status, $SizeBytes, $ProtectReason)
    $days = $null
    if ($LastUse) { $days = [int][math]::Floor(((Get-Date) - $LastUse).TotalDays) }
    # Type: Profile, Backup .bak or Orphan folder (used by the checks), TypeText: shown in the table
    [pscustomobject]@{
        Type          = $Type
        TypeText      = $(switch ($Type) { 'Profile' { T 'Profile' } 'Orphan folder' { T 'Orphan folder' } default { T 'Backup .bak' } })
        UserName      = $UserName
        SID           = $Sid
        KeyName       = $KeyName
        Path          = $Path
        LastUse       = $LastUse
        LastUseText   = $(if ($LastUse) { $LastUse.ToString('yyyy-MM-dd HH:mm') } else { '' })
        DaysUnused    = $days
        Loaded        = [bool]$Loaded
        LoadedText    = Format-WTBool $Loaded
        Status        = $Status
        SizeBytes     = $(if ($null -ne $SizeBytes) { [int64]$SizeBytes } else { [int64]-1 })
        SizeText      = $(if ($null -ne $SizeBytes) { Format-WTSize $SizeBytes } else { '' })
        Protected     = [bool]$ProtectReason
        ProtectReason = $ProtectReason
    }
}

function Get-WTUserProfile {
    <#
    .SYNOPSIS
        Lists the user profiles (ProfileList), the .bak keys and the orphan folders
        present in the profiles folder but not registered.
    #>
    param([switch]$IncludeSize)

    $profilesDir = Get-WTProfilesDirectory
    $cim = @{}
    foreach ($c in Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue) { $cim[$c.SID] = $c }
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $referenced = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $result = New-Object Collections.Generic.List[object]

    foreach ($key in Get-ChildItem $script:WTProfileListKey -ErrorAction SilentlyContinue) {
        $keyName = $key.PSChildName
        $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        $path = ''
        if ($props.ProfileImagePath) { $path = [Environment]::ExpandEnvironmentVariables($props.ProfileImagePath).TrimEnd('\') }
        if ($path) { [void]$referenced.Add($path) }

        $sid = $keyName -replace '\.bak$', ''
        if ($sid -notmatch '^S-1-(5-21|12-1)-[\d-]+$') { continue }   # real accounts only (local, AD, Azure AD)

        $isBak = $keyName -like '*.bak'
        $c = $cim[$keyName]
        $loaded = [bool]($c -and $c.Loaded)
        $exists = $path -and (Test-Path -LiteralPath $path)

        # Last use: LocalProfileLoad/Unload (Win10 1903+), then WMI, then NTUSER.DAT
        $last = @(
            (ConvertTo-WTFileTime $props.LocalProfileLoadTimeHigh $props.LocalProfileLoadTimeLow),
            (ConvertTo-WTFileTime $props.LocalProfileUnloadTimeHigh $props.LocalProfileUnloadTimeLow)
        ) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
        if (-not $last -and $c -and $c.LastUseTime) { $last = $c.LastUseTime }
        if (-not $last -and $exists -and (Test-Path -LiteralPath "$path\NTUSER.DAT")) {
            $last = (Get-Item -LiteralPath "$path\NTUSER.DAT" -Force).LastWriteTime
        }

        $status = 'OK'
        if ($isBak) { $status = T '.bak key (corrupted profile)' }
        elseif ($path -match '\\TEMP(\.[^\\]*)?$') { $status = T 'Temporary profile (TEMP)' }
        elseif (-not $exists) { $status = T 'Folder missing' }

        $protect = ''
        if ($loaded) { $protect = T 'Profile loaded (user signed in)' }
        elseif ($sid -eq $currentSid) { $protect = T 'Account running the toolkit' }
        elseif ($c -and $c.Special) { $protect = T 'System profile' }
        elseif ($path -and -not $path.StartsWith($profilesDir + '\', [StringComparison]::OrdinalIgnoreCase)) { $protect = T 'Path outside {0}' $profilesDir }

        $size = $null
        if ($IncludeSize -and $exists) { $size = Get-WTFolderSize -Path $path }

        $name = Resolve-WTSidName $sid
        if (-not $name) { $name = if ($path) { "$(T '(unresolved)') $(Split-Path $path -Leaf)" } else { T '(unresolved)' } }

        $type = if ($isBak) { 'Backup .bak' } else { 'Profile' }
        $result.Add((New-WTProfileObject -Type $type -UserName $name -Sid $sid -KeyName $keyName -Path $path `
                    -LastUse $last -Loaded $loaded -Status $status -SizeBytes $size -ProtectReason $protect))
    }

    # Folders in C:\Users that are not linked to any profile
    if (Test-Path -LiteralPath $profilesDir) {
        $skip = 'Public', 'Default', 'Default User', 'All Users'
        foreach ($d in Get-ChildItem -LiteralPath $profilesDir -Directory -Force -ErrorAction SilentlyContinue) {
            if ($skip -contains $d.Name) { continue }
            if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($referenced.Contains($d.FullName.TrimEnd('\'))) { continue }
            $size = $null
            if ($IncludeSize) { $size = Get-WTFolderSize -Path $d.FullName }
            $result.Add((New-WTProfileObject -Type 'Orphan folder' -UserName $d.Name -Sid '' -KeyName '' -Path $d.FullName `
                        -LastUse $d.LastWriteTime -Loaded $false -Status (T 'Not registered in ProfileList') -SizeBytes $size -ProtectReason ''))
        }
    }
    $result | Sort-Object Type, UserName
}

function Remove-WTProfileRegistryResidue {
    <# Deletes the registry keys tied to a SID (with .reg backup). #>
    param([Parameter(Mandatory)][string]$Sid, [string[]]$KeyNames, [switch]$IncludeSidKeys, [switch]$Simulate)
    $plKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $keys = @()
    foreach ($kn in $KeyNames) { $keys += "$plKey\$kn" }
    if ($IncludeSidKeys) {
        $keys += @(
            "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\$Sid",
            "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\DataStore\$Sid",
            "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\$Sid",
            "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\$Sid"
        )
        $guidRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid'
        foreach ($g in Get-ChildItem $guidRoot -ErrorAction SilentlyContinue) {
            if ((Get-ItemProperty -LiteralPath $g.PSPath -ErrorAction SilentlyContinue).SidString -eq $Sid) {
                $keys += "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid\$($g.PSChildName)"
            }
        }
    }
    foreach ($k in $keys) {
        if (Test-Path -LiteralPath "Registry::$k") { Remove-WTRegistryKey -Key $k -Simulate:$Simulate | Out-Null }
    }
}

function Remove-WTUserProfile {
    <#
    .SYNOPSIS
        Deletes user profiles with all their leftovers: WMI profile, folder, ProfileList
        keys (also .bak), ProfileGuid, Group Policy and Appx keys of the SID.
    .PARAMETER InputObject
        Objects returned by Get-WTUserProfile.
    #>
    param([Parameter(Mandatory)][object[]]$InputObject, [switch]$Simulate)

    $profilesDir = Get-WTProfilesDirectory
    $ok = 0; $ko = 0
    foreach ($p in $InputObject) {
        Write-WTLog "--- $($p.TypeText): $($p.UserName) [$($p.Path)]"
        if ($p.Protected) { Write-WTLog (T 'Skipped: {0}' $p.ProtectReason) -Level Warn; $ko++; continue }

        if ($p.Type -eq 'Orphan folder') {
            if (-not $p.Path.StartsWith($profilesDir + '\', [StringComparison]::OrdinalIgnoreCase)) {
                Write-WTLog (T 'Skipped: the folder is not under {0}' $profilesDir) -Level Warn; $ko++; continue
            }
            if (Remove-WTFolder -Path $p.Path -Simulate:$Simulate) { $ok++ } else { $ko++ }
            continue
        }

        $sid = $p.SID
        $inst = Get-CimInstance Win32_UserProfile -Filter "SID='$sid'" -ErrorAction SilentlyContinue
        if ($inst -and $inst.Loaded) { Write-WTLog 'Skipped: the profile is currently loaded (user signed in).' -Level Warn; $ko++; continue }

        $fullDelete = $p.Type -eq 'Profile'
        $keyNames = if ($fullDelete) { @($sid, "$sid.bak") } else { @("$sid.bak") }

        # Folders linked to the keys to delete, excluding those used by other keys
        $folders = @()
        $otherPaths = @()
        foreach ($k in Get-ChildItem $script:WTProfileListKey -ErrorAction SilentlyContinue) {
            $ip = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
            if (-not $ip) { continue }
            $ip = [Environment]::ExpandEnvironmentVariables($ip).TrimEnd('\')
            if ($keyNames -contains $k.PSChildName) { $folders += $ip } else { $otherPaths += $ip }
        }
        $folders = @($folders | Select-Object -Unique | Where-Object {
                $_.StartsWith($profilesDir + '\', [StringComparison]::OrdinalIgnoreCase) -and ($otherPaths -notcontains $_)
            })

        # 1) "Official" deletion through WMI (folder + ProfileList)
        if ($fullDelete -and $inst) {
            if ($Simulate) { Write-WTLog (T '[SIMULATION] Would delete the profile through WMI (SID {0})' $sid) }
            else {
                try {
                    Remove-CimInstance -InputObject $inst -ErrorAction Stop
                    Write-WTLog 'Profile deleted through WMI.' -Level OK
                } catch {
                    Write-WTLog (T 'WMI deletion failed ({0}): continuing with manual cleanup.' $_.Exception.Message) -Level Warn
                }
            }
        }
        # 2) Leftover folders
        $allOk = $true
        foreach ($f in $folders) { if (-not (Remove-WTFolder -Path $f -Simulate:$Simulate)) { $allOk = $false } }
        # 3) Leftover registry keys
        Remove-WTProfileRegistryResidue -Sid $sid -KeyNames $keyNames -IncludeSidKeys:$fullDelete -Simulate:$Simulate
        if ($allOk) { $ok++ } else { $ko++ }
    }
    Write-WTLog (T 'Profiles processed: {0} completed, {1} skipped or incomplete.' $ok $ko) -Level $(if ($ko) { 'Warn' } else { 'OK' })
}

function Repair-WTTempProfile {
    <#
    .SYNOPSIS
        Fixes the classic "temporary profile": deletes the SID key that points to TEMP
        and renames SID.bak to SID, resetting State/RefCount.
    #>
    param([Parameter(Mandatory)][string]$Sid, [switch]$Simulate)
    $base = $script:WTProfileListKey
    $main = "$base\$Sid"
    $bak = "$base\$Sid.bak"
    if (-not (Test-Path -LiteralPath $bak)) { Write-WTLog (T 'No {0}.bak key found: nothing to repair.' $Sid) -Level Warn; return }

    $inst = Get-CimInstance Win32_UserProfile -Filter "SID='$Sid'" -ErrorAction SilentlyContinue
    if ($inst -and $inst.Loaded) { Write-WTLog 'The user is signed in: sign them out and try again.' -Level Error; return }

    $mainPath = $null
    if (Test-Path -LiteralPath $main) {
        $mainPath = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty -LiteralPath $main).ProfileImagePath)
        $isTemp = $mainPath -match '\\TEMP(\.[^\\]*)?$' -or -not (Test-Path -LiteralPath $mainPath)
        if (-not $isTemp) {
            Write-WTLog (T 'Both {0} and {0}.bak point to valid profiles ({1}): check manually which one to keep.' $Sid $mainPath) -Level Error
            return
        }
    }
    $bakPath = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty -LiteralPath $bak).ProfileImagePath)
    Write-WTLog (T 'Profile to restore: {0}' $bakPath)
    if ($Simulate) { Write-WTLog (T '[SIMULATION] Would delete {0} (-> {1}) and rename {0}.bak to {0}' $Sid $mainPath); return }

    $regBase = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    Backup-WTRegistryKey -Key "$regBase\$Sid.bak" | Out-Null
    if ($mainPath) { Remove-WTRegistryKey -Key "$regBase\$Sid" | Out-Null }
    Rename-Item -LiteralPath $bak -NewName $Sid
    Set-ItemProperty -LiteralPath $main -Name State -Value 0 -Type DWord
    if ($null -ne (Get-ItemProperty -LiteralPath $main).RefCount) { Set-ItemProperty -LiteralPath $main -Name RefCount -Value 0 -Type DWord }
    Write-WTLog (T 'Key restored: the user will find the profile {0} again at the next sign-in.' $bakPath) -Level OK

    if ($mainPath -and $mainPath -match '\\TEMP(\.[^\\]*)?$' -and (Test-Path -LiteralPath $mainPath)) {
        Remove-WTFolder -Path $mainPath | Out-Null
    }
}
