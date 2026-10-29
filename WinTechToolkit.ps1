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
. (Join-Path $PSScriptRoot 'UI\Window.ps1')

$app = @{ Name = 'WinTech Toolkit'; Version = 'dev'; Repository = '' }
try { (Get-Content (Join-Path $PSScriptRoot 'app.json') -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $app[$_.Name] = $_.Value } } catch { }

$global:WTQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
# programs started by the operations (process id -> task id), terminated by the Stop button
$global:WTProcesses = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[int,string]'
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
    # in a WrapPanel the width is set by Initialize-WTTileRows
    param([string]$Name, [string]$Glyph, [string]$Title, [string]$Desc, [switch]$Danger)
    $icon = if ($Danger) { 'ErrBrush' } else { 'AccentBrush' }
@"
<Button x:Name="$Name" Style="{StaticResource Tile}" ToolTip="$(X $Desc)">
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
        <Border x:Name="AppLogo" DockPanel.Dock="Left" Width="28" Height="28" CornerRadius="7" Background="{DynamicResource AccentBrush}" Margin="0,0,12,0" VerticalAlignment="Center">
          <TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="{DynamicResource OnAccentBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel x:Name="TitleArea" VerticalAlignment="Center" Margin="0,0,12,0">
          <StackPanel Orientation="Horizontal">
            <TextBlock FontSize="14" FontWeight="Bold" Text="$(X $app.Name)" VerticalAlignment="Center"/>
            <Border x:Name="TitleBadge" Background="{DynamicResource AccentSoftBrush}" CornerRadius="4" Padding="5,0,5,1" Margin="8,1,0,0" VerticalAlignment="Center" Visibility="Collapsed">
              <TextBlock x:Name="TxtTitleBadge" FontSize="9.5" FontWeight="Bold" Foreground="{DynamicResource AccentBrush}"/>
            </Border>
          </StackPanel>
          <TextBlock x:Name="TxtHeaderInfo" FontSize="11" Foreground="{DynamicResource SubtleBrush}" TextTrimming="CharacterEllipsis" Margin="0,1,0,0"/>
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
        <ProgressBar x:Name="PbBusy" Width="140" Height="4" Margin="0,0,10,0" Visibility="Collapsed" VerticalAlignment="Center"/>
        <Button x:Name="BtnStop" Style="{StaticResource LinkButton}" Margin="0,0,12,0" Visibility="Collapsed" ToolTip="Stop the running operation">
          <TextBlock><Run Text="&#xE71A;" FontFamily="Segoe MDL2 Assets" FontSize="10"/><Run Text=" Stop"/></TextBlock>
        </Button>
        <TextBlock x:Name="TxtStatus" Text="Ready" FontSize="12" Margin="0,0,10,0" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      </DockPanel>
    </Border>

    <Grid x:Name="AboutOverlay" Grid.Row="1" Grid.RowSpan="3" Background="{DynamicResource OverlayBrush}" Visibility="Collapsed">
      <Grid Width="560" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="24">
        <!-- shadow on a separate layer: an effect on the card would blur its text -->
        <Border Background="{DynamicResource CardBrush}" CornerRadius="12">
          <Border.Effect><DropShadowEffect BlurRadius="32" ShadowDepth="8" Direction="270" Opacity="0.4" Color="Black"/></Border.Effect>
        </Border>
        <Border Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12">
          <StackPanel>
            <Border Background="{DynamicResource AccentSoftBrush}" CornerRadius="11,11,0,0" Padding="26,24,14,22">
              <DockPanel>
                <Button x:Name="BtnAboutClose" DockPanel.Dock="Right" Style="{StaticResource IconButton}" Content="&#xE8BB;" VerticalAlignment="Top" ToolTip="Close (Esc)"/>
                <Border Width="64" Height="64" CornerRadius="16" Background="{DynamicResource AccentBrush}" Margin="0,0,20,0" VerticalAlignment="Center">
                  <TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" FontSize="30" Foreground="{DynamicResource OnAccentBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="$(X $app.Name)" FontSize="24" FontWeight="Bold"/>
                  <StackPanel Orientation="Horizontal" Margin="0,3,0,0">
                    <TextBlock x:Name="TxtAboutVersion" Foreground="{DynamicResource SubtleBrush}" VerticalAlignment="Center"/>
                    <Border x:Name="AboutBadge" Background="{DynamicResource AccentBrush}" CornerRadius="4" Padding="6,0,6,1" Margin="8,0,0,0" VerticalAlignment="Center" Visibility="Collapsed">
                      <TextBlock x:Name="TxtAboutBadge" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource OnAccentBrush}"/>
                    </Border>
                  </StackPanel>
                  <TextBlock Text="Diagnostics, repair and maintenance for Windows 10/11." Margin="0,8,0,0" TextWrapping="Wrap"/>
                </StackPanel>
              </DockPanel>
            </Border>
            <Grid Margin="26,18,26,6">
              <Grid.ColumnDefinitions><ColumnDefinition Width="120"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>
              <Grid.Resources>
                <Style TargetType="TextBlock"><Setter Property="Margin" Value="0,0,0,8"/><Setter Property="TextTrimming" Value="CharacterEllipsis"/></Style>
              </Grid.Resources>
              <TextBlock x:Name="LblAboutPackage" Grid.Row="0" Text="Package" Foreground="{DynamicResource SubtleBrush}"/>
              <TextBlock x:Name="TxtAboutPackage" Grid.Row="0" Grid.Column="1"/>
              <TextBlock Grid.Row="1" Text="Windows" Foreground="{DynamicResource SubtleBrush}"/>
              <TextBlock x:Name="TxtAboutWindows" Grid.Row="1" Grid.Column="1"/>
              <TextBlock Grid.Row="2" Text="PowerShell" Foreground="{DynamicResource SubtleBrush}"/>
              <TextBlock x:Name="TxtAboutPs" Grid.Row="2" Grid.Column="1"/>
              <TextBlock Grid.Row="3" Text="Running as" Foreground="{DynamicResource SubtleBrush}"/>
              <TextBlock x:Name="TxtAboutUser" Grid.Row="3" Grid.Column="1"/>
              <TextBlock Grid.Row="4" Text="Data and logs" Foreground="{DynamicResource SubtleBrush}"/>
              <Button x:Name="BtnAboutData" Grid.Row="4" Grid.Column="1" Style="{StaticResource LinkButton}" FontSize="13" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="0,0,0,8" ToolTip="Open the folder"/>
              <TextBlock Grid.Row="5" Text="Today's log" Foreground="{DynamicResource SubtleBrush}"/>
              <Button x:Name="BtnAboutLog" Grid.Row="5" Grid.Column="1" Style="{StaticResource LinkButton}" FontSize="13" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="0,0,0,8" ToolTip="Open in Notepad"/>
            </Grid>
            <WrapPanel Margin="26,4,20,14">
              $(New-Pill -Name 'BtnAboutProject' -Glyph '&#xE774;' -Text 'Project page' -Primary)
              $(New-Pill -Name 'BtnAboutIssue' -Glyph '&#xED15;' -Text 'Report a problem' -ToolTip 'Opens a new issue on GitHub; attach the copied info')
              $(New-Pill -Name 'BtnAboutReleases' -Glyph '&#xE896;' -Text 'Releases')
              $(New-Pill -Name 'BtnAboutCopy' -Glyph '&#xE8C8;' -Text 'Copy info' -ToolTip 'Version, Windows and PowerShell, for a bug report')
            </WrapPanel>
            <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="26,10,26,12">
              <DockPanel>
                <TextBlock DockPanel.Dock="Right" Text="MIT License" FontSize="11.5" Foreground="{DynamicResource SubtleBrush}"/>
                <TextBlock x:Name="TxtAboutCopyright" FontSize="11.5" Foreground="{DynamicResource SubtleBrush}"/>
              </DockPanel>
            </Border>
          </StackPanel>
        </Border>
      </Grid>
    </Grid>

    <!-- confirmations and messages (Show-WTConfirm, Show-WTInfo) -->
    <Grid x:Name="DialogOverlay" Grid.Row="1" Grid.RowSpan="3" Panel.ZIndex="2" Background="{DynamicResource OverlayBrush}" Visibility="Collapsed">
      <Grid MinWidth="420" MaxWidth="620" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="24">
        <Border Background="{DynamicResource CardBrush}" CornerRadius="12">
          <Border.Effect><DropShadowEffect BlurRadius="32" ShadowDepth="8" Direction="270" Opacity="0.4" Color="Black"/></Border.Effect>
        </Border>
        <Border Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12">
          <DockPanel>
            <Border DockPanel.Dock="Bottom" Background="{DynamicResource PanelBrush}" CornerRadius="0,0,11,11" Padding="20,12">
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="BtnDlgYes" Style="{StaticResource PillPrimary}" MinWidth="96" Margin="0" Content="Yes"/>
                <Button x:Name="BtnDlgNo" Style="{StaticResource Pill}" MinWidth="96" Margin="8,0,0,0" Content="No"/>
              </StackPanel>
            </Border>
            <DockPanel Margin="22,20,24,20">
              <Grid DockPanel.Dock="Left" Width="38" Height="38" VerticalAlignment="Top" Margin="0,0,16,0">
                <Ellipse x:Name="DlgIconBg" Opacity="0.18"/>
                <TextBlock x:Name="DlgIcon" FontFamily="Segoe MDL2 Assets" FontSize="17" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Grid>
              <StackPanel>
                <TextBlock x:Name="TxtDlgTitle" FontSize="16" FontWeight="SemiBold" Margin="0,8,0,8" TextWrapping="Wrap"/>
                <ScrollViewer MaxHeight="420" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                  <TextBox x:Name="TxtDlgMessage" IsReadOnly="True" TextWrapping="Wrap" Background="Transparent" BorderThickness="0" Padding="0" Margin="-2,0,0,0"
                           Foreground="{DynamicResource TextBrush}" FontSize="13">
                    <TextBox.Template><ControlTemplate TargetType="TextBox"><ScrollViewer x:Name="PART_ContentHost" Focusable="False"/></ControlTemplate></TextBox.Template>
                  </TextBox>
                </ScrollViewer>
              </StackPanel>
            </DockPanel>
          </DockPanel>
        </Border>
      </Grid>
    </Grid>
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

