# Static analysis with PSScriptAnalyzer, limited to the rules that point to real mistakes (style
# rules are left out on purpose: global variables, -Simulate instead of ShouldProcess and plural
# nouns are design choices of this project). Also checks that the code still runs on Windows
# PowerShell 5.1 (no PowerShell 7 syntax such as ?? or ?:).
# Exit code 1 and "ANALYZER" lines if something is found.
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Build\Test-Analyzer.ps1 [-SelfTest]
param([switch]$SelfTest)
$root = Split-Path $PSScriptRoot -Parent

if (-not (Get-Module PSScriptAnalyzer -ListAvailable)) {
    'PSScriptAnalyzer not installed: Install-Module PSScriptAnalyzer -Scope CurrentUser'
    exit 1
}
Import-Module PSScriptAnalyzer

$settings = @{
    IncludeRules = @(
        'PSPossibleIncorrectComparisonWithNull',          # $x -eq $null on a collection
        'PSPossibleIncorrectUsageOfAssignmentOperator',   # if ($a = 1)
        'PSPossibleIncorrectUsageOfRedirectionOperator',  # if ($a > 1)
        'PSAvoidAssignmentToAutomaticVariable',           # $input = ..., $args = ...
        'PSMisleadingBacktick',                           # backtick followed by a space
        'PSUseCmdletCorrectly',                           # missing mandatory parameters
        'PSAvoidDefaultValueSwitchParameter',
        'PSAvoidDefaultValueForMandatoryParameter',
        'PSAvoidOverwritingBuiltInCmdlets',
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSUseCompatibleSyntax',                          # syntax not available in 5.1
        'PSAvoidUsingBrokenHashAlgorithms',
        'PSAvoidUsingComputerNameHardcoded'
    )
    Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1') } }
}

function Invoke-WTAnalyzer([string[]]$Paths) {
    $found = foreach ($p in $Paths) {
        Invoke-ScriptAnalyzer -Path $p -Recurse -Settings $settings
        # rules of severity Error are always on
        Invoke-ScriptAnalyzer -Path $p -Recurse -Severity Error
    }
    @($found | Sort-Object ScriptPath, Line, RuleName -Unique)
}

if ($SelfTest) {
    # each mistake below must be found
    $dir = Join-Path $env:TEMP ('wtanalyzer_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir | Out-Null
    $bad = @(
        'if ($a -eq $null) { }',
        'if ($a = 1) { }',
        'if ($a > 1) { }',
        'function Test-X { $input = 1 }',
        '$b = $c ?? 1'
    )
    $missing = 0
    for ($i = 0; $i -lt $bad.Count; $i++) {
        $f = Join-Path $dir "case$i.ps1"
        Set-Content -LiteralPath $f -Value $bad[$i] -Encoding UTF8
        if (-not (Invoke-WTAnalyzer @($f)).Count) { "SELFTEST not found: $($bad[$i])"; $missing++ }
    }
    Remove-Item $dir -Recurse -Force
    if ($missing) { exit 1 } else { 'SELFTEST ok'; exit 0 }
}

$paths = @('Module', 'UI', 'Build', 'WinTechToolkit.ps1', 'start.ps1') | ForEach-Object { Join-Path $root $_ }
$found = Invoke-WTAnalyzer $paths
foreach ($r in $found) {
    'ANALYZER  {0}:{1}  {2}  {3}' -f $r.ScriptPath.Substring($root.Length + 1), $r.Line, $r.RuleName, $r.Message
}
"Analyzer: $($found.Count) problems"
if ($found.Count) { exit 1 }
