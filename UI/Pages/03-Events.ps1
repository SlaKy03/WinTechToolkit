# Events and logs: automatic diagnosis and event categories.

$script:EventCats = [ordered]@{
    Diagnosis = @('&#xE9D9;', 'Automatic diagnosis'); Bsod = @('&#xE7BA;', 'Blue screens'); Shutdown = @('&#xE7E8;', 'Shutdowns and restarts')
    AppCrash = @('&#xE783;', 'App crashes'); AppHang = @('&#xE916;', 'App hangs'); Disk = @('&#xEDA2;', 'Disk')
    Hardware = @('&#xE950;', 'Hardware and drivers'); Updates = @('&#xE895;', 'Windows Update'); Services = @('&#xE713;', 'Services')
    Network = @('&#xE839;', 'Network and domain'); Logon = @('&#xE72E;', 'Failed sign-ins'); Install = @('&#xE896;', 'Installations')
    AllErrors = @('&#xE8A5;', 'All errors'); Reliability = @('&#xE81C;', 'Reliability history')
}
$script:AllEvents = @()
$script:LastReport = ''

function Get-WTEventDays {
    foreach ($n in 'Days1', 'Days7', 'Days30', 'Days90') { if ($ui[$n].IsChecked) { return [int]$ui[$n].Tag } }
    7
}

function Show-WTEvents($Rows) {
    $script:AllEvents = @($Rows | Where-Object { $_ -and $_.PSObject.Properties['Summary'] })
    Update-WTEventFilter
}

function Update-WTEventFilter {
    $f = $ui.TxtEvtFilter.Text.Trim()
    $onlyErr = [bool]$ui.ChkEvtErrorsOnly.IsChecked
    $cmp = [StringComparison]::OrdinalIgnoreCase
    $rows = @($script:AllEvents | Where-Object {
            (-not $onlyErr -or $_.Level -eq 'Critical' -or $_.Level -eq 'Error') -and
            (-not $f -or "$($_.Summary)".IndexOf($f, $cmp) -ge 0 -or "$($_.Source)".IndexOf($f, $cmp) -ge 0 -or
            "$($_.Message)".IndexOf($f, $cmp) -ge 0 -or "$($_.Id)" -eq $f)
        })
    $ui.GridEvents.ItemsSource = $rows
    $ui.TxtEvtCount.Text = '{0} of {1} events' -f $rows.Count, $script:AllEvents.Count
}

