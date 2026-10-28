<#
.SYNOPSIS
    WinTech Toolkit - diagnostics, repair and maintenance for Windows 10/11.
.DESCRIPTION
    WPF interface for IT technicians. Relaunches itself as administrator in 64-bit
    Windows PowerShell 5.1. The sections are in UI\Pages, the functions in the module
    Module\WinTechToolkit.psm1 (also usable from the console).
.NOTES
    Ctrl+1..9 sections, F5 refresh the section, Ctrl+F search, Ctrl+L activity log.
#>
#Requires -Version 5.1

# --- Startup: 64-bit Windows PowerShell 5.1, STA, administrator ----------------
$scriptPath = $MyInvocation.MyCommand.Path
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$is32on64 = [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess
$isSTA = [Threading.Thread]::CurrentThread.ApartmentState -eq 'STA'
$isDesktop = $PSVersionTable.PSEdition -ne 'Core'

if (-not ($isAdmin -and $isSTA -and $isDesktop -and -not $is32on64)) {
    $psExe = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ($is32on64) { $psExe = Join-Path $env:windir 'Sysnative\WindowsPowerShell\v1.0\powershell.exe' }
    $argList = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$scriptPath`""
    try {
        if ($isAdmin) { Start-Process -FilePath $psExe -ArgumentList $argList }
        else { Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs }
    } catch {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("Administrator privileges are required.`n`n$($_.Exception.Message)", 'WinTech Toolkit', 'OK', 'Error') | Out-Null
    }
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$modulePath = Join-Path $PSScriptRoot 'Module\WinTechToolkit.psm1'
Import-Module $modulePath -Force -DisableNameChecking
. (Join-Path $PSScriptRoot 'UI\Styles.ps1')

$app = @{ Name = 'WinTech Toolkit'; Version = 'dev'; Repository = '' }
try { (Get-Content (Join-Path $PSScriptRoot 'app.json') -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $app[$_.Name] = $_.Value } } catch { }

$global:WTQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$dataDir = Get-WTDataFolder
$global:WTLogFile = Join-Path $dataDir ('Logs\WinTech_{0}_{1:yyyyMMdd}.log' -f $env:COMPUTERNAME, (Get-Date))

$settingsFile = Join-Path $dataDir 'settings.json'
$settings = @{ Theme = 'Dark'; LogVisible = $true; SidebarExpanded = $null }
if (Test-Path -LiteralPath $settingsFile) {
    try { (Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value } } catch { }
}

$script:Pages = New-Object System.Collections.Generic.List[object]
$script:CurrentJob = $null
$script:TaskQueue = New-Object 'System.Collections.Generic.Queue[object]'
$script:BgJobs = New-Object System.Collections.Generic.List[object]
$script:LogItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$script:UserTargets = @()
$script:UserPanels = New-Object System.Collections.Generic.List[string]

# --- XAML generators used by the pages ---------------------------------------
function X([string]$Text) { [Security.SecurityElement]::Escape($Text) }

function New-Tile {
    param([string]$Name, [string]$Glyph, [string]$Title, [string]$Desc, [switch]$Danger, [int]$Width = 0)
    $icon = if ($Danger) { 'ErrBrush' } else { 'AccentBrush' }
    $w = if ($Width) { " Width=`"$Width`"" } else { '' }
@"
<Button x:Name="$Name" Style="{StaticResource Tile}"$w ToolTip="$(X $Desc)">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="44"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border Width="34" Height="34" CornerRadius="8" Background="{DynamicResource AccentSoftBrush}" VerticalAlignment="Center" HorizontalAlignment="Left">
      <TextBlock Text="$Glyph" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="{DynamicResource $icon}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <StackPanel Grid.Column="1" VerticalAlignment="Center">
      <TextBlock Text="$(X $Title)" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
      <TextBlock Text="$(X $Desc)" FontSize="11.5" Foreground="{DynamicResource SubtleBrush}" TextWrapping="Wrap" MaxHeight="31" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
    </StackPanel>
  </Grid>
</Button>
"@
}

function New-Pill {
    param([string]$Name, [string]$Glyph, [string]$Text, [switch]$Primary, [switch]$Danger, [string]$ToolTip = '', [string]$Tag = '')
    $style = if ($Danger) { 'PillDanger' } elseif ($Primary) { 'PillPrimary' } else { 'Pill' }
    $tt = if ($ToolTip) { " ToolTip=`"$(X $ToolTip)`"" } else { '' }
    $tg = if ($Tag) { " Tag=`"$(X $Tag)`"" } else { '' }
@"
<Button x:Name="$Name" Style="{StaticResource $style}"$tt$tg>
  <StackPanel Orientation="Horizontal">
    <TextBlock Text="$Glyph" FontFamily="Segoe MDL2 Assets" FontSize="12" VerticalAlignment="Center" Margin="0,0,7,0"/>
    <TextBlock Text="$(X $Text)" VerticalAlignment="Center"/>
  </StackPanel>
</Button>
"@
}

function New-PageHeader {
    param([string]$Title, [string]$Subtitle, [string]$Right = '')
@"
<DockPanel>
  <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top">$Right</StackPanel>
  <StackPanel>
    <TextBlock Style="{StaticResource PageTitle}" Text="$(X $Title)"/>
    <TextBlock Style="{StaticResource PageSubtitle}" Text="$(X $Subtitle)"/>
  </StackPanel>
</DockPanel>
"@
}

function Register-WTPage {
    <#
    .SYNOPSIS
        Registers a section: content XAML, Init (event handlers, run after the window is
        created), Load (initial background load) and Refresh (F5).
    #>
    param(
        [Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Group, [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Glyph, [Parameter(Mandatory)][string]$Xaml,
        [scriptblock]$Init, [scriptblock]$Load, [scriptblock]$Refresh, [string]$SearchBox
    )
    $script:Pages.Add([pscustomobject]@{
            Id = $Id; Group = $Group; Title = $Title; Glyph = $Glyph; Xaml = $Xaml
            Init = $Init; Load = $Load; Refresh = $Refresh; SearchBox = $SearchBox; Index = $script:Pages.Count
        })
}

# Panel (WrapPanel) to fill with the list of users on the computer
function Register-WTUserPanel([string]$Name) { $script:UserPanels.Add($Name) }

foreach ($f in Get-ChildItem (Join-Path $PSScriptRoot 'UI\Pages') -Filter '*.ps1' | Sort-Object Name) { . $f.FullName }

# --- Window --------------------------------------------------------------------
$nav = New-Object System.Text.StringBuilder
$group = $null; $g = 0
for ($i = 0; $i -lt $script:Pages.Count; $i++) {
    $p = $script:Pages[$i]
    if ($p.Group -ne $group) {
        [void]$nav.Append("<TextBlock x:Name=`"NavHdr$g`" Style=`"{StaticResource NavHeader}`" Text=`"$(X $p.Group.ToUpper())`"/>")
        [void]$nav.Append("<Border x:Name=`"NavSep$g`" Height=`"1`" Background=`"{DynamicResource LineBrush}`" Margin=`"16,9,16,8`" Visibility=`"Collapsed`"/>")
        $group = $p.Group; $g++
    }
    $key = if ($i -lt 9) { " (Ctrl+$($i + 1))" } else { '' }
    [void]$nav.Append("<RadioButton x:Name=`"Nav_$($p.Id)`" Style=`"{StaticResource NavButton}`" Tag=`"$($p.Glyph)`" Content=`"$(X $p.Title)`" ToolTip=`"$(X $p.Title)$key`"/>")
}
$tabs = ($script:Pages | ForEach-Object { "<TabItem>$($_.Xaml)</TabItem>" }) -join ''

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$(X $app.Name)" Width="1280" Height="820" MinWidth="960" MinHeight="600" WindowStartupLocation="Manual"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display"
        Background="{DynamicResource BgBrush}" Foreground="{DynamicResource TextBrush}">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="48" ResizeBorderThickness="6" GlassFrameThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Window.Resources>
    $(Get-WTBrushXaml 'Dark')
    $(Get-WTStyleXaml)
  </Window.Resources>

  <Border x:Name="RootBorder" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="48"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="28"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="{DynamicResource PanelBrush}">
      <DockPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <CheckBox x:Name="ChkSimulate" Style="{StaticResource Switch}" Content="Simulation" Margin="0,0,12,0" WindowChrome.IsHitTestVisibleInChrome="True"
                    ToolTip="Operations that change the system are only described in the activity log."/>
          <Button x:Name="BtnTheme" Style="{StaticResource CaptionButton}" FontSize="14" ToolTip="Light / dark theme"/>
          <Button x:Name="BtnMin" Style="{StaticResource CaptionButton}" Content="&#xE921;" ToolTip="Minimize"/>
          <Button x:Name="BtnMax" Style="{StaticResource CaptionButton}" Content="&#xE922;" ToolTip="Maximize"/>
          <Button x:Name="BtnClose" Style="{StaticResource CloseButton}" Content="&#xE8BB;" ToolTip="Close"/>
        </StackPanel>
        <Button x:Name="BtnNavToggle" DockPanel.Dock="Left" Style="{StaticResource CaptionButton}" Width="62" FontSize="15" Content="&#xE700;" ToolTip="Collapse / expand the menu"/>
        <Border DockPanel.Dock="Left" Width="28" Height="28" CornerRadius="7" Background="{DynamicResource AccentBrush}" Margin="0,0,12,0" VerticalAlignment="Center">
          <TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="{DynamicResource OnAccentBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel VerticalAlignment="Center">
          <TextBlock FontSize="14" FontWeight="Bold" Text="$(X $app.Name)"/>
          <TextBlock x:Name="TxtHeaderInfo" FontSize="11" Foreground="{DynamicResource SubtleBrush}" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <Border x:Name="SimBanner" Grid.Row="1" Background="{DynamicResource BannerBrush}" Padding="12,5" Visibility="Collapsed">
      <TextBlock Foreground="{DynamicResource BannerTextBrush}" FontWeight="SemiBold" HorizontalAlignment="Center">
        <Run Text="&#xE7BA;" FontFamily="Segoe MDL2 Assets"/><Run Text="  Simulation mode: no changes will be applied to the system"/>
      </TextBlock>
    </Border>

    <Grid Grid.Row="2">
      <Grid.ColumnDefinitions>
        <ColumnDefinition x:Name="SidebarCol" Width="232"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Border Background="{DynamicResource PanelBrush}">
        <DockPanel>
          <StackPanel DockPanel.Dock="Bottom" Margin="0,6,0,8">
            <Border Height="1" Background="{DynamicResource LineBrush}" Margin="16,0,16,6"/>
            <RadioButton x:Name="NavData" Style="{StaticResource NavButton}" GroupName="Links" Tag="&#xE8B7;" Content="Logs and reports" ToolTip="Opens the folder with logs, reports and registry backups"/>
            <RadioButton x:Name="NavAbout" Style="{StaticResource NavButton}" GroupName="Links" Tag="&#xE946;" Content="About" ToolTip="Version and project page"/>
            <TextBlock x:Name="TxtVersion" FontSize="10.5" Foreground="{DynamicResource SubtleBrush}" Margin="22,4,0,0"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel Margin="0,0,0,8">$($nav.ToString())</StackPanel>
          </ScrollViewer>
        </DockPanel>
      </Border>

      <Grid Grid.Column="1">
        <Grid.RowDefinitions>
          <RowDefinition Height="*" MinHeight="220"/>
          <RowDefinition x:Name="SplitRow" Height="6"/>
          <RowDefinition x:Name="LogRow" Height="170"/>
        </Grid.RowDefinitions>
        <Border Background="{DynamicResource BgBrush}" CornerRadius="10,0,0,0">
          <TabControl x:Name="Tabs" Background="Transparent" BorderThickness="0" Padding="0" Foreground="{DynamicResource TextBrush}">
            <TabControl.ItemContainerStyle>
                          <!-- the content inherits its colour from the TabItem (logical parent), not from the TabControl -->
                          <Style TargetType="TabItem">
                            <Setter Property="Visibility" Value="Collapsed"/>
                            <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
                          </Style>
                        </TabControl.ItemContainerStyle>
            $tabs
          </TabControl>
        </Border>
        <GridSplitter Grid.Row="1" Cursor="SizeNS"/>
        <Border x:Name="LogPanel" Grid.Row="2" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0">
          <DockPanel>
            <DockPanel DockPanel.Dock="Top" Margin="14,3,6,2">
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                <Button x:Name="BtnLogCopy" Style="{StaticResource IconButton}" Content="&#xE8C8;" ToolTip="Copy the whole log"/>
                <Button x:Name="BtnLogOpen" Style="{StaticResource IconButton}" Content="&#xE8E5;" ToolTip="Open the log file"/>
                <Button x:Name="BtnLogClear" Style="{StaticResource IconButton}" Content="&#xE894;" ToolTip="Clear the view"/>
                <Button x:Name="BtnLogHide" Style="{StaticResource IconButton}" Content="&#xE70D;" ToolTip="Hide (Ctrl+L)"/>
              </StackPanel>
              <TextBlock Text="ACTIVITY LOG" FontSize="10.5" FontWeight="SemiBold" Foreground="{DynamicResource SubtleBrush}" VerticalAlignment="Center"/>
            </DockPanel>
            <ListBox x:Name="LogList" Background="{DynamicResource LogBgBrush}" BorderThickness="0" SelectionMode="Extended"
                     VirtualizingPanel.IsVirtualizing="True" VirtualizingPanel.VirtualizationMode="Recycling" ScrollViewer.HorizontalScrollBarVisibility="Auto">
              <ListBox.ItemContainerStyle>
                <Style TargetType="ListBoxItem">
                  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem">
                    <Border x:Name="Bd" Background="Transparent" Padding="12,0"><ContentPresenter/></Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource SelectionBrush}"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate></Setter.Value></Setter>
                </Style>
              </ListBox.ItemContainerStyle>
              <ListBox.ItemTemplate>
                <DataTemplate>
                  <TextBlock x:Name="T" Text="{Binding Line, Mode=OneWay}" FontFamily="Consolas" FontSize="12" Foreground="{DynamicResource TextBrush}"/>
                  <DataTemplate.Triggers>
                    <DataTrigger Binding="{Binding Level, Mode=OneWay}" Value="ERROR"><Setter TargetName="T" Property="Foreground" Value="{DynamicResource ErrBrush}"/></DataTrigger>
                    <DataTrigger Binding="{Binding Level, Mode=OneWay}" Value="WARN"><Setter TargetName="T" Property="Foreground" Value="{DynamicResource WarnBrush}"/></DataTrigger>
                    <DataTrigger Binding="{Binding Level, Mode=OneWay}" Value="OK"><Setter TargetName="T" Property="Foreground" Value="{DynamicResource OkBrush}"/></DataTrigger>
                    <DataTrigger Binding="{Binding Level, Mode=OneWay}" Value="TITLE">
                      <Setter TargetName="T" Property="Foreground" Value="{DynamicResource AccentBrush}"/>
                      <Setter TargetName="T" Property="FontWeight" Value="Bold"/>
                    </DataTrigger>
                  </DataTemplate.Triggers>
                </DataTemplate>
              </ListBox.ItemTemplate>
              <ListBox.ContextMenu>
                <ContextMenu>
                  <MenuItem x:Name="CmLogCopySel" Header="Copy selected lines"/>
                  <MenuItem x:Name="CmLogCopyAll" Header="Copy all"/>
                </ContextMenu>
              </ListBox.ContextMenu>
            </ListBox>
          </DockPanel>
        </Border>
      </Grid>
    </Grid>

    <Border Grid.Row="3" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0">
      <DockPanel Margin="14,0">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <TextBlock x:Name="TxtBg" Foreground="{DynamicResource SubtleBrush}" FontSize="12" VerticalAlignment="Center" Margin="0,0,16,0"/>
          <TextBlock x:Name="TxtQueue" Foreground="{DynamicResource WarnBrush}" FontSize="12" VerticalAlignment="Center" Margin="0,0,16,0"/>
          <Button x:Name="BtnToggleLog" Style="{StaticResource LinkButton}" Content="Hide activity log (Ctrl+L)"/>
        </StackPanel>
        <ProgressBar x:Name="PbBusy" Width="140" Height="4" Visibility="Hidden" VerticalAlignment="Center"/>
        <TextBlock x:Name="TxtStatus" Text="Ready" FontSize="12" Margin="10,0" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      </DockPanel>
    </Border>
  </Grid>
  </Border>
</Window>
"@

$window = [Windows.Markup.XamlReader]::Parse($xaml)
$ui = @{}
foreach ($m in [regex]::Matches($xaml, 'x:Name="([^"]+)"')) {
    $el = $window.FindName($m.Groups[1].Value)
    if ($el) { $ui[$m.Groups[1].Value] = $el }
}
# context-menu items cannot always be reached with FindName
foreach ($m in [regex]::Matches($xaml, '<MenuItem x:Name="([^"]+)"')) {
    if ($ui.ContainsKey($m.Groups[1].Value)) { continue }
    foreach ($ctl in @($ui.Values | Where-Object { $_ -is [System.Windows.FrameworkElement] -and $_.ContextMenu })) {
        foreach ($mi in $ctl.ContextMenu.Items) { if ($mi.Name -eq $m.Groups[1].Value) { $ui[$mi.Name] = $mi } }
    }
}
$ui.LogList.ItemsSource = $script:LogItems

# --- Interface functions --------------------------------------------------
function On([string]$Name, [scriptblock]$Handler, [string]$EventName = 'Click') {
    $c = $ui[$Name]
    if (-not $c) { Write-WTLog "Control not found: $Name" -Level Warn; return }
    $c."Add_$EventName"($Handler)
}

function Show-WTConfirm([string]$Message, [string]$Title = 'Confirm') {
    [System.Windows.MessageBox]::Show($window, $Message, $Title, 'YesNo', 'Warning') -eq 'Yes'
}

function Show-WTInfo([string]$Message) {
    [System.Windows.MessageBox]::Show($window, $Message, $app.Name, 'OK', 'Information') | Out-Null
}

function Get-WTSimulate { [bool]$ui.ChkSimulate.IsChecked }

function Format-WTList([object[]]$Items, [scriptblock]$Format, [int]$Max = 20) {
    $lines = @($Items | Select-Object -First $Max | ForEach-Object $Format)
    if ($Items.Count -gt $Max) { $lines += "... and $($Items.Count - $Max) more" }
    $lines -join "`n"
}

function Set-WTClipboard([string]$Text) {
    if (-not $Text) { return }
    try { [System.Windows.Clipboard]::SetText($Text); Write-WTLog 'Copied to the clipboard.' -Level OK } catch { }
}

function Open-WTPath([string]$Path) {
    if (-not $Path) { return }
    if (Test-Path -LiteralPath $Path -PathType Container) { Start-Process explorer.exe -ArgumentList "`"$Path`"" }
    elseif (Test-Path -LiteralPath $Path) { Start-Process explorer.exe -ArgumentList "/select,`"$Path`"" }
    else { Show-WTInfo "Path not found:`n$Path" }
}

function Open-WTRegistryKey([string]$Key) {
    # regedit opens on the last visited key: set it first (-m = new instance)
    $applet = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit'
    if (-not (Test-Path $applet)) { New-Item -Path $applet -Force | Out-Null }
    Set-ItemProperty -Path $applet -Name LastKey -Value "Computer\$Key"
    Start-Process regedit.exe -ArgumentList '-m'
}

function Open-WTFile($Result) {
    $f = @($Result) | Where-Object { $_ -is [string] } | Select-Object -Last 1
    if ($f -and (Test-Path -LiteralPath $f)) { Start-Process $f }
}

function Set-WTTheme([string]$Name) {
    if (-not $script:Themes.ContainsKey($Name)) { $Name = 'Dark' }
    $t = $script:Themes[$Name]
    foreach ($k in $t.Keys) {
        # ::new() and not New-Object: the resource dictionary wants the .NET brush, not a PSObject
        $b = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($t[$k]))
        $b.Freeze()
        $window.Resources[$k] = $b
    }
    $window.Resources[[System.Windows.SystemColors]::ControlBrushKey] = $window.Resources['CardBrush']
    $settings.Theme = $Name
    $ui.BtnTheme.Content = $(if ($Name -eq 'Dark') { [string][char]0xE706 } else { [string][char]0xE708 })
}

function Set-WTLogVisible([bool]$Visible) {
    if ($Visible) {
        $h = [Math]::Max(130, [Math]::Round($window.Height * 0.2))
        $ui.LogRow.Height = New-Object System.Windows.GridLength $h
        $ui.SplitRow.Height = New-Object System.Windows.GridLength 6
        $ui.LogPanel.Visibility = 'Visible'
        $ui.BtnToggleLog.Content = 'Hide activity log (Ctrl+L)'
    } else {
        $ui.LogRow.Height = New-Object System.Windows.GridLength 0
        $ui.SplitRow.Height = New-Object System.Windows.GridLength 0
        $ui.LogPanel.Visibility = 'Collapsed'
        $ui.BtnToggleLog.Content = 'Show activity log (Ctrl+L)'
    }
    $settings.LogVisible = $Visible
}

function Set-WTSidebar([bool]$Expanded) {
    # Collapsed: centred icons only, names stay in the tooltips
    $ui.SidebarCol.Width = New-Object System.Windows.GridLength $(if ($Expanded) { 232 } else { 62 })
    foreach ($p in $script:Pages) { $ui["Nav_$($p.Id)"].Content = $(if ($Expanded) { $p.Title } else { $null }) }
    $ui.NavData.Content = $(if ($Expanded) { 'Logs and reports' } else { $null })
    $ui.NavAbout.Content = $(if ($Expanded) { 'About' } else { $null })
    $ui.TxtVersion.Visibility = $(if ($Expanded) { 'Visible' } else { 'Collapsed' })
    for ($i = 0; $ui.ContainsKey("NavHdr$i"); $i++) {
        $ui["NavHdr$i"].Visibility = $(if ($Expanded) { 'Visible' } else { 'Collapsed' })
        $ui["NavSep$i"].Visibility = $(if ($Expanded -or $i -eq 0) { 'Collapsed' } else { 'Visible' })
    }
    $settings.SidebarExpanded = $Expanded
    Update-WTLayout
}

function Update-WTLayout {
    # Fits the fixed-column grids to the available width
    $w = $window.ActualWidth
    if (-not $w -or [double]::IsNaN($w)) { $w = $window.Width }
    $w -= $ui.SidebarCol.Width.Value
    if ($ui.DashStats) { $ui.DashStats.Columns = $(if ($w -lt 1000) { 2 } else { 4 }) }
    if ($ui.CleanGrid) { $ui.CleanGrid.Columns = $(if ($w -lt 900) { 1 } elseif ($w -lt 1500) { 2 } else { 3 }) }
}

function Set-WTBusy([bool]$Busy, [string]$Text = '') {
    $ui.PbBusy.IsIndeterminate = $Busy
    $ui.PbBusy.Visibility = $(if ($Busy) { 'Visible' } else { 'Hidden' })
    $ui.TxtStatus.Text = $(if ($Busy) { "Running: $Text" } else { 'Ready' })
}

function Update-WTStatusExtras {
    $n = $script:TaskQueue.Count
    $ui.TxtQueue.Text = $(if ($n) { "$n operations queued" } else { '' })
    $b = $script:BgJobs.Count
    $ui.TxtBg.Text = $(if ($b) { "Loading data in the background ($b)..." } else { '' })
}

function Update-WTLogView {
    $line = $null
    $sb = New-Object System.Text.StringBuilder
    $last = $null
    while ($global:WTQueue.TryDequeue([ref]$line)) {
        [void]$sb.AppendLine($line)
        $level = 'INFO'
        if ($line -match '^\d\d:\d\d:\d\d \[(\S+)\s*\] (.*)$') {
            $level = $Matches[1]
            if ($Matches[2].StartsWith('===')) { $level = 'TITLE' }
        }
        $last = [pscustomobject]@{ Line = $line; Level = $level }
        $script:LogItems.Add($last)
    }
    if (-not $last) { return }
    while ($script:LogItems.Count -gt 5000) { $script:LogItems.RemoveAt(0) }
    $ui.LogList.ScrollIntoView($last)
    try { [IO.File]::AppendAllText($global:WTLogFile, $sb.ToString(), [Text.Encoding]::UTF8) } catch { }
}

# --- Esecuzione delle operazioni -------------------------------------------------
# A runspace pool with the module already loaded: "foreground" operations run one at a
# time (the others wait in a queue), background loads run in parallel.
$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
try { $iss.ExecutionPolicy = 'Bypass' } catch { }
$iss.ImportPSModule([string[]]@($modulePath))
$iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('WTQueue', $global:WTQueue, '')))
$iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('WTLogFile', $global:WTLogFile, '')))
$script:Pool = [runspacefactory]::CreateRunspacePool(1, 5, $iss, $Host)
$script:Pool.ApartmentState = 'STA'
$script:Pool.Open()

function Invoke-WTTaskNow($Task) {
    $ps = [powershell]::Create()
    $ps.RunspacePool = $script:Pool
    [void]$ps.AddScript($Task.Script.ToString())
    if ($Task.Parameters.Count) { [void]$ps.AddParameters($Task.Parameters) }
    $job = [pscustomobject]@{
        PS = $ps; Handle = $null; Title = $Task.Title; OnComplete = $Task.OnComplete; Start = Get-Date; Background = $Task.Background
    }
    if ($Task.Background) {
        $script:BgJobs.Add($job)
    } else {
        Write-WTLog "=== Start: $($Task.Title)$(if (Get-WTSimulate) { ' [SIMULATION]' }) ==="
        $script:CurrentJob = $job
        Set-WTBusy $true $Task.Title
    }
    $job.Handle = $ps.BeginInvoke()
    Update-WTStatusExtras
}

function Start-WTTask {
    <#
    .SYNOPSIS
        Runs a scriptblock in the pool (with the module loaded); OnComplete receives the
        output on the UI thread. -Background: data loading, does not block and never asks anything.
        Otherwise, if an operation is already running, the new one is queued.
    #>
    param(
        [Parameter(Mandatory, Position = 0)][string]$Title,
        [Parameter(Mandatory, Position = 1)][scriptblock]$Script,
        [hashtable]$Parameters = @{},
        [scriptblock]$OnComplete,
        [switch]$Background,
        [switch]$Queue
    )
    $task = [pscustomobject]@{ Title = $Title; Script = $Script; Parameters = $Parameters; OnComplete = $OnComplete; Background = [bool]$Background }
    if (-not $Background -and $script:CurrentJob) {
        if (-not $Queue -and -not (Show-WTConfirm "Currently running: $($script:CurrentJob.Title)`n`nQueue '$Title' to run when it finishes?" 'Operation in progress')) { return }
        $script:TaskQueue.Enqueue($task)
        Write-WTLog "Queued: $Title"
        Update-WTStatusExtras
        return
    }
    Invoke-WTTaskNow $task
}

function Complete-WTJob($Job) {
    $result = $null
    try { $result = $Job.PS.EndInvoke($Job.Handle) }
    catch { Write-WTLog "$($Job.Title): $($_.Exception.GetBaseException().Message)" -Level Error }
    foreach ($e in $Job.PS.Streams.Error) { Write-WTLog "$($Job.Title): $e" -Level $(if ($Job.Background) { 'Warn' } else { 'Error' }) }
    $Job.PS.Dispose()
    if (-not $Job.Background) {
        Write-WTLog ('=== Done: {0} (duration {1:hh\:mm\:ss}) ===' -f $Job.Title, ((Get-Date) - $Job.Start))
    }
    Update-WTLogView
    if ($Job.OnComplete) {
        try { & $Job.OnComplete $result }
        catch { Write-WTLog "Updating the interface ($($Job.Title)):$($_.Exception.Message)" -Level Error }
    }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
        Update-WTLogView
        foreach ($j in @($script:BgJobs | Where-Object { $_.Handle.IsCompleted })) {
            [void]$script:BgJobs.Remove($j)
            Complete-WTJob $j
        }
        $job = $script:CurrentJob
        if ($job) {
            $ui.TxtStatus.Text = 'Running: {0}  ({1:hh\:mm\:ss})' -f $job.Title, ((Get-Date) - $job.Start)
            if ($job.Handle.IsCompleted) {
                $script:CurrentJob = $null
                Set-WTBusy $false
                Complete-WTJob $job
                if (-not $script:CurrentJob -and $script:TaskQueue.Count) { Invoke-WTTaskNow $script:TaskQueue.Dequeue() }
            }
        }
        Update-WTStatusExtras
    })

