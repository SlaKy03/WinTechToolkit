# User profiles: list with sizes, full deletion, repair of the TEMP profile.

function Update-WTProfileCount {
    $items = @($ui.GridProfiles.ItemsSource)
    $sum = ($items | Where-Object { $_.SizeBytes -gt 0 } | Measure-Object SizeBytes -Sum).Sum
    $size = if ($sum) { Format-WTSize $sum } else { T 'calculating...' }
    $ui.TxtProfCount.Text = if ($items.Count -eq 1) { T '1 item · {0} on disk' $size } else { T '{0} items · {1} on disk' $items.Count $size }
}

function Update-WTProfiles {
    # The list first (fast), then the sizes in a second pass
    Start-WTTask 'User profiles' { Get-WTUserProfile } -Background -OnComplete {
        param($r)
        $items = @($r | Where-Object { $_ -and $_.PSObject.Properties['SID'] })
        $ui.GridProfiles.ItemsSource = $items
        Update-WTProfileCount
        $paths = @($items | Where-Object { $_.Path -and $_.Status -ne (T 'Folder missing') } | ForEach-Object { $_.Path } | Select-Object -Unique)
        if (-not $paths.Count) { return }
        Start-WTTask 'Profile sizes' {
            param($Paths)
            foreach ($p in $Paths) { [pscustomobject]@{ Path = $p; Size = Get-WTFolderSize -Path $p } }
        } -Parameters @{ Paths = $paths } -Background -OnComplete {
            param($r)
            $map = @{}
            foreach ($x in @($r)) { if ($x) { $map[$x.Path] = $x.Size } }
            foreach ($item in @($ui.GridProfiles.ItemsSource)) {
                if ($item.Path -and $map.ContainsKey($item.Path)) {
                    $item.SizeBytes = [int64]$map[$item.Path]
                    $item.SizeText = Format-WTSize $item.SizeBytes
                }
            }
            $ui.GridProfiles.Items.Refresh()
            Update-WTProfileCount
        }
    }
}

$pageXaml = @"
<DockPanel Margin="24,18,24,14">
  <StackPanel DockPanel.Dock="Top">
    $(New-PageHeader 'User profiles' 'Registered profiles, orphan folders and temporary profiles, with size and last use.')
  </StackPanel>
  <Border DockPanel.Dock="Top" Style="{StaticResource Card}" Padding="12,12,12,6" Margin="0,0,0,10">
    <StackPanel>
      <WrapPanel>
        $(New-Pill -Name 'BtnProfRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5')
        $(New-Pill -Name 'BtnProfDelete' -Glyph '&#xE74D;' -Text 'Delete selected' -Danger)
        $(New-Pill -Name 'BtnProfRepairTemp' -Glyph '&#xE90F;' -Text 'Repair TEMP profile (.bak)')
        <TextBlock x:Name="TxtProfCount" Style="{StaticResource Counter}" Text="$(TX 'Loading...')"/>
      </WrapPanel>
      <WrapPanel>
        <TextBlock Style="{StaticResource Label}" Text="$(TX 'Select the profiles unused for at least')"/>
        <TextBox x:Name="TxtProfDays" Width="56" Text="90" HorizontalContentAlignment="Center"/>
        <TextBlock Style="{StaticResource Label}" Text="$(TX 'days, excluding:')"/>
        <TextBox x:Name="TxtProfExclude" Width="260" Text="Administrator, admin*" ToolTip="$(TX 'Comma-separated names, * as wildcard')"/>
        $(New-Pill -Name 'BtnProfSelectOld' -Glyph '&#xE762;' -Text 'Select')
      </WrapPanel>
    </StackPanel>
  </Border>
  <TextBlock DockPanel.Dock="Bottom" Style="{StaticResource Hint}" Text="$(TX 'Deletion: WMI profile + folder + ProfileList/.bak keys, ProfileGuid, Group Policy and Appx keys of the SID (automatic .reg backup). Loaded profiles, system profiles and the account in use are protected (greyed out). Right-click for more actions.')"/>
  <DataGrid x:Name="GridProfiles">
    <DataGrid.RowStyle>
      <Style TargetType="DataGridRow" BasedOn="{StaticResource {x:Type DataGridRow}}">
        <Style.Triggers>
          <DataTrigger Binding="{Binding Protected, Mode=OneWay}" Value="True"><Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/></DataTrigger>
          <DataTrigger Binding="{Binding Type, Mode=OneWay}" Value="Orphan folder"><Setter Property="Foreground" Value="{DynamicResource WarnBrush}"/></DataTrigger>
          <DataTrigger Binding="{Binding Type, Mode=OneWay}" Value="Backup .bak"><Setter Property="Foreground" Value="{DynamicResource WarnBrush}"/></DataTrigger>
        </Style.Triggers>
      </Style>
    </DataGrid.RowStyle>
    <DataGrid.ContextMenu>
      <ContextMenu>
        <MenuItem x:Name="CmProfOpen" Header="$(TX 'Open folder')"/>
        <MenuItem x:Name="CmProfCopyPath" Header="$(TX 'Copy path')"/>
        <MenuItem x:Name="CmProfCopySid" Header="$(TX 'Copy SID')"/>
      </ContextMenu>
    </DataGrid.ContextMenu>
    <DataGrid.Columns>
      <DataGridTextColumn Header="$(TX 'Type')" Binding="{Binding TypeText, Mode=OneWay}" SortMemberPath="Type" Width="110"/>
      <DataGridTextColumn Header="$(TX 'User')" Binding="{Binding UserName, Mode=OneWay}" Width="200"/>
      <DataGridTextColumn Header="$(TX 'Last use')" Binding="{Binding LastUseText, Mode=OneWay}" SortMemberPath="LastUse" Width="125"/>
      <DataGridTextColumn Header="$(TX 'Days')" Binding="{Binding DaysUnused, Mode=OneWay}" Width="62"/>
      <DataGridTextColumn Header="$(TX 'Size')" Binding="{Binding SizeText, Mode=OneWay}" SortMemberPath="SizeBytes" Width="115"/>
      <DataGridTextColumn Header="$(TX 'Loaded')" Binding="{Binding LoadedText, Mode=OneWay}" Width="70"/>
      <DataGridTextColumn Header="$(TX 'Status')" Binding="{Binding Status, Mode=OneWay}" Width="190"/>
      <DataGridTextColumn Header="$(TX 'Path')" Binding="{Binding Path, Mode=OneWay}" Width="200"/>
      <DataGridTextColumn Header="$(TX 'Protection')" Binding="{Binding ProtectReason, Mode=OneWay}" Width="200"/>
      <DataGridTextColumn Header="SID" Binding="{Binding SID, Mode=OneWay}" Width="*"/>
    </DataGrid.Columns>
  </DataGrid>
