# Integrity and disks: DISM, SFC, CHKDSK, SMART, memory, WMI.

function Invoke-WTFullRepairAction {
    if (-not (Show-WTConfirm "Run DISM RestoreHealth followed by SFC /scannow?`n`nThis can take 30-60 minutes.")) { return }
    Start-WTTask 'Full repair (DISM + SFC)' { param($Source, $LimitAccess) Invoke-WTFullRepair -Source $Source -LimitAccess:$LimitAccess } `
        -Parameters @{ Source = $ui.TxtDismSource.Text.Trim(); LimitAccess = [bool]$ui.ChkLimitAccess.IsChecked }
}

$pageXaml = @"
<ScrollViewer VerticalScrollBarVisibility="Auto">
  <StackPanel Margin="24,18,24,8">
    $(New-PageHeader 'Integrity and disks' "Check and repair the Windows image, system files, disks and WMI.")
    <Border Style="{StaticResource Card}">
      <StackPanel>
        <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'DISM - Windows image')"/>
        <WrapPanel>
          $(New-Tile -Name 'BtnDismCheck' -Glyph '&#xE73E;' -Title 'CheckHealth' -Desc 'Quick check of the corruption flags')
          $(New-Tile -Name 'BtnDismScan' -Glyph '&#xE721;' -Title 'ScanHealth' -Desc "Deep scan of the component store")
          $(New-Tile -Name 'BtnDismRestore' -Glyph '&#xE90F;' -Title 'RestoreHealth' -Desc "Repairs the image (Windows Update or a source)")
        </WrapPanel>
        <WrapPanel Margin="0,4,0,0">
          <TextBlock Style="{StaticResource Label}" Text="$(TX 'Source (optional):')"/>
          <TextBox x:Name="TxtDismSource" Width="360" ToolTip="$(TX 'E.g. WIM:D:\sources\install.wim:1 or ESD:D:\sources\install.esd:1')"/>
          <CheckBox x:Name="ChkLimitAccess" Style="{StaticResource Switch}" Content="$(TX '/LimitAccess (do not use Windows Update)')" Margin="4,0,0,6"/>
        </WrapPanel>
        <TextBlock Style="{StaticResource Hint}" Text="$(TX 'With WSUS or without Internet access RestoreHealth fails (0x800F081F/0x800F0906): mount an ISO of the same build and enter WIM:D:\sources\install.wim:1 with /LimitAccess.')"/>
      </StackPanel>
    </Border>
    <Border Style="{StaticResource Card}">
      <StackPanel>
        <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'SFC - System file check')"/>
        <WrapPanel>
          $(New-Tile -Name 'BtnSfc' -Glyph '&#xE9F5;' -Title 'SFC /scannow' -Desc 'Checks and repairs the protected Windows files')
          $(New-Tile -Name 'BtnFullRepair' -Glyph '&#xE90F;' -Title 'Full repair' -Desc 'DISM RestoreHealth + SFC (30-60 minutes)' -Danger)
          $(New-Tile -Name 'BtnSfcDetails' -Glyph '&#xE8A5;' -Title 'SFC details' -Desc 'Extracts the [SR] lines from CBS.log')
        </WrapPanel>
      </StackPanel>
    </Border>
    <Border Style="{StaticResource Card}">
      <StackPanel>
        <TextBlock Style="{StaticResource SectionTitle}" Text="$(TX 'Disks and memory')"/>
        <WrapPanel>
          $(New-Tile -Name 'BtnDiskHealth' -Glyph '&#xEDA2;' -Title 'Disk health (SMART)' -Desc 'Health, temperature, wear and errors')
          $(New-Tile -Name 'BtnChkdskScan' -Glyph '&#xE721;' -Title 'Online CHKDSK' -Desc 'chkdsk /scan without a restart')
          $(New-Tile -Name 'BtnChkdskBoot' -Glyph '&#xE7E8;' -Title 'CHKDSK at restart' -Desc 'Schedules chkdsk /F on the system volume')
          $(New-Tile -Name 'BtnMdsched' -Glyph '&#xE950;' -Title 'Memory diagnostic' -Desc 'RAM test at the next restart (mdsched)')
        </WrapPanel>
      </StackPanel>
    </Border>
    <Border Style="{StaticResource Card}">
      <StackPanel>
        <TextBlock Style="{StaticResource SectionTitle}" Text="WMI"/>
        <WrapPanel>
          $(New-Tile -Name 'BtnWmiVerify' -Glyph '&#xE73E;' -Title 'Verify repository' -Desc 'winmgmt /verifyrepository')
          $(New-Tile -Name 'BtnWmiSalvage' -Glyph '&#xE90F;' -Title 'Repair repository' -Desc 'winmgmt /salvagerepository')
        </WrapPanel>
        <TextBlock Style="{StaticResource Hint}" Text="$(TX 'Useful when inventory, SCCM/Intune or Get-CimInstance fail.')"/>
      </StackPanel>
    </Border>
  </StackPanel>
</ScrollViewer>
"@

Register-WTPage -Id 'Integrity' -Group 'Repair' -Title 'Integrity and disks' -Glyph '&#xE90F;' -Xaml $pageXaml -Init {
    On 'BtnDismCheck' { Start-WTTask 'DISM CheckHealth' { Invoke-WTDism -Mode CheckHealth | Out-Null } }
    On 'BtnDismScan' { Start-WTTask 'DISM ScanHealth' { Invoke-WTDism -Mode ScanHealth | Out-Null } }
    On 'BtnDismRestore' {
        Start-WTTask 'DISM RestoreHealth' { param($Source, $LimitAccess) Invoke-WTDism -Mode RestoreHealth -Source $Source -LimitAccess:$LimitAccess | Out-Null } `
            -Parameters @{ Source = $ui.TxtDismSource.Text.Trim(); LimitAccess = [bool]$ui.ChkLimitAccess.IsChecked }
    }
    On 'BtnSfc' { Start-WTTask 'SFC /scannow' { Invoke-WTSfc | Out-Null } }
    On 'BtnFullRepair' { Invoke-WTFullRepairAction }
    On 'BtnSfcDetails' {
        Start-WTTask 'SFC details' { Export-WTSfcDetails } -OnComplete {
            param($r)
            $f = @($r) | Where-Object { $_ -is [string] } | Select-Object -Last 1
            if ($f -and (Test-Path -LiteralPath $f)) { Start-Process notepad.exe -ArgumentList "`"$f`"" }
        }
    }
    On 'BtnDiskHealth' { Start-WTTask 'Disk health (SMART)' { Get-WTDiskHealth } }
    On 'BtnChkdskScan' { Start-WTTask 'Online CHKDSK' { Invoke-WTChkdsk -Mode Scan } }
    On 'BtnChkdskBoot' {
        if (-not (Show-WTConfirm (T 'Schedule CHKDSK /F on {0} at the next restart?' $env:SystemDrive))) { return }
        Start-WTTask 'CHKDSK scheduling' { param($Simulate) Invoke-WTChkdsk -Mode Schedule -Simulate:$Simulate } -Parameters @{ Simulate = Get-WTSimulate }
    }
    On 'BtnMdsched' {
        Write-WTLog 'Starting Windows Memory Diagnostic: choose whether to restart now or at the next startup.'
        Start-Process mdsched.exe
    }
    On 'BtnWmiVerify' { Start-WTTask 'WMI check' { Repair-WTWmi -Mode Verify } }
    On 'BtnWmiSalvage' {
        if (-not (Show-WTConfirm 'Run winmgmt /salvagerepository?')) { return }
        Start-WTTask 'WMI repair' { param($Simulate) Repair-WTWmi -Mode Salvage -Simulate:$Simulate } -Parameters @{ Simulate = Get-WTSimulate }
    }
}
