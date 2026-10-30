# Printers: list, connecting shared printers, queues, drivers and spooler.

Register-WTUserPanel 'UsersPrinter'

function Update-WTPrinters {
    Start-WTTask 'Printers' { Get-WTPrinter } -Background -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Driver'] })
        $ui.GridPrinters.ItemsSource = $rows
        $ui.TxtPrinterCount.Text = T '{0} printers' $rows.Count
    }
}

function Get-WTSelectedPrinterNames {
    $names = @($ui.GridPrinters.SelectedItems | ForEach-Object { $_.Name })
    if (-not $names.Count) { Show-WTInfo 'Select one or more printers.' }
    $names
}

$pageXaml = @"
<Grid Margin="24,18,24,14">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="*" MinHeight="140"/>
    <RowDefinition Height="Auto"/>
  </Grid.RowDefinitions>
  $(New-PageHeader 'Printers' 'Installed printers and print queues, connecting shared printers, unused drivers and spooler.' (New-Pill -Name 'BtnPrintMgmt' -Glyph '&#xE749;' -Text 'Print Management'))
  <Border Grid.Row="1" Style="{StaticResource Card}" Padding="12,12,12,6" Margin="0,0,0,10">
    <WrapPanel>
      $(New-Pill -Name 'BtnPrinterRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5')
      $(New-Pill -Name 'BtnPrinterTest' -Glyph '&#xE749;' -Text 'Test page')
      $(New-Pill -Name 'BtnPrinterQueue' -Glyph '&#xE894;' -Text 'Clear queue')
      $(New-Pill -Name 'BtnPrinterRemove' -Glyph '&#xE74D;' -Text 'Remove selected' -Danger)
      $(New-Pill -Name 'BtnSpooler' -Glyph '&#xE72C;' -Text 'Reset spooler' -ToolTip 'Stops the spooler, empties the PRINTERS folder and starts it again')
      $(New-Pill -Name 'BtnPrinterDrivers' -Glyph '&#xE7BA;' -Text 'Remove unused drivers')
      <TextBlock x:Name="TxtPrinterCount" Style="{StaticResource Counter}" Text="$(TX 'Loading...')"/>
    </WrapPanel>
  </Border>
  <DataGrid x:Name="GridPrinters" Grid.Row="2">
    <DataGrid.RowStyle>
      <Style TargetType="DataGridRow" BasedOn="{StaticResource {x:Type DataGridRow}}">
        <Style.Triggers>
          <DataTrigger Binding="{Binding Status, Mode=OneWay}" Value="Error"><Setter Property="Foreground" Value="{DynamicResource ErrBrush}"/></DataTrigger>
          <DataTrigger Binding="{Binding Status, Mode=OneWay}" Value="Offline"><Setter Property="Foreground" Value="{DynamicResource WarnBrush}"/></DataTrigger>
        </Style.Triggers>
      </Style>
    </DataGrid.RowStyle>
    <DataGrid.ContextMenu>
      <ContextMenu>
        <MenuItem x:Name="CmPrinterQueue" Header="$(TX 'Open the print queue')"/>
        <MenuItem x:Name="CmPrinterProps" Header="$(TX 'Printer properties')"/>
        <MenuItem x:Name="CmPrinterCopy" Header="$(TX 'Copy name')"/>
      </ContextMenu>
    </DataGrid.ContextMenu>
    <DataGrid.Columns>
      <DataGridTextColumn Header="$(TX 'Name')" Binding="{Binding Name, Mode=OneWay}" Width="2*"/>
      <DataGridTextColumn Header="$(TX 'Status')" Binding="{Binding StatusText, Mode=OneWay}" SortMemberPath="Status" Width="100"/>
      <DataGridTextColumn Header="$(TX 'Queued')" Binding="{Binding Jobs, Mode=OneWay}" Width="65"/>
      <DataGridTextColumn Header="$(TX 'Type')" Binding="{Binding Type, Mode=OneWay}" Width="140"/>
      <DataGridTextColumn Header="Driver" Binding="{Binding Driver, Mode=OneWay}" Width="2*"/>
      <DataGridTextColumn Header="$(TX 'Port')" Binding="{Binding Port, Mode=OneWay}" Width="*"/>
      <DataGridTextColumn Header="$(TX 'Shared')" Binding="{Binding Shared, Mode=OneWay}" Width="75"/>
    </DataGrid.Columns>
  </DataGrid>
  <Border Grid.Row="3" Style="{StaticResource Card}" Margin="0,10,0,0">
    <StackPanel>
      <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'Connect a shared printer')"/>
      <WrapPanel>
        <TextBox x:Name="TxtPrinterPath" Style="{StaticResource SearchBox}" Width="320" Tag="$(TX '\\server\printer')"/>
        <RadioButton x:Name="PrnScopeMachine" Style="{StaticResource Chip}" GroupName="PrnScope" Content="$(TX 'All users')" IsChecked="True"
                     ToolTip="$(TX 'printui /ga: the printer appears for every user from the next sign-in')"/>
        <RadioButton x:Name="PrnScopeUser" Style="{StaticResource Chip}" GroupName="PrnScope" Content="$(TX 'Selected user only')"
                     ToolTip="$(TX 'Connected right away in the session of the signed-in user')"/>
        $(New-Pill -Name 'BtnPrinterAdd' -Glyph '&#xE710;' -Text 'Connect' -Primary)
      </WrapPanel>
      <WrapPanel x:Name="UsersPrinter" Margin="0,4,0,0"/>
    </StackPanel>
  </Border>
