# Unit tests (Pester 5) of the delete functions: folders, user profiles, program leftovers and
# registry keys, in Tests\*.Tests.ps1. The destructive calls are mocked; the only real deletions
# are of folders the tests create in TestDrive (%TEMP%). Exit code 1 if a test fails.
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Build\Test-Pester.ps1 [-OutputFile results.xml]
# Needs Pester 5.5 or later (Windows ships 3.4):
#   Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
param([string]$OutputFile)
$root = Split-Path $PSScriptRoot -Parent

$pester = Get-Module Pester -ListAvailable | Where-Object { $_.Version -ge [version]'5.5.0' } | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    'Pester 5.5 or later not installed: Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck'
    exit 1
}
Import-Module $pester.Path -Force

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $root 'Tests'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
if ($OutputFile) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = $OutputFile
}
$result = Invoke-Pester -Configuration $config
"Pester: $($result.PassedCount) passed, $($result.FailedCount) failed, $($result.SkippedCount) skipped"
if ($result.Result -ne 'Passed') { exit 1 }
