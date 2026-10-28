# Dashboard: summary cards and quick actions.

function New-StatCard {
    param([string]$Id, [string]$Glyph, [string]$Label, [switch]$Bar)
    $barXaml = if ($Bar) { "<ProgressBar x:Name=`"Dash${Id}Bar`" Height=`"5`" Margin=`"0,10,0,0`" Maximum=`"100`"/>" } else { '' }
@"
<Border Style="{StaticResource Card}" Margin="6" Padding="16,14">
  <StackPanel>
    <StackPanel Orientation="Horizontal">
      <TextBlock Text="$Glyph" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="{DynamicResource AccentBrush}" VerticalAlignment="Center"/>
      <TextBlock Text="$(X $Label)" Margin="8,0,0,0" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource SubtleBrush}" VerticalAlignment="Center"/>
    </StackPanel>
    <TextBlock x:Name="Dash${Id}Value" Text="..." FontSize="18" FontWeight="SemiBold" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
    <TextBlock x:Name="Dash${Id}Sub" FontSize="11.5" Foreground="{DynamicResource SubtleBrush}" TextTrimming="CharacterEllipsis" Margin="0,3,0,0"/>
    $barXaml
  </StackPanel>
</Border>
"@
}

function Set-WTDash([string]$Id, $Value, $Sub, [string]$Level = '') {
    $v = $ui["Dash${Id}Value"]
    $v.Text = "$Value"
    $ui["Dash${Id}Sub"].Text = "$Sub"
    $key = switch ($Level) { 'Err' { 'ErrBrush' } 'Warn' { 'WarnBrush' } 'Ok' { 'OkBrush' } default { 'TextBrush' } }
    $v.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $key)
    $bar = $ui["Dash${Id}Bar"]
    if ($bar) {
        $barKey = if ($Level -eq 'Err' -or $Level -eq 'Warn') { $key } else { 'AccentBrush' }
        $bar.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, $barKey)
    }
}

function Update-WTDashboard {
    Start-WTTask 'Dashboard' { Get-WTSystemSummary } -Background -OnComplete {
        param($r)
        $s = @($r) | Where-Object { $_ -and $_.PSObject.Properties['Computer'] } | Select-Object -Last 1
        if (-not $s) { return }
        Set-WTDash 'Pc' $s.Computer "$($s.Model) · S/N $($s.Serial)"
        Set-WTDash 'Os' $s.OS $s.Version
        $upSub = if ($s.PendingReboot) { "Restart pending ($($s.PendingText))" } else { "Last boot $($s.LastBoot)" }
        Set-WTDash 'Up' $s.Uptime $upSub $(if ($s.PendingReboot -or $s.UptimeDays -ge 14) { 'Warn' })
        $diskLevel = if ($s.DiskUsedPct -ge 90) { 'Err' } elseif ($s.DiskUsedPct -ge 80) { 'Warn' } else { '' }
        Set-WTDash 'Disk' "$($s.DiskFreeText) free" "of $($s.DiskTotalText) · $($s.DiskUsedPct)% used" $diskLevel
        $ui.DashDiskBar.Value = $s.DiskUsedPct
        Set-WTDash 'Ram' $s.RamText "$($s.RamUsedPct)% in use" $(if ($s.RamUsedPct -ge 90) { 'Warn' })
        $ui.DashRamBar.Value = $s.RamUsedPct
        Set-WTDash 'Net' $s.IP $s.Domain
        Set-WTDash 'Sec' "BitLocker $($s.BitLocker)" "Secure Boot $($s.SecureBoot) · TPM $($s.Tpm)" $(if ($s.BitLocker -ne 'on') { 'Warn' })
        $stabLevel = if ($s.Bsod) { 'Err' } elseif ($s.Unexpected -or $s.AppCrash -ge 5) { 'Warn' } else { 'Ok' }
        $stabText = if ($s.Bsod -or $s.Unexpected) { "$($s.Bsod) BSODs · $($s.Unexpected) shutdowns" } else { 'No abnormal shutdowns' }
        Set-WTDash 'Stab' $stabText "$($s.AppCrash) application crashes" $stabLevel
        $ui.TxtHeaderInfo.Text = '{0}  ·  {1}  ·  signed-in user: {2}  ·  running as {3}' -f $s.Computer, $s.Domain, $(if ($s.User) { $s.User } else { 'none' }), $identity.Name
    }
}

$pageXaml = @"
<ScrollViewer VerticalScrollBarVisibility="Auto">
  <StackPanel Margin="24,18,24,8">
    $(New-PageHeader 'Dashboard' "The state of the computer at a glance and the most used actions." (New-Pill -Name 'BtnDashRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5'))
    <UniformGrid x:Name="DashStats" Columns="4" Margin="-6,0,-6,8">
      $(New-StatCard -Id 'Pc' -Glyph '&#xE7F4;' -Label 'COMPUTER')
      $(New-StatCard -Id 'Os' -Glyph '&#xE770;' -Label 'WINDOWS')
      $(New-StatCard -Id 'Up' -Glyph '&#xE823;' -Label 'UPTIME')
      $(New-StatCard -Id 'Stab' -Glyph '&#xE9D9;' -Label 'STABILITY (7 DAYS)')
      $(New-StatCard -Id 'Disk' -Glyph '&#xEDA2;' -Label 'SYSTEM DISK' -Bar)
      $(New-StatCard -Id 'Ram' -Glyph '&#xE950;' -Label 'MEMORY' -Bar)
      $(New-StatCard -Id 'Net' -Glyph '&#xE839;' -Label 'NETWORK AND DOMAIN')
      $(New-StatCard -Id 'Sec' -Glyph '&#xE72E;' -Label 'SECURITY')
    </UniformGrid>
    <TextBlock Style="{StaticResource SectionTitle}" Text="Quick actions"/>
    <WrapPanel>
      $(New-Tile -Name 'QaDiagnose' -Glyph '&#xE9D9;' -Title 'Diagnose problems' -Desc 'BSODs, crashes, shutdowns and errors of the last 7 days')
      $(New-Tile -Name 'QaRepair' -Glyph '&#xE90F;' -Title 'Full repair' -Desc 'DISM RestoreHealth followed by SFC /scannow')
      $(New-Tile -Name 'QaClean' -Glyph '&#xE74D;' -Title 'Quick cleanup' -Desc 'Temp files, recycle bin, Windows Update cache')
      $(New-Tile -Name 'QaReport' -Glyph '&#xE8A5;' -Title 'Ticket report' -Desc 'Complete HTML report of the computer')
      $(New-Tile -Name 'QaRestorePoint' -Glyph '&#xE777;' -Title 'Restore point' -Desc 'Create one before important changes')
      $(New-Tile -Name 'QaUpdates' -Glyph '&#xE895;' -Title 'Search for updates' -Desc 'Windows updates not installed yet')
      $(New-Tile -Name 'QaGpupdate' -Glyph '&#xE8D7;' -Title 'Update Group Policy' -Desc 'gpupdate /force')
      $(New-Tile -Name 'QaIpRenew' -Glyph '&#xE8AB;' -Title 'Release and renew IP' -Desc 'ipconfig /release + /renew on all adapters')
    </WrapPanel>
  </StackPanel>
</ScrollViewer>
"@

Register-WTPage -Id 'Dashboard' -Group 'Diagnostics' -Title 'Dashboard' -Glyph '&#xE80F;' -Xaml $pageXaml -Load { Update-WTDashboard } -Refresh { Update-WTDashboard } -Init {
    On 'BtnDashRefresh' { Update-WTDashboard }
    On 'QaDiagnose' { Select-WTPageById 'Events'; Invoke-WTEventCategory 'Diagnosis' }
    On 'QaRepair' { Invoke-WTFullRepairAction }
    On 'QaClean' {
        if (-not (Show-WTConfirm 'Quick cleanup of: Windows and user temporary files, Windows Update and Delivery Optimization caches, recycle bin?')) { return }
        Start-WTTask 'Quick cleanup' { param($Simulate) Invoke-WTCleanup -Targets WinTemp, UserTemp, WUCache, DeliveryOpt, RecycleBin -Simulate:$Simulate | Out-Null } `
            -Parameters @{ Simulate = Get-WTSimulate } -OnComplete { Update-WTDashboard }
    }
    On 'QaReport' { Invoke-WTReportAction }
    On 'QaRestorePoint' { Start-WTTask 'Restore point' { New-WTRestorePoint | Out-Null } }
    On 'QaUpdates' { Select-WTPageById 'Updates'; Invoke-WTUpdateSearch }
    On 'QaGpupdate' { Start-WTTask 'gpupdate /force' { Invoke-WTGpUpdate -Target All } }
    On 'QaIpRenew' { Invoke-WTIpAction 'ReleaseRenew' 'Release and renew IP' -AllAdapters }
}
