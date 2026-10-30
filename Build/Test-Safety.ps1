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
        # a whole profile is deleted only on request (Simulate: nothing is touched)
        C "Remove-WTFolder accepts the profile folder $leaf with -AllowProfileRoot (Simulate)" ([bool](Remove-WTFolder -Path $pr -Simulate -AllowProfileRoot 6>$null 3>$null))
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