function Show-WTDialog {
    <#
    .SYNOPSIS
        Modal message in the window theme. Returns $true for Yes/OK.
        Waits in a nested dispatcher frame, like MessageBox: the timer keeps running.
    #>
    param([string]$Message, [string]$Title, [ValidateSet('Info', 'Warning')][string]$Kind = 'Info', [switch]$YesNo)
    $icon = if ($Kind -eq 'Warning') { 'WarnBrush' } else { 'AccentBrush' }
    $buttons = if ($YesNo) { 'YesNo' } else { 'OK' }
    $image = if ($Kind -eq 'Warning') { 'Warning' } else { 'Information' }
    # a dialog already open (e.g. an operation ending during a confirmation) or no window yet
    if ($script:DialogFrame -or -not $window.IsVisible) {
        return ([System.Windows.MessageBox]::Show($window, $Message, $Title, $buttons, $image) -in 'Yes', 'OK')
    }
    $ui.TxtDlgTitle.Text = $Title
    $ui.TxtDlgMessage.Text = $Message
    $ui.TxtDlgMessage.ScrollToHome()
    $ui.DlgIcon.Text = $(if ($Kind -eq 'Warning') { [string][char]0xE7BA } else { [string][char]0xE946 })
    $ui.DlgIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $icon)
    $ui.DlgIconBg.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $icon)
    $ui.BtnDlgYes.Content = $(if ($YesNo) { 'Yes' } else { 'OK' })
    $ui.BtnDlgNo.Visibility = $(if ($YesNo) { 'Visible' } else { 'Collapsed' })

    $focused = [System.Windows.Input.Keyboard]::FocusedElement
    $script:DialogResult = $false
    $script:DialogFrame = New-Object System.Windows.Threading.DispatcherFrame
    $ui.DialogOverlay.Visibility = 'Visible'
    $ui.DialogOverlay.BeginAnimation([System.Windows.UIElement]::OpacityProperty,
        (New-Object System.Windows.Media.Animation.DoubleAnimation 0, 1, ([System.Windows.Duration][TimeSpan]::FromMilliseconds(120))))
    [void]$ui.BtnDlgYes.Focus()
    $pushed = $false
    try { [System.Windows.Threading.Dispatcher]::PushFrame($script:DialogFrame); $pushed = $true }
    catch { }   # dispatcher suspended (e.g. while the window is closing)
    finally {
        $script:DialogFrame = $null
        $ui.DialogOverlay.Visibility = 'Collapsed'
        if ($focused -is [System.Windows.UIElement] -and $focused.IsVisible) { [void]$focused.Focus() }
    }
    if (-not $pushed) { return ([System.Windows.MessageBox]::Show($window, $Message, $Title, $buttons, $image) -in 'Yes', 'OK') }
    $script:DialogResult
}

