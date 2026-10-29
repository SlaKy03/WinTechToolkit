# Startup and tasks: startup programs and third-party scheduled tasks.

function Update-WTStartup {
    Start-WTTask 'Startup programs' { Get-WTStartupItem } -Background -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['ApprovedKey'] })
        $ui.GridStartup.ItemsSource = $rows
        $off = @($rows | Where-Object { -not $_.Enabled }).Count
        $ui.TxtStartupCount.Text = '{0} {1} · {2} disabled' -f $rows.Count, $(if ($rows.Count -eq 1) { 'item' } else { 'items' }), $off
    }
}

function Update-WTTasks {
    Start-WTTask 'Scheduled tasks' { param($All) Get-WTScheduledTaskList -IncludeMicrosoft:$All } -Parameters @{ All = [bool]$ui.ChkTasksMs.IsChecked } -Background -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['RunAs'] })
        $ui.GridTasks.ItemsSource = $rows
        $ui.TxtTasksCount.Text = "$($rows.Count) tasks"
    }
}

function Set-WTStartupSelection([bool]$Enabled) {
    $sel = @($ui.GridStartup.SelectedItems)
    if (-not $sel.Count) { Show-WTInfo 'Select one or more items.'; return }
    Start-WTTask $(if ($Enabled) { 'Enable at startup' } else { 'Disable at startup' }) {
        param($Items, $Enabled, $Simulate) Set-WTStartupItem -InputObject $Items -Enabled $Enabled -Simulate:$Simulate
    } -Parameters @{ Items = $sel; Enabled = $Enabled; Simulate = Get-WTSimulate } -OnComplete { Update-WTStartup }
}

function Set-WTTaskSelection([bool]$Enabled) {
    $sel = @($ui.GridTasks.SelectedItems)
    if (-not $sel.Count) { Show-WTInfo 'Select one or more tasks.'; return }
    if (-not $Enabled -and @($sel | Where-Object { $_.Path -like '\Microsoft\*' }).Count -and
        -not (Show-WTConfirm 'The selected tasks include Windows tasks: disabling them can prevent maintenance and updates. Continue?')) { return }
    Start-WTTask $(if ($Enabled) { 'Enable tasks' } else { 'Disable tasks' }) {
        param($Items, $Enabled, $Simulate) Set-WTScheduledTaskState -InputObject $Items -Enabled $Enabled -Simulate:$Simulate
    } -Parameters @{ Items = $sel; Enabled = $Enabled; Simulate = Get-WTSimulate } -OnComplete { Update-WTTasks }
}

