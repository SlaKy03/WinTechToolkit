# Credentials and access: Credential Manager, Kerberos tickets, local group members.

$script:LocalGroups = [ordered]@{
    'S-1-5-32-544' = 'Administrators'
    'S-1-5-32-555' = 'Remote Desktop Users'

    'S-1-5-32-545' = 'Users'
}
Register-WTUserPanel 'UsersAccounts'

function Get-WTSelectedGroupSid {
    foreach ($sid in $script:LocalGroups.Keys) { if ($ui["Grp_$($sid -replace '-', '_')"].IsChecked) { return $sid } }
    'S-1-5-32-544'
}

function Update-WTGroupMembers {
    $sid = Get-WTSelectedGroupSid
    Start-WTTask 'Local group members' { param($Sid) Get-WTGroupMember -GroupSid $Sid } -Parameters @{ Sid = $sid } -Background -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['AdsPath'] })
        $ui.GridGroup.ItemsSource = $rows
        $ui.TxtGroupCount.Text = "$($rows.Count) members"
    }
}

function Update-WTCredentials {
    $u = Get-WTSelectedUser 'UsersAccounts' -RequireLoggedOn
    if (-not $u) { return }
    Start-WTTask "Saved credentials of $($u.UserName)" { param($User) Get-WTSavedCredential -UserName $User } -Parameters @{ User = $u.UserName } -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Target'] })
        $ui.GridCreds.ItemsSource = $rows
        $ui.TxtCredCount.Text = "$($rows.Count) credentials"
    }
}

$groupChips = ($script:LocalGroups.Keys | ForEach-Object {
        $checked = if ($_ -eq 'S-1-5-32-544') { ' IsChecked="True"' } else { '' }
        "<RadioButton x:Name=`"Grp_$($_ -replace '-', '_')`" Style=`"{StaticResource Chip}`" GroupName=`"LocalGroup`" Tag=`"$_`" Content=`"$(X $script:LocalGroups[$_])`"$checked/>"
    }) -join ''

