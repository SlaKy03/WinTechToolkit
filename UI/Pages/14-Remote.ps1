# Remote computer: the toolkit functions run over WinRM, with nothing installed on the remote PC.

# Id, icon, title, description, command, arguments, changes the system
$script:RemoteActions = @(
    @('Info', '&#xE7F4;', 'Inventory', 'Hardware, Windows, disks, network', 'Get-WTSystemInfo', @{}, $false),
    @('Diag', '&#xE9D9;', 'Diagnose problems', 'BSODs, crashes, shutdowns and errors (7 days)', 'Get-WTProblemReport', @{ Days = 7 }, $false),
    @('Disk', '&#xEDA2;', 'Disk health (SMART)', 'Health, temperature, wear', 'Get-WTDiskHealth', @{}, $false),
    @('Profiles', '&#xE716;', 'User profiles', 'List with last use', 'Get-WTUserProfile', @{}, $false),
    @('Programs', '&#xE71D;', 'Installed programs', 'Name, version, publisher', 'Get-WTInstalledProgram', @{}, $false),
    @('Admins', '&#xE8D7;', 'Local administrators', 'Members of the Administrators group', 'Get-WTGroupMember', @{}, $false),
    @('Updates', '&#xE895;', 'Update history', 'Results and error codes', 'Get-WTUpdateHistory', @{ Max = 40 }, $false),
    @('CleanAn', '&#xE74D;', 'Cleanup analysis', 'Recoverable space (no changes)', 'Invoke-WTCleanup', @{ Targets = @('WinTemp', 'UserTemp', 'WUCache', 'DeliveryOpt', 'RecycleBin'); AnalyzeOnly = $true }, $false),
    @('Clean', '&#xE74D;', 'Quick cleanup', 'Temp files, recycle bin, Windows Update cache', 'Invoke-WTCleanup', @{ Targets = @('WinTemp', 'UserTemp', 'WUCache', 'DeliveryOpt', 'RecycleBin') }, $true),
    @('Repair', '&#xE90F;', 'Full repair', 'DISM RestoreHealth + SFC (30-60 minutes)', 'Invoke-WTFullRepair', @{}, $true),
    @('Gpupdate', '&#xE8D7;', 'gpupdate /force', 'Refreshes Group Policy', 'Invoke-WTGpUpdate', @{ Target = 'All' }, $true),
    @('Dns', '&#xE72C;', 'Flush DNS cache', 'ipconfig /flushdns', 'Clear-WTDnsCache', @{}, $true),
    @('Time', '&#xE823;', 'Sync time', 'w32tm /resync', 'Sync-WTTime', @{}, $true),
    @('Spooler', '&#xE749;', 'Reset spooler', 'Clears the stuck print queue', 'Reset-WTPrintSpooler', @{}, $true)
)
$script:RemoteCred = $null

function Get-WTRemoteTarget {
    $c = $ui.TxtRemoteHost.Text.Trim()
    if (-not $c) { Show-WTInfo 'Enter the name or address of the remote computer.'; return $null }
    if ($ui.ChkRemoteCred.IsChecked -and -not $script:RemoteCred) {
        try { $script:RemoteCred = Get-Credential -Message "Administrator account for $c" } catch { }
        if (-not $script:RemoteCred) { return $null }
    }
    $c
}

$remoteTiles = ($script:RemoteActions | ForEach-Object { New-Tile -Name "Rem_$($_[0])" -Glyph $_[1] -Title $_[2] -Desc $_[3] -Danger:$_[6] }) -join ''

