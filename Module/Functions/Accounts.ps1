# Saved credentials, Kerberos tickets and local group members.

function Get-WTCredentialHelperSource {
    # Code to run in the user's session: lists and deletes Credential Manager entries
    # through CredEnumerate/CredDelete (cmdkey output changes with the Windows language).
    @'
if (-not ('WTCred' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class WTCred {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct CREDENTIAL {
        public int Flags; public int Type; public string TargetName; public string Comment; public long LastWritten;
        public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist; public int AttributeCount;
        public IntPtr Attributes; public string TargetAlias; public string UserName;
    }
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredEnumerate(string filter, int flags, out int count, out IntPtr creds);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredDelete(string target, int type, int flags);
    [DllImport("advapi32.dll")]
    static extern void CredFree(IntPtr buffer);
    public static string[] List() {
        var list = new List<string>();
        int count; IntPtr p;
        if (!CredEnumerate(null, 0, out count, out p)) return list.ToArray();
        for (int i = 0; i < count; i++) {
            var c = (CREDENTIAL)Marshal.PtrToStructure(Marshal.ReadIntPtr(p, i * IntPtr.Size), typeof(CREDENTIAL));
            list.Add(c.Type + "|" + c.TargetName + "|" + c.UserName + "|" + DateTime.FromFileTime(c.LastWritten).ToString("yyyy-MM-dd HH:mm"));
        }
        CredFree(p);
        return list.ToArray();
    }
    public static bool Delete(string target, int type) { return CredDelete(target, type, 0); }
}
"@
}
'@
}

function Get-WTSavedCredential {
    # Credential Manager entries of the signed-in user
    param([Parameter(Mandatory)][string]$UserName)
    $script = (Get-WTCredentialHelperSource) + "`r`n[WTCred]::List() | ForEach-Object { 'CRED|' + `$_ }"
    $types = @{ '1' = 'Generic'; '2' = 'Windows (domain)'; '3' = 'Certificate'; '4' = 'Windows (visible)' }
    $rows = foreach ($l in (Invoke-WTUserContext -UserName $UserName -Script $script)) {
        if ($l -notlike 'CRED|*') { if ($l.Trim()) { Write-WTLog "  $l" -Level Warn }; continue }
        $f = $l.Substring(5).Split('|')
        [pscustomobject]@{
            Type     = $f[0]
            TypeText = $(if ($types[$f[0]]) { $types[$f[0]] } else { "Type $($f[0])" })
            Target   = $f[1]
            User     = $f[2]
            Modified = $f[3]
        }
    }
    Write-WTLog "Saved credentials for $UserName : $(@($rows).Count)"
    $rows | Sort-Object Target
}

function Remove-WTSavedCredential {
    # Deletes the given entries (objects from Get-WTSavedCredential) in the user's session
    param([Parameter(Mandatory)][string]$UserName, [Parameter(Mandatory)][object[]]$Credential, [switch]$Simulate)
    if ($Simulate) {
        foreach ($c in $Credential) { Write-WTLog "[SIMULATION] Would delete credential $($c.Target)" }
        return
    }
    $lines = foreach ($c in $Credential) {
        $t = $c.Target -replace "'", "''"
        "if ([WTCred]::Delete('$t', $([int]$c.Type))) { 'OK|$t' } else { 'KO|$t' }"
    }
    $script = (Get-WTCredentialHelperSource) + "`r`n" + ($lines -join "`r`n")
    foreach ($l in (Invoke-WTUserContext -UserName $UserName -Script $script)) {
        if ($l -like 'OK|*') { Write-WTLog "Credential deleted: $($l.Substring(3))" -Level OK }
        elseif ($l -like 'KO|*') { Write-WTLog "Could not delete: $($l.Substring(3))" -Level Error }
        elseif ($l.Trim()) { Write-WTLog "  $l" }
    }
}

function Clear-WTKerberosTicket {
    # User: session tickets (after a group or password change). Computer: machine account tickets.
    param([ValidateSet('User', 'Computer')][string]$Scope = 'User', [string]$UserName)
    if ($Scope -eq 'Computer') {
        $r = Invoke-WTProcess -FilePath 'klist.exe' -Arguments '-li 0x3e7 purge'
        if ($r.ExitCode -eq 0) { Write-WTLog 'Computer Kerberos tickets deleted: the computer''s new groups apply immediately.' -Level OK }
        return
    }
    if (-not $UserName) { Write-WTLog 'No signed-in user specified.' -Level Error; return }
    foreach ($l in (Invoke-WTUserContext -UserName $UserName -Script 'klist purge')) { Write-WTLog "  $l" }
    Write-WTLog "Kerberos tickets of $UserName deleted: they will be requested again on the next access to a resource." -Level OK
}

function Show-WTKerberosTicket {
    param([Parameter(Mandatory)][string]$UserName)
    foreach ($l in (Invoke-WTUserContext -UserName $UserName -Script 'klist')) { Write-WTLog "  $l" }
}

function Get-WTGroupMember {
    <#
    .SYNOPSIS
        Members of a local group identified by SID (language independent).
        Uses ADSI because Get-LocalGroupMember hangs when the group contains orphaned SIDs.
    #>
    param([string]$GroupSid = 'S-1-5-32-544')
    $groupName = ((New-Object Security.Principal.SecurityIdentifier $GroupSid).Translate([Security.Principal.NTAccount]).Value -split '\\')[-1]
    $group = [ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group"
    foreach ($m in @($group.psbase.Invoke('Members'))) {
        $type = $m.GetType()
        $path = $type.InvokeMember('ADsPath', 'GetProperty', $null, $m, $null)
        $class = $type.InvokeMember('Class', 'GetProperty', $null, $m, $null)
        $sid = ''
        try { $sid = (New-Object Security.Principal.SecurityIdentifier ($type.InvokeMember('objectSid', 'GetProperty', $null, $m, $null)), 0).Value } catch { }

        # WinNT://DOMAIN/user, WinNT://DOMAIN/PC/user for local accounts, WinNT://S-1-... if unresolved
        $parts = ($path -replace '^WinNT://', '') -split '/'
        $name = if ($parts.Count -ge 3) { "$($parts[-2])\$($parts[-1])" } else { $parts -join '\' }
        $source = 'Domain'
        if ($parts.Count -ge 3 -and $parts[-2] -eq $env:COMPUTERNAME) { $source = 'Local' }
        elseif ($name -match '^S-1-12-1-') { $source = 'Entra ID' }
        elseif ($name -match '^S-1-5-21-') { $source = 'Orphaned SID (deleted account?)' }
        elseif ($sid -and $sid -notmatch '^S-1-5-21-|^S-1-12-1-') { $source = 'System' }
        [pscustomobject]@{ Name = $name; Class = $class; Source = $source; SID = $sid; AdsPath = $path; Group = $groupName; GroupSid = $GroupSid }
    }
}

function Add-WTGroupMember {
    # Adds an account (DOMAIN\user, AzureAD\user@domain or local user) to the group
    param([string]$GroupSid = 'S-1-5-32-544', [Parameter(Mandatory)][string]$Member, [switch]$Simulate)
    $groupName = ((New-Object Security.Principal.SecurityIdentifier $GroupSid).Translate([Security.Principal.NTAccount]).Value -split '\\')[-1]
    if ($Simulate) { Write-WTLog "[SIMULATION] Would add $Member to group $groupName"; return }
    $r = Invoke-WTProcess -FilePath 'net.exe' -Arguments "localgroup `"$groupName`" `"$Member`" /add"
    if ($r.ExitCode -eq 0) { Write-WTLog "$Member added to group $groupName (applies at the user's next sign-in)." -Level OK }
    else { Write-WTLog "Could not add $Member to group $groupName." -Level Error }
}

function Remove-WTGroupMember {
    # Removes the given members (objects from Get-WTGroupMember), including orphaned SIDs
    param([Parameter(Mandatory)][object[]]$InputObject, [switch]$Simulate)
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($m in $InputObject) {
        if ($m.SID -eq $me) { Write-WTLog "Skipped $($m.Name): it is the account running the toolkit." -Level Warn; continue }
        if ($m.SID -match '-500$' -and $m.Source -eq 'Local') { Write-WTLog "Skipped $($m.Name): it is the built-in administrator." -Level Warn; continue }
        if ($Simulate) { Write-WTLog "[SIMULATION] Would remove $($m.Name) from group $($m.Group)"; continue }
        try {
            ([ADSI]"WinNT://$env:COMPUTERNAME/$($m.Group),group").psbase.Invoke('Remove', $m.AdsPath)
            Write-WTLog "$($m.Name) removed from group $($m.Group)." -Level OK
        } catch {
            Write-WTLog "Could not remove $($m.Name): $($_.Exception.GetBaseException().Message)" -Level Error
        }
    }
}
