# Dashboard: summary cards (memory and disk live) and quick actions.

function New-StatCard {
    # -Bar: usage bar at the bottom; -Live: extra line updated every second
    param([string]$Id, [string]$Glyph, [string]$Label, [switch]$Bar, [switch]$Live)
    $Label = (T $Label).ToUpper()
    $barXaml = if ($Bar) { "<ProgressBar x:Name=`"Dash${Id}Bar`" DockPanel.Dock=`"Bottom`" Height=`"5`" Margin=`"0,10,0,0`" Maximum=`"100`"/>" } else { '' }
    $liveXaml = if ($Live) { "<TextBlock x:Name=`"Dash${Id}Live`" FontSize=`"11.5`" Foreground=`"{DynamicResource SubtleBrush}`" TextTrimming=`"CharacterEllipsis`" Margin=`"0,3,0,0`"/>" } else { '' }
@"
<Border Style="{StaticResource Card}" Margin="6" Padding="16,14">
  <DockPanel>
    $barXaml
    <StackPanel>
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="$Glyph" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="{DynamicResource AccentBrush}" VerticalAlignment="Center"/>
        <TextBlock Text="$(X $Label)" Margin="8,0,0,0" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource SubtleBrush}" VerticalAlignment="Center"/>
      </StackPanel>
      <TextBlock x:Name="Dash${Id}Value" Text="..." FontSize="18" FontWeight="SemiBold" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
      <TextBlock x:Name="Dash${Id}Sub" FontSize="11.5" Foreground="{DynamicResource SubtleBrush}" TextTrimming="CharacterEllipsis" Margin="0,3,0,0"/>
      $liveXaml
    </StackPanel>
  </DockPanel>
</Border>
"@
}

function New-LiveChart {
    # Card with the chart of the last minute (0-100%) and the current value on the right
    param([string]$Id, [string]$Glyph, [string]$Label)
    $Label = (T $Label).ToUpper()
@"
<Border Style="{StaticResource Card}" Margin="6" Padding="16,12,16,14">
  <DockPanel>
    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,8">
      <TextBlock x:Name="Dash${Id}Now" DockPanel.Dock="Right" Text="..." FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <TextBlock Text="$Glyph" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="{DynamicResource AccentBrush}" VerticalAlignment="Center"/>
        <TextBlock Text="$(X $Label)" Margin="8,0,0,0" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource SubtleBrush}" VerticalAlignment="Center"/>
      </StackPanel>
    </DockPanel>
    <Border Height="64" CornerRadius="6" BorderThickness="1" BorderBrush="{DynamicResource LineBrush}" Background="{DynamicResource InputBrush}">
      <Canvas x:Name="Dash${Id}Chart" ClipToBounds="True">
        <Polygon x:Name="Dash${Id}Area" Fill="{DynamicResource AccentBrush}" Opacity="0.22"/>
        <Polyline x:Name="Dash${Id}Line" Stroke="{DynamicResource AccentBrush}" StrokeThickness="1.5" StrokeLineJoin="Round"/>
      </Canvas>
    </Border>
  </DockPanel>
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
        $upSub = if ($s.PendingReboot) { T 'Restart pending ({0})' $s.PendingText }
        elseif ($s.PendingRenames) { T 'Last boot {0} · file renames queued' $s.LastBoot } else { T 'Last boot {0}' $s.LastBoot }
        Set-WTDash 'Up' $s.Uptime $upSub $(if ($s.PendingReboot -or $s.UptimeDays -ge 14) { 'Warn' })
        $diskLevel = if ($s.DiskUsedPct -ge 90) { 'Err' } elseif ($s.DiskUsedPct -ge 80) { 'Warn' } else { '' }
        Set-WTDash 'Disk' (T '{0} free' $s.DiskFreeText) (T 'of {0} · {1}% used' $s.DiskTotalText $s.DiskUsedPct) $diskLevel
        $ui.DashDiskBar.Value = $s.DiskUsedPct
        # memory is updated every second by Update-WTLiveStats; this is the fallback
        if (-not $script:LiveMemory) {
            Set-WTDash 'Ram' $s.RamText (T '{0}% in use' $s.RamUsedPct) $(if ($s.RamUsedPct -ge 90) { 'Warn' })
            $ui.DashRamBar.Value = $s.RamUsedPct
        }
        Set-WTDash 'Net' $s.IP $s.Domain
        Set-WTDash 'Sec' "BitLocker $(Get-WTStateText $s.BitLocker)" "Secure Boot $(Get-WTStateText $s.SecureBoot) · TPM $(Get-WTStateText $s.Tpm)" $(if ($s.BitLocker -ne 'on') { 'Warn' })
        $stabLevel = if ($s.Bsod) { 'Err' } elseif ($s.Unexpected -or $s.AppCrash -ge 5) { 'Warn' } else { 'Ok' }
        $stabText = if ($s.Bsod -or $s.Unexpected) { T '{0} BSODs · {1} shutdowns' $s.Bsod $s.Unexpected } else { T 'No abnormal shutdowns' }
        Set-WTDash 'Stab' $stabText (T '{0} application crashes' $s.AppCrash) $stabLevel
        Set-WTHeaderInfo -Domain $s.Domain -DomainName $s.DomainName -User $s.User -Loaded
    }
}

# --- Live memory and disk usage ---------------------------------------------------
$script:LiveSamples = 60
$script:LiveHistory = @{ Ram = New-Object System.Collections.Generic.List[double]; Disk = New-Object System.Collections.Generic.List[double] }
$script:LiveMemory = $false
$script:LiveTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:LiveTimer.Interval = [TimeSpan]::FromSeconds(1)