function Close-WTDialog([bool]$Result) {
    if (-not $script:DialogFrame) { return }
    $script:DialogResult = $Result
    $script:DialogFrame.Continue = $false
}

function Show-WTConfirm([string]$Message, [string]$Title = 'Confirm') {
    Show-WTDialog -Message $Message -Title $Title -Kind Warning -YesNo
}

function Show-WTInfo([string]$Message) {
    [void](Show-WTDialog -Message $Message -Title $app.Name)
}

function Write-WTCrash($Exception) {
    # Unexpected error in the interface: saved to Logs\Crash_*.txt, the window stays open.
    # At most one message every 10 seconds, in case the error repeats (e.g. in the timer).
    try {
        $err = $Exception
        while ($err -is [System.Management.Automation.MethodInvocationException] -and $err.InnerException) { $err = $err.InnerException }
        $where = ''
        if ($err -is [System.Management.Automation.IContainsErrorRecord] -and $err.ErrorRecord.InvocationInfo) {
            $where = $err.ErrorRecord.InvocationInfo.PositionMessage
        }
        Write-WTLog "Unexpected error in the interface: $($err.Message)" -Level Error
        $file = Join-Path $dataDir ('Logs\Crash_{0}_{1:yyyyMMdd_HHmmss}.txt' -f $env:COMPUTERNAME, (Get-Date))
        $text = @("$($app.Name) $($app.Version)", "Windows: $(Get-WTWindowsText)", "PowerShell: $($PSVersionTable.PSVersion)", '',
            $err.Message, '', $where, '', $Exception.ToString()) -join "`r`n"
        [IO.File]::WriteAllText($file, $text, [Text.Encoding]::UTF8)
        Update-WTLogView
        if ($script:LastCrashShown -and ((Get-Date) - $script:LastCrashShown).TotalSeconds -lt 10) { return }
        $script:LastCrashShown = Get-Date
        $script:CrashMessage = "An unexpected error occurred in the interface:`n$($err.Message)`n`nYou can keep working. The details were saved to:`n$file`n`nIf it happens again, please report it with this file."
        # shown after the dispatcher has finished handling the exception
        [void]$window.Dispatcher.BeginInvoke([Action]{ Show-WTInfo $script:CrashMessage })
    } catch { }
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
    if ($script:DwmFrame) { [WTWindowHelper]::SetBorderColor($script:Hwnd, $window.Resources['LineBrush'].Color) }
}

