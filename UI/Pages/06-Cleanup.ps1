# Disk cleanup: analysis of the recoverable space and execution.

$script:CleanItems = [ordered]@{
    WinTemp        = @('Windows temporary files', 'C:\Windows\Temp', $true)
    UserTemp       = @('Temp of all users', 'AppData\Local\Temp of every profile', $true)
    WUCache        = @('Windows Update cache', 'Packages already downloaded (SoftwareDistribution\Download)', $true)
    DeliveryOpt    = @('Delivery Optimization', 'Peer-to-peer cache of the updates', $true)
    RecycleBin     = @('Recycle Bin', 'All users and all volumes', $true)
    CrashDumps     = @('Dumps and error reports', 'MEMORY.DMP, minidumps, WER reports: deletes the evidence of BSODs!', $false)
    BrowserCache   = @('Browser cache', 'Edge, Chrome and Firefox of all users', $false)
    ComponentStore = @('WinSxS component store', 'DISM StartComponentCleanup (slow)', $false)
}

function New-CleanItem {
    param([string]$Key, [string]$Label, [string]$Desc, [bool]$Checked)
@"
<Border Style="{StaticResource Card}" Margin="0,0,10,10" Padding="12,10">
  <DockPanel>
    <TextBlock x:Name="CleanSize_$Key" DockPanel.Dock="Right" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="{DynamicResource AccentBrush}" Margin="8,0,0,0"/>
    <StackPanel>
      <CheckBox x:Name="Clean_$Key" Tag="$Key" IsChecked="$Checked" Margin="0" FontWeight="SemiBold" Content="$(X $Label)"/>
      <TextBlock Text="$(X $Desc)" FontSize="11.5" Foreground="{DynamicResource SubtleBrush}" Margin="26,2,0,0" TextWrapping="Wrap"/>
    </StackPanel>
  </DockPanel>
</Border>
"@
}

function Get-WTSelectedCleanTargets { @($script:CleanItems.Keys | Where-Object { $ui["Clean_$_"].IsChecked }) }

function Show-WTCleanResult($Results, [string]$Verb) {
    $total = [int64]0
    foreach ($r in @($Results | Where-Object { $_ -and $_.PSObject.Properties['Target'] })) {
        $tb = $ui["CleanSize_$($r.Target)"]
        if (-not $tb) { continue }
        if ($r.Bytes -lt 0) { $tb.Text = 'done' } else { $tb.Text = Format-WTSize $r.Bytes; $total += $r.Bytes }
    }
    $ui.TxtCleanTotal.Text = "$(Format-WTSize $total) $Verb"
}

$cleanXaml = ($script:CleanItems.Keys | ForEach-Object {
        New-CleanItem -Key $_ -Label $script:CleanItems[$_][0] -Desc $script:CleanItems[$_][1] -Checked $script:CleanItems[$_][2]
    }) -join ''

$pageXaml = @"
<ScrollViewer VerticalScrollBarVisibility="Auto">
  <StackPanel Margin="24,18,24,8">
    $(New-PageHeader 'Cleanup' 'Free up disk space: analyze first, then clean. Files in use are skipped.')
    <Border Style="{StaticResource Card}">
      <StackPanel>
        <DockPanel Margin="0,0,0,8">
          <TextBlock x:Name="TxtCleanTotal" DockPanel.Dock="Right" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource AccentBrush}" VerticalAlignment="Center"/>
          <WrapPanel>
            $(New-Pill -Name 'BtnCleanAnalyze' -Glyph '&#xE9D9;' -Text 'Analyze recoverable space' -Primary)
            $(New-Pill -Name 'BtnCleanRun' -Glyph '&#xE74D;' -Text 'Run cleanup' -Danger)
            $(New-Pill -Name 'BtnCleanRecommended' -Glyph '&#xE762;' -Text 'Select recommended')
          </WrapPanel>
        </DockPanel>
        <UniformGrid x:Name="CleanGrid" Columns="2" Margin="0,0,-10,0">$cleanXaml</UniformGrid>
      </StackPanel>
    </Border>
    <TextBlock Style="{StaticResource Hint}" Text="The Windows Update component reset is in the Windows Update section."/>
  </StackPanel>
</ScrollViewer>
"@

Register-WTPage -Id 'Cleanup' -Group 'Repair' -Title 'Cleanup' -Glyph '&#xE74D;' -Xaml $pageXaml -Init {
    On 'BtnCleanAnalyze' {
        $t = Get-WTSelectedCleanTargets
        if (-not $t.Count) { Show-WTInfo 'Select at least one item.'; return }
        foreach ($k in $script:CleanItems.Keys) { $ui["CleanSize_$k"].Text = '' }
        $ui.TxtCleanTotal.Text = ''
        Start-WTTask 'Analyzing recoverable space' { param($Targets) Invoke-WTCleanup -Targets $Targets -AnalyzeOnly } -Parameters @{ Targets = $t } `
            -OnComplete { param($r) Show-WTCleanResult $r 'recoverable' }
    }
    On 'BtnCleanRun' {
        $t = Get-WTSelectedCleanTargets
        if (-not $t.Count) { Show-WTInfo 'Select at least one item.'; return }
        $names = ($t | ForEach-Object { '• ' + $script:CleanItems[$_][0] }) -join "`n"
        if (-not (Show-WTConfirm "Clean up:`n`n$names")) { return }
        Start-WTTask 'Disk cleanup' { param($Targets, $Simulate) Invoke-WTCleanup -Targets $Targets -Simulate:$Simulate } `
            -Parameters @{ Targets = $t; Simulate = Get-WTSimulate } -OnComplete {
            param($r)
            Show-WTCleanResult $r $(if (Get-WTSimulate) { 'recoverable' } else { 'freed' })
        }
    }
    On 'BtnCleanRecommended' { foreach ($k in $script:CleanItems.Keys) { $ui["Clean_$k"].IsChecked = [bool]$script:CleanItems[$k][2] } }
}
