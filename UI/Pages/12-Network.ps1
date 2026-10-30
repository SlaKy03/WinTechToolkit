# Network and domain: adapters, IP and DNS, Group Policy, trust, time, Explorer.

function Update-WTAdapters {
    Start-WTTask 'Network adapters' { Get-WTNetworkAdapterInfo } -Background -OnComplete {
        param($r)
        $ui.GridAdapters.ItemsSource = @($r | Where-Object { $_ -and $_.PSObject.Properties['MAC'] })
    }
}

function Invoke-WTIpAction([string]$Action, [string]$Label, [switch]$AllAdapters) {
    $ad = if ($AllAdapters) { @() } else { @($ui.GridAdapters.SelectedItems | ForEach-Object { $_.Name }) }
    $target = if ($ad.Count) { $ad -join ', ' } else { T 'all adapters' }
    if ($Action -eq 'Release' -or $Action -eq 'ReleaseRenew') {
        if (-not (Show-WTConfirm (T "{0} on: {1}?`n`nIn remote sessions (RDP, remote assistance) the connection will be dropped." $Label $target))) { return }
    }
    Start-WTTask "$Label ($target)" { param($Action, $Adapter, $Simulate) Invoke-WTIpConfigAction -Action $Action -Adapter $Adapter -Simulate:$Simulate } `
        -Parameters @{ Action = $Action; Adapter = $ad; Simulate = Get-WTSimulate } -OnComplete { Update-WTAdapters }
}

$pageXaml = @"
<ScrollViewer VerticalScrollBarVisibility="Auto">
  <StackPanel Margin="24,18,24,8">
    $(New-PageHeader 'Network and domain' 'Network adapters, IP addresses and DNS, Group Policy, trust relationship and system time.' (New-Pill -Name 'BtnNetRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5'))
    <Border Style="{StaticResource Card}">
      <StackPanel>
        <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'Network adapters')"/>
        <DataGrid x:Name="GridAdapters" MaxHeight="230" MinHeight="90">
          <DataGrid.RowStyle>
            <Style TargetType="DataGridRow" BasedOn="{StaticResource {x:Type DataGridRow}}">
              <Style.Triggers>
                <DataTrigger Binding="{Binding Status, Mode=OneWay}" Value="Connected"><Setter Property="FontWeight" Value="SemiBold"/></DataTrigger>
                <DataTrigger Binding="{Binding Status, Mode=OneWay}" Value="Disconnected"><Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/></DataTrigger>
                <DataTrigger Binding="{Binding Status, Mode=OneWay}" Value="Disabled"><Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/></DataTrigger>
              </Style.Triggers>
            </Style>
          </DataGrid.RowStyle>
          <DataGrid.ContextMenu>
            <ContextMenu>
              <MenuItem x:Name="CmNetCopyIp" Header="$(TX 'Copy IP address')"/>
              <MenuItem x:Name="CmNetCopyMac" Header="$(TX 'Copy MAC address')"/>
            </ContextMenu>
          </DataGrid.ContextMenu>
          <DataGrid.Columns>
            <DataGridTextColumn Header="$(TX 'Name')" Binding="{Binding Name, Mode=OneWay}" Width="200"/>
            <DataGridTextColumn Header="$(TX 'Status')" Binding="{Binding StatusText, Mode=OneWay}" SortMemberPath="Status" Width="115"/>
            <DataGridTextColumn Header="IP" Binding="{Binding IP, Mode=OneWay}" Width="120"/>
            <DataGridTextColumn Header="Gateway" Binding="{Binding Gateway, Mode=OneWay}" Width="115"/>
            <DataGridTextColumn Header="DNS" Binding="{Binding DNS, Mode=OneWay}" Width="190"/>
            <DataGridTextColumn Header="DHCP" Binding="{Binding DHCP, Mode=OneWay}" Width="55"/>
            <DataGridTextColumn Header="MAC" Binding="{Binding MAC, Mode=OneWay}" Width="135"/>
            <DataGridTextColumn Header="$(TX 'Speed')" Binding="{Binding Speed, Mode=OneWay}" Width="85"/>
            <DataGridTextColumn Header="$(TX 'Description')" Binding="{Binding Description, Mode=OneWay}" Width="*"/>
          </DataGrid.Columns>
        </DataGrid>
        <TextBlock Style="{StaticResource Hint}" Text="$(TX 'Release and renew act on the adapters selected in the table; with no selection, on all adapters.')"/>
      </StackPanel>
    </Border>
    <Border Style="{StaticResource Card}">
      <StackPanel>
        <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'IP address and DNS')"/>
        <WrapPanel>
          $(New-Tile -Name 'BtnIpRelease' -Glyph '&#xE898;' -Title 'Release IP' -Desc 'ipconfig /release')
          $(New-Tile -Name 'BtnIpRenew' -Glyph '&#xE896;' -Title 'Renew IP' -Desc 'ipconfig /renew')
          $(New-Tile -Name 'BtnIpReleaseRenew' -Glyph '&#xE8AB;' -Title 'Release and renew' -Desc 'ipconfig /release followed by /renew')
          $(New-Tile -Name 'BtnFlushDns' -Glyph '&#xE72C;' -Title 'Flush DNS cache' -Desc 'ipconfig /flushdns')
          $(New-Tile -Name 'BtnRegisterDns' -Glyph '&#xE8F4;' -Title 'Register in DNS' -Desc 'ipconfig /registerdns (the PC record in the domain)')
          $(New-Tile -Name 'BtnIpConfig' -Glyph '&#xE946;' -Title 'Full configuration' -Desc 'ipconfig /all in the activity log')
          $(New-Tile -Name 'BtnConnTest' -Glyph '&#xE9D9;' -Title 'Connectivity test' -Desc 'Gateway, DNS, HTTPS and proxy')
          $(New-Tile -Name 'BtnNetReset' -Glyph '&#xE7BA;' -Title 'Reset Winsock and TCP/IP' -Desc 'netsh winsock/int ip reset (requires a restart)' -Danger)
        </WrapPanel>
        <WrapPanel Margin="0,6,0,0">
          <TextBlock Style="{StaticResource Label}" Text="$(TX 'TCP port test:')"/>
          <TextBox x:Name="TxtPortHost" Style="{StaticResource HintBox}" Width="220" Tag="$(TX 'Server name or address')" ToolTip="$(TX 'Server name or address')"/>
          <TextBox x:Name="TxtPortNumber" Width="70" Text="443" HorizontalContentAlignment="Center" ToolTip="$(TX 'Port')"/>
          $(New-Pill -Name 'BtnPortTest' -Glyph '&#xE703;' -Text 'Check')
        </WrapPanel>
      </StackPanel>
    </Border>
    <Border Style="{StaticResource Card}">
      <StackPanel>
        <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'Domain and Group Policy')"/>
        <WrapPanel>
          $(New-Tile -Name 'BtnGpUpdate' -Glyph '&#xE895;' -Title 'gpupdate /force' -Desc 'Computer and user policies')
          $(New-Tile -Name 'BtnGpUpdateComputer' -Glyph '&#xE7F4;' -Title 'gpupdate computer only' -Desc '/target:computer /force')
          $(New-Tile -Name 'BtnGpResult' -Glyph '&#xE8A5;' -Title 'Applied policies report' -Desc 'gpresult /h for the computer and the signed-in user')
          $(New-Tile -Name 'BtnTrustTest' -Glyph '&#xE73E;' -Title 'Check domain trust' -Desc 'Test-ComputerSecureChannel and nltest')
          $(New-Tile -Name 'BtnTrustRepair' -Glyph '&#xE90F;' -Title 'Repair domain trust' -Desc 'Requires an account allowed to join computers')
          $(New-Tile -Name 'BtnTimeSync' -Glyph '&#xE823;' -Title 'Sync time' -Desc 'w32tm /resync (Kerberos tolerates 5 minutes)')
        </WrapPanel>
      </StackPanel>
    </Border>
    <Border Style="{StaticResource Card}">
      <StackPanel>
        <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'Windows interface')"/>
        <WrapPanel>
          $(New-Tile -Name 'BtnExplorer' -Glyph '&#xE8B7;' -Title 'Restart Explorer' -Desc 'Frozen taskbar or desktop')
        </WrapPanel>
      </StackPanel>
    </Border>
  </StackPanel>
</ScrollViewer>
"@

Register-WTPage -Id 'Network' -Group 'Network' -Title 'Network and domain' -Glyph '&#xE839;' -Xaml $pageXaml `
    -Load { Update-WTAdapters } -Refresh { Update-WTAdapters } -Init {
    On 'BtnNetRefresh' { Update-WTAdapters }
    On 'BtnIpRelease' { Invoke-WTIpAction 'Release' (T 'Release IP') }
    On 'BtnIpRenew' { Invoke-WTIpAction 'Renew' (T 'Renew IP') }
    On 'BtnIpReleaseRenew' { Invoke-WTIpAction 'ReleaseRenew' (T 'Release and renew IP') }
    On 'BtnFlushDns' { Start-WTTask 'Flush DNS cache' { Clear-WTDnsCache } }
    On 'BtnRegisterDns' { Start-WTTask 'DNS registration' { Invoke-WTIpConfigAction -Action RegisterDns } }
    On 'BtnIpConfig' { Start-WTTask 'ipconfig /all' { Show-WTIpConfig } }
    On 'BtnConnTest' { Start-WTTask 'Connectivity test' { Test-WTConnectivity } }
    On 'BtnPortTest' {
        $h = $ui.TxtPortHost.Text.Trim()
        $port = 0
        if (-not $h -or -not [int]::TryParse($ui.TxtPortNumber.Text, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { Show-WTInfo 'Enter a server and a port (1-65535).'; return }
        Start-WTTask (T 'Test {0}' "${h}:$port") {
            param($HostName, $Port)
            if (Test-WTTcpPort -HostName $HostName -Port $Port) { Write-WTLog (T '{0} reachable.' "${HostName}:$Port") -Level OK }
            else { Write-WTLog (T '{0} not reachable (port closed, filtered or name not resolved).' "${HostName}:$Port") -Level Error }
        } -Parameters @{ HostName = $h; Port = $port }
    }
    On 'BtnNetReset' {
        if (-not (Show-WTConfirm "Reset Winsock and TCP/IP?`nThe computer will need to be restarted.")) { return }
        Start-WTTask 'Network stack reset' { param($Simulate) Reset-WTNetworkStack -Simulate:$Simulate } -Parameters @{ Simulate = Get-WTSimulate }
    }
    On 'BtnGpUpdate' { Start-WTTask 'gpupdate /force' { Invoke-WTGpUpdate -Target All } }
    On 'BtnGpUpdateComputer' { Start-WTTask 'gpupdate computer' { Invoke-WTGpUpdate -Target Computer } }
    On 'BtnGpResult' { Start-WTTask 'Group Policy report' { Export-WTGpResult } -OnComplete { param($r) Open-WTFile $r } }
    On 'BtnTrustTest' { Start-WTTask 'Domain trust check' { Test-WTDomainTrust } }
    On 'BtnTrustRepair' {
        $cred = $null
        try { $cred = Get-Credential -Message (T 'Account allowed to join computers to the domain (DOMAIN\user)') } catch { }
        if (-not $cred) { return }
        Start-WTTask 'Domain trust repair' { param($Cred, $Simulate) Repair-WTDomainTrust -Credential $Cred -Simulate:$Simulate } `
            -Parameters @{ Cred = $cred; Simulate = Get-WTSimulate }
    }
    On 'BtnTimeSync' { Start-WTTask 'Time sync' { Sync-WTTime } }
    On 'BtnExplorer' { Start-WTTask 'Restarting Explorer' { Restart-WTExplorer } }
    On 'CmNetCopyIp' { if ($ui.GridAdapters.SelectedItem) { Set-WTClipboard $ui.GridAdapters.SelectedItem.IP } }
    On 'CmNetCopyMac' { if ($ui.GridAdapters.SelectedItem) { Set-WTClipboard $ui.GridAdapters.SelectedItem.MAC } }
}
