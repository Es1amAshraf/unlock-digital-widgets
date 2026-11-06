# UNLOCK DIGITAL - Desktop Widgets uninstaller
# Runs from the installed folder (copied there by Install.ps1).
#
# Silent usage:
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File Uninstall.ps1 -Silent -AutoUninstall [-RemoveSettings] [-NoWallpaperRestore] [-NoTaskbarRestore]

param(
    [string]$InstallDir = '',
    [switch]$Silent,
    [switch]$AutoUninstall,
    [switch]$RemoveSettings,
    [switch]$NoWallpaperRestore,
    [switch]$NoTaskbarRestore,
    [switch]$TestMode
)

$ErrorActionPreference = 'Stop'
$script:AppVersion = '1.3.0'
$script:StateKey = 'HKCU:\Software\UNLOCK DIGITAL\Widgets'
$script:UninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\UNLOCK DIGITAL Widgets'
$script:ShortcutDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\UNLOCK DIGITAL'
$script:UninstallLog = Join-Path $env:TEMP 'UNLOCK DIGITAL uninstall.log'
$script:Warnings = New-Object System.Collections.ArrayList

function Write-Log([string]$msg) {
    try { Add-Content -LiteralPath $script:UninstallLog -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8 } catch { }
}
function Add-Warning([string]$msg) {
    [void]$script:Warnings.Add($msg)
    Write-Log "WARN: $msg"
}

# ---------------- resolve install folder & state ----------------

$script:Dir = $InstallDir
if (-not $script:Dir) { $script:Dir = $PSScriptRoot }
$script:Dir = $script:Dir.TrimEnd('\')

if (-not (Test-Path -LiteralPath (Join-Path $script:Dir 'ProDesktopWidgets.ps1'))) {
    $msg = "This does not look like the UNLOCK DIGITAL widgets folder:`n$($script:Dir)"
    if (-not $Silent) {
        try {
            Add-Type -AssemblyName PresentationFramework
            [void][System.Windows.MessageBox]::Show($msg, 'UNLOCK DIGITAL Uninstall', 'OK', 'Warning')
        } catch { }
    }
    Write-Output $msg
    exit 1
}

$script:State = @{ TaskPrefix = 'UNLOCK DIGITAL'; WallpaperApplied = 0; TaskbarTweaked = 0; PrevWallpaper = ''; PrevWallpaperStyle = '10'; PrevTileWallpaper = '0' }
try {
    $p = Get-ItemProperty -Path $script:StateKey -ErrorAction SilentlyContinue
    if ($p) {
        if ($p.TaskPrefix) { $script:State.TaskPrefix = [string]$p.TaskPrefix }
        if ($null -ne $p.WallpaperApplied) { $script:State.WallpaperApplied = [int]$p.WallpaperApplied }
        if ($null -ne $p.TaskbarTweaked) { $script:State.TaskbarTweaked = [int]$p.TaskbarTweaked }
        if ($p.PrevWallpaper) { $script:State.PrevWallpaper = [string]$p.PrevWallpaper }
        if ($null -ne $p.PrevWallpaperStyle) { $script:State.PrevWallpaperStyle = [string]$p.PrevWallpaperStyle }
        if ($null -ne $p.PrevTileWallpaper) { $script:State.PrevTileWallpaper = [string]$p.PrevTileWallpaper }
    }
} catch { }

# ---------------- operations ----------------

function Unregister-Tasks {
    foreach ($n in @("$($script:State.TaskPrefix) Widgets", "$($script:State.TaskPrefix) Widgets Watchdog")) {
        try { Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue } catch { }
        try { & schtasks.exe /Delete /TN $n /F 2>&1 | Out-Null } catch { }
    }
    Write-Log 'scheduled tasks removed'
}

function Stop-Widgets {
    $needle = $script:Dir
    $killed = 0
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ForEach-Object {
            try {
                if ($_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and $_.CommandLine -notmatch '\s-Command\s') {
                    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                    $killed++
                }
            } catch { }
        }
    } catch { Add-Warning 'Could not stop the running widgets.' }
    Write-Log "stopped $killed widget process(es)"
}