function Update-WTWindowFrame {
    $max = $window.WindowState -eq 'Maximized'
    # with WindowChrome a maximized window overflows the screen by the resize frame
    $ui.RootBorder.Margin = $(if ($max) { [WTWindowHelper]::MaximizedInset($window) } else { New-Object System.Windows.Thickness 0 })
    # on Windows 11 the border is drawn by DWM, together with the rounded corners
    $ui.RootBorder.BorderThickness = New-Object System.Windows.Thickness $(if ($max -or $script:DwmFrame) { 0 } else { 1 })
    $ui.BtnMax.Content = $(if ($max) { [string][char]0xE923 } else { [string][char]0xE922 })
    $ui.BtnMax.ToolTip = $(if ($max) { 'Restore' } else { 'Maximize' })
}

function Format-WTAccount([string]$Name) {
    # local accounts without the computer name
    if ($Name -like "$env:COMPUTERNAME\*") { return $Name.Substring($env:COMPUTERNAME.Length + 1) }
    $Name
}

function Set-WTHeaderInfo([string]$Domain, [string]$User, [switch]$Loaded) {
    $me = Format-WTAccount $identity.Name
    $parts = @($env:COMPUTERNAME)
    $tip = @("Computer: $env:COMPUTERNAME")
    if ($Domain) { $parts += ($Domain -replace '^Workgroup ', ''); $tip += "Domain: $Domain" }
    if ($Loaded) {
        $u = if ($User) { Format-WTAccount $User } else { '' }
        $parts += $(if ($u) { "signed in: $u" } else { 'nobody signed in' })
        $tip += "Signed-in user: $(if ($User) { $User } else { 'none' })"
        # the toolkit often runs with another administrator account: show it only then
        if ($u -ne $me) { $parts += "running as $me" }
    } else {
        $parts += "running as $me"
    }
    $tip += "Toolkit running as: $($identity.Name)"
    $ui.TxtHeaderInfo.Text = $parts -join '  ·  '
    $ui.TxtHeaderInfo.ToolTip = $tip -join "`n"
}

function Initialize-WTTileRows {
    # Rows of tiles share the width equally, so they line up with the cards around them
    $tileStyle = $window.FindResource('Tile')
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($window)
    while ($stack.Count) {
        $el = $stack.Pop()
        if ($el -is [System.Windows.Controls.WrapPanel] -and $el.Children.Count -and
            -not @($el.Children | Where-Object { -not ($_ -is [System.Windows.Controls.Button] -and $_.Style -eq $tileStyle) }).Count) {
            # the right margin of the last tile goes outside the panel
            $m = $el.Margin
            $el.Margin = New-Object System.Windows.Thickness $m.Left, $m.Top, ($m.Right - 10), $m.Bottom
            $el.Add_SizeChanged({ param($s) Set-WTTileWidth $s })
            continue
        }
        foreach ($c in [System.Windows.LogicalTreeHelper]::GetChildren($el)) {
            if ($c -is [System.Windows.DependencyObject]) { $stack.Push($c) }
        }
    }
}