</Grid>
"@

Register-WTPage -Id 'Printers' -Group 'Network' -Title 'Printers' -Glyph '&#xE749;' -Xaml $pageXaml `
    -Load { Update-WTPrinters } -Refresh { Update-WTPrinters } -Init {
    On 'BtnPrinterRefresh' { Update-WTPrinters }
    On 'BtnPrintMgmt' { Start-Process printmanagement.msc }
    On 'BtnPrinterTest' {
        $n = Get-WTSelectedPrinterNames
        if ($n.Count) { Start-WTTask 'Test page' { param($Names) foreach ($x in $Names) { Invoke-WTPrinterTestPage -Name $x } } -Parameters @{ Names = $n } }
    }
    On 'BtnPrinterQueue' {
        $n = Get-WTSelectedPrinterNames
        if ($n.Count) { Start-WTTask 'Clear print queue' { param($Names) Clear-WTPrintQueue -Name $Names } -Parameters @{ Names = $n } -OnComplete { Update-WTPrinters } }
    }
    On 'BtnPrinterRemove' {
        $n = Get-WTSelectedPrinterNames
        if (-not $n.Count) { return }
        if (-not (Show-WTConfirm ((T "Remove the selected printers?`n`n") + (($n | ForEach-Object { "• $_" }) -join "`n")))) { return }
        Start-WTTask 'Removing printers' { param($Names, $Simulate) Remove-WTPrinter -Name $Names -Simulate:$Simulate } `
            -Parameters @{ Names = $n; Simulate = Get-WTSimulate } -OnComplete { Update-WTPrinters }
    }
    On 'BtnSpooler' {
        Start-WTTask 'Spooler reset' { param($Simulate) Reset-WTPrintSpooler -Simulate:$Simulate } -Parameters @{ Simulate = Get-WTSimulate } -OnComplete { Update-WTPrinters }
    }
    On 'BtnPrinterDrivers' {
        if (-not (Show-WTConfirm "Remove the printer drivers not used by any printer?`n`nThe spooler will be restarted.")) { return }
        Start-WTTask 'Unused printer drivers' { param($Simulate) Remove-WTUnusedPrinterDriver -Simulate:$Simulate } -Parameters @{ Simulate = Get-WTSimulate }
    }
    On 'BtnPrinterAdd' {
        $path = $ui.TxtPrinterPath.Text.Trim()
        if ($path -notmatch '^\\\\[^\\]+\\.+') { Show-WTInfo 'Enter the path in the format \\server\printer.'; return }
        $user = $null
        $scope = 'Machine'
        if ($ui.PrnScopeUser.IsChecked) {
            $u = Get-WTSelectedUser 'UsersPrinter' -RequireLoggedOn
            if (-not $u) { return }
            $scope = 'User'; $user = $u.UserName
        }
        Start-WTTask (T 'Connect {0}' $path) { param($Path, $Scope, $User, $Simulate) Add-WTNetworkPrinter -Path $Path -Scope $Scope -UserName $User -Simulate:$Simulate } `
            -Parameters @{ Path = $path; Scope = $scope; User = $user; Simulate = Get-WTSimulate } -OnComplete { Update-WTPrinters }
    }
    On 'PrnScopeUser' -EventName 'Checked' { $ui.UsersPrinter.Visibility = 'Visible' }
    On 'PrnScopeMachine' -EventName 'Checked' { $ui.UsersPrinter.Visibility = 'Collapsed' }
    $ui.UsersPrinter.Visibility = 'Collapsed'
    On 'CmPrinterQueue' {
        $it = $ui.GridPrinters.SelectedItem
        if ($it) { Start-Process rundll32.exe -ArgumentList "printui.dll,PrintUIEntry /o /n`"$($it.Name)`"" }
    }
    On 'CmPrinterProps' {
        $it = $ui.GridPrinters.SelectedItem
        if ($it) { Start-Process rundll32.exe -ArgumentList "printui.dll,PrintUIEntry /p /n`"$($it.Name)`"" }
    }
    On 'CmPrinterCopy' { if ($ui.GridPrinters.SelectedItem) { Set-WTClipboard $ui.GridPrinters.SelectedItem.Name } }
}
