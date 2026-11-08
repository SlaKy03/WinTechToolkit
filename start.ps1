<#
.SYNOPSIS
    Run without installing anything:
        irm https://raw.githubusercontent.com/SlaKy03/WinTechToolkit/main/start.ps1 | iex
.DESCRIPTION
    Downloads the latest release to a temporary folder, checks it against the published
    SHA-256 file, starts the toolkit as administrator and deletes the folder when the
    window is closed.
#>
$repo = 'SlaKy03/WinTechToolkit'

& {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $work = Join-Path $env:TEMP ('WinTechToolkit_' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    $zip = "$work.zip"
    try {
        $base = "https://github.com/$repo/releases/latest/download/WinTechToolkit.zip"
        Write-Host "Downloading WinTech Toolkit from github.com/$repo ..."
        Invoke-WebRequest -Uri $base -OutFile $zip -UseBasicParsing
        # GitHub serves the .sha256 as application/octet-stream: Content is then a byte array, not text
        $shaText = (Invoke-WebRequest -Uri "$base.sha256" -UseBasicParsing).Content
        if ($shaText -is [byte[]]) { $shaText = [Text.Encoding]::ASCII.GetString($shaText) }
        $expected = [regex]::Match([string]$shaText, '\b[0-9a-fA-F]{64}\b').Value
        $sha = [Security.Cryptography.SHA256]::Create()
        $actual = [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($zip))) -replace '-', ''
        $sha.Dispose()
        if (-not $expected -or $expected -ne $actual) { throw 'The downloaded package does not match its published SHA-256 hash. Nothing was started.' }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $work)
        Remove-Item $zip -Force

        $ps = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $script = Join-Path $work 'WinTechToolkit.ps1'
        Write-Host 'Starting (confirm the User Account Control prompt)...'
        # -Wait: the folder can only be deleted once the window is closed
        Start-Process -FilePath $ps -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$script`"" -Verb RunAs -Wait
    } catch {
        Write-Host "Could not start: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        Remove-Item $zip, $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