function Set-WTTileWidth($Panel) {
    $w = $Panel.ActualWidth
    if ($w -le 0) { return }
    $cols = [Math]::Max(1, [Math]::Floor($w / 270))
    $tileWidth = [Math]::Floor($w / $cols) - 10
    foreach ($t in $Panel.Children) { if ($t.Width -ne $tileWidth) { $t.Width = $tileWidth } }
}

function Get-WTWindowsText {
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        # ProductName still says "Windows 10" on Windows 11
        $name = "$($cv.ProductName)"
        if ([int]$cv.CurrentBuildNumber -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }
        '{0} {1} (build {2}.{3})' -f $name, $cv.DisplayVersion, $cv.CurrentBuildNumber, $cv.UBR
    } catch { [Environment]::OSVersion.VersionString }
}

function Get-WTAboutText {
    $lines = @("$($app.Name) $($app.Version)")
    if ($env:WTK_PACKAGE) { $lines += "Package: $env:WTK_PACKAGE" }
    $lines += "Windows: $script:WindowsText"
    $lines += "PowerShell: $($PSVersionTable.PSVersion) ($([IntPtr]::Size * 8)-bit)"
    $lines += "Domain-joined: $(if ((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain) { 'yes' } else { 'no' })"
    $lines -join "`r`n"
}

function Show-WTAbout {
    if (-not $script:WindowsText) { $script:WindowsText = Get-WTWindowsText }
    $ui.TxtAboutVersion.Text = "Version $($app.Version)"
    $ui.LblAboutPackage.Visibility = $(if ($env:WTK_PACKAGE) { 'Visible' } else { 'Collapsed' })
    $ui.TxtAboutPackage.Visibility = $ui.LblAboutPackage.Visibility
    $ui.TxtAboutPackage.Text = "$env:WTK_PACKAGE"
    $ui.TxtAboutWindows.Text = $script:WindowsText
    $ui.TxtAboutPs.Text = "$($PSVersionTable.PSVersion) ($([IntPtr]::Size * 8)-bit)"
    $ui.TxtAboutUser.Text = "$($identity.Name) (administrator)"
    $ui.BtnAboutData.Content = $dataDir
    $ui.BtnAboutLog.Content = Split-Path $global:WTLogFile -Leaf
    foreach ($b in 'BtnAboutProject', 'BtnAboutIssue', 'BtnAboutReleases') { $ui[$b].IsEnabled = [bool]$script:RepoUrl }
    $ui.AboutOverlay.Opacity = 0
    $ui.AboutOverlay.Visibility = 'Visible'
    $ui.AboutOverlay.BeginAnimation([System.Windows.UIElement]::OpacityProperty,
        (New-Object System.Windows.Media.Animation.DoubleAnimation 0, 1, ([System.Windows.Duration][TimeSpan]::FromMilliseconds(140))))
    [void]$ui.BtnAboutClose.Focus()
}

function Hide-WTAbout {
    $ui.AboutOverlay.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    $ui.AboutOverlay.Visibility = 'Collapsed'
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
    $ui.PbBusy.Visibility = $(if ($Busy) { 'Visible' } else { 'Collapsed' })
    $ui.BtnStop.Visibility = $ui.PbBusy.Visibility
    $ui.BtnStop.IsEnabled = $true
    $window.TaskbarItemInfo.ProgressState = $(if ($Busy) { 'Indeterminate' } else { 'None' })
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
$iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('WTProcesses', $global:WTProcesses, '')))
$script:Pool = [runspacefactory]::CreateRunspacePool(1, 5, $iss, $Host)
$script:Pool.ApartmentState = 'STA'
$script:Pool.Open()

$script:TaskWrapper = {
    param([string]$WTTaskId, [string]$WTScript, [hashtable]$WTParameters)
    $global:WTTaskId = $WTTaskId
    & ([scriptblock]::Create($WTScript)) @WTParameters
}.ToString()

