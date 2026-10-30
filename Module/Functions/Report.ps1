# HTML report of the computer, to attach to a ticket.

function ConvertTo-WTHtmlTable {
    param([object[]]$Rows, [string[]]$Property, [string[]]$Header)
    if (-not $Rows -or -not $Rows.Count) { return '<p class="muted">No data.</p>' }
    $enc = { param($v) [Net.WebUtility]::HtmlEncode("$v") }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('<table><thead><tr>')
    foreach ($h in $Header) { [void]$sb.Append("<th>$(& $enc $h)</th>") }
    [void]$sb.Append('</tr></thead><tbody>')
    foreach ($r in $Rows) {
        [void]$sb.Append('<tr>')
        foreach ($p in $Property) { [void]$sb.Append("<td>$(& $enc $r.$p)</td>") }
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</tbody></table>')
    $sb.ToString()
}

function New-WTHtmlReport {
    <#
    .SYNOPSIS
        Creates an HTML report: summary, event diagnosis, disks, network, programs, startup
        items, local administrators, printers, updates, notes and activities performed.
    .OUTPUTS
        Path of the created file.
    #>
    param([string]$Notes, [string[]]$SessionLog, [int]$Days = 7)
    Write-WTLog 'Collecting data for the report...'
    $enc = { param($v) [Net.WebUtility]::HtmlEncode("$v") }
    # The report is always in English (same format in every ticket, whoever creates it):
    # the data is collected with the interface language switched off
    $language = $global:WTLanguage
    $global:WTLanguage = 'en'
    try {
        $s = Get-WTSystemSummary
        $info = Get-WTSystemInfo
        $diag = Get-WTProblemReport -Days $Days
        $disks = @(Get-WTPhysicalDiskInfo)
        $nets = @(Get-WTNetworkAdapterInfo | Where-Object { $_.Status -eq 'Connected' })
        $programs = @(Get-WTInstalledProgram)
        $startup = @(Get-WTStartupItem)
        $admins = @(Get-WTGroupMember -GroupSid 'S-1-5-32-544')
        $printers = @(Get-WTPrinter)
        $updates = @()
        try { $updates = @(Get-WTUpdateHistory -Max 15) } catch { }
    } finally { $global:WTLanguage = $language }

    $sections = New-Object Collections.Generic.List[string]
    $cards = @(
        @('Computer', $s.Computer, "$($s.Model) - S/N $($s.Serial)"),
        @('Windows', $s.OS, $s.Version),
        @('Up for', $s.Uptime, $(if ($s.PendingReboot) { "Restart pending: $($s.PendingText)" } else { "Last boot $($s.LastBoot)" })),
        @('System disk', "$($s.DiskFreeText) free", "of $($s.DiskTotalText) ($($s.DiskUsedPct)% used)"),
        @('Memory', $s.RamText, "$($s.RamUsedPct)% in use"),
        @('Network', $s.IP, $s.Domain),
        @('Security', "BitLocker $($s.BitLocker)", "Secure Boot $($s.SecureBoot), TPM $($s.Tpm)"),
        @('Stability (7 days)', "$($s.Bsod) BSODs, $($s.Unexpected) unexpected shutdowns", "$($s.AppCrash) application crashes")
    )
    $cardHtml = ($cards | ForEach-Object { "<div class='card'><div class='label'>$(& $enc $_[0])</div><div class='value'>$(& $enc $_[1])</div><div class='sub'>$(& $enc $_[2])</div></div>" }) -join ''
    $sections.Add("<div class='grid'>$cardHtml</div>")

    if ($Notes) { $sections.Add("<h2>Technician notes</h2><div class='notes'>$((& $enc $Notes) -replace "`r?`n", '<br>')</div>") }
    if ($SessionLog) {
        # results and operation titles ("=== Start: ...", in the interface language)
        $acts = @($SessionLog | Where-Object { $_ -match '\[(OK|WARN|ERROR)\s*\]|\] === ' })
        if ($acts.Count) { $sections.Add("<h2>Activities performed in this session</h2><div class='muted'>Log lines are in the language of the interface used during the session.</div><pre>$(& $enc ($acts -join "`n"))</pre>") }
    }
    $sections.Add("<h2>Event diagnosis (last $Days days)</h2><pre>$(& $enc $diag.Report)</pre>")
    $sections.Add('<h2>Physical disks</h2>' + (ConvertTo-WTHtmlTable $disks 'Name', 'MediaType', 'SizeText', 'Health', 'Temperature', 'Wear', 'PowerOnHours' 'Disk', 'Type', 'Size', 'Status', 'Temp. °C', 'Wear %', 'Power-on hours'))
    $sections.Add('<h2>Network</h2>' + (ConvertTo-WTHtmlTable $nets 'Name', 'IP', 'Gateway', 'DNS', 'DHCP', 'MAC', 'Speed' 'Adapter', 'IP', 'Gateway', 'DNS', 'DHCP', 'MAC', 'Speed'))
    $sections.Add('<h2>Local administrators</h2>' + (ConvertTo-WTHtmlTable $admins 'Name', 'Class', 'SourceText' 'Account', 'Type', 'Source'))
    $sections.Add('<h2>Startup programs</h2>' + (ConvertTo-WTHtmlTable $startup 'Name', 'Publisher', 'Location', 'EnabledText', 'Command' 'Name', 'Publisher', 'Location', 'Enabled', 'Command'))
    $sections.Add('<h2>Printers</h2>' + (ConvertTo-WTHtmlTable $printers 'Name', 'Type', 'Driver', 'Port', 'Status' 'Name', 'Type', 'Driver', 'Port', 'Status'))
    $sections.Add('<h2>Recent updates</h2>' + (ConvertTo-WTHtmlTable $updates 'TimeText', 'Title', 'Result', 'Code' 'Date', 'Update', 'Result', 'Code'))
    $sections.Add("<h2>Installed programs ($($programs.Count))</h2>" + (ConvertTo-WTHtmlTable $programs 'DisplayName', 'Version', 'Publisher', 'InstallDate', 'Scope' 'Name', 'Version', 'Publisher', 'Installed on', 'Scope'))
    $sections.Add("<h2>Full inventory</h2><pre>$(& $enc $info)</pre>")

    $css = @'
body{font-family:"Segoe UI",sans-serif;background:#eff1f5;color:#4c4f69;margin:0;padding:28px 36px}
h1{margin:0;font-size:26px}h2{font-size:17px;margin:30px 0 10px;color:#8839ef}
.head{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:2px solid #ccd0da;padding-bottom:12px}
.muted{color:#6c6f85}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px;margin-top:20px}
.card{background:#fff;border:1px solid #ccd0da;border-radius:10px;padding:12px 14px}
.label{font-size:11px;font-weight:600;color:#6c6f85;text-transform:uppercase}.value{font-size:17px;font-weight:600;margin-top:6px}
.sub{font-size:12px;color:#6c6f85;margin-top:2px}
table{border-collapse:collapse;width:100%;background:#fff;border:1px solid #ccd0da;font-size:12.5px}
th{background:#e6e9ef;text-align:left;padding:6px 8px}td{padding:5px 8px;border-top:1px solid #e6e9ef;vertical-align:top}
pre{background:#fff;border:1px solid #ccd0da;border-radius:8px;padding:12px;white-space:pre-wrap;font-size:12px}
.notes{background:#fff;border-left:4px solid #8839ef;padding:10px 14px}
'@
    $who = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $html = @"
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Report $($s.Computer)</title><style>$css</style></head><body>
<div class="head"><div><h1>$(& $enc $s.Computer)</h1><div class="muted">$(& $enc $s.Model) &middot; $(& $enc $s.Domain)</div></div>
<div class="muted">Report of $(Get-Date -Format 'yyyy-MM-dd HH:mm') &middot; technician: $(& $enc $who)<br>WinTech Toolkit</div></div>
$($sections -join "`n")
</body></html>
"@
    $file = Join-Path (Get-WTDataFolder) ('Report\Report_{0}_{1:yyyyMMdd_HHmm}.html' -f $env:COMPUTERNAME, (Get-Date))
    Set-Content -LiteralPath $file -Value $html -Encoding UTF8
    Write-WTLog (T 'Report created: {0}' $file) -Level OK
    $file
}
