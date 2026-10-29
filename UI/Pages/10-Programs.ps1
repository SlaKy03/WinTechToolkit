# Programs and leftovers: uninstall (also silent) and removal of what is left behind.

$script:AllPrograms = @()

function Update-WTProgramFilter {
    $f = $ui.TxtProgFilter.Text.Trim()
    $cmp = [StringComparison]::OrdinalIgnoreCase
    if ($f) {
        $ui.GridPrograms.ItemsSource = @($script:AllPrograms | Where-Object { "$($_.DisplayName)".IndexOf($f, $cmp) -ge 0 -or "$($_.Publisher)".IndexOf($f, $cmp) -ge 0 })
    } else {
        $ui.GridPrograms.ItemsSource = $script:AllPrograms
    }
    $ui.TxtProgCount.Text = '{0} of {1} programs' -f @($ui.GridPrograms.ItemsSource).Count, $script:AllPrograms.Count
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
    $ui.TxtResCount.Text = '{0} leftovers · {1}' -f $items.Count, (Format-WTSize $sum)
}

$pageXaml = @"
<Grid Margin="24,18,24,14">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="3*" MinHeight="120"/>
    <RowDefinition Height="8"/>
    <RowDefinition Height="2*" MinHeight="120"/>
  </Grid.RowDefinitions>
  $(New-PageHeader 'Programs and leftovers' 'Uninstall (also silently) and remove the leftover folders, keys, services, tasks and shortcuts.')
  <Border Grid.Row="1" Style="{StaticResource Card}" Padding="12,12,12,6" Margin="0,0,0,10">
    <WrapPanel>
      <TextBox x:Name="TxtProgFilter" Style="{StaticResource SearchBox}" Width="290" Tag="Search by name or publisher (Ctrl+F)"/>
      $(New-Pill -Name 'BtnProgRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5')
      $(New-Pill -Name 'BtnProgExport' -Glyph '&#xE74E;' -Text 'Export CSV')
      <CheckBox x:Name="ChkSilent" Style="{StaticResource Switch}" Content="Silent" IsChecked="True" Margin="6,0,6,6"
                ToolTip="MSI with /qn; EXE with QuietUninstallString or the Inno Setup / NSIS switch detected automatically."/>
      <CheckBox x:Name="ChkRestorePoint" Style="{StaticResource Switch}" Content="Restore point" IsChecked="True" Margin="6,0,10,6"/>
      $(New-Pill -Name 'BtnProgUninstall' -Glyph '&#xE74D;' -Text 'Uninstall selected' -Danger)
      $(New-Pill -Name 'BtnResidueScan' -Glyph '&#xE721;' -Text 'Find leftovers of selected')
      <TextBlock x:Name="TxtProgCount" Style="{StaticResource Counter}" Text="Loading..."/>
    </WrapPanel>
  </Border>
  <DataGrid x:Name="GridPrograms" Grid.Row="2">
    <DataGrid.ContextMenu>
      <ContextMenu>
        <MenuItem x:Name="CmProgOpen" Header="Open install folder"/>
        <MenuItem x:Name="CmProgRegedit" Header="Open the key in the Registry"/>
        <MenuItem x:Name="CmProgCopyCmd" Header="Copy uninstall command"/>
        <MenuItem x:Name="CmProgWeb" Header="Search the web"/>
      </ContextMenu>
    </DataGrid.ContextMenu>
    <DataGrid.Columns>
      <DataGridTextColumn Header="Name" Binding="{Binding DisplayName, Mode=OneWay}" Width="2*"/>
      <DataGridTextColumn Header="Version" Binding="{Binding Version, Mode=OneWay}" Width="115"/>
      <DataGridTextColumn Header="Publisher" Binding="{Binding Publisher, Mode=OneWay}" Width="*"/>
      <DataGridTextColumn Header="Installed on" Binding="{Binding InstallDate, Mode=OneWay}" SortMemberPath="InstallDateSort" Width="95"/>
      <DataGridTextColumn Header="Size" Binding="{Binding SizeText, Mode=OneWay}" SortMemberPath="SizeBytes" Width="90"/>
      <DataGridTextColumn Header="Type" Binding="{Binding InstallerType, Mode=OneWay}" Width="55"/>
      <DataGridTextColumn Header="Scope" Binding="{Binding Scope, Mode=OneWay}" Width="175"/>
    </DataGrid.Columns>
  </DataGrid>
  <GridSplitter Grid.Row="3" Cursor="SizeNS"/>
  <Border Grid.Row="4" Style="{StaticResource Card}" Margin="0" Padding="12">
    <DockPanel>
      <DockPanel DockPanel.Dock="Top">
        <TextBlock Style="{StaticResource SectionTitle}" Text="Leftovers found" Margin="0,4,14,6" VerticalAlignment="Top"/>
        <WrapPanel>
          <TextBox x:Name="TxtResName" Style="{StaticResource SearchBox}" Width="200" Tag="Manual search: name" ToolTip="For programs that are already uninstalled, e.g. 'Zoom'"/>
          <TextBox x:Name="TxtResPublisher" Style="{StaticResource SearchBox}" Width="170" Tag="Publisher (optional)"/>
          $(New-Pill -Name 'BtnResidueManual' -Glyph '&#xE721;' -Text 'Search')
          $(New-Pill -Name 'BtnResidueSelectAll' -Glyph '&#xE762;' -Text 'Select all')
          $(New-Pill -Name 'BtnResidueRemove' -Glyph '&#xE74D;' -Text 'Delete selected leftovers' -Danger)
          <TextBlock x:Name="TxtResCount" Style="{StaticResource Counter}"/>
        </WrapPanel>
      </DockPanel>
      <DataGrid x:Name="GridResidues" Margin="0,4,0,0">
        <DataGrid.ContextMenu>
          <ContextMenu>
            <MenuItem x:Name="CmResOpen" Header="Open / show"/>
            <MenuItem x:Name="CmResCopy" Header="Copy path"/>
          </ContextMenu>
        </DataGrid.ContextMenu>
        <DataGrid.Columns>
          <DataGridTextColumn Header="Type" Binding="{Binding Type, Mode=OneWay}" Width="135"/>
          <DataGridTextColumn Header="Path" Binding="{Binding Path, Mode=OneWay}" Width="3*"/>
          <DataGridTextColumn Header="Size" Binding="{Binding SizeText, Mode=OneWay}" SortMemberPath="SizeBytes" Width="90"/>
          <DataGridTextColumn Header="Reason" Binding="{Binding Reason, Mode=OneWay}" Width="2*"/>
          <DataGridTextColumn Header="Program" Binding="{Binding Program, Mode=OneWay}" Width="*"/>
        </DataGrid.Columns>
      </DataGrid>
    </DockPanel>
  </Border>
