# Windows Update: search and install, history, component reset.

function Update-WTUpdateHistory {
    Start-WTTask 'Update history' { Get-WTUpdateHistory } -Background -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Title'] })
        $ui.GridUpdHistory.ItemsSource = $rows
        $failed = @($rows | Where-Object { $_.Result -eq 'Failed' }).Count
        $ui.TxtUpdHistCount.Text = '{0} entries · {1} failed' -f $rows.Count, $failed
    }
}

function Invoke-WTUpdateSearch {
    $ui.TxtUpdCount.Text = 'Searching...'
    Start-WTTask 'Update search' { param($Online, $Drivers) Find-WTUpdate -Online:$Online -IncludeDrivers:$Drivers } `
        -Parameters @{ Online = [bool]$ui.ChkUpdOnline.IsChecked; Drivers = [bool]$ui.ChkUpdDrivers.IsChecked } -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Id'] })
        $ui.GridUpdates.ItemsSource = $rows
        $sum = ($rows | Measure-Object SizeBytes -Sum).Sum
        $ui.TxtUpdCount.Text = if ($rows.Count) { '{0} updates · {1}' -f $rows.Count, (Format-WTSize $sum) } else { 'No updates available' }
    }
}

function Invoke-WTUpdateInstall([object[]]$Items) {
    $list = if ($Items) { Format-WTList $Items { "• $($_.Title)" } } else { 'all available updates' }
    if (-not (Show-WTConfirm "Download and install:`n`n$list`n`nThe computer may need to restart." 'Install updates')) { return }
    $ids = @($Items | ForEach-Object { $_.Id })
    Start-WTTask 'Installing updates' {
        param($Id, $Online, $Drivers, $Simulate)
        Install-WTUpdate -Id $Id -Online:$Online -IncludeDrivers:$Drivers -Simulate:$Simulate
    } -Parameters @{ Id = $ids; Online = [bool]$ui.ChkUpdOnline.IsChecked; Drivers = [bool]$ui.ChkUpdDrivers.IsChecked; Simulate = Get-WTSimulate } `
        -OnComplete { Update-WTUpdateHistory; Invoke-WTUpdateSearch }
}

