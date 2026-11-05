# Microsoft Store apps (Appx / MSIX packages): list, removal for all users and leftovers.

# Apps that Windows or the other apps need: listed, but never removed
$script:WTStoreAppsProtected = @(
    'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller', 'Microsoft.SecHealthUI',
    'Microsoft.MicrosoftEdge.Stable', 'Microsoft.MicrosoftEdge', 'Microsoft.Windows.ShellExperienceHost',
    'Microsoft.WindowsAppRuntime*', 'Microsoft.LanguageExperiencePack*', 'Microsoft.VCLibs*', 'Microsoft.UI.Xaml*',
    'Microsoft.NET.Native*', 'Microsoft.Services.Store.Engagement', 'MicrosoftWindows.Client.*Core*'
)

function Test-WTStoreAppProtected {
    param([string]$Name)
    foreach ($p in $script:WTStoreAppsProtected) { if ($Name -like $p) { return $true } }
    $false
}

function Get-WTStoreAppDisplayName {
    # "ms-resource:AppStoreName" in the manifest -> name shown in Start (in the Windows language)
    param($Package, [string]$Value)
    if ($Value -notlike 'ms-resource:*') { return $Value }
    if (-not ('WTNative.IndirectString' -as [type])) {
        Add-Type -Namespace WTNative -Name IndirectString -MemberDefinition @'
[DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
public static extern int SHLoadIndirectString(string source, System.Text.StringBuilder buffer, int size, IntPtr reserved);
'@
    }
    $r = $Value.Substring(12)
    $candidates = if ($r.StartsWith('//')) { @("ms-resource:$r") }
    elseif ($r.StartsWith('/')) { @("ms-resource://$($Package.Name)$r") }
    else { @("ms-resource://$($Package.Name)/Resources/$r", "ms-resource://$($Package.Name)/$r") }
    foreach ($c in $candidates) {
        $sb = New-Object Text.StringBuilder 512
        try {
            if ([WTNative.IndirectString]::SHLoadIndirectString("@{$($Package.PackageFullName)? $c}", $sb, 512, [IntPtr]::Zero) -eq 0 -and $sb.Length) { return $sb.ToString() }
        } catch { }
    }
    $null
}

function Get-WTStoreApp {
    <#
    .SYNOPSIS
        Microsoft Store apps installed for any user of the computer. Frameworks, resource
        packages and the system apps that Windows does not allow to remove are left out.
    .NOTES
        Protected = $true: needed by Windows or by other apps (Store, App Installer/winget,
        Windows Security, Edge, runtimes): shown, never removed.
    #>
    try { $pkgs = @(Get-AppxPackage -AllUsers -PackageTypeFilter Main -ErrorAction Stop) }
    catch { Write-WTLog (T 'Could not read the Store apps: {0}' $_.Exception.Message.Trim()) -Level Error; return }

    $provisioned = @{}
    try { foreach ($pp in Get-AppxProvisionedPackage -Online -ErrorAction Stop) { $provisioned[$pp.DisplayName] = $pp.PackageName } } catch { }

    $list = New-Object Collections.Generic.List[object]
    foreach ($p in $pkgs) {
        if ($p.IsFramework -or $p.NonRemovable -or "$($p.SignatureKind)" -eq 'System') { continue }
        $display = $null; $publisher = ''
        $manifest = if ($p.InstallLocation) { Join-Path $p.InstallLocation 'AppxManifest.xml' } else { $null }
        if ($manifest -and (Test-Path -LiteralPath $manifest)) {
            try {
                $props = ([xml][IO.File]::ReadAllText($manifest)).Package.Properties
                $display = Get-WTStoreAppDisplayName -Package $p -Value "$($props.DisplayName)"
                $publisher = Get-WTStoreAppDisplayName -Package $p -Value "$($props.PublisherDisplayName)"
            } catch { }
        }
        if (-not $display) { $display = $p.Name }
        if (-not $publisher -and $p.Publisher -match 'CN=([^,]+)') { $publisher = $Matches[1].Trim('"') }

        $users = @(foreach ($u in @($p.PackageUserInformation)) {
                if ("$($u.InstallState)" -ne 'Installed') { continue }
                $n = "$($u.UserSecurityId.Username)"
                if (-not $n) { $n = Resolve-WTSidName "$($u.UserSecurityId.Sid)" }
                if (-not $n) { $n = "$($u.UserSecurityId.Sid)" }
                $n -replace "^$([regex]::Escape($env:COMPUTERNAME))\\", ''
            }) | Select-Object -Unique

        $size = [int64]0
        if ($p.InstallLocation) { $size = [int64](Get-WTFolderSize -Path $p.InstallLocation) }
        $list.Add([pscustomobject]@{
                DisplayName       = $display.Trim()
                Name              = $p.Name
                Version           = "$($p.Version)"
                Publisher         = $publisher.Trim()
                Users             = ($users -join ', ')
                Provisioned       = [bool]$provisioned.ContainsKey($p.Name)
                ProvisionedText   = $(if ($provisioned.ContainsKey($p.Name)) { T 'Yes' } else { '' })
                ProvisionedName   = $provisioned[$p.Name]
                Protected         = [bool](Test-WTStoreAppProtected $p.Name)
                SizeBytes         = $size
                SizeText          = $(if ($size) { Format-WTSize $size } else { '' })
                # who signed the package: the Store, or the publisher itself (Developer) for apps
                # that come with Windows or the PC maker, winget or an .msix file (e.g. Quick Assist,
                # Edge, Teams), or a company certificate
                Source            = $(switch ("$($p.SignatureKind)") { 'Store' { 'Microsoft Store' } 'Developer' { T 'Outside the Store' } 'Enterprise' { T 'Company' } default { "$($p.SignatureKind)" } })
                PackageFullName   = $p.PackageFullName
                PackageFamilyName = $p.PackageFamilyName
                InstallLocation   = "$($p.InstallLocation)"
            })
    }
    $list | Sort-Object DisplayName
}

function Find-WTStoreAppResidue {
    <#
    .SYNOPSIS
        Leftovers of a removed Store app: the data folders %LOCALAPPDATA%\Packages\<family name>
        of every profile. Deletes nothing: returns a list for Remove-WTResidue.
    #>
    param([Parameter(Mandatory)]$App)
    $pfn = "$($App.PackageFamilyName)"
    if ($pfn -notmatch '^[\w.-]+_[a-z0-9]{13}$') { return }
    # still installed for some user (removal failed or refused): its data is not a leftover
    try { if (Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.PackageFamilyName -eq $pfn }) { return } } catch { return }
    foreach ($pr in Get-WTProfileFolders) {
        $dir = Join-Path $pr "AppData\Local\Packages\$pfn"
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        $size = [int64](Get-WTFolderSize -Path $dir)
        [pscustomobject]@{
            Type = 'Folder'; TypeText = (T 'Folder'); Path = $dir; Program = $App.DisplayName
            Reason = (T 'App data ({0})' (Split-Path $pr -Leaf)); SizeBytes = $size; SizeText = (Format-WTSize $size)
        }
    }
}