# --- Target users (shared by several sections) -----------------------------------
function Update-WTUserTargets {
    Start-WTTask 'Computer users' { Get-WTUserTargets } -Background -OnComplete {
        param($r)
        $script:UserTargets = @($r | Where-Object { $_ -and $_.PSObject.Properties['UserName'] })
        foreach ($p in $script:UserPanels) { Show-WTUserChips $p }
    }
}

function Show-WTUserChips([string]$PanelName) {
    $panel = $ui[$PanelName]
    if (-not $panel) { return }
    $panel.Children.Clear()
    if (-not $script:UserTargets.Count) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = 'No user profile found.'
        [void]$panel.Children.Add($tb)
        return
    }
    $first = $true
    foreach ($u in $script:UserTargets) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = $window.FindResource('Chip')
        $rb.GroupName = $PanelName
        $rb.Content = $(if ($u.LoggedOn) { "$([char]0x25CF)  $($u.UserName)" } else { $u.UserName })
        $rb.ToolTip = $(if ($u.LoggedOn) { "Signed in - $($u.ProfilePath)" } else { "Not signed in - $($u.ProfilePath)" })
        $rb.Tag = $u
        if ($first) { $rb.IsChecked = $true; $first = $false }
        [void]$panel.Children.Add($rb)
    }
}