function Invoke-WTTaskNow($Task) {
    $ps = [powershell]::Create()
    $ps.RunspacePool = $script:Pool
    # the runspaces are reused: every task sets its own id (empty for background loads,
    # whose programs are not stopped by the Stop button). A wrapper and not AddStatement():
    # with a second statement the pipeline did not start in the pool (PowerShell 5.1).
    $id = if ($Task.Background) { '' } else { [guid]::NewGuid().ToString('N') }
    [void]$ps.AddScript($script:TaskWrapper).AddArgument($id).AddArgument($Task.Script.ToString()).AddArgument($Task.Parameters)
    $job = [pscustomobject]@{
        PS = $ps; Handle = $null; Title = $Task.Title; OnComplete = $Task.OnComplete; Start = Get-Date; Background = $Task.Background
        Id = $id; Cancelled = $false
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

function Stop-WTCurrentTask([switch]$Force) {
    <#
    .SYNOPSIS
        Stops the running operation: terminates the programs it started (with their child
        processes, e.g. DismHost) and stops its runspace. -Force: without asking.
    #>
    $job = $script:CurrentJob
    if (-not $job -or $job.Cancelled) { return }
    if (-not $Force) {
        $msg = "Stop '$($job.Title)'?`n`nThe programs it started (e.g. DISM, SFC, CHKDSK) are terminated: run the operation again later to complete it. An uninstaller already running is left to finish."
        if (-not (Show-WTConfirm $msg 'Stop the operation')) { return }
        if ($script:CurrentJob -ne $job) { return }   # finished while the question was open
    }
    $job.Cancelled = $true
    $ui.BtnStop.IsEnabled = $false
    $window.TaskbarItemInfo.ProgressState = 'Paused'
    $window.TaskbarItemInfo.ProgressValue = 1
    Write-WTLog "Stopping: $($job.Title)..." -Level Warn
    foreach ($kv in @($global:WTProcesses.GetEnumerator())) {
        if ($kv.Value -ne $job.Id) { continue }
        & taskkill.exe /PID $kv.Key /T /F 2>&1 | Out-Null
    }
    [void]$job.PS.BeginStop($null, $null)
    if ($script:TaskQueue.Count) { Write-WTLog "$($script:TaskQueue.Count) queued operations will still run." }
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
    $failed = $false
    try { $result = $Job.PS.EndInvoke($Job.Handle) }
    catch { if (-not $Job.Cancelled) { $failed = $true; Write-WTLog "$($Job.Title): $($_.Exception.GetBaseException().Message)" -Level Error } }
    if (-not $Job.Cancelled) {
        if ($Job.PS.Streams.Error.Count) { $failed = $true }
        foreach ($e in $Job.PS.Streams.Error) { Write-WTLog "$($Job.Title): $e" -Level $(if ($Job.Background) { 'Warn' } else { 'Error' }) }
    }
    $Job | Add-Member -NotePropertyName Failed -NotePropertyValue $failed -Force
    $Job.PS.Dispose()
    if ($Job.Cancelled) {
        Write-WTLog ('=== Stopped: {0} (after {1:hh\:mm\:ss}) ===' -f $Job.Title, ((Get-Date) - $Job.Start))
    } elseif (-not $Job.Background) {
        Write-WTLog ('=== Done: {0} (duration {1:hh\:mm\:ss}) ===' -f $Job.Title, ((Get-Date) - $Job.Start))
    }
    Update-WTLogView
    # a stopped operation returns partial results: the interface is not updated with them
    if ($Job.OnComplete -and -not $Job.Cancelled) {
        try { & $Job.OnComplete $result }
        catch { Write-WTLog "Updating the interface ($($Job.Title)):$($_.Exception.Message)" -Level Error }
    }
}

function Send-WTCompletionNotice($Job) {
    # Long operation ended while the technician works elsewhere: taskbar button (red if it
    # failed) and a Windows notification; clicking it brings the window back
    $elapsed = (Get-Date) - $Job.Start
    if ($window.IsActive -or $elapsed.TotalSeconds -lt 15) { return }
    $outcome = if ($Job.Cancelled) { 'stopped' } elseif ($Job.Failed) { 'finished with errors: see the activity log' } else { 'completed' }
    if ($Job.Failed) { $window.TaskbarItemInfo.ProgressState = 'Error'; $window.TaskbarItemInfo.ProgressValue = 1 }
    [WTWindowHelper]::FlashTaskbar($script:Hwnd)
    Show-WTNotification $Job.Title ('{0} ({1:hh\:mm\:ss})' -f $outcome, $elapsed) -Warning:$Job.Failed
}

function Show-WTNotification([string]$Title, [string]$Text, [switch]$Warning) {
    try {
        if (-not $script:TrayIcon) {
            Add-Type -AssemblyName System.Windows.Forms, System.Drawing
            $ni = New-Object System.Windows.Forms.NotifyIcon
            $ms = New-Object IO.MemoryStream
            $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create((New-WTAppIcon 32)))
            $enc.Save($ms)
            $ni.Icon = [System.Drawing.Icon]::FromHandle((New-Object System.Drawing.Bitmap $ms).GetHicon())
            $ni.Text = $app.Name
            $ni.Add_BalloonTipClicked({ Show-WTWindowFront })
            $ni.Add_Click({ Show-WTWindowFront })
            $script:TrayIcon = $ni
            # the icon only stays in the notification area for a short time
            $script:TrayTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:TrayTimer.Interval = [TimeSpan]::FromSeconds(30)
            $script:TrayTimer.Add_Tick({ $script:TrayTimer.Stop(); $script:TrayIcon.Visible = $false })
        }
        $script:TrayIcon.Visible = $true
        $script:TrayIcon.ShowBalloonTip(8000, $Title, $Text, $(if ($Warning) { 'Warning' } else { 'Info' }))
        $script:TrayTimer.Stop(); $script:TrayTimer.Start()
    } catch { }
}

function Show-WTWindowFront {
    if ($window.WindowState -eq 'Minimized') { $window.WindowState = 'Normal' }
    [void]$window.Activate()
}

function New-WTAppIcon([int]$Size = 64) {
    # The logo of the title bar (wrench on a rounded square) as a bitmap: window and tray icon
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $bg = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x88, 0x39, 0xEF))
    $dc.DrawRoundedRectangle($bg, $null, (New-Object System.Windows.Rect 0, 0, $Size, $Size), ($Size * 0.22), ($Size * 0.22))
    $ft = New-Object System.Windows.Media.FormattedText ([string][char]0xE90F), ([Globalization.CultureInfo]::InvariantCulture),
        ([System.Windows.FlowDirection]::LeftToRight), (New-Object System.Windows.Media.Typeface 'Segoe MDL2 Assets'), ($Size * 0.56),
        ([System.Windows.Media.Brushes]::White), 1.0
    $dc.DrawText($ft, (New-Object System.Windows.Point (($Size - $ft.Width) / 2), (($Size - $ft.Height) / 2)))
    $dc.Close()
    $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $Size, $Size, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $bmp.Freeze()
    $bmp
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
        # an exception escaping a Tick handler stops the DispatcherTimer for good
        # (log, queue and status bar would freeze): it is caught here
        try {
            Update-WTLogView
            foreach ($j in @($script:BgJobs | Where-Object { $_.Handle.IsCompleted })) {
                [void]$script:BgJobs.Remove($j)
                Complete-WTJob $j
            }
            $job = $script:CurrentJob
            if ($job) {
                $ui.TxtStatus.Text = '{0}: {1}  ({2:hh\:mm\:ss})' -f $(if ($job.Cancelled) { 'Stopping' } else { 'Running' }), $job.Title, ((Get-Date) - $job.Start)
                if ($job.Handle.IsCompleted) {
                    $script:CurrentJob = $null
                    Set-WTBusy $false
                    Complete-WTJob $job
                    Send-WTCompletionNotice $job
                    if (-not $script:CurrentJob -and $script:TaskQueue.Count) { Invoke-WTTaskNow $script:TaskQueue.Dequeue() }
                }
            }
            Update-WTStatusExtras
        } catch { Write-WTCrash $_.Exception }
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
$window.Dispatcher.Add_UnhandledException({
        param($s, $e)
        $e.Handled = $true
        Write-WTCrash $e.Exception
    })