$pageXaml = @"
<Grid Margin="24,18,24,14">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="*" MinHeight="200"/>
  </Grid.RowDefinitions>
  <Grid.ColumnDefinitions>
    <ColumnDefinition Width="*"/>
    <ColumnDefinition Width="14"/>
    <ColumnDefinition Width="*"/>
  </Grid.ColumnDefinitions>
  <StackPanel Grid.ColumnSpan="3">
    $(New-PageHeader 'Credentials and access' "Saved credentials and Kerberos tickets of the user (after a password change or a locked account) and local group members.")
  </StackPanel>

  <Border Grid.Row="1" Style="{StaticResource Card}" Margin="0" Padding="12">
    <DockPanel>
      <StackPanel DockPanel.Dock="Top">
        <TextBlock Style="{StaticResource SectionTitle}" Text="User"/>
        <WrapPanel x:Name="UsersAccounts"><TextBlock Text="Loading users..." Foreground="{DynamicResource SubtleBrush}" Margin="0,0,0,6"/></WrapPanel>
        <TextBlock Style="{StaticResource Hint}" Margin="0,0,0,8" Text="The dot marks signed-in users: credentials and tickets can only be read in their session."/>
        <TextBlock Style="{StaticResource SectionTitle}" Text="Credential Manager" Margin="0,4,0,8"/>
        <WrapPanel>
          $(New-Pill -Name 'BtnCredLoad' -Glyph '&#xE72C;' -Text 'Read credentials' -Primary)
          $(New-Pill -Name 'BtnCredDelete' -Glyph '&#xE74D;' -Text 'Delete selected' -Danger)
          $(New-Pill -Name 'BtnCredSelectOffice' -Glyph '&#xE762;' -Text 'Select Office/Teams/OneDrive')
          <TextBlock x:Name="TxtCredCount" Style="{StaticResource Counter}"/>
        </WrapPanel>
      </StackPanel>
      <DockPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
        <TextBlock DockPanel.Dock="Top" Style="{StaticResource SectionTitle}" Text="Kerberos tickets"/>
        <WrapPanel>
          $(New-Pill -Name 'BtnKrbShow' -Glyph '&#xE8A5;' -Text 'Show user tickets')
          $(New-Pill -Name 'BtnKrbUser' -Glyph '&#xE72C;' -Text 'Purge user tickets' -ToolTip 'klist purge in the session: new groups and passwords apply without signing out')
          $(New-Pill -Name 'BtnKrbComputer' -Glyph '&#xE7F4;' -Text 'Purge computer tickets' -ToolTip 'klist -li 0x3e7 purge: new computer groups without a restart')
        </WrapPanel>
      </DockPanel>
      <DataGrid x:Name="GridCreds" Margin="0,4,0,0">
        <DataGrid.ContextMenu>
          <ContextMenu>
            <MenuItem x:Name="CmCredCopy" Header="Copy target"/>
          </ContextMenu>
        </DataGrid.ContextMenu>
        <DataGrid.Columns>
          <DataGridTextColumn Header="Target" Binding="{Binding Target, Mode=OneWay}" Width="2*"/>
          <DataGridTextColumn Header="User" Binding="{Binding User, Mode=OneWay}" Width="*"/>
          <DataGridTextColumn Header="Type" Binding="{Binding TypeText, Mode=OneWay}" Width="120"/>
          <DataGridTextColumn Header="Modified" Binding="{Binding Modified, Mode=OneWay}" Width="115"/>
        </DataGrid.Columns>
      </DataGrid>
    </DockPanel>
  </Border>

  <Border Grid.Row="1" Grid.Column="2" Style="{StaticResource Card}" Margin="0" Padding="12">
    <DockPanel>
      <StackPanel DockPanel.Dock="Top">
        <TextBlock Style="{StaticResource SectionTitle}" Text="Local groups"/>
        <WrapPanel>$groupChips</WrapPanel>
        <WrapPanel Margin="0,4,0,0">
          <TextBox x:Name="TxtGroupMember" Style="{StaticResource SearchBox}" Width="240" Tag="DOMAIN\user to add" ToolTip="DOMAIN\user, DOMAIN\group, AzureAD\user@domain or a local user"/>
          $(New-Pill -Name 'BtnGroupAdd' -Glyph '&#xE710;' -Text 'Add')
          $(New-Pill -Name 'BtnGroupRemove' -Glyph '&#xE74D;' -Text 'Remove selected' -Danger)
          $(New-Pill -Name 'BtnGroupRefresh' -Glyph '&#xE72C;' -Text 'Refresh')
          <TextBlock x:Name="TxtGroupCount" Style="{StaticResource Counter}"/>
        </WrapPanel>
      </StackPanel>
      <TextBlock DockPanel.Dock="Bottom" Style="{StaticResource Hint}" Text="Changes apply at the user's next sign-in. Orphaned SIDs (deleted accounts) can be removed; the account in use and the built-in administrator are protected."/>
      <DataGrid x:Name="GridGroup" Margin="0,4,0,0">
        <DataGrid.RowStyle>
          <Style TargetType="DataGridRow" BasedOn="{StaticResource {x:Type DataGridRow}}">
            <Style.Triggers>
              <DataTrigger Binding="{Binding Source, Mode=OneWay}" Value="Orphaned SID (deleted account?)"><Setter Property="Foreground" Value="{DynamicResource WarnBrush}"/></DataTrigger>
              <DataTrigger Binding="{Binding Source, Mode=OneWay}" Value="System"><Setter Property="Foreground" Value="{DynamicResource SubtleBrush}"/></DataTrigger>
            </Style.Triggers>
          </Style>
        </DataGrid.RowStyle>
        <DataGrid.ContextMenu>
          <ContextMenu>
            <MenuItem x:Name="CmGroupCopy" Header="Copy name"/>
            <MenuItem x:Name="CmGroupCopySid" Header="Copy SID"/>
          </ContextMenu>
        </DataGrid.ContextMenu>
        <DataGrid.Columns>
          <DataGridTextColumn Header="Name" Binding="{Binding Name, Mode=OneWay}" Width="2*"/>
          <DataGridTextColumn Header="Type" Binding="{Binding Class, Mode=OneWay}" Width="70"/>
          <DataGridTextColumn Header="Source" Binding="{Binding Source, Mode=OneWay}" Width="*"/>
          <DataGridTextColumn Header="SID" Binding="{Binding SID, Mode=OneWay}" Width="*"/>
        </DataGrid.Columns>
      </DataGrid>
    </DockPanel>
  </Border>
</Grid>
"@