function Remove-WTStoreApp {
    <#
    .SYNOPSIS
        Removes Store apps (objects from Get-WTStoreApp) for every user. With -Deprovision the
        app is also removed from the Windows image, so it is not installed again for new users.
    .OUTPUTS
        The leftovers found after the removal (to review, nothing else is deleted).
    #>
    param([Parameter(Mandatory)][object[]]$InputObject, [switch]$Deprovision, [switch]$Simulate)
    foreach ($a in $InputObject) {
        $label = "$($a.DisplayName) $($a.Version)".Trim()
        if ($a.Protected -or (Test-WTStoreAppProtected $a.Name)) {
            Write-WTLog (T '{0}: needed by Windows or by other apps, not removed.' $a.DisplayName) -Level Warn
            continue
        }
        if ($Simulate) {
            Write-WTLog (T '[SIMULATION] Would remove the app {0} for all users' $label)
            if ($Deprovision -and $a.Provisioned) { Write-WTLog (T '[SIMULATION] Would remove {0} for new users too' $a.DisplayName) }
            continue
        }
        Write-WTLog (T 'Removing the app: {0}' $label)
        try {
            Remove-AppxPackage -Package $a.PackageFullName -AllUsers -ErrorAction Stop
            Write-WTLog (T '{0} removed.' $a.DisplayName) -Level OK
        } catch {
            # 0x80073D02: the app is running; 0x80073CFA: removal refused by Windows
            Write-WTLog (T 'Could not remove {0}: {1}' $a.DisplayName $_.Exception.Message.Trim()) -Level Error
            continue
        }
        if ($Deprovision -and $a.ProvisionedName) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $a.ProvisionedName -ErrorAction Stop | Out-Null
                Write-WTLog (T '{0} will not be installed for new users.' $a.DisplayName) -Level OK
            } catch { Write-WTLog (T 'Could not remove {0} for new users: {1}' $a.DisplayName $_.Exception.Message.Trim()) -Level Warn }
        }
        Find-WTStoreAppResidue -App $a
    }
}