$pageXaml = @"
<Grid Margin="24,18,24,14">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="*" MinHeight="120"/>
    <RowDefinition Height="8"/>
    <RowDefinition Height="*" MinHeight="120"/>
  </Grid.RowDefinitions>
  $(New-PageHeader 'Windows Update' 'Available updates, installation from the toolkit, history with error codes and component reset.' (New-Pill -Name 'BtnUpdSettings' -Glyph '&#xE713;' -Text 'Windows Update settings'))
  <Border Grid.Row="1" Style="{StaticResource Card}" Padding="12,12,12,6" Margin="0,0,0,10">
    <WrapPanel>
      $(New-Pill -Name 'BtnUpdSearch' -Glyph '&#xE721;' -Text 'Search for updates' -Primary)
      $(New-Pill -Name 'BtnUpdInstallSel' -Glyph '&#xE896;' -Text 'Install selected')
      $(New-Pill -Name 'BtnUpdInstallAll' -Glyph '&#xE896;' -Text 'Install all')
      <CheckBox x:Name="ChkUpdOnline" Style="{StaticResource Switch}" Content="Directly from Microsoft" Margin="6,0,6,6"
                ToolTip="Queries Windows Update even if the PC is managed by WSUS or corporate policies."/>
      <CheckBox x:Name="ChkUpdDrivers" Style="{StaticResource Switch}" Content="Include drivers" Margin="6,0,10,6"/>
      $(New-Pill -Name 'BtnUpdScan' -Glyph '&#xE72C;' -Text 'Background scan' -ToolTip 'UsoClient StartScan: like "Check for updates"')
      $(New-Pill -Name 'BtnResetWU' -Glyph '&#xE7BA;' -Text 'Reset components' -Danger -ToolTip 'Stops the services, renames SoftwareDistribution and catroot2')
      <TextBlock x:Name="TxtUpdCount" Style="{StaticResource Counter}"/>
    </WrapPanel>
  </Border>
  <DataGrid x:Name="GridUpdates" Grid.Row="2">
    <DataGrid.Columns>
      <DataGridTextColumn Header="Update" Binding="{Binding Title, Mode=OneWay}" Width="3*"/>
      <DataGridTextColumn Header="KB" Binding="{Binding KB, Mode=OneWay}" Width="95"/>
      <DataGridTextColumn Header="Category" Binding="{Binding Category, Mode=OneWay}" Width="*"/>
      <DataGridTextColumn Header="Severity" Binding="{Binding Severity, Mode=OneWay}" Width="90"/>
      <DataGridTextColumn Header="Type" Binding="{Binding Type, Mode=OneWay}" Width="70"/>
      <DataGridTextColumn Header="Size" Binding="{Binding SizeText, Mode=OneWay}" SortMemberPath="SizeBytes" Width="90"/>
      <DataGridTextColumn Header="Downloaded" Binding="{Binding Downloaded, Mode=OneWay}" Width="90"/>
    </DataGrid.Columns>
  </DataGrid>
  <GridSplitter Grid.Row="3" Cursor="SizeNS"/>
  <Border Grid.Row="4" Style="{StaticResource Card}" Margin="0" Padding="12">
    <DockPanel>
      <DockPanel DockPanel.Dock="Top">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <TextBlock x:Name="TxtUpdHistCount" Style="{StaticResource Counter}"/>
          $(New-Pill -Name 'BtnUpdHistRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5')
        </StackPanel>
        <TextBlock Style="{StaticResource SectionTitle}" Text="History" Margin="0,4,0,6"/>
      </DockPanel>
      <DataGrid x:Name="GridUpdHistory" Margin="0,4,0,0">
        <DataGrid.RowStyle>
          <Style TargetType="DataGridRow" BasedOn="{StaticResource {x:Type DataGridRow}}">
            <Style.Triggers>
              <DataTrigger Binding="{Binding Result, Mode=OneWay}" Value="Failed"><Setter Property="Foreground" Value="{DynamicResource ErrBrush}"/></DataTrigger>
              <DataTrigger Binding="{Binding Result, Mode=OneWay}" Value="Succeeded with errors"><Setter Property="Foreground" Value="{DynamicResource WarnBrush}"/></DataTrigger>
            </Style.Triggers>
          </Style>
        </DataGrid.RowStyle>
        <DataGrid.ContextMenu>
          <ContextMenu>
            <MenuItem x:Name="CmUpdSearchCode" Header="Search the error code on the web"/>
            <MenuItem x:Name="CmUpdCopy" Header="Copy title"/>
          </ContextMenu>
        </DataGrid.ContextMenu>
        <DataGrid.Columns>
          <DataGridTextColumn Header="Date" Binding="{Binding TimeText, Mode=OneWay}" SortMemberPath="Time" Width="125"/>
          <DataGridTextColumn Header="Result" Binding="{Binding Result, Mode=OneWay}" Width="135"/>
          <DataGridTextColumn Header="Code" Binding="{Binding Code, Mode=OneWay}" Width="95"/>
          <DataGridTextColumn Header="KB" Binding="{Binding KB, Mode=OneWay}" Width="95"/>
          <DataGridTextColumn Header="Update" Binding="{Binding Title, Mode=OneWay}" Width="*"/>
        </DataGrid.Columns>
      </DataGrid>
    </DockPanel>
  </Border>
</Grid>
"@

Register-WTPage -Id 'Updates' -Group 'Repair' -Title 'Windows Update' -Glyph '&#xE895;' -Xaml $pageXaml `
    -Load { Update-WTUpdateHistory } -Refresh { Update-WTUpdateHistory } -Init {
    On 'BtnUpdSearch' { Invoke-WTUpdateSearch }
    On 'BtnUpdInstallSel' {
        $sel = @($ui.GridUpdates.SelectedItems)
        if (-not $sel.Count) { Show-WTInfo 'Select one or more updates (run the search first).'; return }
        Invoke-WTUpdateInstall $sel
    }
    On 'BtnUpdInstallAll' { Invoke-WTUpdateInstall @() }
    On 'BtnUpdScan' { Start-WTTask 'Windows Update scan' { Start-WTUpdateScan } }
    On 'BtnResetWU' {
        if (-not (Show-WTConfirm "Reset the Windows Update components?`n`nUse this when updates keep failing; then restart and search again.")) { return }
        Start-WTTask 'Windows Update reset' { param($Simulate) Reset-WTWindowsUpdate -Simulate:$Simulate } -Parameters @{ Simulate = Get-WTSimulate }
    }
    On 'BtnUpdSettings' { Start-Process 'ms-settings:windowsupdate' }
    On 'BtnUpdHistRefresh' { Update-WTUpdateHistory }
    On 'CmUpdSearchCode' {
        $it = $ui.GridUpdHistory.SelectedItem
        if (-not $it) { return }
        $q = if ($it.Code) { "Windows Update $($it.Code) $($it.KB)" } else { $it.Title }
        Start-Process ('https://www.google.com/search?q=' + [uri]::EscapeDataString($q))
    }
    On 'CmUpdCopy' { if ($ui.GridUpdHistory.SelectedItem) { Set-WTClipboard $ui.GridUpdHistory.SelectedItem.Title } }
}
