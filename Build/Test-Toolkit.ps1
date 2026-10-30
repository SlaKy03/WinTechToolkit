# Static checks: encoding, syntax, XAML (in every language), control names, functions called
# by the pages and translations.
param([switch]$FixBom, [switch]$ListMissing)
$root = Split-Path $PSScriptRoot -Parent
$errs = 0
$utf8Bom = New-Object Text.UTF8Encoding $true
Get-ChildItem $root -Recurse -Include *.ps1, *.psm1, *.psd1 | Where-Object { $_.FullName -notlike '*\.git\*' } | ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF) {
        if ($FixBom) {
            $text = [IO.File]::ReadAllText($_.FullName, (New-Object Text.UTF8Encoding $false))
            [IO.File]::WriteAllText($_.FullName, $text, $utf8Bom)
            "BOM added: $($_.Name)"
        } else { "$($_.Name): missing BOM" }
    }
    $t = $null; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$t, [ref]$e)
    foreach ($x in $e) { $errs++; '{0}:{1} {2}' -f $_.Name, $x.Extent.StartLineNumber, $x.Message }
}
"Syntax errors: $errs"
if ($errs) { return }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Import-Module (Join-Path $root 'Module\WinTechToolkit.psm1') -Force -DisableNameChecking
$global:WTQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
. (Join-Path $root 'UI\Styles.ps1')
$app = @{ Name = 'WinTech Toolkit'; Version = 'check'; Repository = '' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$dataDir = Join-Path $env:TEMP 'wtcheck'

# Same sequence as the main script: generators, pages, XAML, window
$main = [IO.File]::ReadAllText((Join-Path $root 'WinTechToolkit.ps1'))
$start = $main.IndexOf('$script:Pages = ')
$end = $main.IndexOf('$ui.LogList.ItemsSource')
$code = $main.Substring($start, $end - $start).Replace('$PSScriptRoot', "'$root'")

# the window is built in every language: a translation can break the XAML
$languages = @('en') + @(Get-ChildItem (Join-Path $root 'Module\Lang') -Filter '*.psd1' -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
foreach ($lang in $languages) {
    $global:WTLanguage = $lang
    . ([scriptblock]::Create($code))
    "XAML OK ($lang) - pages: $($script:Pages.Count), named controls: $($ui.Count)"
}
$global:WTLanguage = 'en'

# Every name used by the handlers must exist in the window
$missing = New-Object Collections.Generic.List[string]
function On([string]$Name, [scriptblock]$Handler, [string]$EventName = 'Click') {
    if (-not $ui[$Name]) { $missing.Add($Name); return }
    if (-not ($ui[$Name].GetType().GetEvent($EventName))) { $missing.Add("$Name.$EventName") }
}
foreach ($p in $script:Pages) { if ($p.Init) { try { . $p.Init } catch { "Init $($p.Id): $($_.Exception.Message)" } } }
foreach ($m in [regex]::Matches($main, "On '([^']+)'")) { if (-not $ui[$m.Groups[1].Value]) { $missing.Add($m.Groups[1].Value) } }
if ($missing.Count) { 'Missing controls: ' + (($missing | Select-Object -Unique) -join ', ') } else { 'Handlers: all controls found' }

# WT* functions called by the pages but not defined
$defined = @(Get-Command -Module WinTechToolkit | ForEach-Object Name) + @(Get-ChildItem function: | ForEach-Object Name) +
    @([regex]::Matches($main, '(?m)^function ([\w-]+)') | ForEach-Object { $_.Groups[1].Value })
$used = foreach ($f in Get-ChildItem (Join-Path $root 'UI\Pages') -Filter *.ps1) {
    [regex]::Matches([IO.File]::ReadAllText($f.FullName), '\b([A-Z][a-z]+-WT[A-Za-z]+)\b') | ForEach-Object { $_.Groups[1].Value }
}
$undef = @($used | Select-Object -Unique | Where-Object { $defined -notcontains $_ })
if ($undef.Count) { 'Undefined functions: ' + ($undef -join ', ') } else { 'Functions: all defined' }

# --- Translations ----------------------------------------------------------------------
# The constant texts passed to T/TX, or to the functions that translate their text parameters
# (positions and names below), must be in every Module\Lang\*.psd1 with the same {0} {1}...
$translating = @{
    'T' = @(0); 'TX' = @(0); 'Get-WTText' = @(0); 'Add-Line' = @(0)
    'Write-WTLog' = @(0, 'Message'); 'Show-WTInfo' = @(0, 'Message'); 'Show-WTConfirm' = @(0, 1, 'Message', 'Title')
    'Start-WTTask' = @(0, 'Title'); 'New-Pill' = @('Text', 'ToolTip'); 'New-Tile' = @('Title', 'Desc')
    'New-PageHeader' = @(0, 1, 'Title', 'Subtitle'); 'Register-WTPage' = @('Title', 'Group'); 'New-StatCard' = @('Label')
    'Invoke-WTOfficeUserAction' = @(0, 'Title', 'Confirm')
}
$switches = 'Primary', 'Danger', 'Background', 'Queue', 'YesNo', 'Bar', 'LoggedOn', 'AllAdapters', 'RequireLoggedOn'
$texts = New-Object 'Collections.Generic.HashSet[string]'
$codeFiles = @(Get-Item (Join-Path $root 'WinTechToolkit.ps1')) + @(Get-ChildItem (Join-Path $root 'UI'), (Join-Path $root 'Module') -Recurse -Filter '*.ps1')
foreach ($f in $codeFiles) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
    foreach ($cmd in $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $name = $cmd.GetCommandName()
        if (-not $name -or -not $translating.ContainsKey($name)) { continue }
        $els = $cmd.CommandElements
        $pos = 0
        for ($i = 1; $i -lt $els.Count; $i++) {
            $e = $els[$i]
            if ($e -is [System.Management.Automation.Language.CommandParameterAst]) {
                if ($switches -contains $e.ParameterName) { continue }
                $slot = $e.ParameterName
                if ($e.Argument) { $e = $e.Argument } elseif (++$i -lt $els.Count) { $e = $els[$i] } else { break }
            } else { $slot = $pos++ }
            if ($translating[$name] -notcontains $slot) { continue }
            # only constant texts with words (single acronyms like CPU or F5 stay as they are)
            if ($e -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                ($e.Value -cmatch '[a-z]{2}' -or $e.Value -match '\b[A-Za-z]{2,}\b.*\b[A-Za-z]{2,}\b')) { [void]$texts.Add($e.Value) }
        }
    }
}
$placeholders = { param($s) (@([regex]::Matches($s, '\{\d+[^}]*\}') | ForEach-Object { $_.Value } | Sort-Object -Unique)) -join ' ' }
foreach ($lang in $languages | Where-Object { $_ -ne 'en' }) {
    $dict = Read-WTStringTable (Join-Path $root "Module\Lang\$lang.psd1")
    $missing = @($texts | Where-Object { -not $dict.ContainsKey($_) } | Sort-Object)
    $wrong = @($texts | Where-Object { $dict.ContainsKey($_) -and (& $placeholders $_) -ne (& $placeholders $dict[$_]) } | Sort-Object)
    "Translations ($lang): $($texts.Count) texts, $($missing.Count) missing, $($wrong.Count) with different placeholders"
    if ($missing.Count) { "Missing translations ($lang):"; if ($ListMissing) { $missing } else { $missing | Select-Object -First 15; if ($missing.Count -gt 15) { '...' } } }
    if ($wrong.Count) { "Different placeholders ($lang):"; $wrong }
}

# Texts written directly in the XAML, without TX
$sameInEveryLanguage = 'Windows', 'PowerShell', 'Driver', 'Gateway', 'Administrator, admin*'
$raw = foreach ($f in @(Get-Item (Join-Path $root 'WinTechToolkit.ps1')) + @(Get-ChildItem (Join-Path $root 'UI\Pages') -Filter '*.ps1')) {
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($f.FullName), '\b(Text|Content|Header|ToolTip)="(?![^"]*\$)([^"&{][^"]*)"')) {
        if ($m.Groups[2].Value -cmatch '[a-z]{2}' -and $sameInEveryLanguage -notcontains $m.Groups[2].Value) { "$($f.Name): $($m.Value)" }
    }
}
if ($raw) { 'Untranslated XAML texts:'; $raw } else { 'XAML texts: all translated' }