$window.Add_StateChanged({ Update-WTWindowFrame })
$window.Add_SizeChanged({ Update-WTLayout })
$window.Add_SourceInitialized({
        $script:Hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
        if ([WTWindowHelper]::RoundCorners($script:Hwnd)) {
            # Windows 11: rounded corners, DWM border in the theme colour; a minimal glass
            # frame brings back the window shadow
            $script:DwmFrame = $true
            [System.Windows.Shell.WindowChrome]::GetWindowChrome($window).GlassFrameThickness = New-Object System.Windows.Thickness 0, 0, 0, 1
            [WTWindowHelper]::SetBorderColor($script:Hwnd, $window.Resources['LineBrush'].Color)
        }
        # added after the WindowChrome hook, so it sees the messages first
        $script:SnapHook = New-Object WTSnapLayoutHook $window, $ui.BtnMax, 'CardHoverBrush'
        $script:SnapHook.Attach()
        Update-WTWindowFrame
    })
# like the system title bar, the title fades when the window is not active
$window.Add_Activated({
        $ui.TitleArea.Opacity = 1; $ui.AppLogo.Opacity = 1
        # the red "failed" state stays on the taskbar button until the window is seen
        if (-not $script:CurrentJob) { $window.TaskbarItemInfo.ProgressState = 'None' }
    })
$window.Add_Deactivated({ $ui.TitleArea.Opacity = 0.55; $ui.AppLogo.Opacity = 0.55 })

