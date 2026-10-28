# Windows Update through the agent's COM API (Microsoft.Update.Session).

function Get-WTUpdateHistory {
    param([int]$Max = 80)
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $total = $searcher.GetTotalHistoryCount()
    if (-not $total) { Write-WTLog 'Update history is empty.'; return }
    $results = @{ 0 = 'Not started'; 1 = 'In progress'; 2 = 'Succeeded'; 3 = 'Succeeded with errors'; 4 = 'Failed'; 5 = 'Aborted' }
    $rows = foreach ($h in $searcher.QueryHistory(0, [Math]::Min($total, $Max))) {
        if (-not $h.Title) { continue }
        $date = [DateTime]::SpecifyKind($h.Date, 'Utc').ToLocalTime()
        [pscustomobject]@{
            Time     = $date
            TimeText = $date.ToString('yyyy-MM-dd HH:mm')
            Title    = $h.Title
            KB       = $(if ($h.Title -match '(KB\d+)') { $Matches[1] } else { '' })
            Result   = $results[[int]$h.ResultCode]
            Code     = $(if ($h.HResult) { '0x{0:X8}' -f $h.HResult } else { '' })
        }
    }
    $failed = @($rows | Where-Object { $_.Result -eq 'Failed' }).Count
    Write-WTLog "History: $(@($rows).Count) entries, $failed failed." -Level $(if ($failed) { 'Warn' } else { 'OK' })
    $rows
}

function New-WTUpdateSearcher {
    param([switch]$Online)
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    # 2 = directly from Windows Update, ignoring WSUS/policies
    if ($Online) { $searcher.ServerSelection = 2 }
    [pscustomobject]@{ Session = $session; Searcher = $searcher }
}

function Find-WTUpdate {
    <#
    .SYNOPSIS
        Searches for updates that are not installed. -Online queries Windows Update even if
        the PC is managed by WSUS; -IncludeDrivers adds drivers.
    #>
    param([switch]$Online, [switch]$IncludeDrivers)
    $s = New-WTUpdateSearcher -Online:$Online
    $criteria = if ($IncludeDrivers) { 'IsInstalled=0 and IsHidden=0' } else { "IsInstalled=0 and IsHidden=0 and Type='Software'" }
    Write-WTLog "Searching for updates on $(if ($Online) { 'Windows Update' } else { 'the configured server (WSUS or Windows Update)' })..."
    try { $result = $s.Searcher.Search($criteria) }
    catch { Write-WTLog "Search failed: $($_.Exception.Message)" -Level Error; return }
    $rows = foreach ($u in $result.Updates) {
        [pscustomobject]@{
            Id         = $u.Identity.UpdateID
            Title      = $u.Title
            KB         = (@($u.KBArticleIDs) | ForEach-Object { "KB$_" }) -join ', '
            Type       = $(if ($u.Type -eq 2) { 'Driver' } else { 'Software' })
            Category   = (@($u.Categories) | Select-Object -First 1).Name
            Severity   = $u.MsrcSeverity
            SizeBytes  = [int64]$u.MaxDownloadSize
            SizeText   = Format-WTSize $u.MaxDownloadSize
            Downloaded = Format-WTBool $u.IsDownloaded
        }
    }
    Write-WTLog "Updates available: $(@($rows).Count)" -Level $(if (@($rows).Count) { 'Warn' } else { 'OK' })
    $rows
}

function Install-WTUpdate {
    # Downloads and installs the given updates (Id from Find-WTUpdate); without Id installs everything
    param([string[]]$Id, [switch]$Online, [switch]$IncludeDrivers, [switch]$Simulate)
    $s = New-WTUpdateSearcher -Online:$Online
    $criteria = if ($IncludeDrivers) { 'IsInstalled=0 and IsHidden=0' } else { "IsInstalled=0 and IsHidden=0 and Type='Software'" }
    Write-WTLog 'Preparing the updates...'
    $result = $s.Searcher.Search($criteria)
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $result.Updates) {
        if ($Id -and $Id -notcontains $u.Identity.UpdateID) { continue }
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        [void]$coll.Add($u)
    }
    if ($coll.Count -eq 0) { Write-WTLog 'No updates to install.' -Level OK; return }
    if ($Simulate) {
        foreach ($u in $coll) { Write-WTLog "[SIMULATION] Would install: $($u.Title)" }
        return
    }

    Write-WTLog "Downloading $($coll.Count) updates..."
    $dl = $s.Session.CreateUpdateDownloader()
    $dl.Updates = $coll
    $dr = $dl.Download()
    Write-WTLog "Download finished (code $($dr.ResultCode))."

    Write-WTLog 'Installing: this can take several minutes.'
    $inst = $s.Session.CreateUpdateInstaller()
    $inst.Updates = $coll
    $ir = $inst.Install()
    for ($i = 0; $i -lt $coll.Count; $i++) {
        $r = $ir.GetUpdateResult($i)
        $ok = $r.ResultCode -eq 2 -or $r.ResultCode -eq 3
        $msg = '{0}: {1}' -f $coll.Item($i).Title, $(if ($ok) { 'installed' } else { 'NOT installed (0x{0:X8})' -f $r.HResult })
        Write-WTLog $msg -Level $(if ($ok) { 'OK' } else { 'Error' })
    }
    if ($ir.RebootRequired) { Write-WTLog 'A restart is required to complete the updates.' -Level Warn }
}

function Start-WTUpdateScan {
    # Asks the Windows Update agent for a background scan (like "Check for updates")
    $r = Invoke-WTProcess -FilePath "$env:windir\System32\UsoClient.exe" -Arguments 'StartScan'
    if ($r.ExitCode -eq 0) { Write-WTLog 'Windows Update scan started in the background.' -Level OK }
}
