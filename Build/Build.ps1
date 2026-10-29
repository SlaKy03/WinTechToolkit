<#
.SYNOPSIS
    Builds dist\WinTechToolkit.zip (the scripts) and dist\WinTechToolkit.exe (a launcher with
    the scripts embedded and automatic update from the latest GitHub release), plus a
    .sha256 file for each.
.DESCRIPTION
    Uses the .NET Framework 4 C# compiler, present on every Windows 10/11: no Visual Studio
    or other tools needed.
    The zip and its .sha256 must be attached to the GitHub release with these names: the
    launcher downloads them from
    https://github.com/<Repository>/releases/latest/download/WinTechToolkit.zip
.EXAMPLE
    .\Build\Build.ps1
#>
#Requires -Version 5.1
param([string]$OutDir)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }
$app = Get-Content (Join-Path $root 'app.json') -Raw | ConvertFrom-Json
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw '.NET Framework 4 C# compiler not found.' }

if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutDir | Out-Null

# --- Script package ----------------------------------------------------------------
$files = @('WinTechToolkit.ps1', 'Start-WinTechToolkit.cmd', 'app.json', 'README.md', 'LICENSE') +
    @(Get-ChildItem (Join-Path $root 'Module'), (Join-Path $root 'UI') -Recurse -File | ForEach-Object { $_.FullName.Substring($root.Length + 1) })
$zipPath = Join-Path $OutDir 'WinTechToolkit.zip'
$zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    foreach ($f in $files) {
        $full = Join-Path $root $f
        if (-not (Test-Path -LiteralPath $full)) { Write-Warning "File not found, skipped: $f"; continue }
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $full, ($f -replace '\\', '/'), 'Optimal')
    }
} finally { $zip.Dispose() }
Write-Host "Package: $zipPath ($([math]::Round((Get-Item $zipPath).Length / 1KB)) KB)"

# --- Executable ----------------------------------------------------------------------
$exePath = Join-Path $OutDir 'WinTechToolkit.exe'
# "0.9.0-beta" -> assembly version 0.9.0
$version = if ($app.Version -match '^(\d+(\.\d+){1,3})') { $Matches[1] } else { '1.0.0' }
$info = Join-Path $env:TEMP 'WinTechToolkit_AssemblyInfo.cs'
# author and copyright from the LICENSE ("Copyright (c) 2026 Name")
$copyright = (Get-Content (Join-Path $root 'LICENSE') -TotalCount 5) -match '^Copyright' | Select-Object -First 1
$owner = if ($copyright -match '^Copyright \(c\) \d{4}\s+(.+)$') { $Matches[1].Trim() } else { $app.Name }
@"
using System.Reflection;
[assembly: AssemblyTitle("$($app.Name)")]
[assembly: AssemblyProduct("$($app.Name)")]
[assembly: AssemblyDescription("Diagnostics, repair and maintenance toolkit for Windows 10/11")]
[assembly: AssemblyCompany("$owner")]
[assembly: AssemblyCopyright("$copyright")]
[assembly: AssemblyVersion("$version")]
[assembly: AssemblyFileVersion("$version")]
[assembly: AssemblyInformationalVersion("$($app.Version)")]
"@ | Set-Content -LiteralPath $info -Encoding UTF8

$cscArgs = @(
    '/nologo', '/target:winexe', '/optimize+', '/platform:anycpu',
    "/out:$exePath",
    "/win32manifest:$(Join-Path $PSScriptRoot 'Launcher.manifest')",
    "/resource:$zipPath,payload.zip",
    '/reference:System.IO.Compression.dll', '/reference:System.IO.Compression.FileSystem.dll', '/reference:System.Windows.Forms.dll'
)
$icon = Join-Path $PSScriptRoot 'icon.ico'
if (Test-Path $icon) { $cscArgs += "/win32icon:$icon" }
$cscArgs += (Join-Path $PSScriptRoot 'Launcher.cs'), $info

& $csc @cscArgs
$code = $LASTEXITCODE
Remove-Item $info -Force -ErrorAction SilentlyContinue
if ($code -ne 0) { throw "Compilation failed (exit code $code)." }
Write-Host "Executable: $exePath ($([math]::Round((Get-Item $exePath).Length / 1KB)) KB)"

# --- SHA-256 files (the launcher and start.ps1 verify the zip against its .sha256) ----
foreach ($f in $zipPath, $exePath) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($f))) -replace '-', '').ToLowerInvariant()
    $sha.Dispose()
    # no BOM, plain "hash  name" line (sha256sum format)
    [IO.File]::WriteAllText("$f.sha256", "$hash  $(Split-Path $f -Leaf)`n", (New-Object Text.UTF8Encoding $false))
    Write-Host "SHA-256: $(Split-Path $f -Leaf) $hash"
}

if ($app.Repository -like 'OWNER/*' -or -not $app.Repository) {
    Write-Warning 'Repository not configured in app.json: the exe will only work with the embedded version.'
}
