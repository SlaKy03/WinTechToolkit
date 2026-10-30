# System: inventory, HTML report, tools and Windows consoles.

$script:Consoles = @(
    @('compmgmt.msc', '&#xE7F4;', (T 'Computer Management')), @('devmgmt.msc', '&#xE950;', (T 'Device Manager')),
    @('services.msc', '&#xE713;', (T 'Services')), @('eventvwr.msc', '&#xE81C;', (T 'Event Viewer')),
    @('appwiz.cpl', '&#xE71D;', (T 'Programs and Features')), @('ncpa.cpl', '&#xE839;', (T 'Network Connections')),
    @('lusrmgr.msc', '&#xE716;', (T 'Local Users and Groups')), @('printmanagement.msc', '&#xE749;', (T 'Print Management')),
    @('taskschd.msc', '&#xE823;', (T 'Task Scheduler')), @('diskmgmt.msc', '&#xEDA2;', (T 'Disk Management')),
    @('taskmgr.exe', '&#xE9D9;', (T 'Task Manager')), @('regedit.exe', '&#xE8A5;', (T 'Registry Editor')),
    @('sysdm.cpl', '&#xE770;', (T 'System Properties')), @('msinfo32.exe', '&#xE946;', (T 'System Information')),
    @('control.exe', '&#xE713;', (T 'Control Panel')), @('powershell.exe', '&#xE756;', (T 'PowerShell (admin)'))
)

function Update-WTSysInfo {
    Start-WTTask 'Inventory' { Get-WTSystemInfo } -Background -OnComplete { param($r) $ui.TxtSysInfo.Text = (@($r) -join "`r`n") }
}

function Invoke-WTReportAction {
    $notes = if ($ui.TxtReportNotes) { $ui.TxtReportNotes.Text.Trim() } else { '' }
    $log = @($script:LogItems | ForEach-Object { $_.Line })
    Start-WTTask 'HTML report' { param($Notes, $Log) New-WTHtmlReport -Notes $Notes -SessionLog $Log } `
        -Parameters @{ Notes = $notes; Log = $log } -OnComplete { param($r) Open-WTFile $r }
}

$consoleXaml = (0..($script:Consoles.Count - 1) | ForEach-Object {
        New-Pill -Name "Con$_" -Glyph $script:Consoles[$_][1] -Text $script:Consoles[$_][2] -Tag $script:Consoles[$_][0] -ToolTip $script:Consoles[$_][0]
    }) -join ''

$pageXaml = @"
<Grid Margin="24,18,24,14">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="370"/></Grid.ColumnDefinitions>
  <StackPanel Grid.ColumnSpan="2">
    <TextBlock Style="{StaticResource PageTitle}" Text="$(TX 'System')"/>
    <TextBlock Style="{StaticResource PageSubtitle}" Text="$(TX 'Full inventory, ticket report, support tools and Windows consoles.')"/>
  </StackPanel>
  <Border Grid.Row="1" Style="{StaticResource Card}" Margin="0,0,14,0" Padding="12">
    <DockPanel>
      <WrapPanel DockPanel.Dock="Top">
        $(New-Pill -Name 'BtnSysRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5')
        $(New-Pill -Name 'BtnSysExport' -Glyph '&#xE74E;' -Text 'Save as text')
        $(New-Pill -Name 'BtnSysCopy' -Glyph '&#xE8C8;' -Text 'Copy')
      </WrapPanel>
      <TextBox x:Name="TxtSysInfo" Style="{StaticResource CodeBox}" TextWrapping="NoWrap" Text="$(TX 'Loading...')"/>
    </DockPanel>
  </Border>
  <ScrollViewer Grid.Row="1" Grid.Column="1" VerticalScrollBarVisibility="Auto">
    <StackPanel>
      <Border Style="{StaticResource Card}">
        <StackPanel>
          <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'Ticket report')"/>
          <TextBox x:Name="TxtReportNotes" Style="{StaticResource HintBox}" Height="70" Margin="0,0,0,8" AcceptsReturn="True" TextWrapping="Wrap" VerticalContentAlignment="Top"
                   VerticalScrollBarVisibility="Auto" Tag="$(TX 'Technician notes for the report (optional)')" ToolTip="$(TX 'Technician notes to include in the report (optional)')"/>
          $(New-Pill -Name 'BtnReport' -Glyph '&#xE8A5;' -Text 'Create HTML report' -Primary)
          <TextBlock Style="{StaticResource Hint}" Text="$(TX 'Summary, event diagnosis, disks, network, programs, startup items, administrators, printers, updates and the activities performed in this session. The report is in English.')"/>
        </StackPanel>
      </Border>
      <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'Tools')"/>
      <WrapPanel>
        $(New-Tile -Name 'BtnRestorePoint' -Glyph '&#xE777;' -Title 'Create restore point' -Desc 'Bypasses the one-per-24-hours limit')
        $(New-Tile -Name 'BtnBattery' -Glyph '&#xE83F;' -Title 'Battery report' -Desc 'powercfg /batteryreport (laptops)')
      </WrapPanel>
      <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'Windows consoles')" Margin="0,8,0,10"/>
      <WrapPanel>$consoleXaml</WrapPanel>
    </StackPanel>
  </ScrollViewer>
</Grid>
"@

Register-WTPage -Id 'System' -Group 'Diagnostics' -Title 'System' -Glyph '&#xE7F4;' -Xaml $pageXaml -Load { Update-WTSysInfo } -Refresh { Update-WTSysInfo } -Init {
    On 'BtnSysRefresh' { Update-WTSysInfo }
    On 'BtnSysExport' {
        if (-not $ui.TxtSysInfo.Text) { return }
        $file = Join-Path $dataDir ('Report\Info_{0}_{1:yyyyMMdd_HHmm}.txt' -f $env:COMPUTERNAME, (Get-Date))
        Set-Content -LiteralPath $file -Value $ui.TxtSysInfo.Text -Encoding UTF8
        Write-WTLog (T 'Inventory saved to {0}' $file) -Level OK
        Start-Process notepad.exe -ArgumentList "`"$file`""
    }
    On 'BtnSysCopy' { Set-WTClipboard $ui.TxtSysInfo.Text }
    On 'BtnReport' { Invoke-WTReportAction }
    On 'BtnRestorePoint' { Start-WTTask 'Restore point' { New-WTRestorePoint | Out-Null } }
    On 'BtnBattery' { Start-WTTask 'Battery report' { New-WTBatteryReport } -OnComplete { param($r) Open-WTFile $r } }
    for ($i = 0; $i -lt $script:Consoles.Count; $i++) {
        On "Con$i" { param($s) try { Start-Process ([string]$s.Tag) } catch { Write-WTLog (T 'Could not open {0}: {1}' $s.Tag $_.Exception.Message) -Level Error } }
    }
}
