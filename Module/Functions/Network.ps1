# Network, domain, Group Policy and services.

function Clear-WTDnsCache {
    Invoke-WTProcess -FilePath 'ipconfig.exe' -Arguments '/flushdns' | Out-Null
}

function Show-WTIpConfig {
    Invoke-WTProcess -FilePath 'ipconfig.exe' -Arguments '/all' | Out-Null
}

function Get-WTNetworkAdapterInfo {
    <# Network adapters with status, IP, gateway, DNS, DHCP, MAC and speed. #>
    $cfg = @{}
    foreach ($c in Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue) { $cfg[[int]$c.InterfaceIndex] = $c }
    $status = @{ Up = 'Connected'; Disconnected = 'Disconnected'; Disabled = 'Disabled'; 'Not Present' = 'Not present' }
    # connected adapters first, then by name
    $rank = @{ Up = 0; Disconnected = 1; Disabled = 2 }
    $sortRank = { $r = $rank["$($_.Status)"]; if ($null -eq $r) { 3 } else { $r } }
    foreach ($a in Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object $sortRank, Name) {
        $c = $cfg[[int]$a.ifIndex]
        $st = $status["$($a.Status)"]
        if (-not $st) { $st = "$($a.Status)" }
        [pscustomobject]@{
            Name        = $a.Name
            Description = $a.InterfaceDescription
            Status      = $st
            Speed       = $(if ($a.Status -eq 'Up') { $a.LinkSpeed } else { '' })
            MAC         = $a.MacAddress
            IP          = $(if ($c) { (@($c.IPAddress) | Where-Object { $_ -and $_ -notmatch ':' }) -join ', ' } else { '' })
            Gateway     = $(if ($c) { (@($c.DefaultIPGateway) | Where-Object { $_ }) -join ', ' } else { '' })
            DNS         = $(if ($c) { (@($c.DNSServerSearchOrder) | Where-Object { $_ }) -join ', ' } else { '' })
            DHCP        = $(if ($c -and $c.DHCPEnabled) { 'Yes' } elseif ($c) { 'No' } else { '' })
        }
    }
}

function Invoke-WTIpConfigAction {
    <#
    .SYNOPSIS
        ipconfig /release, /renew, both, or /registerdns, on all adapters
        or only the given ones (connection name, e.g. "Ethernet").
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('Release', 'Renew', 'ReleaseRenew', 'RegisterDns')][string]$Action,
        [string[]]$Adapter,
        [switch]$Simulate
    )
    $steps = @(switch ($Action) {
            'Release' { '/release' }
            'Renew' { '/renew' }
            'ReleaseRenew' { '/release'; '/renew' }
            'RegisterDns' { '/registerdns' }
        })
    $targets = @($Adapter | Where-Object { $_ })
    if (-not $targets.Count -or $Action -eq 'RegisterDns') { $targets = @('') }

    foreach ($s in $steps) {
        foreach ($a in $targets) {
            $arguments = if ($a) { "$s `"$a`"" } else { $s }
            if ($Simulate -and $s -ne '/registerdns') { Write-WTLog "[SIMULATION] Would run: ipconfig $arguments"; continue }
            if ($s -eq '/release') { Write-WTLog 'Releasing the IP: remote sessions will be disconnected.' -Level Warn }
            if ($s -eq '/renew') { Write-WTLog 'Requesting a new address from the DHCP server (may take up to a minute)...' }
            Write-WTLog "Running: ipconfig $arguments"
            $r = Invoke-WTProcess -FilePath 'ipconfig.exe' -Arguments $arguments
            if ($r.ExitCode -eq 0) { Write-WTLog "ipconfig $s completed$(if ($a) { " on $a" })." -Level OK }
            else { Write-WTLog "ipconfig $s finished with code $($r.ExitCode)." -Level Warn }
        }
    }
}

function Export-WTGpResult {
    <# HTML report of the applied policies (gpresult) for the computer and the signed-in user. #>
    $file = Join-Path (Get-WTDataFolder) ('Report\GPResult_{0}_{1:yyyyMMdd_HHmm}.html' -f $env:COMPUTERNAME, (Get-Date))
    $user = (Get-CimInstance Win32_ComputerSystem).UserName
    $arguments = if ($user) { "/user `"$user`" /h `"$file`" /f" } else { "/scope computer /h `"$file`" /f" }
    Write-WTLog "Generating the Group Policy report$(if ($user) { " for $user" })..."
    $r = Invoke-WTProcess -FilePath 'gpresult.exe' -Arguments $arguments
    if ($r.ExitCode -ne 0 -and $user) {
        Write-WTLog 'User report not available, generating the computer part only.' -Level Warn
        $r = Invoke-WTProcess -FilePath 'gpresult.exe' -Arguments "/scope computer /h `"$file`" /f"
    }
    if (Test-Path -LiteralPath $file) { Write-WTLog "Report created: $file" -Level OK; $file }
    else { Write-WTLog 'Could not create the gpresult report.' -Level Error }
}

function Reset-WTNetworkStack {
    <# Flush DNS, reset Winsock and TCP/IP (requires a restart). #>
    param([switch]$Simulate)
    if ($Simulate) { Write-WTLog '[SIMULATION] Would run flushdns, netsh winsock reset, netsh int ip reset'; return }
    Invoke-WTProcess -FilePath 'ipconfig.exe' -Arguments '/flushdns' | Out-Null
    Invoke-WTProcess -FilePath 'netsh.exe' -Arguments 'winsock reset' | Out-Null
    Invoke-WTProcess -FilePath 'netsh.exe' -Arguments 'int ip reset' | Out-Null
    Write-WTLog 'Network stack reset done: RESTART the computer.' -Level Warn
}

function Test-WTTcpPort {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 3000)
    $client = New-Object Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        if ($task.Wait($TimeoutMs)) { return $client.Connected }
        $false
    } catch { $false } finally { $client.Dispose() }
}

