# Static checks: encoding, syntax, XAML, control names and functions called by the pages.
param([switch]$FixBom)
$root = Split-Path $PSScriptRoot -Parent
$errs = 0
$utf8Bom = New-Object Text.UTF8Encoding $true
Get-ChildItem $root -Recurse -Include *.ps1, *.psm1 | Where-Object { $_.FullName -notlike '*\.git\*' } | ForEach-Object {
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

. ([scriptblock]::Create($code))
"XAML OK - pages: $($script:Pages.Count), named controls: $($ui.Count)"

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
