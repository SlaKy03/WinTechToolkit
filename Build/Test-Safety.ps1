# Safety checks of the delete functions. Nothing real is deleted: it uses -Simulate, folders
# created in %TEMP% and read-only checks. Exit code 1 (and "FAIL" lines) if a protection is missing.
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Build\Test-Safety.ps1
$root = Split-Path $PSScriptRoot -Parent
$mod = Import-Module (Join-Path $root 'Module\WinTechToolkit.psm1') -Force -DisableNameChecking -PassThru
$global:WTLanguage = 'en'
$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { $script:pass++; "PASS  $Name" } else { $script:fail++; "FAIL  $Name" }
}

# Everything below runs inside the module, where the private functions are visible
$report = & $mod {
    param($tempRoot)
    $out = New-Object Collections.Generic.List[string]
    $f = 0; $p = 0
    function C([string]$Name, [bool]$Cond) { if ($Cond) { $script:p++; $out.Add("PASS  $Name") } else { $script:f++; $out.Add("FAIL  $Name") } }
    $script:p = 0; $script:f = 0

    # Quiet log: these checks provoke refusals on purpose
    $global:WTQueue = $null
    $log = { param($m) }

    # --- 1. Names that are never offered as leftovers --------------------------------------
    foreach ($n in 'Microsoft', 'Windows', 'Windows NT', 'Common Files', 'WindowsApps', 'Users', 'Public', 'Documents', 'Downloads', 'Desktop', 'Temp') {
        C "protected name: $n" (Test-WTProtectedName $n)
    }
    C 'protected name: empty string' (Test-WTProtectedName '')
    C 'protected name: Windows Defender (prefix Windows)' (Test-WTProtectedName 'Windows Something New')
    C 'not protected: a normal program name' (-not (Test-WTProtectedName 'ZoomVideoApps'))

    # --- 2. Paths that are never offered as leftovers ---------------------------------------
    $profiles = @(Get-WTProfileFolders)
    foreach ($path in @($env:windir, "$env:windir\System32", $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, "$env:SystemDrive\Users", $env:PUBLIC, "$env:SystemDrive\")) {
        if ($path) { C "protected path: $path" (Test-WTProtectedPath -Path $path -ProfileFolders $profiles) }
    }
    C 'protected path: inside Windows (C:\Windows\Temp\x)' (Test-WTProtectedPath -Path "$env:windir\Temp\x" -ProfileFolders $profiles)
    foreach ($pr in $profiles) {
        $leaf = Split-Path $pr -Leaf
        foreach ($sub in '', '\AppData', '\AppData\Roaming', '\AppData\Local', '\Desktop', '\Documents', '\Downloads') {
            C "protected path: profile $leaf$sub" (Test-WTProtectedPath -Path ($pr + $sub) -ProfileFolders $profiles)
        }
    }
    C 'not protected: a folder of an application in AppData\Local' (-not (Test-WTProtectedPath -Path "$env:LOCALAPPDATA\WTSafetyTestFolder" -ProfileFolders $profiles))

    # --- 3. Remove-WTFolder refuses critical paths (Simulate: nothing is touched) ------------
    foreach ($path in @($env:windir, "$env:windir\System32", $env:ProgramFiles, $env:ProgramData, "$env:SystemDrive\Users", "$env:SystemDrive\", 'C:')) {
        if ($path) { C "Remove-WTFolder refuses: $path" (-not (Remove-WTFolder -Path $path -Simulate 6>$null 3>$null)) }
    }

    # --- 4. Remove-WTFolder is the last line of defense, whoever calls it ----------------------
    # (the GUI only offers folders returned by the search, which filters them; the module can also
    # be used from the console)
    foreach ($pr in $profiles) {
        $leaf = Split-Path $pr -Leaf
        C "Remove-WTFolder refuses a profile folder: $leaf" (-not (Remove-WTFolder -Path $pr -Simulate 6>$null 3>$null))
        foreach ($sub in 'Documents', 'Desktop', 'Downloads', 'AppData', 'AppData\Local', 'AppData\Roaming', 'Pictures', 'OneDrive') {
            C "Remove-WTFolder refuses $leaf\$sub" (-not (Remove-WTFolder -Path "$pr\$sub" -Simulate 6>$null 3>$null))
        }
        # the personal folders stay protected even for the profile functions
        C "Remove-WTFolder refuses $leaf\Documents even with -AllowProfileRoot" (-not (Remove-WTFolder -Path "$pr\Documents" -Simulate -AllowProfileRoot 6>$null 3>$null))
        # a whole profile is deleted only on request (Simulate: nothing is touched), never the one
        # that contains the running toolkit (e.g. run from the Desktop or from %TEMP%)
        if (Test-WTToolkitPath $pr) {
            C "Remove-WTFolder refuses the profile folder $leaf that contains the toolkit" (-not (Remove-WTFolder -Path $pr -Simulate -AllowProfileRoot 6>$null 3>$null))
        } elseif (Test-WTSystemProfileName $leaf) {
            C "Remove-WTFolder refuses the Windows profile $leaf even with -AllowProfileRoot" (-not (Remove-WTFolder -Path $pr -Simulate -AllowProfileRoot 6>$null 3>$null))
        } else {
            C "Remove-WTFolder accepts the profile folder $leaf with -AllowProfileRoot (Simulate)" ([bool](Remove-WTFolder -Path $pr -Simulate -AllowProfileRoot 6>$null 3>$null))
        }
    }
    # legitimate uses keep working: a leftover folder of an application
    $legit = Join-Path $env:LOCALAPPDATA 'WTSafetyLegitFolder'
    New-Item -ItemType Directory -Path $legit -Force | Out-Null
    try { C 'Remove-WTFolder accepts an application folder (Simulate)' ([bool](Remove-WTFolder -Path $legit -Simulate 6>$null 3>$null)) }
    finally { Remove-Item -LiteralPath $legit -Recurse -Force -ErrorAction SilentlyContinue }

    # Real deletion (not Simulate) of a folder created here: it must really disappear, and a sibling
    # folder with a file inside must stay untouched
    $real = Join-Path $env:LOCALAPPDATA 'WTSafetyRealDelete'
    $sibling = Join-Path $env:LOCALAPPDATA 'WTSafetyRealDelete_Sibling'
    New-Item -ItemType Directory -Path "$real\sub" -Force | Out-Null
    New-Item -ItemType Directory -Path $sibling -Force | Out-Null
    Set-Content -LiteralPath "$real\sub\a.txt" -Value 'x'
    Set-Content -LiteralPath "$sibling\keep.txt" -Value 'x'
    try {
        $res = Remove-WTFolder -Path $real 6>$null 3>$null
        C 'Remove-WTFolder really deletes an application folder with content' ([bool]$res -and -not (Test-Path -LiteralPath $real))
        C 'a sibling folder is left untouched' (Test-Path -LiteralPath "$sibling\keep.txt")
    } finally {
        Remove-Item -LiteralPath $real, $sibling -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --- 5. Profiles: loaded, current and system profiles are marked as protected ---------------
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $all = @(Get-WTUserProfile)
    $mine = @($all | Where-Object { $_.SID -eq $currentSid })
    C 'the profile of the account running the tests is listed' ($mine.Count -ge 1)
    foreach ($m in $mine) { C "current account profile is protected: $($m.UserName)" ([bool]$m.Protected) }
    foreach ($l in @($all | Where-Object { $_.Loaded })) { C "loaded profile is protected: $($l.UserName)" ([bool]$l.Protected) }
    C 'no profile outside the profiles folder is unprotected' (@($all | Where-Object { $_.Path -and -not $_.Protected -and $_.Type -ne 'Orphan folder' -and -not $_.Path.StartsWith((Get-WTProfilesDirectory) + '\', [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0)

    # Remove-WTUserProfile skips protected profiles even if asked (Simulate)
    $prot = @($all | Where-Object { $_.Protected } | Select-Object -First 1)
    if ($prot.Count) {
        $before = Test-Path -LiteralPath $prot[0].Path
        Remove-WTUserProfile -InputObject $prot -Simulate 6>$null 3>$null 4>$null | Out-Null
        C 'Remove-WTUserProfile leaves a protected profile alone' ($before -and (Test-Path -LiteralPath $prot[0].Path))
    }

    # --- 6. Partial search never proposes protected or system things ---------------------------
    foreach ($name in 'Windows', 'Microsoft', 'Users', 'Data') {
        $pseudo = [pscustomobject]@{ DisplayName = $name; Publisher = ''; Version = ''; InstallLocation = ''; UninstallString = ''; QuietUninstallString = ''; ProductCode = $null; RegistryKey = ''; InstallerType = '' }
        $found = @(Find-WTProgramResidue -Program $pseudo -Partial 6>$null 3>$null 4>$null | Where-Object { $_.PSObject.Properties['Reason'] })
        C "partial search for '$name' proposes nothing" ($found.Count -eq 0)
    }

    # A name that is too short is not searched in partial mode
    $short = [pscustomobject]@{ DisplayName = 'abc'; Publisher = ''; Version = ''; InstallLocation = ''; UninstallString = ''; QuietUninstallString = ''; ProductCode = $null; RegistryKey = ''; InstallerType = '' }
    $r = @(Find-WTProgramResidue -Program $short -Partial 6>$null 3>$null 4>$null | Where-Object { $_.PSObject.Properties['Reason'] })
    C "partial search for a 3-letter name proposes nothing" ($r.Count -eq 0)

    # --- 7. Partial search finds a folder it should, in a temp-like safe place, and never a protected one
    $probe = Join-Path $env:LOCALAPPDATA 'WTSafetyProbeAlpha_Folder'
    New-Item -ItemType Directory -Path $probe -Force | Out-Null
    try {
        $probeProg = [pscustomobject]@{ DisplayName = 'WTSafetyProbeAlpha'; Publisher = ''; Version = ''; InstallLocation = ''; UninstallString = ''; QuietUninstallString = ''; ProductCode = $null; RegistryKey = ''; InstallerType = '' }
        $exact = @(Find-WTProgramResidue -Program $probeProg 6>$null 3>$null 4>$null | Where-Object { $_.PSObject.Properties['Reason'] })
        $partial = @(Find-WTProgramResidue -Program $probeProg -Partial 6>$null 3>$null 4>$null | Where-Object { $_.PSObject.Properties['Reason'] })
        C 'exact search does not find a folder that only contains the name' (@($exact | Where-Object { $_.Path -eq $probe }).Count -eq 0)
        C 'partial search finds a folder that contains the name' (@($partial | Where-Object { $_.Path -eq $probe }).Count -eq 1)
        # Simulate: the folder must still be there afterwards
        Remove-WTResidue -InputObject @($partial | Where-Object { $_.Path -eq $probe }) -Simulate 6>$null 3>$null 4>$null | Out-Null
        C 'Remove-WTResidue -Simulate does not delete anything' (Test-Path -LiteralPath $probe)
    } finally {
        Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --- 6b. Profiles Windows uses for itself (defaultuser0...) -------------------------------------
    foreach ($n in 'defaultuser0', 'defaultuser100000', 'PC01\defaultuser0', 'WsiAccount') { C "system profile name: $n" (Test-WTSystemProfileName $n) }
    foreach ($n in 'mario.rossi', 'defaultuser', 'defaultuserX', 'Administrator') { C "normal profile name: $n" (-not (Test-WTSystemProfileName $n)) }
    C 'defaultuser profiles are not listed' (@(Get-WTUserProfile | Where-Object { Test-WTSystemProfileName (Split-Path "$($_.Path)" -Leaf) }).Count -eq 0)
    C 'defaultuser profiles are not offered as targets' (@(Get-WTUserTargets | Where-Object { Test-WTSystemProfileName $_.UserName }).Count -eq 0)
    $du = Join-Path (Get-WTProfilesDirectory) 'defaultuser0'
    C 'Remove-WTFolder refuses C:\Users\defaultuser0 even with -AllowProfileRoot' (-not (Remove-WTFolder -Path $du -Simulate -AllowProfileRoot 6>$null 3>$null 4>$null))
    $fakeDu = [pscustomobject]@{ Type = 'Profile'; TypeText = 'Profile'; UserName = 'PC01\defaultuser0'; SID = 'S-1-5-21-1-2-3-1001'; KeyName = 'S-1-5-21-1-2-3-1001'
        Path = $du; Protected = $false; ProtectReason = ''; Loaded = $false }
    $global:WTQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    Remove-WTUserProfile -InputObject $fakeDu -Simulate 6>$null 3>$null 4>$null | Out-Null
    $logLines = @($global:WTQueue.ToArray())
    $global:WTQueue = $null
    C 'Remove-WTUserProfile skips defaultuser0 even if asked' ([bool]($logLines -match 'account used by Windows') -and -not ($logLines -match 'SIMULATION'))

    # --- 6c. Automatic cleanup after an uninstall ----------------------------------------------------
    # an uninstall that did not complete never deletes the files of the program that is still there
    $keep = Join-Path $env:LOCALAPPDATA 'WTSafetyRemovalProbe'
    New-Item -ItemType Directory -Path $keep -Force | Out-Null
    try {
        $prog = [pscustomobject]@{ DisplayName = 'WTSafetyRemovalProbe'; Publisher = ''; Version = '1'; InstallLocation = $keep; UninstallString = ''
            QuietUninstallString = ''; ProductCode = $null; RegistryKey = ''; InstallerType = 'EXE' }
        $r = @(Invoke-WTProgramRemoval -Program $prog 6>$null 3>$null 4>$null)
        C 'failed uninstall: the program folder is not deleted' (Test-Path -LiteralPath $keep)
        C 'failed uninstall: the leftovers are returned for review' (@($r | Where-Object { $_.PSObject.Properties['Reason'] -and $_.Path -eq $keep }).Count -eq 1)
    } finally { Remove-Item -LiteralPath $keep -Recurse -Force -ErrorAction SilentlyContinue }
    # deletion at the next restart has the same protections as Remove-WTFolder
    foreach ($path in @($env:windir, $env:ProgramFiles, [Environment]::GetFolderPath('MyDocuments'), $script:WTToolkitRoot, (Join-Path (Get-WTProfilesDirectory) 'defaultuser0'))) {
        if ($path) { C "Register-WTDeleteAtReboot refuses: $path" (-not (Register-WTDeleteAtReboot -Path $path 6>$null 3>$null 4>$null)) }
    }
    foreach ($pr in $profiles) { C "Register-WTDeleteAtReboot refuses the profile folder $(Split-Path $pr -Leaf)" (-not (Register-WTDeleteAtReboot -Path $pr 6>$null 3>$null 4>$null)) }

    # --- 7a. Store apps: the ones Windows needs are never removed --------------------------------
    foreach ($n in 'Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller', 'Microsoft.SecHealthUI', 'Microsoft.MicrosoftEdge.Stable',
        'Microsoft.VCLibs.140.00', 'Microsoft.UI.Xaml.2.8', 'Microsoft.WindowsAppRuntime.1.5', 'Microsoft.LanguageExperiencePackit-IT') {
        C "Store app protected: $n" (Test-WTStoreAppProtected $n)
    }
    C 'Store app not protected: Microsoft.WindowsCalculator' (-not (Test-WTStoreAppProtected 'Microsoft.WindowsCalculator'))
    # a protected app passed to the remove function anyway (no -Simulate: it must refuse before acting)
    $fakeStore = [pscustomobject]@{ DisplayName = 'Microsoft Store'; Name = 'Microsoft.WindowsStore'; Version = '1'; Protected = $false
        Provisioned = $false; ProvisionedName = $null; PackageFullName = 'Microsoft.WindowsStore_0.0.0.0_x64__8wekyb3d8bbwe'; PackageFamilyName = 'Microsoft.WindowsStore_8wekyb3d8bbwe' }
    $res = @(Remove-WTStoreApp -InputObject $fakeStore 6>$null 3>$null 4>$null)
    C 'Remove-WTStoreApp refuses Microsoft Store even if not marked as protected' ($res.Count -eq 0)
    # an app that does not exist has no leftovers (no key of other apps or of Windows is proposed)
    $ghost = [pscustomobject]@{ DisplayName = 'Ghost'; Name = 'Contoso.WTGhostApp'; PackageFamilyName = 'Contoso.WTGhostApp_abcdefghjkmnp' }
    C 'Store leftovers: nothing for an app that does not exist' (@(Find-WTStoreAppResidue -App $ghost -Preview 6>$null 3>$null 4>$null).Count -eq 0)
    $calc = [pscustomobject]@{ DisplayName = 'Calculator'; Name = 'Microsoft.WindowsCalculator'; PackageFamilyName = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe' }
    $calcKeys = @(Find-WTStoreAppResidue -App $calc -Preview 6>$null 3>$null 4>$null | Where-Object { $_.Type -eq 'Registry' })
    C 'Store leftovers: registry keys only of that app, never Deprovisioned' (@($calcKeys | Where-Object { $_.Path -match 'Deprovisioned' -or $_.Path -notmatch 'WindowsCalculator|\\AppX[a-z0-9]+$' }).Count -eq 0)
    # leftovers are only proposed for a well-formed family name, never for a generic path
    foreach ($pfn in '', '..', 'Packages', '..\..\Desktop', 'Microsoft.WindowsCalculator') {
        $r = @(Find-WTStoreAppResidue -App ([pscustomobject]@{ DisplayName = 'x'; PackageFamilyName = $pfn }) 6>$null 3>$null 4>$null)
        C "Store leftovers: nothing for family name '$pfn'" ($r.Count -eq 0)
    }

    # --- 7b. The folder the toolkit runs from (and other running copies) is never deleted ------
    C 'toolkit folder is protected' (Test-WTProtectedPath -Path $script:WTToolkitRoot -ProfileFolders $profiles)
    C 'a folder containing the toolkit is protected' (Test-WTToolkitPath (Split-Path $script:WTToolkitRoot -Parent))
    C 'a folder inside the toolkit is protected' (Test-WTToolkitPath (Join-Path $script:WTToolkitRoot 'Module'))
    C 'another running copy in a Temp folder is protected' (Test-WTToolkitPath (Join-Path $tempRoot 'WinTechToolkit_0123456789'))
    C 'an unrelated temp folder is not protected' (-not (Test-WTToolkitPath (Join-Path $tempRoot 'SomeSetup_123')))
    C 'Remove-WTFolder refuses the toolkit folder' (-not (Remove-WTFolder -Path $script:WTToolkitRoot -Simulate 6>$null 3>$null 4>$null))
    $fakeTemp = Join-Path $tempRoot ('wt_safety_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $copy = Join-Path $fakeTemp 'WinTechToolkit_running'
    try {
        New-Item -ItemType Directory -Path $copy, (Join-Path $fakeTemp 'junk') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $copy 'WinTechToolkit.ps1') -Value 'x'
        Set-Content -LiteralPath (Join-Path $fakeTemp 'junk\a.tmp') -Value 'x'
        # $copy is in 8.3 form when %TEMP% is (C:\Users\ABCDEF~1\...): the check must still match
        $saved = $script:WTToolkitRoot
        $script:WTToolkitRoot = $copy
        Remove-WTTreeBestEffort -Directory (New-Object IO.DirectoryInfo $fakeTemp)
        $script:WTToolkitRoot = $saved
        C 'emptying a temp folder keeps the running toolkit files' (Test-Path -LiteralPath (Join-Path $copy 'WinTechToolkit.ps1'))
        C 'emptying a temp folder still deletes the rest' (-not (Test-Path -LiteralPath (Join-Path $fakeTemp 'junk')))
    } finally {
        Remove-Item -LiteralPath $fakeTemp -Recurse -Force -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{ Lines = $out.ToArray(); Pass = $script:p; Fail = $script:f }
} $env:TEMP

$report.Lines
$script:pass += $report.Pass
$script:fail += $report.Fail

# --- 8. start.ps1 has no BOM and passes its own integrity expression on byte input ------------
$startBytes = [IO.File]::ReadAllBytes((Join-Path $root 'start.ps1'))
Check 'start.ps1 has no BOM (it is run with irm | iex)' (-not ($startBytes.Length -ge 3 -and $startBytes[0] -eq 0xEF))
$startText = [Text.Encoding]::UTF8.GetString($startBytes)
Check 'start.ps1 decodes the .sha256 when it arrives as bytes' ($startText.Contains('-is [byte[]]'))

# --- 8b. The operations keep working if the toolkit files are deleted during the session --------
$mainText = [IO.File]::ReadAllText((Join-Path $root 'WinTechToolkit.ps1'))
Check 'a runspace created after the files are gone loads the module from memory' ($mainText.Contains('New-Module -Name WinTechToolkit') -and $mainText.Contains("'WTModuleSource'"))
Check 'the translations are passed to the runspaces' ($mainText.Contains("'WTStringTables'"))

# --- 9. Language fallback: a language without a translation file falls back to English ----------
$script:WTSimLang = $null
foreach ($code in 'xx', 'zz', '', $null) {
    $lang = & $mod { param($c) Get-WTLanguage $c } $code
    $expected = 'en'
    if ($lang -eq 'it' -and [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'it') { $expected = 'it' }
    Check "unknown language '$code' falls back correctly ($lang)" ($lang -eq $expected -or $lang -eq 'en')
}
Check "available translation is honored: it" ((& $mod { Get-WTLanguage 'it' }) -eq 'it')
Check "English is always honored: en" ((& $mod { Get-WTLanguage 'en' }) -eq 'en')

# A text without a translation stays in English, and {0} placeholders still work
$global:WTLanguage = 'it'
$untranslated = & $mod { Get-WTText 'This text has no translation in any file {0}' 'ok' }
Check 'a missing translation stays in English and formats placeholders' ($untranslated -eq 'This text has no translation in any file ok')
$global:WTLanguage = 'xx'
$unknownLang = & $mod { Get-WTText 'Cancel' }
Check 'an unknown language code shows English text' ($unknownLang -eq 'Cancel')
$global:WTLanguage = 'en'

''
"Safety checks: $($script:pass) passed, $($script:fail) failed"
if ($script:fail) { exit 1 }
