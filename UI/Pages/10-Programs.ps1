# Programs and apps: desktop programs (uninstall, also silent) and Microsoft Store apps,
# with the removal of what is left behind.

$script:AllPrograms = @()
$script:AllStoreApps = @()
$script:StoreAppsLoaded = $false

function Test-WTStoreTab { [bool]$ui.TabProgStore.IsChecked }

function Set-WTProgramsTab {
    $store = Test-WTStoreTab
    $ui.ProgToolbar.Visibility = $(if ($store) { 'Collapsed' } else { 'Visible' })
    $ui.GridPrograms.Visibility = $ui.ProgToolbar.Visibility
    $ui.StoreToolbar.Visibility = $(if ($store) { 'Visible' } else { 'Collapsed' })
    $ui.GridStore.Visibility = $ui.StoreToolbar.Visibility
    if ($store -and -not $script:StoreAppsLoaded) { Update-WTStoreApps }
}

function Update-WTStoreFilter {
    $f = $ui.TxtStoreFilter.Text.Trim()
    $cmp = [StringComparison]::OrdinalIgnoreCase
    if ($f) {
        $ui.GridStore.ItemsSource = @($script:AllStoreApps | Where-Object {
                "$($_.DisplayName)".IndexOf($f, $cmp) -ge 0 -or "$($_.Publisher)".IndexOf($f, $cmp) -ge 0 -or "$($_.Name)".IndexOf($f, $cmp) -ge 0 })
    } else {
        $ui.GridStore.ItemsSource = $script:AllStoreApps
    }
    $ui.TxtStoreCount.Text = T '{0} of {1} apps' (@($ui.GridStore.ItemsSource).Count) $script:AllStoreApps.Count
}

function Update-WTStoreApps {
    $script:StoreAppsLoaded = $true
    $ui.TxtStoreCount.Text = T 'Loading...'
    Start-WTTask 'Microsoft Store apps' { Get-WTStoreApp } -Background -OnComplete {
        param($r)
        $script:AllStoreApps = @($r | Where-Object { $_ -and $_.PSObject.Properties['PackageFullName'] })
        Update-WTStoreFilter
    }
}

function Update-WTProgramFilter {
    $f = $ui.TxtProgFilter.Text.Trim()
    $cmp = [StringComparison]::OrdinalIgnoreCase
    if ($f) {
        $ui.GridPrograms.ItemsSource = @($script:AllPrograms | Where-Object { "$($_.DisplayName)".IndexOf($f, $cmp) -ge 0 -or "$($_.Publisher)".IndexOf($f, $cmp) -ge 0 })
    } else {
        $ui.GridPrograms.ItemsSource = $script:AllPrograms
    }
    $ui.TxtProgCount.Text = T '{0} of {1} programs' (@($ui.GridPrograms.ItemsSource).Count) $script:AllPrograms.Count
}

function Update-WTPrograms {
    Start-WTTask 'Installed programs' { Get-WTInstalledProgram } -Background -OnComplete {
        param($r)
        $script:AllPrograms = @($r | Where-Object { $_ -and $_.PSObject.Properties['DisplayName'] })
        Update-WTProgramFilter
    }
}

function Show-WTResidues($Items) {
    $items = @($Items | Where-Object { $_ -and $_.PSObject.Properties['Reason'] })
    $ui.GridResidues.ItemsSource = $items
    if ($items.Count) { $ui.GridResidues.SelectAll() }
    $sum = ($items | Measure-Object SizeBytes -Sum).Sum
    $ui.TxtResCount.Text = T '{0} leftovers · {1}' $items.Count (Format-WTSize $sum)
}