function Remove-Shortcuts {
    try {
        if (Test-Path -LiteralPath $script:ShortcutDir) { Remove-Item -LiteralPath $script:ShortcutDir -Recurse -Force }
        Write-Log 'shortcuts removed'
    } catch { Add-Warning 'Could not remove the Start Menu shortcuts.' }
}

function Restore-Wallpaper {
    $restore = -not $NoWallpaperRestore
    if ($script:State.WallpaperApplied -ne 1) { return }
    $wp = Join-Path $script:Dir 'wallpaper.png'
    try {
        if (-not $restore) {
            # keep the current look: move the picture out of the app folder and re-apply it
            $keepDir = Join-Path $env:LOCALAPPDATA 'UNLOCK DIGITAL'
            if (-not (Test-Path -LiteralPath $keepDir)) { New-Item -ItemType Directory -Path $keepDir -Force | Out-Null }
            $dest = Join-Path $keepDir 'wallpaper.png'
            if (Test-Path -LiteralPath $wp) { Copy-Item -LiteralPath $wp -Destination $dest -Force }
            if (-not ('UDW.Wall' -as [type])) {
                Add-Type -Namespace UDW -Name Wall -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@
            }
            if (Test-Path -LiteralPath $dest) { [void][UDW.Wall]::SystemParametersInfo(20, 0, $dest, 0x01 -bor 0x02) }
            Write-Log 'wallpaper kept'
            return
        }
        $prev = [string]$script:State.PrevWallpaper
        if ($prev -and (Test-Path -LiteralPath $prev)) {
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value ([string]$script:State.PrevWallpaperStyle) -Type String
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value ([string]$script:State.PrevTileWallpaper) -Type String
            if (-not ('UDW.Wall' -as [type])) {
                Add-Type -Namespace UDW -Name Wall -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@
            }
            [void][UDW.Wall]::SystemParametersInfo(20, 0, $prev, 0x01 -bor 0x02)
            Write-Log 'previous wallpaper restored'
        } else {
            $default = "$env:WINDIR\Web\Wallpaper\Windows\img0.jpg"
            if (Test-Path -LiteralPath $default) {
                if (-not ('UDW.Wall' -as [type])) {
                    Add-Type -Namespace UDW -Name Wall -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@
                }
                [void][UDW.Wall]::SystemParametersInfo(20, 0, $default, 0x01 -bor 0x02)
            }
            Write-Log 'default wallpaper restored'
        }
    } catch { Add-Warning 'Could not restore the wallpaper.' }
}