function Get-WTSelectedUser([string]$PanelName, [switch]$RequireLoggedOn) {
    $rb = @($ui[$PanelName].Children | Where-Object { $_ -is [System.Windows.Controls.RadioButton] -and $_.IsChecked }) | Select-Object -First 1
    if (-not $rb) { Show-WTInfo 'Select a user.'; return $null }
    $u = $rb.Tag
    if ($RequireLoggedOn -and -not $u.LoggedOn) {
        Show-WTInfo "$($u.UserName) has no open session: this operation requires the user to be signed in to the PC."
        return $null
    }
    $u
}

function Select-WTPage([int]$Index) {
    if ($Index -ge 0 -and $Index -lt $script:Pages.Count) { $ui["Nav_$($script:Pages[$Index].Id)"].IsChecked = $true }
}

function Select-WTPageById([string]$Id) {
    $p = $script:Pages | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($p) { Select-WTPage $p.Index }
}

# --- General handlers ------------------------------------------------------------
On 'BtnMin' { $window.WindowState = 'Minimized' }
On 'BtnMax' { $window.WindowState = $(if ($window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }) }
On 'BtnClose' { $window.Close() }
On 'BtnTheme' { Set-WTTheme $(if ($settings.Theme -eq 'Dark') { 'Light' } else { 'Dark' }) }
On 'BtnNavToggle' { Set-WTSidebar (-not [bool]$settings.SidebarExpanded) }
$window.Add_StateChanged({
        # with WindowChrome a maximized window overflows the screen by a few pixels
        $ui.RootBorder.Margin = New-Object System.Windows.Thickness $(if ($window.WindowState -eq 'Maximized') { 7 } else { 0 })
        $ui.BtnMax.Content = $(if ($window.WindowState -eq 'Maximized') { [string][char]0xE923 } else { [string][char]0xE922 })
    })
