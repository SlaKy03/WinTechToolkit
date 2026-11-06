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
    # loaded at startup with the programs; here only if that has not happened yet
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
    # a name that matches no installed program: its leftovers are searched (program removed without the toolkit)
    if ($script:AllPrograms.Count -and -not @($ui.GridPrograms.ItemsSource).Count -and (Get-WTOrphanSearchName)) { Request-WTResidueRefresh }
}

function Get-WTOrphanSearchName {
    # text of the search box when it matches no installed program (at least 4 characters)
    $f = $ui.TxtProgFilter.Text.Trim()
    if ($f.Length -lt 4 -or (Test-WTStoreTab) -or @($ui.GridPrograms.ItemsSource).Count) { return $null }
    $f
}

function Update-WTPrograms {
    Start-WTTask 'Installed programs' { Get-WTInstalledProgram } -Background -OnComplete {
        param($r)
        $script:AllPrograms = @($r | Where-Object { $_ -and $_.PSObject.Properties['DisplayName'] })
        Update-WTProgramFilter
    }
}

function Show-WTResidues($Items, [switch]$Preview, [string]$Orphan) {
    # -Preview: what is deleted together with the selected program (nothing pre-selected)
    # -Orphan: leftovers of a program that is no longer installed, to select and delete
    $items = @($Items | Where-Object { $_ -and $_.PSObject.Properties['Reason'] })
    $ui.GridResidues.ItemsSource = $items
    if ($items.Count -and -not $Preview -and -not $Orphan) { $ui.GridResidues.SelectAll() }
    $sum = ($items | Measure-Object SizeBytes -Sum).Sum
    $ui.TxtResCount.Text = if ($Orphan) {
        if ($items.Count) { T "'{0}' is not installed: {1} leftovers · {2}, select them and delete" $Orphan $items.Count (Format-WTSize $sum) }
        else { T "'{0}' is not installed and no leftovers were found." $Orphan }
    } elseif ($Preview) { T '{0} items · {1} - deleted automatically after the uninstall' $items.Count (Format-WTSize $sum) }
    else { T '{0} leftovers · {1}' $items.Count (Format-WTSize $sum) }
}

# Leftovers of the selected programs/apps, shown right away (short delay while the selection changes)
$script:ResidueToken = 0
$script:ResidueTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ResidueTimer.Interval = [TimeSpan]::FromMilliseconds(450)
$script:ResidueTimer.Add_Tick({
        $script:ResidueTimer.Stop()
        $store = Test-WTStoreTab
        $sel = @($(if ($store) { $ui.GridStore.SelectedItems } else { $ui.GridPrograms.SelectedItems }) | Select-Object -First 10)
        $orphan = Get-WTOrphanSearchName
        # nothing selected (also when the list reloads after an uninstall): the table keeps the result
        if (-not $sel.Count -and -not $orphan) { return }
        if ($orphan) {
            # program removed without the toolkit: folders and keys whose name contains the text
            $sel = @([pscustomobject]@{ DisplayName = $orphan; Publisher = ''; Version = ''; InstallLocation = ''; UninstallString = ''
                    QuietUninstallString = ''; ProductCode = $null; RegistryKey = ''; InstallerType = '' })
        }
        $script:ResidueToken++
        $ui.TxtResCount.Text = T 'Searching for leftovers...'
        Start-WTTask 'Leftovers of the selection' {
            param($Items, $Store, $Token, $Orphan)
            [pscustomobject]@{ WTResidueToken = $Token }
            foreach ($i in $Items) {
                if ($Store) { Find-WTStoreAppResidue -App $i -Preview }
                elseif ($Orphan) { Find-WTProgramResidue -Program $i -Partial -Quiet }
                else { Find-WTProgramResidue -Program $i -Quiet }
            }
        } -Parameters @{ Items = $sel; Store = $store; Token = $script:ResidueToken; Orphan = [bool]$orphan } -Background -OnComplete {
            param($r)
            # a newer selection already started its own search
            $tok = @($r | Where-Object { $_ -and $_.PSObject.Properties['WTResidueToken'] } | Select-Object -First 1)
            if (-not $tok.Count -or $tok[0].WTResidueToken -ne $script:ResidueToken) { return }
            $name = Get-WTOrphanSearchName
            if ($name) { Show-WTResidues $r -Orphan $name } else { Show-WTResidues $r -Preview }
        }
    })

function Request-WTResidueRefresh { $script:ResidueTimer.Stop(); $script:ResidueTimer.Start() }

function Clear-WTResiduePreview {
    # other tab: the leftovers of the other list no longer apply (a search still running is ignored)
    $script:ResidueToken++
    $ui.GridResidues.ItemsSource = @()
    $ui.TxtResCount.Text = ''
}

