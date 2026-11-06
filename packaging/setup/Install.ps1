# UNLOCK DIGITAL - Desktop Widgets installer
# Per-user install (no admin rights needed).
#
# Silent usage:
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File Install.ps1 -Silent -AutoInstall
#   optional: -InstallDir <path> -TaskPrefix <name> -NoTasks -NoShortcuts -NoRegistry -NoWallpaper -NoLaunch -Wallpaper -Taskbar

param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'UNLOCK DIGITAL\Widgets'),
    [string]$TaskPrefix = 'UNLOCK DIGITAL',
    [switch]$Silent,
    [switch]$AutoInstall,
    [switch]$NoTasks,
    [switch]$NoShortcuts,
    [switch]$NoRegistry,
    [switch]$NoWallpaper,
    [switch]$NoLaunch,
    [switch]$Wallpaper,
    [switch]$Taskbar,
    [switch]$TestMode
)

$ErrorActionPreference = 'Stop'
$script:AppVersion = '1.3.0'
$script:AppName = 'UNLOCK DIGITAL Desktop Widgets'
$script:PkgRoot = Split-Path -Parent $PSScriptRoot
$script:Payload = Join-Path $script:PkgRoot 'payload'
$script:Extras = Join-Path $script:PkgRoot 'extras'
$script:StateKey = 'HKCU:\Software\UNLOCK DIGITAL\Widgets'
$script:UninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\UNLOCK DIGITAL Widgets'
$script:ShortcutDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\UNLOCK DIGITAL'
$script:InstallLog = Join-Path $env:TEMP 'UNLOCK DIGITAL install.log'

function Write-Log([string]$msg) {
    try {
        $logDir = Split-Path -Parent $script:InstallLog
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Add-Content -LiteralPath $script:InstallLog -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
    } catch { }
}

# ---------------- install steps ----------------

