# Microsoft 365: Office repair and update, Teams reset, Outlook, sign-in and OneDrive.

Register-WTUserPanel 'UsersOffice'

function Update-WTOfficeInfo {
    Start-WTTask 'Office version' { Get-WTOfficeInfo } -Background -OnComplete {
        param($r)
        $i = @($r) | Where-Object { $_ -and $_.PSObject.Properties['Version'] } | Select-Object -Last 1
        if ($i) {
            $ui.TxtOfficeVersion.Text = "Microsoft 365 / Office $($i.Version) · $($i.Platform) · $($i.Channel) · $($i.Culture)"
            $ui.TxtOfficeProducts.Text = "Products: $($i.Products)"
        } else {
            $ui.TxtOfficeVersion.Text = 'Office Click-to-Run not found'
            $ui.TxtOfficeProducts.Text = 'Office is not installed or is an MSI version: repair it from Apps & features.'
        }
    }
}

function Invoke-WTOfficeUserAction {
    # Runs an action on the selected user; -LoggedOn for those that run in their session
    param([string]$Title, [scriptblock]$Script, [switch]$LoggedOn, [string]$Confirm)
    $u = Get-WTSelectedUser 'UsersOffice' -RequireLoggedOn:$LoggedOn
    if (-not $u) { return }
    if ($Confirm -and -not (Show-WTConfirm ($Confirm -f $u.UserName))) { return }
    $all = @{ User = $u.UserName; ProfilePath = $u.ProfilePath; Simulate = Get-WTSimulate }
    # only the parameters declared by the scriptblock, the others would make the binding fail
    $params = @{}
    foreach ($p in $Script.Ast.ParamBlock.Parameters) { $n = $p.Name.VariablePath.UserPath; $params[$n] = $all[$n] }
    Start-WTTask "$Title ($($u.UserName))" $Script -Parameters $params
}

$pageXaml = @"
<ScrollViewer VerticalScrollBarVisibility="Auto">
  <StackPanel Margin="24,18,24,8">
    $(New-PageHeader 'Office and Teams' 'The most frequent Microsoft 365 requests: constant sign-in prompts, license, slow Teams, stuck Outlook, OneDrive not syncing.')
    <Border Style="{StaticResource Card}">
      <StackPanel>
        <DockPanel>
          <Border DockPanel.Dock="Left" Width="34" Height="34" CornerRadius="8" Background="{DynamicResource AccentSoftBrush}" Margin="0,0,12,0" VerticalAlignment="Top">
            <TextBlock Text="&#xE8A5;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel>
            <TextBlock x:Name="TxtOfficeVersion" FontWeight="SemiBold" Text="Reading the Office version..." TextWrapping="Wrap"/>
            <TextBlock x:Name="TxtOfficeProducts" Style="{StaticResource Hint}" Margin="0,2,0,0"/>
          </StackPanel>
        </DockPanel>
        <WrapPanel Margin="0,12,0,0">
          $(New-Tile -Name 'BtnOfficeQuick' -Glyph '&#xE90F;' -Title 'Quick repair' -Desc 'Offline, a few minutes: fixes most crashes')
          $(New-Tile -Name 'BtnOfficeFull' -Glyph '&#xE895;' -Title 'Online repair' -Desc 'Full reinstall from the Internet (slow)' -Danger)
          $(New-Tile -Name 'BtnOfficeUpdate' -Glyph '&#xE896;' -Title 'Update Office' -Desc 'Starts the update check right away')
        </WrapPanel>
      </StackPanel>
    </Border>
    <Border Style="{StaticResource Card}">
      <StackPanel>
        <TextBlock Style="{StaticResource SectionTitle}" Text="User"/>
        <WrapPanel x:Name="UsersOffice"><TextBlock Text="Loading users..." Foreground="{DynamicResource SubtleBrush}" Margin="0,0,0,6"/></WrapPanel>
        <TextBlock Style="{StaticResource Hint}" Text="The dot marks signed-in users. Actions marked 'Session' require the user to be signed in; the applications involved are closed."/>
        <WrapPanel Margin="0,12,0,0">
          $(New-Tile -Name 'BtnTeamsCache' -Glyph '&#xE8F2;' -Title 'Clear Teams cache' -Desc 'New and classic Teams: slowness, chats or images that do not load')
          $(New-Tile -Name 'BtnOfficeSignIn' -Glyph '&#xE8D7;' -Title "Reset sign-in and license" -Desc "Session · constant sign-in prompts, 'unlicensed product'")
          $(New-Tile -Name 'BtnOutlookOst' -Glyph '&#xE715;' -Title 'Rebuild Outlook cache' -Desc 'Renames the .ost files: the mailbox is downloaded again')
          $(New-Tile -Name 'BtnOutlookSafe' -Glyph '&#xE7BA;' -Title 'Outlook in safe mode' -Desc 'Session · without add-ins (outlook /safe)')
          $(New-Tile -Name 'BtnOutlookNav' -Glyph '&#xE72C;' -Title 'Reset navigation pane' -Desc 'Session · Outlook does not open or closes immediately')
          $(New-Tile -Name 'BtnOneDrive' -Glyph '&#xE753;' -Title 'Reset OneDrive' -Desc 'Session · sync stuck (local files are kept)')
        </WrapPanel>
      </StackPanel>
    </Border>
  </StackPanel>