$pageXaml = @"
<Grid Margin="24,18,24,14">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="3*" MinHeight="120"/>
    <RowDefinition Height="8"/>
    <RowDefinition Height="2*" MinHeight="120"/>
  </Grid.RowDefinitions>
  $(New-PageHeader 'Programs and apps' 'Uninstall desktop programs (also silently) and Microsoft Store apps, then remove the leftover folders, keys, services, tasks and shortcuts.')
  <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,2">
    <RadioButton x:Name="TabProgDesktop" Style="{StaticResource Chip}" GroupName="ProgramsTab" IsChecked="True"
                 ToolTip="$(TX 'Programs installed for the computer or for a user (Apps and features)')">
      <TextBlock><Run Text="&#xE7F8;" FontFamily="Segoe MDL2 Assets" FontSize="12"/><Run Text="  $(TX 'Desktop programs')"/></TextBlock>
    </RadioButton>
    <RadioButton x:Name="TabProgStore" Style="{StaticResource Chip}" GroupName="ProgramsTab"
                 ToolTip="$(TX 'Appx / MSIX packages of every user, also the preinstalled ones')">
      <TextBlock><Run Text="&#xE719;" FontFamily="Segoe MDL2 Assets" FontSize="12"/><Run Text="  $(TX 'Microsoft Store apps')"/></TextBlock>
    </RadioButton>
  </StackPanel>
  <Border Grid.Row="2" Style="{StaticResource Card}" Padding="12,12,12,4" Margin="0,0,0,10">
      <Grid>
        <WrapPanel x:Name="ProgToolbar">
          <TextBox x:Name="TxtProgFilter" Style="{StaticResource SearchBox}" Width="260" Tag="$(TX 'Search by name or publisher (Ctrl+F)')"/>
          $(New-Pill -Name 'BtnProgRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5')
          $(New-Pill -Name 'BtnProgExport' -Glyph '&#xE74E;' -Text 'Export CSV')
          <CheckBox x:Name="ChkSilent" Style="{StaticResource Switch}" Content="$(TX 'Silent')" IsChecked="True"
                    ToolTip="$(TX 'MSI with /qn; EXE with QuietUninstallString or the Inno Setup / NSIS switch detected automatically.')"/>
          <CheckBox x:Name="ChkRestorePoint" Style="{StaticResource Switch}" Content="$(TX 'Restore point')" IsChecked="True"/>
          $(New-Pill -Name 'BtnProgUninstall' -Glyph '&#xE74D;' -Text 'Uninstall selected' -Danger)
          $(New-Pill -Name 'BtnResidueScan' -Glyph '&#xE721;' -Text 'Find leftovers of selected')
          <TextBlock x:Name="TxtProgCount" Style="{StaticResource Counter}" Text="$(TX 'Loading...')"/>
        </WrapPanel>
        <WrapPanel x:Name="StoreToolbar" Visibility="Collapsed">
          <TextBox x:Name="TxtStoreFilter" Style="{StaticResource SearchBox}" Width="260" Tag="$(TX 'Search by name or publisher')"/>
          $(New-Pill -Name 'BtnStoreRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5')
          <CheckBox x:Name="ChkStoreDeprovision" Style="{StaticResource Switch}" Content="$(TX 'Also for new users')" IsChecked="True"
                    ToolTip="$(TX 'Removes the app from the Windows image too, so it is not installed again when a new user signs in.')"/>
          $(New-Pill -Name 'BtnStoreRemove' -Glyph '&#xE74D;' -Text 'Remove selected apps' -Danger -ToolTip 'Removes the apps for all users, then searches their leftover data')
          <TextBlock x:Name="TxtStoreCount" Style="{StaticResource Counter}"/>
        </WrapPanel>
      </Grid>
  </Border>
  <Grid Grid.Row="3">
  <DataGrid x:Name="GridPrograms">
    <DataGrid.ContextMenu>
      <ContextMenu>
        <MenuItem x:Name="CmProgOpen" Header="$(TX 'Open install folder')"/>
        <MenuItem x:Name="CmProgRegedit" Header="$(TX 'Open the key in the Registry')"/>
        <MenuItem x:Name="CmProgCopyCmd" Header="$(TX 'Copy uninstall command')"/>
        <MenuItem x:Name="CmProgWeb" Header="$(TX 'Search the web')"/>
      </ContextMenu>
    </DataGrid.ContextMenu>
    <DataGrid.Columns>
      <DataGridTextColumn Header="$(TX 'Name')" Binding="{Binding DisplayName, Mode=OneWay}" Width="2*"/>
      <DataGridTextColumn Header="$(TX 'Version')" Binding="{Binding Version, Mode=OneWay}" Width="115"/>
      <DataGridTextColumn Header="$(TX 'Publisher')" Binding="{Binding Publisher, Mode=OneWay}" Width="*"/>
      <DataGridTextColumn Header="$(TX 'Installed on')" Binding="{Binding InstallDate, Mode=OneWay}" SortMemberPath="InstallDateSort" Width="95"/>
      <DataGridTextColumn Header="$(TX 'Size')" Binding="{Binding SizeText, Mode=OneWay}" SortMemberPath="SizeBytes" Width="110"/>
      <DataGridTextColumn Header="$(TX 'Type')" Binding="{Binding InstallerType, Mode=OneWay}" Width="55"/>
      <DataGridTextColumn Header="$(TX 'Scope')" Binding="{Binding Scope, Mode=OneWay}" Width="175"/>
    </DataGrid.Columns>
  </DataGrid>
  <DataGrid x:Name="GridStore" Visibility="Collapsed">
    <DataGrid.RowStyle>
      <Style TargetType="DataGridRow" BasedOn="{StaticResource {x:Type DataGridRow}}">
        <Style.Triggers>
          <DataTrigger Binding="{Binding Protected, Mode=OneWay}" Value="True">
            <Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/>
            <Setter Property="ToolTip" Value="$(TX 'Needed by Windows or by other apps: it is not removed')"/>
          </DataTrigger>
        </Style.Triggers>
      </Style>
    </DataGrid.RowStyle>
    <DataGrid.ContextMenu>
      <ContextMenu>
        <MenuItem x:Name="CmStoreCopy" Header="$(TX 'Copy package name')"/>
        <MenuItem x:Name="CmStoreWeb" Header="$(TX 'Search the web')"/>
      </ContextMenu>
    </DataGrid.ContextMenu>
    <DataGrid.Columns>
      <DataGridTextColumn Header="$(TX 'Name')" Binding="{Binding DisplayName, Mode=OneWay}" Width="2*"/>
      <DataGridTextColumn Header="$(TX 'Version')" Binding="{Binding Version, Mode=OneWay}" Width="115"/>
      <DataGridTextColumn Header="$(TX 'Publisher')" Binding="{Binding Publisher, Mode=OneWay}" Width="*"/>
      <DataGridTextColumn Header="$(TX 'Size')" Binding="{Binding SizeText, Mode=OneWay}" SortMemberPath="SizeBytes" Width="110"/>
      <DataGridTextColumn Binding="{Binding Source, Mode=OneWay}" Width="125">
        <DataGridTextColumn.Header>
          <TextBlock Text="$(TX 'Source')" ToolTip="$(TX 'Microsoft Store: signed by the Store. Outside the Store: signed by the publisher, it may come with Windows or the PC maker, from winget or from an .msix file. Company: signed with a company certificate.')"/>
        </DataGridTextColumn.Header>
      </DataGridTextColumn>
      <DataGridTextColumn Header="$(TX 'Installed for')" Binding="{Binding Users, Mode=OneWay}" Width="*"/>
      <DataGridTextColumn Header="$(TX 'New users')" Binding="{Binding ProvisionedText, Mode=OneWay}" SortMemberPath="Provisioned" Width="115"/>
    </DataGrid.Columns>
  </DataGrid>
  </Grid>
  <GridSplitter Grid.Row="4" Cursor="SizeNS"/>
  <Border Grid.Row="5" Style="{StaticResource Card}" Margin="0" Padding="12">
    <DockPanel>
      <DockPanel DockPanel.Dock="Top">
        <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'Leftovers found')" Margin="0,4,14,6" VerticalAlignment="Top"/>
        <WrapPanel>
          <TextBox x:Name="TxtResName" Style="{StaticResource SearchBox}" Width="200" Tag="$(TX 'Manual search: name')" ToolTip="$(TX "For programs that are already uninstalled, e.g. 'Zoom'")"/>
          <TextBox x:Name="TxtResPublisher" Style="{StaticResource SearchBox}" Width="170" Tag="$(TX 'Publisher (optional)')"/>
          $(New-Pill -Name 'BtnResidueManual' -Glyph '&#xE721;' -Text 'Search')
          $(New-Pill -Name 'BtnResidueSelectAll' -Glyph '&#xE762;' -Text 'Select all')
          $(New-Pill -Name 'BtnResidueRemove' -Glyph '&#xE74D;' -Text 'Delete selected leftovers' -Danger)
          <TextBlock x:Name="TxtResCount" Style="{StaticResource Counter}"/>
        </WrapPanel>
      </DockPanel>
      <DataGrid x:Name="GridResidues" Margin="0,4,0,0">
        <DataGrid.ContextMenu>
          <ContextMenu>
            <MenuItem x:Name="CmResOpen" Header="$(TX 'Open / show')"/>
            <MenuItem x:Name="CmResCopy" Header="$(TX 'Copy path')"/>
          </ContextMenu>
        </DataGrid.ContextMenu>
        <DataGrid.Columns>
          <DataGridTextColumn Header="$(TX 'Type')" Binding="{Binding TypeText, Mode=OneWay}" SortMemberPath="Type" Width="135"/>
          <DataGridTextColumn Header="$(TX 'Path')" Binding="{Binding Path, Mode=OneWay}" Width="3*"/>
          <DataGridTextColumn Header="$(TX 'Size')" Binding="{Binding SizeText, Mode=OneWay}" SortMemberPath="SizeBytes" Width="110"/>
          <DataGridTextColumn Header="$(TX 'Reason')" Binding="{Binding Reason, Mode=OneWay}" Width="2*"/>
          <DataGridTextColumn Header="$(TX 'Program')" Binding="{Binding Program, Mode=OneWay}" Width="*"/>
        </DataGrid.Columns>
      </DataGrid>
    </DockPanel>
  </Border>