function Test-Package {
    $need = @('ProDesktopWidgets.ps1', 'ProDesktopWidgets.vbs', 'UNLOCK-DIGITAL.ico')
    foreach ($f in $need) {
        $p = Join-Path $script:Payload $f
        if (-not (Test-Path -LiteralPath $p)) { throw "Package file missing: payload\$f" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1'))) { throw 'Package file missing: setup\Uninstall.ps1' }
}

function Copy-Payload([hashtable]$o) {
    if (-not (Test-Path -LiteralPath $o.Dir)) { New-Item -ItemType Directory -Path $o.Dir -Force | Out-Null }
    foreach ($f in @('ProDesktopWidgets.ps1', 'ProDesktopWidgets.vbs', 'UNLOCK-DIGITAL.ico')) {
        Copy-Item -LiteralPath (Join-Path $script:Payload $f) -Destination (Join-Path $o.Dir $f) -Force
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination (Join-Path $o.Dir 'Uninstall.ps1') -Force

    $cmd = "@echo off`r`nstart `"`" wscript.exe `"%~dp0Uninstall.vbs`"`r`n"
    Set-Content -LiteralPath (Join-Path $o.Dir 'Uninstall.cmd') -Value $cmd -Encoding ASCII

    $vbs = @'
' UNLOCK DIGITAL - invisible uninstaller launcher
Option Explicit
Dim sh, fso, dir
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\Uninstall.ps1""", 0, False
'@
    Set-Content -LiteralPath (Join-Path $o.Dir 'Uninstall.vbs') -Value $vbs -Encoding ASCII

    if ($o.Wallpaper) {
        $wp = Join-Path $script:Payload 'wallpaper.png'
        if (Test-Path -LiteralPath $wp) { Copy-Item -LiteralPath $wp -Destination (Join-Path $o.Dir 'wallpaper.png') -Force }
    }
    if ($o.Taskbar) {
        $ex = Join-Path $o.Dir 'extras'
        if (-not (Test-Path -LiteralPath $ex)) { New-Item -ItemType Directory -Path $ex -Force | Out-Null }
        foreach ($f in @('Set-ProDesktop.ps1', 'Undo-ProDesktop.cmd')) {
            $src = Join-Path $script:Extras $f
            if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $ex $f) -Force }
        }
    }
    Write-Log "payload copied to $($o.Dir)"
}

function New-DefaultConfig([hashtable]$o) {
    $cfgPath = Join-Path $o.Dir 'widgets.json'
    if (Test-Path -LiteralPath $cfgPath) { Write-Log 'existing widgets.json kept'; return $true }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        $psi.Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($o.Dir)\ProDesktopWidgets.ps1`" -MakeConfig"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        [void]$proc.WaitForExit(30000)
        $limit = (Get-Date).AddSeconds(15)
        while (-not (Test-Path -LiteralPath $cfgPath) -and (Get-Date) -lt $limit) { Start-Sleep -Milliseconds 250 }
        if (Test-Path -LiteralPath $cfgPath) { Write-Log 'default widgets.json created'; return $true }
        Write-Log 'widgets.json was not created (the widgets will create it on first run)'
        return $false
    } catch {
        Write-Log "MakeConfig failed: $($_.Exception.Message)"
        return $false
    }
}

function Unregister-WidgetTasks([string]$prefix) {
    foreach ($n in @("$prefix Widgets", "$prefix Widgets Watchdog")) {
        try { Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue } catch { }
        try { & schtasks.exe /Delete /TN $n /F 2>&1 | Out-Null } catch { }
    }
}

function Register-WidgetTasks([hashtable]$o) {
    Unregister-WidgetTasks $o.Prefix
    $wscript = "$env:WINDIR\System32\wscript.exe"
    $vbs = Join-Path $o.Dir 'ProDesktopWidgets.vbs'
    $user = "$env:USERDOMAIN\$env:USERNAME"
    try {
        $action = New-ScheduledTaskAction -Execute $wscript -Argument "`"$vbs`"" -WorkingDirectory $o.Dir
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $logon = New-ScheduledTaskTrigger -AtLogOn -User $user
        Register-ScheduledTask -TaskName "$($o.Prefix) Widgets" -Action $action -Trigger $logon -Principal $principal -Settings $settings -Description 'UNLOCK DIGITAL desktop widgets at sign-in' -Force | Out-Null
        if ($o.Watchdog) {
            $watch = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
            Register-ScheduledTask -TaskName "$($o.Prefix) Widgets Watchdog" -Action $action -Trigger $watch -Principal $principal -Settings $settings -Description 'Restarts UNLOCK DIGITAL widgets if they are closed' -Force | Out-Null
        }
        Write-Log 'scheduled tasks registered'
    } catch {
        Write-Log "ScheduledTasks failed: $($_.Exception.Message) - falling back to schtasks"
        $tr = "wscript.exe `"$vbs`""
        & schtasks.exe /Create /TN "$($o.Prefix) Widgets" /TR $tr /SC ONLOGON /F 2>&1 | Out-Null
        if ($o.Watchdog) { & schtasks.exe /Create /TN "$($o.Prefix) Widgets Watchdog" /TR $tr /SC MINUTE /MO 1 /F 2>&1 | Out-Null }
        if ($LASTEXITCODE -ne 0) { throw 'Could not register the startup tasks.' }
    }
}

function New-Shortcuts([hashtable]$o) {
    if (-not (Test-Path -LiteralPath $script:ShortcutDir)) { New-Item -ItemType Directory -Path $script:ShortcutDir -Force | Out-Null }
    $ws = New-Object -ComObject WScript.Shell
    $ico = Join-Path $o.Dir 'UNLOCK-DIGITAL.ico'

    $l1 = $ws.CreateShortcut((Join-Path $script:ShortcutDir 'Desktop Widgets.lnk'))
    $l1.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $l1.Arguments = "`"$(Join-Path $o.Dir 'ProDesktopWidgets.vbs')`""
    $l1.WorkingDirectory = $o.Dir
    $l1.IconLocation = "$ico,0"
    $l1.Description = 'UNLOCK DIGITAL desktop widgets'
    $l1.Save()

    $l2 = $ws.CreateShortcut((Join-Path $script:ShortcutDir 'Widgets Settings.lnk'))
    $l2.TargetPath = "$env:WINDIR\System32\notepad.exe"
    $l2.Arguments = "`"$(Join-Path $o.Dir 'widgets.json')`""
    $l2.WorkingDirectory = $o.Dir
    $l2.IconLocation = "$ico,0"
    $l2.Description = 'Edit the UNLOCK DIGITAL widgets settings'
    $l2.Save()

    $l3 = $ws.CreateShortcut((Join-Path $script:ShortcutDir 'Uninstall Widgets.lnk'))
    $l3.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $l3.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $o.Dir 'Uninstall.ps1')`""
    $l3.WorkingDirectory = $o.Dir
    $l3.IconLocation = "$ico,0"
    $l3.Description = 'Remove the UNLOCK DIGITAL desktop widgets'
    $l3.Save()
    Write-Log 'start menu shortcuts created'
}

function Set-WidgetWallpaper([hashtable]$o) {
    $wp = Join-Path $o.Dir 'wallpaper.png'
    if (-not (Test-Path -LiteralPath $wp)) { Write-Log 'wallpaper.png missing, skipped'; return }
    $desk = 'HKCU:\Control Panel\Desktop'
    $prevApplied = 0
    try { $prevApplied = [int](Get-ItemProperty -Path $script:StateKey -Name WallpaperApplied -ErrorAction SilentlyContinue).WallpaperApplied } catch { }
    if ($prevApplied -ne 1) {
        $prev = ''
        $ps = '10'; $pt = '0'
        try { $prev = [string](Get-ItemProperty -Path $desk -Name WallPaper -ErrorAction SilentlyContinue).WallPaper } catch { }
        try { $ps = [string](Get-ItemProperty -Path $desk -Name WallpaperStyle -ErrorAction SilentlyContinue).WallpaperStyle } catch { }
        try { $pt = [string](Get-ItemProperty -Path $desk -Name TileWallpaper -ErrorAction SilentlyContinue).TileWallpaper } catch { }
        if (-not (Test-Path -LiteralPath $script:StateKey)) { New-Item -Path $script:StateKey -Force | Out-Null }
        Set-ItemProperty -Path $script:StateKey -Name PrevWallpaper -Value $prev
        Set-ItemProperty -Path $script:StateKey -Name PrevWallpaperStyle -Value $ps
        Set-ItemProperty -Path $script:StateKey -Name PrevTileWallpaper -Value $pt
        Set-ItemProperty -Path $script:StateKey -Name WallpaperApplied -Value 1 -Type DWord
    }
    Set-ItemProperty -Path $desk -Name WallpaperStyle -Value '10' -Type String
    Set-ItemProperty -Path $desk -Name TileWallpaper -Value '0' -Type String
    if (-not ('UDW.Wall' -as [type])) {
        Add-Type -Namespace UDW -Name Wall -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@
    }
    [void][UDW.Wall]::SystemParametersInfo(20, 0, $wp, 0x01 -bor 0x02)
    Write-Log 'wallpaper applied'
}

function Set-TaskbarTweaks([hashtable]$o) {
    $ex = Join-Path $o.Dir 'extras'
    $script1 = Join-Path $ex 'Set-ProDesktop.ps1'
    if (-not (Test-Path -LiteralPath $script1)) { Write-Log 'Set-ProDesktop.ps1 missing, skipped'; return }
    $p = Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script1`"") -WindowStyle Hidden -PassThru
    [void]$p.WaitForExit(60000)
    if (-not (Test-Path -LiteralPath $script:StateKey)) { New-Item -Path $script:StateKey -Force | Out-Null }
    Set-ItemProperty -Path $script:StateKey -Name TaskbarTweaked -Value 1 -Type DWord
    Write-Log 'taskbar tweaks applied'
}

function Set-InstallRegistry([hashtable]$o) {
    if (-not (Test-Path -LiteralPath $script:StateKey)) { New-Item -Path $script:StateKey -Force | Out-Null }
    Set-ItemProperty -Path $script:StateKey -Name InstallDir -Value $o.Dir
    Set-ItemProperty -Path $script:StateKey -Name Version -Value $script:AppVersion
    Set-ItemProperty -Path $script:StateKey -Name InstalledAt -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Set-ItemProperty -Path $script:StateKey -Name TaskPrefix -Value $o.Prefix
    Set-ItemProperty -Path $script:StateKey -Name TasksEnabled -Value ([int][bool]$o.Tasks) -Type DWord

    if (-not (Test-Path -LiteralPath $script:UninstKey)) { New-Item -Path $script:UninstKey -Force | Out-Null }
    $size = 0
    try { $size = [int](((Get-ChildItem -LiteralPath $o.Dir -Recurse -File | Measure-Object Length -Sum).Sum) / 1KB) } catch { }
    $uninst = "`"$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $o.Dir 'Uninstall.ps1')`""
    Set-ItemProperty -Path $script:UninstKey -Name DisplayName -Value $script:AppName
    Set-ItemProperty -Path $script:UninstKey -Name DisplayVersion -Value $script:AppVersion
    Set-ItemProperty -Path $script:UninstKey -Name Publisher -Value 'UNLOCK DIGITAL'
    Set-ItemProperty -Path $script:UninstKey -Name InstallLocation -Value $o.Dir
    Set-ItemProperty -Path $script:UninstKey -Name DisplayIcon -Value (Join-Path $o.Dir 'UNLOCK-DIGITAL.ico')
    Set-ItemProperty -Path $script:UninstKey -Name UninstallString -Value $uninst
    Set-ItemProperty -Path $script:UninstKey -Name QuietUninstallString -Value $uninst
    Set-ItemProperty -Path $script:UninstKey -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty -Path $script:UninstKey -Name NoRepair -Value 1 -Type DWord
    Set-ItemProperty -Path $script:UninstKey -Name EstimatedSize -Value $size -Type DWord
    Write-Log 'registry entries written'
}

function Start-Widgets([hashtable]$o) {
    Start-Process -FilePath "$env:WINDIR\System32\wscript.exe" -ArgumentList "`"$(Join-Path $o.Dir 'ProDesktopWidgets.vbs')`"" -WindowStyle Hidden
    Write-Log 'widgets launched'
}

function Invoke-Install([hashtable]$o, [scriptblock]$onStep) {
    if ($onStep) { & $onStep 'Checking package files...' }
    Test-Package
    if ($onStep) { & $onStep 'Copying application files...' }
    Copy-Payload $o
    if ($onStep) { & $onStep 'Preparing settings...' }
    [void](New-DefaultConfig $o)
    if ($o.Tasks) {
        if ($onStep) { & $onStep 'Registering sign-in and watchdog tasks...' }
        Register-WidgetTasks $o
    } else {
        Unregister-WidgetTasks $o.Prefix
    }
    if ($o.Shortcuts) {
        if ($onStep) { & $onStep 'Creating Start Menu shortcuts...' }
        New-Shortcuts $o
    }
    if ($o.Wallpaper) {
        if ($onStep) { & $onStep 'Applying wallpaper...' }
        Set-WidgetWallpaper $o
    }
    if ($o.Taskbar) {
        if ($onStep) { & $onStep 'Applying theme and taskbar settings...' }
        Set-TaskbarTweaks $o
    }
    if ($o.Registry) {
        if ($onStep) { & $onStep 'Finishing setup...' }
        Set-InstallRegistry $o
    }
    if ($o.Launch -and -not $o.TestMode) {
        if ($onStep) { & $onStep 'Starting the widgets...' }
        Start-Widgets $o
    }
    Write-Log 'install finished'
    return $true
}

# ---------------- silent mode ----------------

$script:AutoOpts = @{
    Dir = $InstallDir
    Prefix = $TaskPrefix
    Tasks = -not $NoTasks
    Watchdog = -not $NoTasks
    Shortcuts = -not $NoShortcuts
    Registry = -not $NoRegistry
    Wallpaper = -not $NoWallpaper
    Taskbar = [bool]$Taskbar
    Launch = -not $NoLaunch
    TestMode = [bool]$TestMode
}

if ($Silent) { $AutoInstall = $true }

if ($AutoInstall) {
    try {
        Invoke-Install $script:AutoOpts $null | Out-Null
        Write-Output 'INSTALL OK'
        exit 0
    } catch {
        Write-Output ("INSTALL FAILED: " + $_.Exception.Message)
        Write-Log ("INSTALL FAILED: " + $_.Exception.Message)
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
        'Light'    { [System.Windows.FontWeights]::Light }
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
        $b.Background = Gradient 0 0 1 1 @(@('#4CC2FF', 0), @('#7C6CFF', 1))
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
    $normal = $b.Background
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
$win.Width = 620
$win.Height = 520
$win.WindowStyle = 'None'
$win.AllowsTransparency = $true
$win.Background = $null
$win.ResizeMode = 'NoResize'
$win.WindowStartupLocation = 'CenterScreen'
$win.Topmost = $true
$win.ShowInTaskbar = $true
$win.Title = 'UNLOCK DIGITAL - Setup'
try { $win.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([uri](Join-Path $script:Payload 'UNLOCK-DIGITAL.ico')) } catch { }

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
$accent.Background = Gradient 0 0 1 0 @(@('#4CC2FF', 0), @('#8B5CF6', 0.55), @('#34D399', 1))
[System.Windows.Controls.Grid]::SetRow($accent, 0)
[void]$outer.Children.Add($accent)

$content = New-Object System.Windows.Controls.StackPanel
$content.Margin = Th 30 24 30 24
[System.Windows.Controls.Grid]::SetRow($content, 1)
[void]$outer.Children.Add($content)
$root.Child = $outer

# header
$head = New-Object System.Windows.Controls.Grid
$hc1 = New-Object System.Windows.Controls.ColumnDefinition
$hc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$hc2 = New-Object System.Windows.Controls.ColumnDefinition
$hc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
[void]$head.ColumnDefinitions.Add($hc1)
[void]$head.ColumnDefinitions.Add($hc2)

$brand = New-Object System.Windows.Controls.StackPanel
$brand.Orientation = 'Horizontal'
$logo = New-Object System.Windows.Controls.Border
$logo.Width = 46; $logo.Height = 46
$logo.CornerRadius = CR 13
$logo.Background = Gradient 0 0 1 1 @(@('#4CC2FF', 0), @('#8B5CF6', 1))
$logo.Margin = Th 0 0 14 0
$logoT = Txt 'UD' 15 '#FFFFFF' 'Bold'
$logoT.HorizontalAlignment = 'Center'; $logoT.VerticalAlignment = 'Center'
$logoT.TextWrapping = 'NoWrap'
$logo.Child = $logoT
[void]$brand.Children.Add($logo)
$titleStack = New-Object System.Windows.Controls.StackPanel
$t1 = Txt 'UNLOCK DIGITAL' 9.5 '#8FA3BF' 'SemiBold'
$t1.TextWrapping = 'NoWrap'
$t2 = Txt 'Desktop Widgets' 22 '#F4F8FF' 'Bold'
$t2.TextWrapping = 'NoWrap'
[void]$titleStack.Children.Add($t1)
[void]$titleStack.Children.Add($t2)
[void]$brand.Children.Add($titleStack)
[void]$head.Children.Add($brand)

$badge = New-Object System.Windows.Controls.Border
$badge.CornerRadius = CR 9
$badge.BorderThickness = Th 1 1 1 1
$badge.BorderBrush = Br '#26FFFFFF'
$badge.Background = Br '#0CFFFFFF'
$badge.Padding = Th 11 4 11 4
$badge.VerticalAlignment = 'Top'
$badge.Margin = Th 0 0 46 0
$badge.Child = (Txt "v$($script:AppVersion)" 10 '#A9B7CC' 'SemiBold')
[System.Windows.Controls.Grid]::SetColumn($badge, 1)
[void]$head.Children.Add($badge)
[void]$content.Children.Add($head)

$sub = Txt "Install the glass dock, system HUD, clock and music widget for $env:USERNAME." 11.5 '#8FA3BF'
$sub.TextWrapping = 'Wrap'
$sub.Margin = Th 0 14 0 0
[void]$content.Children.Add($sub)

# info card
$info = New-Object System.Windows.Controls.Border
$info.CornerRadius = CR 12
$info.Background = Br '#08FFFFFF'
$info.BorderThickness = Th 1 1 1 1
$info.BorderBrush = Br '#14FFFFFF'
$info.Padding = Th 16 13 16 13
$info.Margin = Th 0 16 0 0
$infoStack = New-Object System.Windows.Controls.StackPanel
$lbl1 = Txt 'INSTALLS FOR' 9 '#6F7F97' 'SemiBold'
$lbl1.TextWrapping = 'NoWrap'
[void]$infoStack.Children.Add($lbl1)
$val1 = Txt "$env:USERDOMAIN\$env:USERNAME" 12 '#E8EEF8'
$val1.TextWrapping = 'NoWrap'
$val1.Margin = Th 0 1 0 9
[void]$infoStack.Children.Add($val1)
$lbl2 = Txt 'LOCATION' 9 '#6F7F97' 'SemiBold'
$lbl2.TextWrapping = 'NoWrap'
[void]$infoStack.Children.Add($lbl2)
$val2 = Txt $InstallDir 11 '#A9B7CC'
$val2.Margin = Th 0 1 0 0
[void]$infoStack.Children.Add($val2)
$info.Child = $infoStack
[void]$content.Children.Add($info)

# options
$optTitle = Txt 'INSTALLATION OPTIONS' 9 '#6F7F97' 'SemiBold'
$optTitle.TextWrapping = 'NoWrap'
$optTitle.Margin = Th 2 18 0 10
[void]$content.Children.Add($optTitle)
$cbTasks = New-Check 'Start automatically when I sign in' $true
$cbWatch = New-Check 'Keep the widgets running (restart within a minute if closed)' $true
$cbShort = New-Check 'Create Start Menu shortcuts' $true
$cbWall = New-Check 'Apply the UNLOCK DIGITAL wallpaper' (-not $NoWallpaper)
$cbBar = New-Check 'Apply dark theme + clean taskbar  (restarts Explorer)' $false
[void]$content.Children.Add($cbTasks)
[void]$content.Children.Add($cbWatch)
[void]$content.Children.Add($cbShort)
[void]$content.Children.Add($cbWall)
[void]$content.Children.Add($cbBar)

$note = Txt 'No admin rights needed. Everything is installed for the current user.' 10 '#6F7F97'
$note.Margin = Th 0 0 0 0
[void]$content.Children.Add($note)

# status
$status = Txt '' 11 '#8FA3BF'
$status.Margin = Th 0 14 0 6
[void]$content.Children.Add($status)
$prog = New-Object System.Windows.Controls.ProgressBar
$prog.Height = 4
$prog.IsIndeterminate = $true
$prog.Visibility = 'Collapsed'
$prog.Foreground = Gradient 0 0 1 0 @(@('#4CC2FF', 0), @('#8B5CF6', 1))
$prog.Background = Br '#12FFFFFF'
$prog.BorderThickness = Th 0 0 0 0
$prog.Margin = Th 0 0 0 14
[void]$content.Children.Add($prog)

# buttons
$btnRow = New-Object System.Windows.Controls.StackPanel
$btnRow.Orientation = 'Horizontal'
$btnRow.HorizontalAlignment = 'Right'
$btnRow.Margin = Th 0 6 0 0
$btnCancel = New-ActionButton 'Cancel' $false { $win.Close() }
$btnCancel.Margin = Th 0 0 10 0
$btnInstall = New-ActionButton 'Install' $true { }
[void]$btnRow.Children.Add($btnCancel)
[void]$btnRow.Children.Add($btnInstall)
[void]$content.Children.Add($btnRow)

# close button
$close = New-Object System.Windows.Controls.Border
$close.Width = 30; $close.Height = 30
$close.CornerRadius = CR 7
$close.Background = Br '#00FFFFFF'
$close.HorizontalAlignment = 'Right'
$close.VerticalAlignment = 'Top'
$close.Margin = Th 0 0 14 0
$close.Cursor = 'Hand'
$closeT = Txt ([string][char]0x2715) 12 '#7C8CA3' 'SemiBold'
$closeT.HorizontalAlignment = 'Center'; $closeT.VerticalAlignment = 'Center'
$closeT.TextWrapping = 'NoWrap'
$close.Child = $closeT
$close.Add_MouseEnter({ param($s, $e) try { $s.Background = Br '#18FFFFFF' } catch { } })
$close.Add_MouseLeave({ param($s, $e) try { $s.Background = Br '#00FFFFFF' } catch { } })
$close.Add_MouseLeftButtonUp({ param($s, $e) try { $win.Close() } catch { } })

# drag the window by its header only
$head.Add_MouseLeftButtonDown({ param($s, $e) try { $win.DragMove() } catch { } })

# the watchdog only makes sense together with the sign-in task
$cbWatch.Add_IsEnabledChanged({ param($s, $e) try { if (-not $cbTasks.IsChecked) { $s.IsChecked = $false } } catch { } })
$cbTasks.Add_Checked({ param($s, $e) try { $cbWatch.IsEnabled = $true } catch { } })
$cbTasks.Add_Unchecked({ param($s, $e) try { $cbWatch.IsEnabled = $false; $cbWatch.IsChecked = $false } catch { } })

# overlay close button on the root grid
$closeHost = New-Object System.Windows.Controls.Grid
$closeHost.Margin = Th 0 12 14 0
$closeHost.VerticalAlignment = 'Top'
$closeHost.HorizontalAlignment = 'Right'
[void]$closeHost.Children.Add($close)
[System.Windows.Controls.Grid]::SetRow($closeHost, 1)
[void]$outer.Children.Add($closeHost)

# install click
$btnInstall.Tag = {
    $btnInstall.IsEnabled = $false
    $btnCancel.IsEnabled = $false
    $status.Text = 'Starting...'
    $prog.Visibility = 'Visible'
    $win.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})
    $opts = @{
        Dir = $InstallDir
        Prefix = $TaskPrefix
        Tasks = [bool]$cbTasks.IsChecked
        Watchdog = [bool]($cbTasks.IsChecked -and $cbWatch.IsChecked)
        Shortcuts = [bool]$cbShort.IsChecked
        Registry = $true
        Wallpaper = [bool]$cbWall.IsChecked
        Taskbar = [bool]$cbBar.IsChecked
        Launch = $true
        TestMode = [bool]$TestMode
    }
    try {
        Invoke-Install $opts {
            param($msg)
            $status.Text = $msg
            try { $win.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{}) } catch { }
        } | Out-Null
        $prog.Visibility = 'Collapsed'
        Show-Success $opts
    } catch {
        $prog.Visibility = 'Collapsed'
        $status.Text = 'Installation failed.'
        $status.Foreground = Br '#F87171'
        [void][System.Windows.MessageBox]::Show($win, ("Could not finish the installation.`n`n" + $_.Exception.Message + "`n`nLog: " + $script:InstallLog), 'UNLOCK DIGITAL Setup', 'OK', 'Error')
        $btnInstall.IsEnabled = $true
        $btnCancel.IsEnabled = $true
    }
}

function Show-Success([hashtable]$o) {
    $content.Children.Clear()
    $ok = New-Object System.Windows.Controls.Border
    $ok.Width = 58; $ok.Height = 58
    $ok.CornerRadius = CR 29
    $ok.Background = Br '#1A34D399'
    $ok.BorderBrush = Br '#5534D399'
    $ok.BorderThickness = Th 1 1 1 1
    $ok.HorizontalAlignment = 'Left'
    $ok.Child = (Txt ([string][char]0x2713) 24 '#34D399' 'Bold')
    $ok.Child.HorizontalAlignment = 'Center'; $ok.Child.VerticalAlignment = 'Center'; $ok.Child.TextWrapping = 'NoWrap'
    [void]$content.Children.Add($ok)

    $h = Txt 'Installed successfully' 22 '#F4F8FF' 'Bold'
    $h.Margin = Th 0 16 0 0
    $h.TextWrapping = 'NoWrap'
    [void]$content.Children.Add($h)
    $p = Txt 'The widgets are starting now. Settings and the uninstaller are in the Start Menu under "UNLOCK DIGITAL".' 11.5 '#8FA3BF'
    $p.Margin = Th 0 8 0 0
    [void]$content.Children.Add($p)

    $pathCard = New-Object System.Windows.Controls.Border
    $pathCard.CornerRadius = CR 10
    $pathCard.Background = Br '#08FFFFFF'
    $pathCard.BorderBrush = Br '#14FFFFFF'
    $pathCard.BorderThickness = Th 1 1 1 1
    $pathCard.Padding = Th 14 10 14 10
    $pathCard.Margin = Th 0 18 0 0
    $pathCard.Child = (Txt $o.Dir 10.5 '#A9B7CC')
    [void]$content.Children.Add($pathCard)

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.HorizontalAlignment = 'Right'
    $row.Margin = Th 0 26 0 0
    $b1 = New-ActionButton 'Open folder' $false { try { Start-Process explorer.exe $o.Dir } catch { } }
    $b1.Margin = Th 0 0 10 0
    $b2 = New-ActionButton 'Done' $true { $win.Close() }
    [void]$row.Children.Add($b1)
    [void]$row.Children.Add($b2)
    [void]$content.Children.Add($row)
}

# window chrome drag from the empty glass area
$root.Add_MouseLeftButtonDown({
    param($s, $e)
    try {
        if ($e.OriginalSource -is [System.Windows.Controls.TextBlock]) { return }  # keep buttons/links usable
        $win.DragMove()
    } catch { }
})

$win.Add_Loaded({
    try { $win.Activate() } catch { }
})

[void]$win.ShowDialog()
