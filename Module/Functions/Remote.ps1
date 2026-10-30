# Runs the toolkit functions on another computer over WinRM.

function Test-WTRemote {
    param([Parameter(Mandatory)][string]$ComputerName, [pscredential]$Credential)
    $ping = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($ping) { Write-WTLog (T 'Ping to {0}: answers' $ComputerName) -Level OK }
    else { Write-WTLog (T 'Ping to {0}: no answer (it may be filtered)' $ComputerName) -Level Warn }
    try {
        $p = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
        if ($Credential) { $p.Credential = $Credential; $p.Authentication = 'Default' }
        Test-WSMan @p | Out-Null
        Write-WTLog (T 'WinRM reachable on {0}.' $ComputerName) -Level OK
        $ic = @{ ComputerName = $ComputerName; ScriptBlock = { "$env:COMPUTERNAME - $((Get-CimInstance Win32_OperatingSystem).Caption)" }; ErrorAction = 'Stop' }
        if ($Credential) { $ic.Credential = $Credential }
        Write-WTLog (T 'Remote session succeeded: {0}' (Invoke-Command @ic)) -Level OK
        $true
    } catch {
        Write-WTLog (T 'WinRM not available on {0}: {1}' $ComputerName $_.Exception.Message) -Level Error
        Write-WTLog "The remote PC needs 'Enable-PSRemoting' (or the WinRM Group Policy) and the firewall open on port 5985." -Level Warn
        $false
    }
}

function Invoke-WTRemote {
    <#
    .SYNOPSIS
        Runs a toolkit function on a remote computer. The module code is sent with the
        request: nothing needs to be installed on the remote PC.
    .OUTPUTS
        The result of the function; the log lines come back to the local log with the PC name.
    #>
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z]+-WT[A-Za-z]+$')][string]$Command,
        [hashtable]$Arguments = @{},
        [pscredential]$Credential
    )
    $code = (Get-ChildItem (Join-Path $script:WTModuleRoot 'Functions') -Filter '*.ps1' | Sort-Object Name |
            ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`r`n"
    # the remote PC has no language files: the translations travel with the code
    $lang = $global:WTLanguage
    $strings = @{}
    if ($lang -and $lang -ne 'en') { [void](Get-WTText 'Yes'); $strings = $script:WTStrings }   # the first T loads them
    $sb = {
        param($Code, $Command, $Arguments, $Language, $Strings)
        $global:WTQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
        $PSDefaultParameterValues = @{ 'Test-Path:ErrorAction' = 'SilentlyContinue' }
        . ([scriptblock]::Create($Code))
        $global:WTLanguage = $Language
        $script:WTStringsLanguage = $Language
        $script:WTStrings = $Strings
        $out = & $Command @Arguments
        $lines = New-Object Collections.Generic.List[string]
        $l = $null
        while ($global:WTQueue.TryDequeue([ref]$l)) { $lines.Add($l) }
        [pscustomobject]@{ Log = $lines.ToArray(); Output = $out }
    }
    Write-WTLog (T 'Running {0} on {1}...' $Command $ComputerName)
    $p = @{ ComputerName = $ComputerName; ScriptBlock = $sb; ArgumentList = @($code, $Command, $Arguments, $lang, $strings); ErrorAction = 'Stop' }
    if ($Credential) { $p.Credential = $Credential }
    try { $r = Invoke-Command @p }
    catch { Write-WTLog (T 'Remote execution failed: {0}' $_.Exception.Message) -Level Error; return }

    foreach ($line in $r.Log) {
        $tagged = $line -replace '^(\S+ \[[^\]]+\] )', "`$1[$ComputerName] "
        if ($null -ne $global:WTQueue) { $global:WTQueue.Enqueue($tagged) } else { Write-Host $tagged }
    }
    $r.Output
}

function Format-WTRemoteOutput {
    # Makes the (deserialized) output of Invoke-WTRemote readable in a text box
    param($Output)
    if ($null -eq $Output) { return '' }
    $items = @($Output)
    if ($items.Count -eq 1 -and $items[0].PSObject.Properties['Report']) { return $items[0].Report }
    if (@($items | Where-Object { $_ -isnot [string] }).Count -eq 0) { return ($items -join "`r`n") }
    $props = @($items[0].PSObject.Properties | Where-Object { $_.Name -notmatch '^(PSComputerName|RunspaceId|PSShowComputerName)$' } |
            Select-Object -First 7 | ForEach-Object { $_.Name })
    ($items | Format-Table -Property $props -AutoSize | Out-String -Width 260).Trim()
}