foreach ($p in $script:Pages) {
    On "Nav_$($p.Id)" -EventName 'Checked' {
        param($s)
        $page = $script:Pages | Where-Object { "Nav_$($_.Id)" -eq $s.Name } | Select-Object -First 1
        $ui.Tabs.SelectedIndex = $page.Index
    }
}
On 'NavData' { param($s) $s.IsChecked = $false; Start-Process explorer.exe -ArgumentList "`"$dataDir`"" }
On 'NavAbout' { param($s) $s.IsChecked = $false; Show-WTAbout }
On 'BtnAboutClose' { Hide-WTAbout }
$ui.AboutOverlay.Add_MouseLeftButtonDown({
        param($s, $e)
        # click on the dimmed area outside the card
        if ($e.OriginalSource -eq $ui.AboutOverlay) { Hide-WTAbout }
    })
On 'BtnAboutProject' { Start-Process $script:RepoUrl }
On 'BtnAboutIssue' { Set-WTClipboard (Get-WTAboutText); Start-Process "$script:RepoUrl/issues/new/choose" }
On 'BtnAboutReleases' { Start-Process "$script:RepoUrl/releases" }
On 'BtnAboutCopy' { Set-WTClipboard (Get-WTAboutText) }
On 'BtnAboutData' { Start-Process explorer.exe -ArgumentList "`"$dataDir`"" }
On 'BtnAboutLog' { if (Test-Path -LiteralPath $global:WTLogFile) { Start-Process notepad.exe -ArgumentList "`"$global:WTLogFile`"" } }
On 'ChkSimulate' {
    $on = Get-WTSimulate
    $ui.SimBanner.Visibility = $(if ($on) { 'Visible' } else { 'Collapsed' })
    if ($on) { Write-WTLog 'Simulation mode on: no changes will be applied.' -Level Warn } else { Write-WTLog 'Simulation mode off.' }
}
On 'BtnStop' { Stop-WTCurrentTask }
On 'BtnDlgYes' { Close-WTDialog $true }
On 'BtnDlgNo' { Close-WTDialog $false }
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
        if ($ui.DialogOverlay.IsVisible) {
            # Enter = the focused button (Yes/OK by default), Esc = No; no shortcuts meanwhile
            if ($e.Key -eq [System.Windows.Input.Key]::Escape) { Close-WTDialog (-not $ui.BtnDlgNo.IsVisible); $e.Handled = $true }
            elseif ($e.Key -eq [System.Windows.Input.Key]::Enter) { Close-WTDialog (-not $ui.BtnDlgNo.IsKeyboardFocused); $e.Handled = $true }
            return
        }
        if ($ui.AboutOverlay.IsVisible) {
            if ($e.Key -eq [System.Windows.Input.Key]::Escape) { Hide-WTAbout; $e.Handled = $true; return }
        }
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
            $msg = "An operation is still running: $($script:CurrentJob.Title).`n`nStop it and close? The programs it started (e.g. SFC, DISM) are terminated."
            if (-not (Show-WTConfirm $msg 'Close')) { $e.Cancel = $true; return }
            $script:TaskQueue.Clear()
            Stop-WTCurrentTask -Force
        }
        $script:TaskQueue.Clear()
        Write-WTLog 'Session ended.'
        Update-WTLogView
        $timer.Stop()
        if ($script:TrayIcon) { $script:TrayIcon.Dispose() }
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

Set-WTHeaderInfo
$ui.TxtVersion.Text = "Version $($app.Version)"
$script:RepoUrl = if ($app.Repository -and $app.Repository -notlike 'OWNER/*') { "https://github.com/$($app.Repository)" } else { '' }
# "0.9.0-beta" -> BETA badge next to the name
$badge = if ($app.Version -match '-([A-Za-z]+)') { $Matches[1].ToUpper() } elseif ($app.Version -eq 'dev') { 'DEV' } else { '' }
foreach ($n in 'Title', 'About') {
    $ui["Txt${n}Badge"].Text = $badge
    $ui["${n}Badge"].Visibility = $(if ($badge) { 'Visible' } else { 'Collapsed' })
}
$ui.TxtAboutCopyright.Text = $(try {
        ((Get-Content (Join-Path $PSScriptRoot 'LICENSE') -TotalCount 5 -ErrorAction Stop) -match '^Copyright' | Select-Object -First 1) -replace '^Copyright \(c\)', ([string][char]0xA9)
    } catch { '' })
Initialize-WTTileRows
$window.Icon = New-WTAppIcon 64
$window.TaskbarItemInfo = New-Object System.Windows.Shell.TaskbarItemInfo
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
