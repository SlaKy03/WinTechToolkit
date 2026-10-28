# Starts the UI off-screen, visits every section and saves a screenshot of each one.
param([string]$Theme = 'Dark', [string]$OutDir = (Join-Path $env:TEMP 'wtsmoke'))
$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$main = [IO.File]::ReadAllText((Join-Path $root 'WinTechToolkit.ps1'))
$main = $main.Replace('if (-not ($isAdmin -and $isSTA -and $isDesktop -and -not $is32on64)) {', 'if ($false) {')
$main = $main.Replace('$PSScriptRoot', "'$root'").Replace('$MyInvocation.MyCommand.Path', "'$root\WinTechToolkit.ps1'")
$hook = @'
$window.Left = -6000; $window.Top = 0; $window.ShowInTaskbar = $false
Set-WTTheme '__THEME__'
$script:SmokeStep = 0
$smoke = New-Object System.Windows.Threading.DispatcherTimer
$smoke.Interval = [TimeSpan]::FromMilliseconds(2500)
$smoke.Add_Tick({
    $i = $script:SmokeStep
    if ($i -gt 0 -and $i -le $script:Pages.Count) {
        $p = $script:Pages[$i - 1]
        $window.UpdateLayout()
        $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$window.ActualWidth), ([int]$window.ActualHeight), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($window)
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [IO.File]::Create((Join-Path '__OUT__' ('{0:00}-{1}.png' -f $i, $p.Id)))
        $enc.Save($fs); $fs.Close()
    }
    if ($i -ge $script:Pages.Count) {
        if ($script:SmokeStep -eq $script:Pages.Count) {
            Set-WTSidebar $false
            $script:SmokeStep++
            return
        }
        $window.UpdateLayout()
        $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$window.ActualWidth), ([int]$window.ActualHeight), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($window)
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [IO.File]::Create((Join-Path '__OUT__' '99-sidebar-collapsed.png')); $enc.Save($fs); $fs.Close()
        $smoke.Stop()
        $lines = @($script:LogItems | ForEach-Object { $_.Line })
        Set-Content -LiteralPath (Join-Path '__OUT__' 'log.txt') -Value $lines -Encoding UTF8
        $script:CurrentJob = $null
        $window.Close()
        return
    }
    Select-WTPage $i
    $script:SmokeStep++
})
$smoke.Start()
'@
$hook = $hook.Replace('__THEME__', $Theme).Replace('__OUT__', $OutDir)
$main = $main.Replace('$timer.Start()', "`$timer.Start()`r`n$hook")
$main = $main.Replace('try { $settings | ConvertTo-Json', 'try { return; $settings | ConvertTo-Json')
. ([scriptblock]::Create($main))
"Screenshot in $OutDir"