</Grid>
"@

Register-WTPage -Id 'Programs' -Group 'Software' -Title 'Programs and apps' -Glyph '&#xE71D;' -Xaml $pageXaml -SearchBox 'TxtProgFilter' `
    -Load { Update-WTPrograms } -Refresh { if (Test-WTStoreTab) { Update-WTStoreApps } else { Update-WTPrograms } } -Init {
    On 'TabProgDesktop' { Set-WTProgramsTab } -EventName 'Checked'
    On 'TabProgStore' { Set-WTProgramsTab } -EventName 'Checked'
    On 'BtnStoreRefresh' { Update-WTStoreApps }
    On 'TxtStoreFilter' -EventName 'TextChanged' { Update-WTStoreFilter }
    On 'BtnStoreRemove' {
        $sel = @($ui.GridStore.SelectedItems)
        if (-not $sel.Count) { Show-WTInfo 'Select one or more apps.'; return }
        $apps = @($sel | Where-Object { -not $_.Protected })
        $skipped = @($sel | Where-Object { $_.Protected })
        if (-not $apps.Count) { Show-WTInfo 'The selected apps are needed by Windows or by other apps and cannot be removed.'; return }
        $deprov = [bool]$ui.ChkStoreDeprovision.IsChecked
        $msg = (T "Remove the following apps for all users?`n`n") + (Format-WTList $apps { "• $($_.DisplayName) $($_.Version)" })
        if ($skipped.Count) { $msg += T "`n`nNot removed (needed by Windows): {0}" (($skipped | ForEach-Object { $_.DisplayName }) -join ', ') }
        $msg += $(if ($deprov) { T "`n`nThey will not be installed again for new users." } else { T "`n`nThey may be installed again when a new user signs in." })
        $msg += T "`n`nWhen done, the leftover data is searched: nothing is deleted without a further confirmation."
        if (-not (Show-WTConfirm $msg 'Remove apps')) { return }
        Start-WTTask 'Removing Store apps' {
            param($Apps, $Deprovision, $Simulate)
            Remove-WTStoreApp -InputObject $Apps -Deprovision:$Deprovision -Simulate:$Simulate
        } -Parameters @{ Apps = $apps; Deprovision = $deprov; Simulate = Get-WTSimulate } `
            -OnComplete { param($r) Show-WTResidues $r; Update-WTStoreApps }
    }
    On 'CmStoreCopy' { if ($ui.GridStore.SelectedItem) { Set-WTClipboard $ui.GridStore.SelectedItem.PackageFullName } }
    On 'CmStoreWeb' {
        $it = $ui.GridStore.SelectedItem
        if ($it) { Start-Process ('https://www.google.com/search?q=' + [uri]::EscapeDataString("$($it.DisplayName) $($it.Publisher)")) }
    }
    On 'BtnProgRefresh' { Update-WTPrograms }
    On 'TxtProgFilter' -EventName 'TextChanged' { Update-WTProgramFilter }
    On 'BtnProgExport' {
        if (-not $script:AllPrograms.Count) { Show-WTInfo "The program list is not loaded yet."; return }
        $file = Join-Path $dataDir ('Report\Programs_{0}_{1:yyyyMMdd_HHmm}.csv' -f $env:COMPUTERNAME, (Get-Date))
        $script:AllPrograms | Select-Object DisplayName, Version, Publisher, InstallDate, SizeText, InstallerType, Scope, InstallLocation, UninstallString |
            Export-Csv -LiteralPath $file -NoTypeInformation -Delimiter ';' -Encoding UTF8
        Write-WTLog (T 'Program list exported to {0}' $file) -Level OK
        Open-WTPath $file
    }
    On 'BtnProgUninstall' {
        $sel = @($ui.GridPrograms.SelectedItems)
        if (-not $sel.Count) { Show-WTInfo 'Select one or more programs.'; return }
        $msg = (T "Uninstall the following programs?`n`n") + (Format-WTList $sel { "• $($_.DisplayName) $($_.Version)" }) +
            (T "`n`nWhen done, leftovers will be searched: nothing is deleted without a further confirmation.")
        if (-not (Show-WTConfirm $msg 'Uninstall')) { return }
        Start-WTTask 'Uninstalling programs' {
            param($Programs, $Silent, $Simulate, $RestorePoint)
            if ($RestorePoint -and -not $Simulate) { New-WTRestorePoint -Description (T 'Before uninstalling') | Out-Null }
            foreach ($p in $Programs) {
                $null = Uninstall-WTProgram -Program $p -Silent:$Silent -Simulate:$Simulate
                Find-WTProgramResidue -Program $p
            }
        } -Parameters @{ Programs = $sel; Silent = [bool]$ui.ChkSilent.IsChecked; Simulate = Get-WTSimulate; RestorePoint = [bool]$ui.ChkRestorePoint.IsChecked } `
            -OnComplete { param($r) Show-WTResidues $r; Update-WTPrograms }
    }
    On 'BtnResidueScan' {
        $sel = @($ui.GridPrograms.SelectedItems)
        if (-not $sel.Count) { Show-WTInfo 'Select one or more programs.'; return }
        Start-WTTask 'Searching for leftovers' { param($Programs) foreach ($p in $Programs) { Find-WTProgramResidue -Program $p } } `
            -Parameters @{ Programs = $sel } -OnComplete { param($r) Show-WTResidues $r }
    }
    On 'BtnResidueManual' {
        $name = $ui.TxtResName.Text.Trim()
        if ($name.Length -lt 3) { Show-WTInfo 'Enter the program name (at least 3 characters).'; return }
        $pseudo = [pscustomobject]@{
            DisplayName = $name; Publisher = $ui.TxtResPublisher.Text.Trim(); Version = ''; InstallLocation = ''
            UninstallString = ''; QuietUninstallString = ''; ProductCode = $null; RegistryKey = ''; InstallerType = ''
        }
        Start-WTTask (T 'Searching for leftovers: {0}' $name) { param($Program) Find-WTProgramResidue -Program $Program -Partial } `
            -Parameters @{ Program = $pseudo } -OnComplete { param($r) Show-WTResidues $r }
    }
    On 'BtnResidueSelectAll' { $ui.GridResidues.SelectAll() }
    On 'BtnResidueRemove' {
        $sel = @($ui.GridResidues.SelectedItems)
        if (-not $sel.Count) { Show-WTInfo 'No leftovers selected.'; return }
        $msg = (T "Delete {0} leftovers?`n`n" $sel.Count) + (Format-WTList $sel { "• [$($_.TypeText)] $($_.Path)" } 25) +
            (T "`n`nRegistry keys are saved to .reg before deletion; processes running from the folders will be closed.")
        if (-not (Show-WTConfirm $msg 'Delete leftovers')) { return }
        Start-WTTask 'Removing leftovers' { param($Items, $Simulate) Remove-WTResidue -InputObject $Items -Simulate:$Simulate } `
            -Parameters @{ Items = $sel; Simulate = Get-WTSimulate } -OnComplete {
            param($r)
            $left = @($r | Where-Object { $_ -and $_.PSObject.Properties['Reason'] })
            $ui.GridResidues.ItemsSource = $left
            $ui.TxtResCount.Text = T '{0} leftovers remaining' $left.Count
        }
    }
    On 'CmProgOpen' {
        $it = $ui.GridPrograms.SelectedItem
        if (-not $it) { return }
        $loc = $it.InstallLocation
        if (-not $loc -and $it.UninstallString -and $it.UninstallString -notmatch 'msiexec') {
            $loc = Split-Path (Split-WTCommandLine ([Environment]::ExpandEnvironmentVariables($it.UninstallString)))[0] -Parent
        }
        if ($loc) { Open-WTPath $loc } else { Show-WTInfo 'The program does not report an install folder.' }
    }
    On 'CmProgRegedit' { if ($ui.GridPrograms.SelectedItem) { Open-WTRegistryKey $ui.GridPrograms.SelectedItem.RegistryKey } }
    On 'CmProgCopyCmd' { if ($ui.GridPrograms.SelectedItem) { Set-WTClipboard $ui.GridPrograms.SelectedItem.UninstallString } }
    On 'CmProgWeb' {
        $it = $ui.GridPrograms.SelectedItem
        if ($it) { Start-Process ('https://www.google.com/search?q=' + [uri]::EscapeDataString("$($it.DisplayName) $($it.Publisher)")) }
    }
    On 'CmResOpen' {
        $it = $ui.GridResidues.SelectedItem
        if (-not $it) { return }
        switch ($it.Type) {
            'Registry' { Open-WTRegistryKey $it.Path }
            'Service' { Start-Process services.msc }
            'Scheduled task' { Start-Process taskschd.msc }
            default { Open-WTPath $it.Path }
        }
    }
    On 'CmResCopy' { if ($ui.GridResidues.SelectedItem) { Set-WTClipboard $ui.GridResidues.SelectedItem.Path } }
}