function Add-WTLiveSample([string]$Id, [double]$Value) {
    $h = $script:LiveHistory[$Id]
    # the first value fills the whole minute, so the chart starts across the full width
    if (-not $h.Count) { for ($i = 1; $i -lt $script:LiveSamples; $i++) { $h.Add($Value) } }
    $h.Add($Value)
    while ($h.Count -gt $script:LiveSamples) { $h.RemoveAt(0) }
    # a drawing problem must not stop the values of the other card
    try { Show-WTLiveChart $Id } catch { }
}

function Show-WTLiveChart([string]$Id) {
    # area chart of the last minute, newest value on the right, 0-100%
    $canvas = $ui["Dash${Id}Chart"]
    $h = $script:LiveHistory[$Id]
    $w = $canvas.ActualWidth; $ht = $canvas.ActualHeight
    if ($w -le 0 -or $ht -le 0 -or $h.Count -lt 2) { return }
    $step = $w / ($script:LiveSamples - 1)
    $line = New-Object System.Windows.Media.PointCollection
    for ($i = 0; $i -lt $h.Count; $i++) {
        $x = $w - ($h.Count - 1 - $i) * $step
        # 1 pixel from the edges, so 0% and 100% stay visible
        $y = 1 + ($ht - 2) * (1 - [Math]::Max(0, [Math]::Min(100, $h[$i])) / 100)
        $line.Add((New-Object System.Windows.Point $x, $y))
    }
    $ui["Dash${Id}Line"].Points = $line
    $area = $line.Clone()
    $area.Add((New-Object System.Windows.Point $w, $ht))
    $area.Add((New-Object System.Windows.Point $line[0].X, $ht))
    $ui["Dash${Id}Area"].Points = $area
}

function Update-WTLiveStats {
    # only while the Dashboard is on screen
    if ($window.WindowState -eq 'Minimized' -or $ui.Tabs.SelectedIndex -ne $script:DashIndex) { return }
    $m = [WTLiveStats]::Memory()
    if ($m -and $m[0]) {
        $script:LiveMemory = $true
        $used = $m[0] - $m[1]
        $pct = [int][Math]::Round($used / $m[0] * 100)
        Set-WTDash 'Ram' (T '{0} of {1}' (Format-WTSize $used) (Format-WTSize $m[0])) (T '{0}% in use · {1} available' $pct (Format-WTSize $m[1])) $(if ($pct -ge 90) { 'Warn' })
        $ui.DashRamBar.Value = $pct
        $ui.DashRamNow.Text = "$pct%"
        Add-WTLiveSample 'Ram' $pct
    }
    $d = [WTLiveStats]::Disk()
    if ($d) {
        $ui.DashDiskLive.Text = T 'Activity {0}% · read {1}/s · write {2}/s' ([int][Math]::Round($d[0])) (Format-WTSize $d[1]) (Format-WTSize $d[2])
        $ui.DashDiskNow.Text = "$([int][Math]::Round($d[0]))%"
        Add-WTLiveSample 'Disk' $d[0]
    }
}

$pageXaml = @"
<ScrollViewer VerticalScrollBarVisibility="Auto">
  <StackPanel Margin="24,18,24,8">
    $(New-PageHeader 'Dashboard' "The state of the computer at a glance and the most used actions." (New-Pill -Name 'BtnDashRefresh' -Glyph '&#xE72C;' -Text 'Refresh' -ToolTip 'F5'))
    <UniformGrid x:Name="DashStats" Columns="4" Margin="-6,0,-6,0">
      $(New-StatCard -Id 'Pc' -Glyph '&#xE7F4;' -Label 'Computer')
      $(New-StatCard -Id 'Os' -Glyph '&#xE770;' -Label 'Windows')
      $(New-StatCard -Id 'Up' -Glyph '&#xE823;' -Label 'Uptime')
      $(New-StatCard -Id 'Stab' -Glyph '&#xE9D9;' -Label 'Stability (7 days)')
    </UniformGrid>
    <UniformGrid x:Name="DashLive" Columns="4" Margin="-6,0,-6,0">
      $(New-StatCard -Id 'Ram' -Glyph '&#xE950;' -Label 'Memory' -Bar)
      $(New-StatCard -Id 'Disk' -Glyph '&#xEDA2;' -Label 'System disk' -Bar -Live)
      $(New-StatCard -Id 'Net' -Glyph '&#xE839;' -Label 'Network and domain')
      $(New-StatCard -Id 'Sec' -Glyph '&#xE72E;' -Label 'Security')
    </UniformGrid>
    <UniformGrid Columns="2" Margin="-6,0,-6,8">
      $(New-LiveChart -Id 'Ram' -Glyph '&#xE950;' -Label 'Memory in use, last minute')
      $(New-LiveChart -Id 'Disk' -Glyph '&#xEDA2;' -Label 'Disk activity, last minute')
    </UniformGrid>
    <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'Quick actions')"/>
    <WrapPanel Tag="Cols:4">
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
    $script:DashIndex = ($script:Pages | Where-Object { $_.Id -eq 'Dashboard' } | Select-Object -First 1).Index
    [WTLiveStats]::Start($env:SystemDrive)
    # an exception escaping a Tick handler would stop the timer for good
    $script:LiveTimer.Add_Tick({ try { Update-WTLiveStats } catch { } })
    $script:LiveTimer.Start()
    foreach ($id in 'Ram', 'Disk') { $ui["Dash${id}Chart"].Add_SizeChanged({ param($s) Show-WTLiveChart ($s.Name -replace '^Dash|Chart$') }) }
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
    On 'QaIpRenew' { Invoke-WTIpAction 'ReleaseRenew' (T 'Release and renew IP') -AllAdapters }
}