</ScrollViewer>
"@

Register-WTPage -Id 'Office' -Group 'Users' -Title 'Office and Teams' -Glyph '&#xE8F2;' -Xaml $pageXaml `
    -Load { Update-WTOfficeInfo } -Refresh { Update-WTOfficeInfo; Update-WTUserTargets } -Init {
    On 'BtnOfficeQuick' {
        if (-not (Show-WTConfirm 'Start the Office quick repair? Open Office applications will be closed.')) { return }
        Start-WTTask 'Office quick repair' { param($Simulate) Repair-WTOffice -Mode Quick -Simulate:$Simulate } -Parameters @{ Simulate = Get-WTSimulate }
    }
    On 'BtnOfficeFull' {
        if (-not (Show-WTConfirm "Start the Office online repair?`n`nOffice is uninstalled and reinstalled from the Internet: it can take more than 30 minutes.")) { return }
        Start-WTTask 'Office online repair' { param($Simulate) Repair-WTOffice -Mode Full -Simulate:$Simulate } -Parameters @{ Simulate = Get-WTSimulate }
    }
    On 'BtnOfficeUpdate' { Start-WTTask 'Office update' { Update-WTOffice } }
    On 'BtnTeamsCache' {
        Invoke-WTOfficeUserAction 'Teams cache' { param($User, $ProfilePath, $Simulate) Reset-WTTeamsCache -ProfilePath $ProfilePath -UserName $User -Simulate:$Simulate } `
            -Confirm "Clear the Teams cache of {0}? Teams will be closed."
    }
    On 'BtnOfficeSignIn' {
        Invoke-WTOfficeUserAction 'Microsoft 365 sign-in reset' { param($User, $Simulate) Reset-WTOfficeSignIn -UserName $User -Simulate:$Simulate } -LoggedOn `
            -Confirm "Reset the Microsoft 365 sign-in and license for {0}?`n`nThe Office apps will be closed and the user will have to sign in again when opening them."
    }
    On 'BtnOutlookOst' {
        Invoke-WTOfficeUserAction 'Outlook cache' { param($User, $ProfilePath, $Simulate) Reset-WTOutlookCache -ProfilePath $ProfilePath -UserName $User -Simulate:$Simulate } `
            -Confirm "Rename the .ost files of {0}?`n`nOutlook will be closed and will download the mailbox again at the next start."
    }
    On 'BtnOutlookSafe' {
        Invoke-WTOfficeUserAction 'Outlook in safe mode' { param($User) Start-WTOutlookMode -UserName $User -Mode Safe } -LoggedOn
    }
    On 'BtnOutlookNav' {
        Invoke-WTOfficeUserAction 'Outlook /resetnavpane' { param($User) Start-WTOutlookMode -UserName $User -Mode ResetNavPane } -LoggedOn `
            -Confirm "Restart Outlook for {0} resetting the navigation pane?"
    }
    On 'BtnOneDrive' {
        Invoke-WTOfficeUserAction 'OneDrive reset' { param($User, $Simulate) Reset-WTOneDrive -UserName $User -Simulate:$Simulate } -LoggedOn `
            -Confirm "Reset OneDrive for {0}?`n`nSync will start again from scratch; local files are not deleted."
    }
}