Register-WTPage -Id 'Accounts' -Group 'Users' -Title 'Credentials and access' -Glyph '&#xE8D7;' -Xaml $pageXaml `
    -Load { Update-WTGroupMembers } -Refresh { Update-WTGroupMembers; Update-WTUserTargets } -Init {
    foreach ($sid in $script:LocalGroups.Keys) {
        On "Grp_$($sid -replace '-', '_')" -EventName 'Checked' { Update-WTGroupMembers }
    }
    On 'BtnCredLoad' { Update-WTCredentials }
    On 'BtnCredSelectOffice' {
        $ui.GridCreds.UnselectAll()
        foreach ($c in $ui.GridCreds.Items) {
            if ($c.Target -match 'MicrosoftOffice|msteams|OneAuth|Microsoft_OC|SSO_POP|OneDrive|virtualapp/didlogical') { [void]$ui.GridCreds.SelectedItems.Add($c) }
        }
    }
    On 'BtnCredDelete' {
        $u = Get-WTSelectedUser 'UsersAccounts' -RequireLoggedOn
        if (-not $u) { return }
        $sel = @($ui.GridCreds.SelectedItems)
        if (-not $sel.Count) { Show-WTInfo "Select the credentials to delete (press 'Read credentials' first)."; return }
        if (-not (Show-WTConfirm ("Delete $($sel.Count) credentials of $($u.UserName)?`n`n" + (Format-WTList $sel { "• $($_.Target)" })))) { return }
        Start-WTTask 'Deleting credentials' { param($User, $Items, $Simulate) Remove-WTSavedCredential -UserName $User -Credential $Items -Simulate:$Simulate } `
            -Parameters @{ User = $u.UserName; Items = $sel; Simulate = Get-WTSimulate } -OnComplete { Update-WTCredentials }
    }
    On 'BtnKrbShow' {
        $u = Get-WTSelectedUser 'UsersAccounts' -RequireLoggedOn
        if ($u) { Start-WTTask "Kerberos tickets of $($u.UserName)" { param($User) Show-WTKerberosTicket -UserName $User } -Parameters @{ User = $u.UserName } }
    }
    On 'BtnKrbUser' {
        $u = Get-WTSelectedUser 'UsersAccounts' -RequireLoggedOn
        if ($u) { Start-WTTask "Purge tickets of $($u.UserName)" { param($User) Clear-WTKerberosTicket -Scope User -UserName $User } -Parameters @{ User = $u.UserName } }
    }
    On 'BtnKrbComputer' { Start-WTTask 'Purge computer tickets' { Clear-WTKerberosTicket -Scope Computer } }
    On 'BtnGroupRefresh' { Update-WTGroupMembers }
    On 'BtnGroupAdd' {
        $m = $ui.TxtGroupMember.Text.Trim()
        if (-not $m) { Show-WTInfo "Enter the account to add (e.g. DOMAIN\user)."; return }
        $sid = Get-WTSelectedGroupSid
        if (-not (Show-WTConfirm "Add $m to the group $($script:LocalGroups[$sid])?")) { return }
        Start-WTTask "Adding $m" { param($Sid, $Member, $Simulate) Add-WTGroupMember -GroupSid $Sid -Member $Member -Simulate:$Simulate } `
            -Parameters @{ Sid = $sid; Member = $m; Simulate = Get-WTSimulate } -OnComplete { $ui.TxtGroupMember.Text = ''; Update-WTGroupMembers }
    }
    On 'BtnGroupRemove' {
        $sel = @($ui.GridGroup.SelectedItems)
        if (-not $sel.Count) { Show-WTInfo 'Select one or more members.'; return }
        if (-not (Show-WTConfirm ("Remove from the group $($sel[0].Group):`n`n" + (Format-WTList $sel { "• $($_.Name)" })))) { return }
        Start-WTTask 'Removing from the group' { param($Items, $Simulate) Remove-WTGroupMember -InputObject $Items -Simulate:$Simulate } `
            -Parameters @{ Items = $sel; Simulate = Get-WTSimulate } -OnComplete { Update-WTGroupMembers }
    }
    On 'CmCredCopy' { if ($ui.GridCreds.SelectedItem) { Set-WTClipboard $ui.GridCreds.SelectedItem.Target } }
    On 'CmGroupCopy' { if ($ui.GridGroup.SelectedItem) { Set-WTClipboard $ui.GridGroup.SelectedItem.Name } }
    On 'CmGroupCopySid' { if ($ui.GridGroup.SelectedItem) { Set-WTClipboard $ui.GridGroup.SelectedItem.SID } }
}