</Grid>
"@

Register-WTPage -Id 'Programs' -Group 'Software' -Title 'Programs and leftovers' -Glyph '&#xE71D;' -Xaml $pageXaml -SearchBox 'TxtProgFilter' `
    -Load { Update-WTPrograms } -Refresh { Update-WTPrograms } -Init {
    On 'BtnProgRefresh' { Update-WTPrograms }
    On 'TxtProgFilter' -EventName 'TextChanged' { Update-WTProgramFilter }
    On 'BtnProgExport' {
        if (-not $script:AllPrograms.Count) { Show-WTInfo "The program list is not loaded yet."; return }
        $file = Join-Path $dataDir ('Report\Programs_{0}_{1:yyyyMMdd_HHmm}.csv' -f $env:COMPUTERNAME, (Get-Date))
        $script:AllPrograms | Select-Object DisplayName, Version, Publisher, InstallDate, SizeText, InstallerType, Scope, InstallLocation, UninstallString |
            Export-Csv -LiteralPath $file -NoTypeInformation -Delimiter ';' -Encoding UTF8
        Write-WTLog "Program list exported to $file" -Level OK
        Open-WTPath $file
    }
    On 'BtnProgUninstall' {
        $sel = @($ui.GridPrograms.SelectedItems)
        if (-not $sel.Count) { Show-WTInfo 'Select one or more programs.'; return }
        $msg = "Uninstall the following programs?`n`n" + (Format-WTList $sel { "• $($_.DisplayName) $($_.Version)" }) +
            "`n`nWhen done, leftovers will be searched: nothing is deleted without a further confirmation."
        if (-not (Show-WTConfirm $msg 'Uninstall')) { return }
        Start-WTTask 'Uninstalling programs' {
            param($Programs, $Silent, $Simulate, $RestorePoint)
            if ($RestorePoint -and -not $Simulate) { New-WTRestorePoint -Description 'Before uninstalling' | Out-Null }
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
        Start-WTTask "Searching for leftovers: $name" { param($Program) Find-WTProgramResidue -Program $Program } `
            -Parameters @{ Program = $pseudo } -OnComplete { param($r) Show-WTResidues $r }
    }
    On 'BtnResidueSelectAll' { $ui.GridResidues.SelectAll() }
    On 'BtnResidueRemove' {
        $sel = @($ui.GridResidues.SelectedItems)
        if (-not $sel.Count) { Show-WTInfo 'No leftovers selected.'; return }
        $msg = "Delete $($sel.Count) leftovers?`n`n" + (Format-WTList $sel { "• [$($_.Type)] $($_.Path)" } 25) +
            "`n`nRegistry keys are saved to .reg before deletion; processes running from the folders will be closed."
        if (-not (Show-WTConfirm $msg 'Delete leftovers')) { return }
        Start-WTTask 'Removing leftovers' { param($Items, $Simulate) Remove-WTResidue -InputObject $Items -Simulate:$Simulate } `
            -Parameters @{ Items = $sel; Simulate = Get-WTSimulate } -OnComplete {
            param($r)
            $left = @($r | Where-Object { $_ -and $_.PSObject.Properties['Reason'] })
            $ui.GridResidues.ItemsSource = $left
            $ui.TxtResCount.Text = "$($left.Count) leftovers remaining"
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