$window.Add_SizeChanged({ Update-WTLayout })

foreach ($p in $script:Pages) {
    On "Nav_$($p.Id)" -EventName 'Checked' {
        param($s)
        $page = $script:Pages | Where-Object { "Nav_$($_.Id)" -eq $s.Name } | Select-Object -First 1
        $ui.Tabs.SelectedIndex = $page.Index
    }
}
On 'NavData' { param($s) $s.IsChecked = $false; Start-Process explorer.exe -ArgumentList "`"$dataDir`"" }
On 'NavAbout' {
    param($s)
    $s.IsChecked = $false
    $url = if ($app.Repository -and $app.Repository -notlike 'OWNER/*') { "https://github.com/$($app.Repository)" } else { '' }
    $pkg = if ($env:WTK_PACKAGE) { "`nPackage: $env:WTK_PACKAGE" } else { '' }
    $msg = "$($app.Name) $($app.Version)$pkg`n`nDiagnostics, repair and maintenance for Windows 10/11.`n`nData and logs: $dataDir"
    if ($url) {
        if ([System.Windows.MessageBox]::Show($window, "$msg`n`nOpen the project page?`n$url", $app.Name, 'YesNo', 'Information') -eq 'Yes') { Start-Process $url }
    } else { Show-WTInfo $msg }
}
On 'ChkSimulate' {
    $on = Get-WTSimulate
    $ui.SimBanner.Visibility = $(if ($on) { 'Visible' } else { 'Collapsed' })
    if ($on) { Write-WTLog 'Simulation mode on: no changes will be applied.' -Level Warn } else { Write-WTLog 'Simulation mode off.' }
}
On 'BtnToggleLog' { Set-WTLogVisible (-not [bool]$settings.LogVisible) }
On 'BtnLogHide' { Set-WTLogVisible $false }
On 'BtnLogClear' { $script:LogItems.Clear() }
On 'BtnLogOpen' { if (Test-Path -LiteralPath $global:WTLogFile) { Start-Process notepad.exe -ArgumentList "`"$global:WTLogFile`"" } }
On 'BtnLogCopy' { Set-WTClipboard (($script:LogItems | ForEach-Object { $_.Line }) -join "`r`n") }
On 'CmLogCopyAll' { Set-WTClipboard (($script:LogItems | ForEach-Object { $_.Line }) -join "`r`n") }
On 'CmLogCopySel' { Set-WTClipboard ((@($ui.LogList.SelectedItems) | ForEach-Object { $_.Line }) -join "`r`n") }

$window.Add_PreviewKeyDown({
        param($s, $e)
        $ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
        $page = $script:Pages[$ui.Tabs.SelectedIndex]
        if ($ctrl -and $e.Key -ge [System.Windows.Input.Key]::D1 -and $e.Key -le [System.Windows.Input.Key]::D9) {
            Select-WTPage ([int]$e.Key - [int][System.Windows.Input.Key]::D1); $e.Handled = $true; return
        }
        if ($e.Key -eq [System.Windows.Input.Key]::F5) { if ($page.Refresh) { . $page.Refresh }; $e.Handled = $true; return }
        if ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::L) { Set-WTLogVisible (-not [bool]$settings.LogVisible); $e.Handled = $true; return }
        if ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::F -and $page.SearchBox) { [void]$ui[$page.SearchBox].Focus(); $e.Handled = $true }
    })

foreach ($p in $script:Pages) { if ($p.Init) { . $p.Init } }

$window.Add_ContentRendered({
        Write-WTLog "$($app.Name) $($app.Version) - session started by $($identity.Name) on $env:COMPUTERNAME"
        Update-WTUserTargets
        foreach ($p in $script:Pages) { if ($p.Load) { . $p.Load } }
    })

$window.Add_Closing({
        param($s, $e)
        if ($script:CurrentJob) {
            $msg = "An operation is still running: $($script:CurrentJob.Title).`nClose anyway? External processes (e.g. SFC/DISM) may keep running in the background."
            if (-not (Show-WTConfirm $msg)) { $e.Cancel = $true; return }
        }
        $script:TaskQueue.Clear()
        Write-WTLog 'Session ended.'
        Update-WTLogView
        $timer.Stop()
        Remove-Item -Path (Join-Path $dataDir 'Temp\*') -Recurse -Force -ErrorAction SilentlyContinue
        try { $settings | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8 } catch { }
    })