function Invoke-WTEventCategory([string]$Category, [switch]$Background) {
    $days = Get-WTEventDays
    $label = $script:EventCats[$Category][1]
    if ($Category -eq 'Diagnosis') {
        Start-WTTask "Problem diagnosis (last $days days)" { param($Days) Get-WTProblemReport -Days $Days } -Parameters @{ Days = $days } -Background:$Background -OnComplete {
            param($r)
            $rep = @($r) | Where-Object { $_ -and $_.PSObject.Properties['Report'] } | Select-Object -Last 1
            if (-not $rep) { return }
            $script:LastReport = $rep.Report
            Show-WTEvents $rep.Rows
            $ui.TxtEventDetail.Text = $rep.Report
        }
    } elseif ($Category -eq 'Reliability') {
        Start-WTTask "Reliability history ($days days)" { param($Days) Get-WTReliabilityHistory -Days $Days } -Parameters @{ Days = $days } -OnComplete {
            param($r)
            Show-WTEvents $r
            $ui.TxtEventDetail.Text = "Reliability Monitor history: crashes, Windows errors, installations and updates.`r`nSelect a row for details, or open the chart with 'Reliability Monitor'."
        }
    } else {
        Start-WTTask "Events - $label ($days days)" { param($Category, $Days) Get-WTEvents -Category $Category -Days $Days } `
            -Parameters @{ Category = $Category; Days = $days } -OnComplete {
            param($r)
            Show-WTEvents $r
            $ui.TxtEventDetail.Text = 'Select an event to see its full details.'
        }
    }
}

$eventCatXaml = ($script:EventCats.Keys | ForEach-Object {
        New-Pill -Name "EvtCat_$_" -Glyph $script:EventCats[$_][0] -Text $script:EventCats[$_][1] -Tag $_ -Primary:($_ -eq 'Diagnosis')
    }) -join ''

$pageXaml = @"
<Grid Margin="24,18,24,14">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="3*" MinHeight="120"/>
    <RowDefinition Height="8"/>
    <RowDefinition Height="2*" MinHeight="90"/>
  </Grid.RowDefinitions>
  <DockPanel>
    <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top" Margin="0,6,0,0">
      <TextBlock Text="Period:" VerticalAlignment="Center" Foreground="{DynamicResource SubtleBrush}" Margin="0,0,6,6"/>
      <RadioButton x:Name="Days1" Style="{StaticResource Chip}" GroupName="Days" Tag="1" Content="24 hours"/>
      <RadioButton x:Name="Days7" Style="{StaticResource Chip}" GroupName="Days" Tag="7" Content="7 days" IsChecked="True"/>
      <RadioButton x:Name="Days30" Style="{StaticResource Chip}" GroupName="Days" Tag="30" Content="30 days"/>
      <RadioButton x:Name="Days90" Style="{StaticResource Chip}" GroupName="Days" Tag="90" Content="90 days"/>
    </StackPanel>
    <StackPanel>
      <TextBlock Style="{StaticResource PageTitle}" Text="Events and logs"/>
      <TextBlock Style="{StaticResource PageSubtitle}" Text="Why the PC or a program stopped working: blue screens, crashes, shutdowns, disk, hardware, update, network and sign-in errors."/>
    </StackPanel>
  </DockPanel>
  <Border Grid.Row="1" Style="{StaticResource Card}" Padding="12,12,6,6" Margin="0,0,0,10">
    <WrapPanel>$eventCatXaml</WrapPanel>
  </Border>
  <WrapPanel Grid.Row="2" Margin="0,0,0,4">
    <TextBox x:Name="TxtEvtFilter" Style="{StaticResource SearchBox}" Width="240" Tag="Filter events (Ctrl+F)"/>
    <CheckBox x:Name="ChkEvtErrorsOnly" Style="{StaticResource Switch}" Content="Errors and critical only" Margin="4,0,10,6"/>
    $(New-Pill -Name 'BtnEvtReport' -Glyph '&#xE8A5;' -Text 'Diagnosis report')
    $(New-Pill -Name 'BtnEvtExport' -Glyph '&#xE74E;' -Text 'Export CSV')
    $(New-Pill -Name 'BtnEvtViewer' -Glyph '&#xE81C;' -Text 'Event Viewer')
    $(New-Pill -Name 'BtnEvtReliability' -Glyph '&#xE9D9;' -Text 'Reliability Monitor')
    $(New-Pill -Name 'BtnEvtDumps' -Glyph '&#xE8B7;' -Text 'Minidump folder')
    <TextBlock x:Name="TxtEvtCount" Style="{StaticResource Counter}"/>
  </WrapPanel>
  <DataGrid x:Name="GridEvents" Grid.Row="3" SelectionMode="Single">
    <DataGrid.RowStyle>
      <Style TargetType="DataGridRow" BasedOn="{StaticResource {x:Type DataGridRow}}">
        <Style.Triggers>
          <DataTrigger Binding="{Binding Level, Mode=OneWay}" Value="Critical">
            <Setter Property="Foreground" Value="{DynamicResource ErrBrush}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
          </DataTrigger>
          <DataTrigger Binding="{Binding Level, Mode=OneWay}" Value="Error"><Setter Property="Foreground" Value="{DynamicResource ErrBrush}"/></DataTrigger>
          <DataTrigger Binding="{Binding Level, Mode=OneWay}" Value="Warning"><Setter Property="Foreground" Value="{DynamicResource WarnBrush}"/></DataTrigger>
        </Style.Triggers>
      </Style>
    </DataGrid.RowStyle>
    <DataGrid.ContextMenu>
      <ContextMenu>
        <MenuItem x:Name="CmEvtCopy" Header="Copy event details"/>
        <MenuItem x:Name="CmEvtSearch" Header="Search the event on the web"/>
      </ContextMenu>
    </DataGrid.ContextMenu>
    <DataGrid.Columns>
      <DataGridTextColumn Header="Date and time" Binding="{Binding TimeText, Mode=OneWay}" SortMemberPath="Time" Width="155"/>
      <DataGridTextColumn Header="Level" Binding="{Binding Level, Mode=OneWay}" Width="75"/>
      <DataGridTextColumn Header="Category" Binding="{Binding Category, Mode=OneWay}" Width="175"/>
      <DataGridTextColumn Header="Source" Binding="{Binding Source, Mode=OneWay}" Width="230"/>
      <DataGridTextColumn Header="ID" Binding="{Binding Id, Mode=OneWay}" Width="58"/>
      <DataGridTextColumn Header="Description" Binding="{Binding Summary, Mode=OneWay}" Width="*" MinWidth="260"/>
    </DataGrid.Columns>
  </DataGrid>
  <GridSplitter Grid.Row="4" Cursor="SizeNS"/>
  <Border Grid.Row="5" Style="{StaticResource Card}" Margin="0" Padding="0">
    <TextBox x:Name="TxtEventDetail" Style="{StaticResource CodeBox}" TextWrapping="Wrap" BorderThickness="0"
             Text="Loading automatic diagnosis..."/>
  </Border>
</Grid>
"@

Register-WTPage -Id 'Events' -Group 'Diagnostics' -Title 'Events and logs' -Glyph '&#xE81C;' -Xaml $pageXaml -SearchBox 'TxtEvtFilter' `
    -Load { Invoke-WTEventCategory 'Diagnosis' -Background } -Refresh { Invoke-WTEventCategory 'Diagnosis' } -Init {
    foreach ($k in $script:EventCats.Keys) {
        On "EvtCat_$k" { param($s) Invoke-WTEventCategory ([string]$s.Tag) }
    }
    foreach ($n in 'Days1', 'Days7', 'Days30', 'Days90') {
        On $n -EventName 'Checked' { if ($script:AllEvents.Count) { Write-WTLog "Period: $(Get-WTEventDays) days. Pick a category to refresh." } }
    }
    On 'TxtEvtFilter' -EventName 'TextChanged' { Update-WTEventFilter }
    On 'ChkEvtErrorsOnly' { Update-WTEventFilter }
    On 'GridEvents' -EventName 'SelectionChanged' {
        $it = $ui.GridEvents.SelectedItem
        if (-not $it) { return }
        $ui.TxtEventDetail.Text = "{0}   {1}   {2} (ID {3})   Log: {4}`r`n`r`nINTERPRETATION: {5}`r`n`r`n{6}" -f $it.TimeText, $it.Level, $it.Source, $it.Id, $it.Log, $it.Summary, $it.Message
    }
    On 'BtnEvtReport' { if ($script:LastReport) { $ui.TxtEventDetail.Text = $script:LastReport } else { Invoke-WTEventCategory 'Diagnosis' } }
    On 'BtnEvtExport' {
        $rows = @($ui.GridEvents.ItemsSource)
        if (-not $rows.Count) { Show-WTInfo 'No events to export.'; return }
        $file = Join-Path $dataDir ('Report\Events_{0}_{1:yyyyMMdd_HHmm}.csv' -f $env:COMPUTERNAME, (Get-Date))
        $rows | Select-Object TimeText, Level, Category, Source, Id, Log, Summary, Message | Export-Csv -LiteralPath $file -NoTypeInformation -Delimiter ';' -Encoding UTF8
        if ($script:LastReport) { Set-Content -LiteralPath ($file -replace '\.csv$', '_diagnosis.txt') -Value $script:LastReport -Encoding UTF8 }
        Write-WTLog "Events exported to $file" -Level OK
        Open-WTPath $file
    }
    On 'BtnEvtViewer' { Start-Process eventvwr.msc }
    On 'BtnEvtReliability' { Start-Process perfmon.exe -ArgumentList '/rel' }
    On 'BtnEvtDumps' {
        $d = "$env:windir\Minidump"
        if (Test-Path -LiteralPath $d) { Open-WTPath $d } else { Show-WTInfo "The folder $d does not exist: no minidumps saved." }
    }
    On 'CmEvtCopy' { if ($ui.GridEvents.SelectedItem) { Set-WTClipboard $ui.TxtEventDetail.Text } }
    On 'CmEvtSearch' {
        $it = $ui.GridEvents.SelectedItem
        if ($it) { Start-Process ('https://www.google.com/search?q=' + [uri]::EscapeDataString("Event ID $($it.Id) $($it.Source)")) }
    }
}