function Restore-Taskbar {
    if ($script:State.TaskbarTweaked -ne 1) { return }
    if ($NoTaskbarRestore -or $TestMode) { return }
    $script1 = Join-Path $script:Dir 'extras\Set-ProDesktop.ps1'
    if (-not (Test-Path -LiteralPath $script1)) { return }
    try {
        $p = Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script1`"", '-Undo') -WindowStyle Hidden -PassThru
        [void]$p.WaitForExit(60000)
        Write-Log 'taskbar settings restored'
    } catch { Add-Warning 'Could not restore the taskbar settings.' }
}

function Remove-Registry {
    try { if (Test-Path -LiteralPath $script:UninstKey) { Remove-Item -LiteralPath $script:UninstKey -Recurse -Force } } catch { Add-Warning 'Could not remove the Programs entry.' }
    try { if (Test-Path -LiteralPath $script:StateKey) { Remove-Item -LiteralPath $script:StateKey -Recurse -Force } } catch { Add-Warning 'Could not remove the settings registry key.' }
    try { if ((Test-Path -LiteralPath 'HKCU:\Software\UNLOCK DIGITAL') -and -not (Get-ChildItem -LiteralPath 'HKCU:\Software\UNLOCK DIGITAL' -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath 'HKCU:\Software\UNLOCK DIGITAL' -Force } } catch { }
    Write-Log 'registry entries removed'
}

function Remove-Files([bool]$keepSettings) {
    $dir = $script:Dir
    $keepNames = @('widgets.json', 'notes.txt')
    $delayed = @('Uninstall.ps1', 'Uninstall.cmd', 'Uninstall.vbs')
    try {
        Get-ChildItem -LiteralPath $dir -Force | Where-Object {
            $_.Name -notin $delayed -and -not ($keepSettings -and $_.Name -in $keepNames)
        } | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force } catch { Add-Warning "Could not delete $($_.Name)." }
        }
    } catch { Add-Warning 'Could not delete the application files.' }

    $q = '"' + $dir + '"'
    if ($keepSettings) {
        $cmd = 'ping -n 3 127.0.0.1 >nul & del /f /q ' + (($delayed | ForEach-Object { '"' + (Join-Path $dir $_) + '"' }) -join ' ')
    } else {
        $cmd = 'ping -n 3 127.0.0.1 >nul & rmdir /s /q ' + $q
    }
    try { Start-Process -FilePath "$env:WINDIR\System32\cmd.exe" -ArgumentList @('/c', $cmd) -WindowStyle Hidden } catch { }
    Write-Log 'files removed'
}

function Invoke-Uninstall([bool]$keepSettings, [scriptblock]$onStep) {
    if ($onStep) { & $onStep 'Stopping the widgets...' }
    Unregister-Tasks
    Stop-Widgets
    if ($onStep) { & $onStep 'Removing shortcuts...' }
    Remove-Shortcuts
    if ($script:State.WallpaperApplied -eq 1) {
        if ($onStep) { & $onStep 'Restoring the wallpaper...' }
        Restore-Wallpaper
    }
    if ($script:State.TaskbarTweaked -eq 1 -and -not $NoTaskbarRestore) {
        if ($onStep) { & $onStep 'Restoring the taskbar settings...' }
        Restore-Taskbar
    }
    if ($onStep) { & $onStep 'Removing registry entries...' }
    Remove-Registry
    if ($onStep) { & $onStep 'Removing files...' }
    Remove-Files $keepSettings
    Write-Log 'uninstall finished'
}

# ---------------- silent mode ----------------

if ($Silent) { $AutoUninstall = $true }

if ($AutoUninstall) {
    try {
        $keep = -not $RemoveSettings
        Invoke-Uninstall $keep $null
        Write-Output 'UNINSTALL OK'
        exit 0
    } catch {
        Write-Output ("UNINSTALL FAILED: " + $_.Exception.Message)
        Write-Log ("UNINSTALL FAILED: " + $_.Exception.Message)
        exit 1
    }
}

# ---------------- WPF user interface ----------------

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Drawing

$script:BrushCache = @{}
function Br([string]$hex) {
    if (-not $script:BrushCache.ContainsKey($hex)) {
        $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
        $b.Freeze()
        $script:BrushCache[$hex] = $b
    }
    $script:BrushCache[$hex]
}
function Th([double]$l, [double]$t, [double]$r, [double]$b) { New-Object System.Windows.Thickness($l, $t, $r, $b) }
function CR([double]$r) { New-Object System.Windows.CornerRadius($r) }
function Txt([string]$text, [double]$size, [string]$color, [string]$weight = 'Normal') {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text
    $t.FontSize = $size
    $t.Foreground = Br $color
    $t.FontWeight = switch ($weight) {
        'SemiBold' { [System.Windows.FontWeights]::SemiBold }
        'Bold'     { [System.Windows.FontWeights]::Bold }
        default    { [System.Windows.FontWeights]::Normal }
    }
    $t.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Variable Text, Segoe UI')
    $t.TextWrapping = 'Wrap'
    return $t
}
function Gradient([double]$x1, [double]$y1, [double]$x2, [double]$y2, [object[]]$stops) {
    $g = New-Object System.Windows.Media.LinearGradientBrush
    $g.StartPoint = New-Object System.Windows.Point($x1, $y1)
    $g.EndPoint = New-Object System.Windows.Point($x2, $y2)
    foreach ($s in $stops) {
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($s[0]), [double]$s[1])))
    }
    return $g
}
function New-ActionButton([string]$text, [bool]$primary, [scriptblock]$onClick) {
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = CR 10
    $b.Padding = Th 22 11 22 11
    $b.Cursor = 'Hand'
    $b.HorizontalAlignment = 'Right'
    $b.VerticalAlignment = 'Center'
    if ($primary) {
        $b.Background = Gradient 0 0 1 1 @(@('#F0716B', 0), @('#D94A5F', 1))
        $b.BorderThickness = Th 0 0 0 0
        $t = Txt $text 13.5 '#FFFFFF' 'SemiBold'
    } else {
        $b.Background = Br '#10FFFFFF'
        $b.BorderBrush = Br '#26FFFFFF'
        $b.BorderThickness = Th 1 1 1 1
        $t = Txt $text 13 '#C7D2E4' 'SemiBold'
    }
    $t.TextWrapping = 'NoWrap'
    $b.Child = $t
    $b.Tag = $onClick
    $b.Add_MouseEnter({ param($s, $e) try { $s.Opacity = 0.88 } catch { } })
    $b.Add_MouseLeave({ param($s, $e) try { $s.Opacity = 1.0 } catch { } })
    $b.Add_MouseLeftButtonUp({ param($s, $e) try { if ($s.Tag) { & $s.Tag } } catch { } })
    return $b
}
function New-Check([string]$text, [bool]$checked) {
    $c = New-Object System.Windows.Controls.CheckBox
    $c.Content = $text
    $c.IsChecked = $checked
    $c.Foreground = Br '#E8EEF8'
    $c.FontSize = 13
    $c.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Variable Text, Segoe UI')
    $c.Margin = Th 0 0 0 11
    $c.VerticalContentAlignment = 'Center'
    return $c
}

$win = New-Object System.Windows.Window
$win.Width = 580
$win.Height = 540
$win.WindowStyle = 'None'
$win.AllowsTransparency = $true
$win.Background = $null
$win.ResizeMode = 'NoResize'
$win.WindowStartupLocation = 'CenterScreen'
$win.ShowInTaskbar = $true
$win.Title = 'UNLOCK DIGITAL - Uninstall'
try { $win.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([uri](Join-Path $script:Dir 'UNLOCK-DIGITAL.ico')) } catch { }

$root = New-Object System.Windows.Controls.Border
$root.CornerRadius = CR 20
$root.BorderThickness = Th 1 1 1 1
$root.BorderBrush = Br '#26FFFFFF'
$root.Background = Gradient 0.1 0 0.9 1 @(@('#FB0C1220', 0), @('#F8060A12', 1))
$shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
$shadow.BlurRadius = 32; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.65; $shadow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#000000')
$root.Effect = $shadow
$win.Content = $root

$outer = New-Object System.Windows.Controls.Grid
$r0 = New-Object System.Windows.Controls.RowDefinition
$r0.Height = New-Object System.Windows.GridLength(3)
$r1 = New-Object System.Windows.Controls.RowDefinition
$r1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
[void]$outer.RowDefinitions.Add($r0)
[void]$outer.RowDefinitions.Add($r1)

$accent = New-Object System.Windows.Controls.Border
$accent.CornerRadius = New-Object System.Windows.CornerRadius(19, 19, 0, 0)
$accent.Background = Gradient 0 0 1 0 @(@('#F0716B', 0), @('#8B5CF6', 1))
[System.Windows.Controls.Grid]::SetRow($accent, 0)
[void]$outer.Children.Add($accent)

$content = New-Object System.Windows.Controls.StackPanel
$content.Margin = Th 30 26 30 24
[System.Windows.Controls.Grid]::SetRow($content, 1)
[void]$outer.Children.Add($content)
$root.Child = $outer

$head = New-Object System.Windows.Controls.StackPanel
$brand = New-Object System.Windows.Controls.StackPanel
$brand.Orientation = 'Horizontal'
$logo = New-Object System.Windows.Controls.Border
$logo.Width = 42; $logo.Height = 42
$logo.CornerRadius = CR 12
$logo.Background = Gradient 0 0 1 1 @(@('#F0716B', 0), @('#D94A5F', 1))
$logo.Margin = Th 0 13 0 0
$logoT = Txt 'UD' 14 '#FFFFFF' 'Bold'
$logoT.HorizontalAlignment = 'Center'; $logoT.VerticalAlignment = 'Center'; $logoT.TextWrapping = 'NoWrap'
$logo.Child = $logoT
[void]$brand.Children.Add($logo)
$ts = New-Object System.Windows.Controls.StackPanel
$t1 = Txt 'UNLOCK DIGITAL' 9.5 '#8FA3BF' 'SemiBold'; $t1.TextWrapping = 'NoWrap'
$t2 = Txt 'Uninstall widgets' 21 '#F4F8FF' 'Bold'; $t2.TextWrapping = 'NoWrap'
[void]$ts.Children.Add($t1)
[void]$ts.Children.Add($t2)
[void]$brand.Children.Add($ts)
[void]$head.Children.Add($brand)
[void]$content.Children.Add($head)

$sub = Txt 'This stops the widgets and removes them from this PC.' 12 '#A9B7CC'
$sub.Margin = Th 0 16 0 0
[void]$content.Children.Add($sub)

$pathCard = New-Object System.Windows.Controls.Border
$pathCard.CornerRadius = CR 10
$pathCard.Background = Br '#08FFFFFF'
$pathCard.BorderBrush = Br '#14FFFFFF'
$pathCard.BorderThickness = Th 1 1 1 1
$pathCard.Padding = Th 14 10 14 10
$pathCard.Margin = Th 0 14 0 0
$pathCard.Child = (Txt $script:Dir 10.5 '#8FA3BF')
[void]$content.Children.Add($pathCard)

$optTitle = Txt 'OPTIONS' 9 '#6F7F97' 'SemiBold'; $optTitle.TextWrapping = 'NoWrap'; $optTitle.Margin = Th 2 18 0 10
[void]$content.Children.Add($optTitle)
$cbKeep = New-Check 'Keep my settings (widgets.json, notes.txt)' $true
$cbWall = New-Check 'Restore my previous wallpaper' ($script:State.WallpaperApplied -eq 1)
$cbBar = New-Check 'Restore the previous theme / taskbar' ($script:State.TaskbarTweaked -eq 1)
[void]$content.Children.Add($cbKeep)
[void]$content.Children.Add($cbWall)
[void]$content.Children.Add($cbBar)
if ($script:State.WallpaperApplied -ne 1) { $cbWall.IsEnabled = $false }
if ($script:State.TaskbarTweaked -ne 1) { $cbBar.IsEnabled = $false }

$status = Txt '' 11 '#8FA3BF'
$status.Margin = Th 0 12 0 6
[void]$content.Children.Add($status)
$prog = New-Object System.Windows.Controls.ProgressBar
$prog.Height = 4
$prog.IsIndeterminate = $true
$prog.Visibility = 'Collapsed'
$prog.Foreground = Gradient 0 0 1 0 @(@('#F0716B', 0), @('#8B5CF6', 1))
$prog.Background = Br '#12FFFFFF'
$prog.BorderThickness = Th 0 0 0 0
$prog.Margin = Th 0 0 0 14
[void]$content.Children.Add($prog)

$btnRow = New-Object System.Windows.Controls.StackPanel
$btnRow.Orientation = 'Horizontal'
$btnRow.HorizontalAlignment = 'Right'
$btnRow.Margin = Th 0 4 0 0
$btnCancel = New-ActionButton 'Cancel' $false { $win.Close() }
$btnCancel.Margin = Th 0 0 10 0
$btnGo = New-ActionButton 'Uninstall' $true { }
[void]$btnRow.Children.Add($btnCancel)
[void]$btnRow.Children.Add($btnGo)
[void]$content.Children.Add($btnRow)

$close = New-Object System.Windows.Controls.Border
$close.Width = 30; $close.Height = 30
$close.CornerRadius = CR 7
$close.Background = Br '#00FFFFFF'
$close.Cursor = 'Hand'
$closeT = Txt ([string][char]0x2715) 12 '#7C8CA3' 'SemiBold'
$closeT.HorizontalAlignment = 'Center'; $closeT.VerticalAlignment = 'Center'; $closeT.TextWrapping = 'NoWrap'
$close.Child = $closeT
$close.Add_MouseEnter({ param($s, $e) try { $s.Background = Br '#18FFFFFF' } catch { } })
$close.Add_MouseLeave({ param($s, $e) try { $s.Background = Br '#00FFFFFF' } catch { } })
$close.Add_MouseLeftButtonUp({ param($s, $e) try { $win.Close() } catch { } })
$closeHost = New-Object System.Windows.Controls.Grid
$closeHost.Margin = Th 0 12 14 0
$closeHost.VerticalAlignment = 'Top'
$closeHost.HorizontalAlignment = 'Right'
[void]$closeHost.Children.Add($close)
[System.Windows.Controls.Grid]::SetRow($closeHost, 1)
[void]$outer.Children.Add($closeHost)

$head.Add_MouseLeftButtonDown({ param($s, $e) try { $win.DragMove() } catch { } })
$brand.Add_MouseLeftButtonDown({ param($s, $e) try { $win.DragMove() } catch { } })

$btnGo.Tag = {
    $btnGo.IsEnabled = $false
    $btnCancel.IsEnabled = $false
    $cbKeep.IsEnabled = $false; $cbWall.IsEnabled = $false; $cbBar.IsEnabled = $false
    $status.Text = 'Starting...'
    $prog.Visibility = 'Visible'
    $win.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})
    $keepSettings = [bool]$cbKeep.IsChecked
    $script:NoWallpaperRestore = [bool](-not $cbWall.IsChecked)
    $script:NoTaskbarRestore = [bool](-not $cbBar.IsChecked)
    try {
        Invoke-Uninstall $keepSettings {
            param($msg)
            $status.Text = $msg
            try { $win.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{}) } catch { }
        }
        $prog.Visibility = 'Collapsed'
        Show-Success $keepSettings
    } catch {
        $prog.Visibility = 'Collapsed'
        $status.Text = 'Uninstall failed.'
        $status.Foreground = Br '#F87171'
        [void][System.Windows.MessageBox]::Show($win, ("Could not finish the uninstall.`n`n" + $_.Exception.Message + "`n`nLog: " + $script:UninstallLog), 'UNLOCK DIGITAL Uninstall', 'OK', 'Error')
        $btnGo.IsEnabled = $true
        $btnCancel.IsEnabled = $true
    }
}

function Show-Success([bool]$keepSettings) {
    $content.Children.Clear()
    $ok = New-Object System.Windows.Controls.Border
    $ok.Width = 54; $ok.Height = 54
    $ok.CornerRadius = CR 27
    $ok.Background = Br '#1A34D399'
    $ok.BorderBrush = Br '#5534D399'
    $ok.BorderThickness = Th 1 1 1 1
    $ok.HorizontalAlignment = 'Left'
    $ok.Child = (Txt ([string][char]0x2713) 22 '#34D399' 'Bold')
    $ok.Child.HorizontalAlignment = 'Center'; $ok.Child.VerticalAlignment = 'Center'; $ok.Child.TextWrapping = 'NoWrap'
    [void]$content.Children.Add($ok)
    $h = Txt 'Uninstalled' 22 '#F4F8FF' 'Bold'; $h.Margin = Th 0 16 0 0; $h.TextWrapping = 'NoWrap'
    [void]$content.Children.Add($h)
    $p = Txt 'The widgets and their startup tasks have been removed. You can close this window.' 11.5 '#8FA3BF'
    $p.Margin = Th 0 8 0 0
    [void]$content.Children.Add($p)
    if ($keepSettings) {
        $k = Txt "Your settings and notes were kept in:`n$($script:Dir)\widgets.json`n$($script:Dir)\notes.txt" 10.5 '#8FA3BF'
        $k.Margin = Th 0 12 0 0
        [void]$content.Children.Add($k)
    }
    if ($script:Warnings.Count -gt 0) {
        $wn = Txt ("Some items could not be removed:`n- " + (($script:Warnings | Select-Object -Unique) -join "`n- ")) 10 '#F0A3A3'
        $wn.Margin = Th 0 12 0 0
        [void]$content.Children.Add($wn)
    }
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.HorizontalAlignment = 'Right'
    $row.Margin = Th 0 24 0 0
    $b = New-ActionButton 'Close' $true { $win.Close() }
    [void]$row.Children.Add($b)
    [void]$content.Children.Add($row)
}

[void]$win.ShowDialog()