# --- Initial size: proportional to the screen ------------------------------------
$wa = [System.Windows.SystemParameters]::WorkArea
$w = [Math]::Min([Math]::Max($wa.Width * 0.86, 1080), 1720)
$h = [Math]::Min([Math]::Max($wa.Height * 0.9, 680), 1060)
$window.Width = [Math]::Min($w, $wa.Width)
$window.Height = [Math]::Min($h, $wa.Height)
$window.Left = $wa.Left + ($wa.Width - $window.Width) / 2
$window.Top = $wa.Top + ($wa.Height - $window.Height) / 2
if ($wa.Width -lt 1100 -or $wa.Height -lt 650) { $window.WindowState = 'Maximized' }

$ui.TxtHeaderInfo.Text = "$env:COMPUTERNAME  ·  running as $($identity.Name)"
$ui.TxtVersion.Text = "Version $($app.Version)"
Set-WTTheme $settings.Theme
Set-WTLogVisible ([bool]$settings.LogVisible)
Set-WTSidebar $(if ($null -eq $settings.SidebarExpanded) { $wa.Width -ge 1400 } else { [bool]$settings.SidebarExpanded })
$ui.Nav_Dashboard.IsChecked = $true
$timer.Start()
try {
    [void]$window.ShowDialog()
} catch {
    [System.Windows.MessageBox]::Show("Unexpected error:`n$($_.Exception.Message)", $app.Name, 'OK', 'Error') | Out-Null
} finally {
    $script:Pool.Close()
    $script:Pool.Dispose()
}