$pageXaml = @"
<Grid Margin="24,18,24,14">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="*" MinHeight="140"/>
  </Grid.RowDefinitions>
  $(New-PageHeader 'Remote computer' "Runs the toolkit functions on another PC over WinRM: the code is sent with the request, nothing is installed on the remote PC.")
  <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" MaxHeight="420">
    <StackPanel>
      <Border Style="{StaticResource Card}">
        <StackPanel>
          <WrapPanel>
            <TextBox x:Name="TxtRemoteHost" Style="{StaticResource SearchBox}" Width="260" Tag="Computer name or address"/>
            <CheckBox x:Name="ChkRemoteCred" Style="{StaticResource Switch}" Content="Use a different account" Margin="6,0,10,6"/>
            $(New-Pill -Name 'BtnRemoteTest' -Glyph '&#xE703;' -Text 'Test connection' -Primary)
            $(New-Pill -Name 'BtnRemoteRdp' -Glyph '&#xE7F4;' -Text 'Remote Desktop')
            $(New-Pill -Name 'BtnRemoteMgmt' -Glyph '&#xE713;' -Text 'Computer Management')
          </WrapPanel>
          <TextBlock Style="{StaticResource Hint}" Text="The remote PC needs WinRM enabled (Enable-PSRemoting or Group Policy) and port 5985 open. Actions in red change the system and respect simulation mode."/>
        </StackPanel>
      </Border>
      <WrapPanel>$remoteTiles</WrapPanel>
    </StackPanel>
  </ScrollViewer>
  <Border Grid.Row="2" Style="{StaticResource Card}" Margin="0,4,0,0" Padding="0">
    <DockPanel>
      <DockPanel DockPanel.Dock="Top" Margin="12,8,8,0">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          $(New-Pill -Name 'BtnRemoteCopy' -Glyph '&#xE8C8;' -Text 'Copy')
          $(New-Pill -Name 'BtnRemoteSave' -Glyph '&#xE74E;' -Text 'Save')
        </StackPanel>
        <TextBlock x:Name="TxtRemoteTitle" Style="{StaticResource SectionTitle}" Text="Result" Margin="0,4,0,6"/>
      </DockPanel>
      <TextBox x:Name="TxtRemoteOut" Style="{StaticResource CodeBox}" TextWrapping="NoWrap" BorderThickness="0"/>
    </DockPanel>
  </Border>
</Grid>
"@

Register-WTPage -Id 'Remote' -Group 'Network' -Title 'Remote computer' -Glyph '&#xE8AF;' -Xaml $pageXaml -Init {
    On 'ChkRemoteCred' { $script:RemoteCred = $null }
    On 'TxtRemoteHost' -EventName 'TextChanged' { $script:RemoteCred = $null }
    On 'BtnRemoteTest' {
        $c = Get-WTRemoteTarget
        if ($c) { Start-WTTask "Connecting to $c" { param($Computer, $Cred) $null = Test-WTRemote -ComputerName $Computer -Credential $Cred } -Parameters @{ Computer = $c; Cred = $script:RemoteCred } }
    }
    On 'BtnRemoteRdp' { $c = $ui.TxtRemoteHost.Text.Trim(); if ($c) { Start-Process mstsc.exe -ArgumentList "/v:$c" } }
    On 'BtnRemoteMgmt' { $c = $ui.TxtRemoteHost.Text.Trim(); if ($c) { Start-Process compmgmt.msc -ArgumentList "/computer:$c" } }
    foreach ($a in $script:RemoteActions) {
        On "Rem_$($a[0])" {
            param($s)
            $a = $script:RemoteActions | Where-Object { "Rem_$($_[0])" -eq $s.Name } | Select-Object -First 1
            $c = Get-WTRemoteTarget
            if (-not $c) { return }
            $arguments = $a[5].Clone()
            if ($a[6]) {
                if (-not (Show-WTConfirm "Run '$($a[2])' on $c?")) { return }
                if (Get-WTSimulate) {
                    Write-WTLog "[SIMULATION] Would run $($a[4]) on $c" -Level Warn
                    return
                }
            }
            $ui.TxtRemoteTitle.Text = "$($a[2]) - $c"
            $ui.TxtRemoteOut.Text = 'Running...'
            Start-WTTask "$($a[2]) on $c" {
                param($Computer, $Command, $Arguments, $Cred)
                Format-WTRemoteOutput (Invoke-WTRemote -ComputerName $Computer -Command $Command -Arguments $Arguments -Credential $Cred)
            } -Parameters @{ Computer = $c; Command = $a[4]; Arguments = $arguments; Cred = $script:RemoteCred } -OnComplete {
                param($r)
                $ui.TxtRemoteOut.Text = (@($r) | Where-Object { $_ -is [string] }) -join "`r`n"
            }
        }
    }
    On 'BtnRemoteCopy' { Set-WTClipboard $ui.TxtRemoteOut.Text }
    On 'BtnRemoteSave' {
        if (-not $ui.TxtRemoteOut.Text) { return }
        $name = ($ui.TxtRemoteTitle.Text -replace '[\\/:*?"<>| ]+', '_')
        $file = Join-Path $dataDir ('Report\Remote_{0}_{1:yyyyMMdd_HHmm}.txt' -f $name, (Get-Date))
        Set-Content -LiteralPath $file -Value $ui.TxtRemoteOut.Text -Encoding UTF8
        Write-WTLog "Result saved to $file" -Level OK
        Start-Process notepad.exe -ArgumentList "`"$file`""
    }
}