$pageXaml = @"
<Grid Margin="24,18,24,14">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="*" MinHeight="140"/>
    <RowDefinition Height="8"/>
    <RowDefinition Height="*" MinHeight="140"/>
  </Grid.RowDefinitions>
  $(New-PageHeader 'Startup and tasks' "What starts with Windows, for all users and for each one. Disabling works like Task Manager: nothing is deleted and it is reversible.")
  <Border Grid.Row="1" Style="{StaticResource Card}" Margin="0" Padding="12">
    <DockPanel>
      <DockPanel DockPanel.Dock="Top">
        <TextBlock Style="{StaticResource SectionTitle}" Text="Startup programs" Margin="0,4,14,6" VerticalAlignment="Top"/>
        <WrapPanel>
          $(New-Pill -Name 'BtnStartupDisable' -Glyph '&#xE711;' -Text 'Disable')
          $(New-Pill -Name 'BtnStartupEnable' -Glyph '&#xE73E;' -Text 'Enable')
          $(New-Pill -Name 'BtnStartupRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5')
          $(New-Pill -Name 'BtnStartupTaskmgr' -Glyph '&#xE9D9;' -Text 'Task Manager')
          <TextBlock x:Name="TxtStartupCount" Style="{StaticResource Counter}" Text="Loading..."/>
        </WrapPanel>
      </DockPanel>
      <DataGrid x:Name="GridStartup" Margin="0,4,0,0">
        <DataGrid.RowStyle>
          <Style TargetType="DataGridRow" BasedOn="{StaticResource {x:Type DataGridRow}}">
            <Style.Triggers>
              <DataTrigger Binding="{Binding Enabled, Mode=OneWay}" Value="False"><Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/></DataTrigger>
            </Style.Triggers>
          </Style>
        </DataGrid.RowStyle>
        <DataGrid.ContextMenu>
          <ContextMenu>
            <MenuItem x:Name="CmStartupOpen" Header="Open file location"/>
            <MenuItem x:Name="CmStartupCopy" Header="Copy command"/>
            <MenuItem x:Name="CmStartupWeb" Header="Search the web"/>
          </ContextMenu>
        </DataGrid.ContextMenu>
        <DataGrid.Columns>
          <DataGridTextColumn Header="Name" Binding="{Binding Name, Mode=OneWay}" Width="*"/>
          <DataGridTextColumn Header="Enabled" Binding="{Binding EnabledText, Mode=OneWay}" Width="75"/>
          <DataGridTextColumn Header="Publisher" Binding="{Binding Publisher, Mode=OneWay}" Width="*"/>
          <DataGridTextColumn Header="Source" Binding="{Binding Location, Mode=OneWay}" Width="*"/>
          <DataGridTextColumn Header="Command" Binding="{Binding Command, Mode=OneWay}" Width="2*"/>
        </DataGrid.Columns>
      </DataGrid>
    </DockPanel>
  </Border>
  <GridSplitter Grid.Row="2" Cursor="SizeNS"/>
  <Border Grid.Row="3" Style="{StaticResource Card}" Margin="0" Padding="12">
    <DockPanel>
      <DockPanel DockPanel.Dock="Top">
        <TextBlock Style="{StaticResource SectionTitle}" Text="Scheduled tasks" Margin="0,4,14,6" VerticalAlignment="Top"/>
        <WrapPanel>
          $(New-Pill -Name 'BtnTaskDisable' -Glyph '&#xE711;' -Text 'Disable')
          $(New-Pill -Name 'BtnTaskEnable' -Glyph '&#xE73E;' -Text 'Enable')
          $(New-Pill -Name 'BtnTaskRefresh' -Glyph '&#xE72C;' -Text 'Refresh')
          <CheckBox x:Name="ChkTasksMs" Style="{StaticResource Switch}" Content="Include Windows tasks" Margin="6,0,10,6"/>
          $(New-Pill -Name 'BtnTaskSchd' -Glyph '&#xE823;' -Text 'Task Scheduler')
          <TextBlock x:Name="TxtTasksCount" Style="{StaticResource Counter}" Text="Loading..."/>
        </WrapPanel>
      </DockPanel>
      <DataGrid x:Name="GridTasks" Margin="0,4,0,0">
        <DataGrid.RowStyle>
          <Style TargetType="DataGridRow" BasedOn="{StaticResource {x:Type DataGridRow}}">
            <Style.Triggers>
              <DataTrigger Binding="{Binding Enabled, Mode=OneWay}" Value="False"><Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/></DataTrigger>
            </Style.Triggers>
          </Style>
        </DataGrid.RowStyle>
        <DataGrid.ContextMenu>
          <ContextMenu>
            <MenuItem x:Name="CmTaskCopy" Header="Copy action"/>
          </ContextMenu>
        </DataGrid.ContextMenu>
        <DataGrid.Columns>
          <DataGridTextColumn Header="Name" Binding="{Binding Name, Mode=OneWay}" Width="*"/>
          <DataGridTextColumn Header="State" Binding="{Binding State, Mode=OneWay}" Width="100"/>
          <DataGridTextColumn Header="Folder" Binding="{Binding Path, Mode=OneWay}" Width="120"/>
          <DataGridTextColumn Header="Account" Binding="{Binding RunAs, Mode=OneWay}" Width="110"/>
          <DataGridTextColumn Header="Last run" Binding="{Binding LastRun, Mode=OneWay}" Width="125"/>
          <DataGridTextColumn Header="Result" Binding="{Binding LastResult, Mode=OneWay}" Width="85"/>
          <DataGridTextColumn Header="Action" Binding="{Binding Action, Mode=OneWay}" Width="2*"/>
        </DataGrid.Columns>
      </DataGrid>
    </DockPanel>
  </Border>
</Grid>
"@

Register-WTPage -Id 'Startup' -Group 'Software' -Title 'Startup and tasks' -Glyph '&#xE7E8;' -Xaml $pageXaml `
    -Load { Update-WTStartup; Update-WTTasks } -Refresh { Update-WTStartup; Update-WTTasks } -Init {
    On 'BtnStartupDisable' { Set-WTStartupSelection $false }
    On 'BtnStartupEnable' { Set-WTStartupSelection $true }
    On 'BtnStartupRefresh' { Update-WTStartup }
    On 'BtnStartupTaskmgr' { Start-Process taskmgr.exe -ArgumentList '/0 /startup' }
    On 'BtnTaskDisable' { Set-WTTaskSelection $false }
    On 'BtnTaskEnable' { Set-WTTaskSelection $true }
    On 'BtnTaskRefresh' { Update-WTTasks }
    On 'ChkTasksMs' { Update-WTTasks }
    On 'BtnTaskSchd' { Start-Process taskschd.msc }
    On 'CmStartupOpen' {
        $it = $ui.GridStartup.SelectedItem
        if ($it -and $it.Target) { Open-WTPath $it.Target } elseif ($it) { Show-WTInfo "File not found for: $($it.Command)" }
    }
    On 'CmStartupCopy' { if ($ui.GridStartup.SelectedItem) { Set-WTClipboard $ui.GridStartup.SelectedItem.Command } }
    On 'CmStartupWeb' {
        $it = $ui.GridStartup.SelectedItem
        if (-not $it) { return }
        $exe = if ($it.Target) { [IO.Path]::GetFileName($it.Target) } else { '' }
        Start-Process ('https://www.google.com/search?q=' + [uri]::EscapeDataString("$($it.Name) $exe".Trim()))
    }
    On 'CmTaskCopy' { if ($ui.GridTasks.SelectedItem) { Set-WTClipboard $ui.GridTasks.SelectedItem.Action } }
}