function Test-WTConnectivity {
    <# Checks the gateway, DNS resolution and HTTPS to a few hosts, plus the WinHTTP proxy. #>
    param([string[]]$Hosts = @('www.microsoft.com', 'www.google.com'))
    $gw = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' |
        ForEach-Object { $_.DefaultIPGateway } | Where-Object { $_ -match '^\d+\.' } | Select-Object -First 1
    if ($gw) {
        if (Test-Connection -ComputerName $gw -Count 2 -Quiet) { Write-WTLog "Gateway $gw reachable." -Level OK }
        else { Write-WTLog "Gateway $gw does not answer ping (it may be filtered)." -Level Warn }
    } else {
        Write-WTLog 'No default gateway configured.' -Level Error
    }
    foreach ($h in $Hosts) {
        try {
            $ips = @([Net.Dns]::GetHostAddresses($h) | ForEach-Object { $_.IPAddressToString })
            Write-WTLog "DNS $h -> $($ips -join ', ')" -Level OK
        } catch {
            Write-WTLog "DNS: could not resolve $h" -Level Error
            continue
        }
        if (Test-WTTcpPort -HostName $h -Port 443) { Write-WTLog "HTTPS to $h reachable." -Level OK }
        else { Write-WTLog "HTTPS to $h NOT reachable (firewall/proxy?)." -Level Error }
    }
    Invoke-WTProcess -FilePath 'netsh.exe' -Arguments 'winhttp show proxy' | Out-Null
}

function Invoke-WTGpUpdate {
    param([ValidateSet('Computer', 'All')][string]$Target = 'All')
    if ($Target -eq 'Computer') { $arguments = '/target:computer /force' } else { $arguments = '/force' }
    Write-WTLog "Running: gpupdate $arguments"
    Write-WTLog "Note: USER policies are applied to the account running the toolkit, not to the signed-in user."
    $r = Invoke-WTProcess -FilePath 'gpupdate.exe' -Arguments $arguments
    if ($r.ExitCode -eq 0) { Write-WTLog 'Group Policy updated.' -Level OK }
    else { Write-WTLog "gpupdate finished with code $($r.ExitCode). For details: gpresult /h report.html" -Level Warn }
}

function Test-WTDomainTrust {
    <# Checks the trust relationship between the computer and the domain. #>
    $cs = Get-CimInstance Win32_ComputerSystem
    if (-not $cs.PartOfDomain) { Write-WTLog 'The computer is not a domain member.' -Level Warn; return }
    Write-WTLog "Domain: $($cs.Domain)"
    try {
        if (Test-ComputerSecureChannel -ErrorAction Stop) { Write-WTLog 'Trust relationship with the domain is valid.' -Level OK }
        else { Write-WTLog "Trust relationship NOT valid: use 'Repair domain trust'." -Level Error }
    } catch {
        Write-WTLog "Check failed: $($_.Exception.Message)" -Level Error
    }
    Invoke-WTProcess -FilePath 'nltest.exe' -Arguments "/sc_query:$($cs.Domain)" | Out-Null
}

function Repair-WTDomainTrust {
    param([Parameter(Mandatory)][pscredential]$Credential, [switch]$Simulate)
    if ($Simulate) { Write-WTLog "[SIMULATION] Would run Test-ComputerSecureChannel -Repair with the account $($Credential.UserName)"; return }
    try {
        if (Test-ComputerSecureChannel -Repair -Credential $Credential -ErrorAction Stop) { Write-WTLog 'Trust relationship repaired.' -Level OK }
        else { Write-WTLog 'Repair failed: consider removing the computer from the domain and joining it again.' -Level Error }
    } catch {
        Write-WTLog "Repair failed: $($_.Exception.Message)" -Level Error
    }
}

function Sync-WTTime {
    $svc = Get-Service w32time -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') { Start-Service w32time -ErrorAction SilentlyContinue }
    Invoke-WTProcess -FilePath 'w32tm.exe' -Arguments '/resync /force' | Out-Null
    Invoke-WTProcess -FilePath 'w32tm.exe' -Arguments '/query /status' | Out-Null
}

function Reset-WTPrintSpooler {
    <# Stops the spooler, clears the print queue and starts it again. #>
    param([switch]$Simulate)
    $queue = "$env:windir\System32\spool\PRINTERS"
    $n = @(Get-ChildItem -LiteralPath $queue -Force -ErrorAction SilentlyContinue).Count
    if ($Simulate) { Write-WTLog "[SIMULATION] Would restart the spooler, deleting $n files from the queue."; return }
    Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $queue -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Start-Service -Name Spooler -ErrorAction SilentlyContinue
    if ((Get-Service Spooler).Status -eq 'Running') { Write-WTLog "Spooler restarted, $n files removed from the queue." -Level OK }
    else { Write-WTLog 'The spooler did not start again.' -Level Error }
}

function Restart-WTExplorer {
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 4
    if (Get-Process explorer -ErrorAction SilentlyContinue) { Write-WTLog 'Explorer restarted.' -Level OK }
    else { Write-WTLog "Explorer did not start again: start it from the user's session (Task Manager > Run new task > explorer.exe)." -Level Warn }
}