function Show-WTRemovalResult($Result) {
    # leftovers still present in the table; when a restart is needed to finish, a question
    Show-WTResidues $Result
    $restart = @($Result | Where-Object { $_ -and $_.PSObject.Properties['RestartReason'] })
    if (-not $restart.Count) { return }
    $why = @($restart | ForEach-Object { $_.RestartReason } | Select-Object -Unique)
    $msg = (T "A restart is needed to complete the removal:`n`n") + (($why | ForEach-Object { "• $_" }) -join "`n") +
        (T "`n`nRestart now? The computer restarts in 60 seconds; save your work first.")
    if (-not (Show-WTConfirm $msg 'Restart required')) {
        Write-WTLog 'Restart postponed: the removal is completed at the next restart.' -Level Warn
        return
    }
    & "$env:windir\System32\shutdown.exe" /r /t 60 /c (T 'Restart to complete the removal of programs (WinTech Toolkit).') 2>&1 | Out-Null
    Write-WTLog 'The computer restarts in 60 seconds (shutdown /a cancels it).' -Level Warn
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
          <TextBox x:Name="TxtProgFilter" Style="{StaticResource SearchBox}" Width="260" Tag="$(TX 'Search by name or publisher (Ctrl+F)')"
                   ToolTip="$(TX "If no installed program matches (e.g. 'Zoom' already uninstalled), its leftovers are searched")"/>
          $(New-Pill -Name 'BtnProgRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5')
          $(New-Pill -Name 'BtnProgExport' -Glyph '&#xE74E;' -Text 'Export CSV')
          <CheckBox x:Name="ChkSilent" Style="{StaticResource Switch}" Content="$(TX 'Silent')" IsChecked="True"
                    ToolTip="$(TX 'MSI with /qn; EXE with QuietUninstallString or the Inno Setup / NSIS switch detected automatically.')"/>
          <CheckBox x:Name="ChkRestorePoint" Style="{StaticResource Switch}" Content="$(TX 'Restore point')" IsChecked="True"/>
          $(New-Pill -Name 'BtnProgUninstall' -Glyph '&#xE74D;' -Text 'Uninstall selected' -Danger -ToolTip 'Uninstalls the programs and deletes their leftovers')
          <TextBlock x:Name="TxtProgCount" Style="{StaticResource Counter}" Text="$(TX 'Loading...')"/>
        </WrapPanel>
        <WrapPanel x:Name="StoreToolbar" Visibility="Collapsed">
          <TextBox x:Name="TxtStoreFilter" Style="{StaticResource SearchBox}" Width="260" Tag="$(TX 'Search by name or publisher')"/>
          $(New-Pill -Name 'BtnStoreRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5')
          <CheckBox x:Name="ChkStoreDeprovision" Style="{StaticResource Switch}" Content="$(TX 'Also for new users')" IsChecked="True"
                    ToolTip="$(TX 'Removes the app from the Windows image too, so it is not installed again when a new user signs in.')"/>
          $(New-Pill -Name 'BtnStoreRemove' -Glyph '&#xE74D;' -Text 'Remove selected apps' -Danger -ToolTip 'Removes the apps for all users and deletes their leftover data')
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
          $(New-Pill -Name 'BtnResidueRemove' -Glyph '&#xE74D;' -Text 'Delete selected leftovers' -Danger -ToolTip 'Deletes only the selected rows (Ctrl+A selects all), without uninstalling the program')
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
    -Load { Update-WTPrograms; Update-WTStoreApps } -Refresh { if (Test-WTStoreTab) { Update-WTStoreApps } else { Update-WTPrograms } } -Init {
    On 'TabProgDesktop' { Set-WTProgramsTab; Clear-WTResiduePreview; Request-WTResidueRefresh } -EventName 'Checked'
    On 'TabProgStore' { Set-WTProgramsTab; Clear-WTResiduePreview; Request-WTResidueRefresh } -EventName 'Checked'
    On 'GridPrograms' { Request-WTResidueRefresh } -EventName 'SelectionChanged'
    On 'GridStore' { Request-WTResidueRefresh } -EventName 'SelectionChanged'
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
        $msg += T "`n`nWhen done, their leftover data is deleted automatically."
        if (-not (Show-WTConfirm $msg 'Remove apps')) { return }
        Start-WTTask 'Removing Store apps' {
            param($Apps, $Deprovision, $Simulate)
            $found = @(Remove-WTStoreApp -InputObject $Apps -Deprovision:$Deprovision -Simulate:$Simulate)
            foreach ($g in @($found | Group-Object Program)) { Complete-WTResidueCleanup -InputObject $g.Group -Program $g.Name -Simulate:$Simulate }
        } -Parameters @{ Apps = $apps; Deprovision = $deprov; Simulate = Get-WTSimulate } `
            -OnComplete { param($r) Show-WTRemovalResult $r; Update-WTStoreApps }
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
            (T "`n`nWhen done, the leftovers are deleted automatically (registry keys are saved to .reg first); files in use are deleted at the next restart.")
        if (-not (Show-WTConfirm $msg 'Uninstall')) { return }
        Start-WTTask 'Uninstalling programs' {
            param($Programs, $Silent, $Simulate, $RestorePoint)
            if ($RestorePoint -and -not $Simulate) { New-WTRestorePoint -Description (T 'Before uninstalling') | Out-Null }
            foreach ($p in $Programs) { Invoke-WTProgramRemoval -Program $p -Silent:$Silent -Simulate:$Simulate }
        } -Parameters @{ Programs = $sel; Silent = [bool]$ui.ChkSilent.IsChecked; Simulate = Get-WTSimulate; RestorePoint = [bool]$ui.ChkRestorePoint.IsChecked } `
            -OnComplete { param($r) Show-WTRemovalResult $r; Update-WTPrograms }
    }
    On 'BtnResidueRemove' {
        $sel = @($ui.GridResidues.SelectedItems)
        if (-not $sel.Count) { Show-WTInfo 'Select the leftovers to delete (Ctrl+A selects all).'; return }
        $msg = (T "Delete {0} leftovers?`n`n" $sel.Count) + (Format-WTList $sel { "• [$($_.TypeText)] $($_.Path)" } 25) +
            (T "`n`nRegistry keys are saved to .reg before deletion; processes running from the folders will be closed.")
        # leftovers of a program or app that is still installed: deleting them can break it
        $names = @($sel | ForEach-Object { $_.Program } | Select-Object -Unique)
        $still = @($names | Where-Object { $n = $_; $script:AllPrograms + $script:AllStoreApps | Where-Object { $_.DisplayName -eq $n } | Select-Object -First 1 })
        if ($still.Count) { $msg += T "`n`nStill installed: {0}. Deleting its files can stop it from working: to remove it, use Uninstall." ($still -join ', ') }
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