</DockPanel>
"@

Register-WTPage -Id 'Profiles' -Group 'Users' -Title 'User profiles' -Glyph '&#xE716;' -Xaml $pageXaml `
    -Load { Update-WTProfiles } -Refresh { Update-WTProfiles } -Init {
    On 'BtnProfRefresh' { Update-WTProfiles }
    On 'BtnProfDelete' {
        $sel = @($ui.GridProfiles.SelectedItems)
        if (-not $sel.Count) { Show-WTInfo 'Select one or more profiles (Ctrl/Shift + click for multiple selection).'; return }
        $valid = @($sel | Where-Object { -not $_.Protected })
        if (-not $valid.Count) { Show-WTInfo 'All the selected items are protected.'; return }
        $sum = ($valid | Where-Object { $_.SizeBytes -gt 0 } | Measure-Object SizeBytes -Sum).Sum
        $msg = (T "PERMANENTLY delete {0} profiles/folders ({1}) with all their data?`n`n" $valid.Count (Format-WTSize $sum)) +
            (Format-WTList $valid { "• $($_.UserName)  [$($_.Path)]  $($_.SizeText)" })
        $skipped = $sel.Count - $valid.Count
        if ($skipped) { $msg += "`n`n" + (T '{0} protected items will be skipped.' $skipped) }
        if (-not (Show-WTConfirm $msg 'Delete profiles')) { return }
        Start-WTTask 'Deleting profiles' { param($Items, $Simulate) Remove-WTUserProfile -InputObject $Items -Simulate:$Simulate } `
            -Parameters @{ Items = $valid; Simulate = Get-WTSimulate } -OnComplete { Update-WTProfiles; Update-WTUserTargets }
    }
    On 'BtnProfRepairTemp' {
        $sel = @($ui.GridProfiles.SelectedItems | Where-Object { $_.SID })
        if ($sel.Count -ne 1) { Show-WTInfo "Select a single profile (the user's 'Profile' or 'Backup .bak' row)."; return }
        $sid = $sel[0].SID
        if (-not (Show-WTConfirm (T "Restore the original profile of {0}?`n`nThe key pointing to the TEMP profile will be deleted and {1}.bak renamed. The user must be signed out." $sel[0].UserName $sid))) { return }
        Start-WTTask 'TEMP profile repair' { param($Sid, $Simulate) Repair-WTTempProfile -Sid $Sid -Simulate:$Simulate } `
            -Parameters @{ Sid = $sid; Simulate = Get-WTSimulate } -OnComplete { Update-WTProfiles }
    }
    On 'BtnProfSelectOld' {
        $days = 0
        if (-not [int]::TryParse($ui.TxtProfDays.Text, [ref]$days) -or $days -lt 1) { Show-WTInfo 'Enter a valid number of days.'; return }
        $excl = @($ui.TxtProfExclude.Text -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $ui.GridProfiles.UnselectAll()
        $n = 0
        foreach ($item in $ui.GridProfiles.Items) {
            if ($item.Protected -or $null -eq $item.DaysUnused -or $item.DaysUnused -lt $days) { continue }
            $short = ($item.UserName -split '\\')[-1]
            $skip = $false
            foreach ($e in $excl) { if ($item.UserName -like $e -or $short -like $e) { $skip = $true; break } }
            if ($skip) { continue }
            [void]$ui.GridProfiles.SelectedItems.Add($item)
            $n++
        }
        Write-WTLog (T "Selected {0} profiles unused for at least {1} days. Review them and press 'Delete selected'." $n $days)
    }
    On 'CmProfOpen' { if ($ui.GridProfiles.SelectedItem) { Open-WTPath $ui.GridProfiles.SelectedItem.Path } }
    On 'CmProfCopyPath' { if ($ui.GridProfiles.SelectedItem) { Set-WTClipboard $ui.GridProfiles.SelectedItem.Path } }
    On 'CmProfCopySid' { if ($ui.GridProfiles.SelectedItem) { Set-WTClipboard $ui.GridProfiles.SelectedItem.SID } }
}
