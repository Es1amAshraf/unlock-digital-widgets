# ProDesktopWidgets.ps1 — UNLOCK DIGITAL desktop suite
#   * App Dock   : floating glass dock with your apps (bottom-centre)
#   * System HUD : live CPU / RAM / Disk / Network speed / Ping (top-left)
#   * Clock      : glass clock with seconds, date and seconds progress (drag to move)
#
# Usage:
#   powershell -STA -ExecutionPolicy Bypass -File .\ProDesktopWidgets.ps1
#   powershell -STA -ExecutionPolicy Bypass -File .\ProDesktopWidgets.ps1 -Preview   (render PNG previews and exit)
#   powershell -STA -ExecutionPolicy Bypass -File .\ProDesktopWidgets.ps1 -Reset     (reset app list)
#   powershell -STA -ExecutionPolicy Bypass -File .\ProDesktopWidgets.ps1 -MakeConfig (create the default config and exit)
#   powershell -STA -ExecutionPolicy Bypass -File .\ProDesktopWidgets.ps1 -WidgetsManager  (open the widgets manager at start)

param(
    [switch]$NoDock,
    [switch]$NoHud,
    [switch]$NoMusic,
    [switch]$NoClock,
    [switch]$NoCalendar,
    [switch]$NoFocus,
    [switch]$NoNotes,
    [switch]$NoWeather,
    [switch]$Reset,
    [switch]$Preview,
    [switch]$MakeConfig,
    [switch]$WidgetsManager
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

# ---------------- never show a console window ----------------
# The widgets must live purely in the background: no console, no taskbar tab.
try {
    Add-Type -Namespace UD -Name Con -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
    $conHwnd = [UD.Con]::GetConsoleWindow()
    if ($conHwnd -ne [IntPtr]::Zero) { [void][UD.Con]::ShowWindow($conHwnd, 0) }
} catch { }

# ---------------- make sure we are STA (WPF needs it) ----------------
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $actualScriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { Join-Path $PSScriptRoot 'ProDesktopWidgets.ps1' }
    $args2 = @('-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$actualScriptPath`"")
    if ($NoDock) { $args2 += '-NoDock' }
    if ($NoHud) { $args2 += '-NoHud' }
    if ($NoMusic) { $args2 += '-NoMusic' }
    if ($NoClock) { $args2 += '-NoClock' }
    if ($NoCalendar) { $args2 += '-NoCalendar' }
    if ($NoFocus) { $args2 += '-NoFocus' }
    if ($NoNotes) { $args2 += '-NoNotes' }
    if ($NoWeather) { $args2 += '-NoWeather' }
    if ($Reset) { $args2 += '-Reset' }
    if ($Preview) { $args2 += '-Preview' }
    if ($MakeConfig) { $args2 += '-MakeConfig' }
    if ($WidgetsManager) { $args2 += '-WidgetsManager' }
    Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $args2 -WindowStyle Hidden
    exit
}

# ---------------- single instance ----------------
$mutexName = 'Global\UnlockDigitalProDesktopWidgets'
if ($Preview) { $mutexName = 'Global\UnlockDigitalProDesktopWidgetsPreview' }
$mutex = $null
if (-not $MakeConfig) {
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    if (-not $mutex.WaitOne(0)) { exit }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

# WinForms (tray menu) exceptions must never pop the .NET crash dialog: log and keep running.
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({
        param($s, $e)
        try { Write-WidgetError $e.Exception 'winforms' } catch { }
        try { if ($script:tray) { $script:tray.ShowBalloonTip(4000, 'UNLOCK DIGITAL', 'An action failed. Details are in widgets-error.log.', 'Warning') } } catch { }
    })
} catch { }

$actualScriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { Join-Path $PSScriptRoot 'ProDesktopWidgets.ps1' }
$ConfigDir  = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $actualScriptPath }
$ConfigPath = Join-Path $ConfigDir 'widgets.json'
$NotesPath  = Join-Path $ConfigDir 'notes.txt'
$PreviewDir = Join-Path $env:TEMP 'UNLOCK DIGITAL'
try { if (-not (Test-Path -LiteralPath $PreviewDir)) { New-Item -ItemType Directory -Path $PreviewDir -Force | Out-Null } } catch { }

# record UI errors instead of letting them take down every widget
function Write-WidgetError($err, [string]$where) {
    try {
        $msg = "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$where] ===`r`n"
        if ($err -is [System.Management.Automation.ErrorRecord]) {
            $msg += $err.Exception.ToString() + "`r`n---`r`n" + $err.ScriptStackTrace
        } else {
            $msg += [string]$err
        }
        Add-Content -LiteralPath (Join-Path $PreviewDir 'widgets-error.log') -Value ($msg + "`r`n") -Encoding UTF8
    } catch { }
}

# ---------------- native helpers ----------------
$native = @'
using System;
using System.Runtime.InteropServices;

public static class UDWin
{
    [StructLayout(LayoutKind.Sequential)]
    public struct FILETIME { public uint Low; public uint High; }
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORYSTATUSEX
    {
        public uint dwLength; public uint dwMemoryLoad;
        public ulong ullTotalPhys; public ulong ullAvailPhys;
        public ulong ullTotalPageFile; public ulong ullAvailPageFile;
        public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetSystemTimes(out FILETIME idle, out FILETIME kernel, out FILETIME user);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SHFILEINFO
    {
        public IntPtr hIcon; public int iIcon; public uint dwAttributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szDisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string szTypeName;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SHGetFileInfo(string pszPath, uint dwFileAttributes, ref SHFILEINFO psfi, uint cbFileInfo, uint uFlags);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr hIcon);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr hObject);

    // --- icons for packaged (Store / UWP) apps and shell items ---
    [StructLayout(LayoutKind.Sequential)] public struct SIZEL { public int cx; public int cy; }
    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItemImageFactory { [PreserveSig] int GetImage(SIZEL size, int flags, out IntPtr phbm); }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    public static extern void SHCreateItemFromParsingName(string pszPath, IntPtr pbc, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory factory);
    public static IntPtr GetShellImage(string parsingName, int size, int flags)
    {
        try
        {
            Guid iid = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b");
            IShellItemImageFactory f = null;
            SHCreateItemFromParsingName(parsingName, IntPtr.Zero, ref iid, out f);
            if (f == null) return IntPtr.Zero;
            SIZEL s; s.cx = size; s.cy = size;
            IntPtr hbm = IntPtr.Zero;
            int hr = f.GetImage(s, flags, out hbm);
            if (hr != 0) return IntPtr.Zero;
            return hbm;
        }
        catch { return IntPtr.Zero; }
    }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

    // --- window titles (browser "now playing" fallback) + global media keys ---
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public static System.Collections.Generic.List<string> GetVisibleWindowTitles()
    {
        var list = new System.Collections.Generic.List<string>();
        try
        {
            EnumWindows(delegate(IntPtr h, IntPtr p)
            {
                try
                {
                    if (!IsWindowVisible(h)) return true;
                    var sb = new System.Text.StringBuilder(512);
                    GetWindowText(h, sb, 512);
                    if (sb.Length > 3) list.Add(sb.ToString());
                }
                catch { }
                return true;
            }, IntPtr.Zero);
        }
        catch { }
        return list;
    }

    public static void MediaKey(byte vk)
    {
        try
        {
            keybd_event(vk, 0, 0, UIntPtr.Zero);
            System.Threading.Thread.Sleep(30);
            keybd_event(vk, 0, 2, UIntPtr.Zero);
        }
        catch { }
    }

    // --- focus an already-running app instead of opening a second copy ---
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    // --- fullscreen detection (auto-hide widgets while a game/video is fullscreen) ---
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint dwFlags);
    [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO
    {
        public uint cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags;
    }

    public static bool IsFullscreenWindow(IntPtr hWnd, uint ignorePid)
    {
        try
        {
            if (hWnd == IntPtr.Zero || !IsWindowVisible(hWnd) || IsIconic(hWnd) || IsZoomed(hWnd)) return false;
            uint pid = 0; GetWindowThreadProcessId(hWnd, out pid);
            if (pid == ignorePid) return false;
            var sb = new System.Text.StringBuilder(64);
            GetClassName(hWnd, sb, 64);
            string cls = sb.ToString();
            if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd") return false;
            RECT r; if (!GetWindowRect(hWnd, out r)) return false;
            IntPtr mon = MonitorFromWindow(hWnd, 2); // MONITOR_DEFAULTTONEAREST
            MONITORINFO mi = new MONITORINFO();
            mi.cbSize = (uint)Marshal.SizeOf(mi);
            if (!GetMonitorInfo(mon, ref mi)) return false;
            int tol = 3;
            bool covers = Math.Abs(r.L - mi.rcMonitor.L) <= tol && Math.Abs(r.T - mi.rcMonitor.T) <= tol
                       && Math.Abs(r.R - mi.rcMonitor.R) <= tol && Math.Abs(r.B - mi.rcMonitor.B) <= tol;
            return covers && (r.R - r.L) >= 640 && (r.B - r.T) >= 480;
        }
        catch { return false; }
    }

    [DllImport("shell32.dll")] public static extern int SHQueryUserNotificationState(out int s);

    public static bool ForceForeground(IntPtr hWnd)
    {
        try
        {
            if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) return false;
            IntPtr fg = GetForegroundWindow();
            uint fgThread = 0, targetThread = 0, pid = 0;
            if (fg != IntPtr.Zero) fgThread = GetWindowThreadProcessId(fg, out pid);
            targetThread = GetWindowThreadProcessId(hWnd, out pid);
            uint cur = GetCurrentThreadId();
            bool a1 = false, a2 = false;
            if (fgThread != 0 && fgThread != cur) a1 = AttachThreadInput(cur, fgThread, true);
            if (targetThread != 0 && targetThread != cur) a2 = AttachThreadInput(cur, targetThread, true);
            try
            {
                if (IsIconic(hWnd)) ShowWindow(hWnd, 9);   // SW_RESTORE
                else ShowWindow(hWnd, 5);                  // SW_SHOW
                BringWindowToTop(hWnd);
                SetForegroundWindow(hWnd);
            }
            finally
            {
                if (a1) AttachThreadInput(cur, fgThread, false);
                if (a2) AttachThreadInput(cur, targetThread, false);
            }
            return true;
        }
        catch { return false; }
    }

    // visible, titled top-level windows that belong to one process
    public static IntPtr[] GetProcessWindows(uint pid)
    {
        var list = new System.Collections.Generic.List<IntPtr>();
        try
        {
            EnumWindows(delegate(IntPtr h, IntPtr p)
            {
                try
                {
                    if (!IsWindowVisible(h)) return true;
                    uint wpid = 0;
                    GetWindowThreadProcessId(h, out wpid);
                    if (wpid != pid) return true;
                    int ex = GetWindowLong(h, GWL_EXSTYLE);
                    if ((ex & WS_EX_TOOLWINDOW) != 0) return true;
                    if (GetWindowTextLength(h) == 0) return true;
                    RECT r; if (!GetWindowRect(h, out r)) return true;
                    if (r.R - r.L < 40 || r.B - r.T < 30) return true;
                    list.Add(h);
                }
                catch { }
                return true;
            }, IntPtr.Zero);
        }
        catch { }
        return list.ToArray();
    }

    // pid -> how many real windows it owns (one pass for all dock apps)
    public static System.Collections.Generic.Dictionary<uint,int> GetVisibleWindowCounts()
    {
        var d = new System.Collections.Generic.Dictionary<uint,int>();
        try
        {
            EnumWindows(delegate(IntPtr h, IntPtr p)
            {
                try
                {
                    if (!IsWindowVisible(h)) return true;
                    if (GetWindowTextLength(h) == 0) return true;
                    int ex = GetWindowLong(h, GWL_EXSTYLE);
                    if ((ex & WS_EX_TOOLWINDOW) != 0) return true;
                    RECT r; if (!GetWindowRect(h, out r)) return true;
                    if (r.R - r.L < 40 || r.B - r.T < 30) return true;
                    uint pid = 0; GetWindowThreadProcessId(h, out pid);
                    int n; d.TryGetValue(pid, out n);
                    d[pid] = n + 1;
                }
                catch { }
                return true;
            }, IntPtr.Zero);
        }
        catch { }
        return d;
    }

    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const int WS_EX_NOACTIVATE = 0x08000000;
    public const int WS_EX_TRANSPARENT = 0x00000020;
    public const uint SHGFI_ICON = 0x000000100;
    public const uint SHGFI_LARGEICON = 0x000000000;
    public const uint SHGFI_SMALLICON = 0x000000001;

    // --- async weather fetcher (runs pure C# on ThreadPool, zero PowerShell TLS dependency) ---
    private static volatile string _weatherResult = null;
    private static volatile bool _weatherFetching = false;
    public static void FetchWeatherAsync(string url)
    {
        if (_weatherFetching) return;
        _weatherFetching = true;
        System.Threading.ThreadPool.QueueUserWorkItem(_ =>
        {
            try
            {
                using (var wc = new System.Net.WebClient())
                {
                    wc.Headers["User-Agent"] = "Mozilla/5.0";
                    string res = wc.DownloadString(url);
                    _weatherResult = res;
                }
            }
            catch {}
            finally
            {
                _weatherFetching = false;
            }
        });
    }

    public static string PollWeatherResult()
    {
        if (_weatherResult == null) return null;
        string res = _weatherResult;
        _weatherResult = null;
        return res;
    }
}
'@
Add-Type -TypeDefinition $native -ReferencedAssemblies 'System.Drawing' -ErrorAction SilentlyContinue

# ---------------- brushes / helpers ----------------
$script:BrushCache = @{}
function Br([string]$hex) {
    if (-not $script:BrushCache.ContainsKey($hex)) {
        $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
        $b.Freeze()
        $script:BrushCache[$hex] = $b
    }
    return $script:BrushCache[$hex]
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
    $t.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
    $t.VerticalAlignment = 'Center'
    return $t
}
function New-ThemeGlass([double]$x1 = 0.1, [double]$y1 = 0, [double]$x2 = 0.9, [double]$y2 = 1) {
    $g = New-Object System.Windows.Media.LinearGradientBrush
    $g.StartPoint = New-Object System.Windows.Point($x1, $y1)
    $g.EndPoint = New-Object System.Windows.Point($x2, $y2)
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($script:theme.bg1), 0)))
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($script:theme.bg2), 1)))
    return $g
}
function New-ThemeAccent2([double]$x1 = 0, [double]$y1 = 0, [double]$x2 = 1, [double]$y2 = 0) {
    $g = New-Object System.Windows.Media.LinearGradientBrush
    $g.StartPoint = New-Object System.Windows.Point($x1, $y1)
    $g.EndPoint = New-Object System.Windows.Point($x2, $y2)
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($script:theme.accent1), 0)))
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($script:theme.accent2), 1)))
    return $g
}
function New-ThemeAccent3 {
    $g = New-Object System.Windows.Media.LinearGradientBrush
    $g.StartPoint = New-Object System.Windows.Point(0, 0)
    $g.EndPoint = New-Object System.Windows.Point(1, 0)
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($script:theme.accent1), 0)))
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($script:theme.accent2), 0.55)))
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($script:theme.accent3), 1)))
    return $g
}

function Get-FileIcon([string]$path, [int]$size = 32) {
    try {
    $hIcon = [IntPtr]::Zero
    if (Test-Path -LiteralPath $path) {
        $shfi = New-Object UDWin+SHFILEINFO
        $flags = [uint32]([UDWin]::SHGFI_ICON -bor $(if ($size -le 16) { [UDWin]::SHGFI_SMALLICON } else { [UDWin]::SHGFI_LARGEICON }))
        $res = [UDWin]::SHGetFileInfo($path, 0, [ref]$shfi, [System.Runtime.InteropServices.Marshal]::SizeOf($shfi), $flags)
        if ($res -ne [IntPtr]::Zero -and $shfi.hIcon -ne [IntPtr]::Zero) { $hIcon = $shfi.hIcon }
    }
    if ($hIcon -eq [IntPtr]::Zero) {
        # not a plain file (packaged app, protocol like ms-settings:, folder) -> ask the shell for its image
        $pn = Resolve-ShellParsingName $path
        if ($pn) {
            $hb = [UDWin]::GetShellImage($pn, 64, 4)   # SIIGBF_ICONONLY
            if ($hb -ne [IntPtr]::Zero) {
                try {
                    $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap($hb, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
                    $src.Freeze()
                    return $src
                } finally { [void][UDWin]::DeleteObject($hb) }
            }
        }
        return $null
    }
    try {
        $bmp = [System.Drawing.Icon]::FromHandle($hIcon).ToBitmap()
        $hb = $bmp.GetHbitmap()
        try {
            $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap($hb, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
            $src.Freeze()
            return $src
        } finally { [void][UDWin]::DeleteObject($hb) }
        $bmp.Dispose()
    } finally {
        [void][UDWin]::DestroyIcon($hIcon)
    }
    } catch {
        return $null
    }
}

# ---------------- resolve anything to a shell parsing name ----------------
$script:AppsFolderMap = $null
function Get-AppsFolderMap {
    if ($script:AppsFolderMap) { return $script:AppsFolderMap }
    $map = @{}
    try {
        $sh = New-Object -ComObject Shell.Application
        foreach ($it in @($sh.NameSpace('shell:AppsFolder').Items())) {
            if (-not $it.Path) { continue }
            $map[([string]$it.Path).ToLower()] = [string]$it.Path
            if ($it.Name) {
                $k = ([string]$it.Name).ToLower()
                if (-not $map.ContainsKey($k)) { $map[$k] = [string]$it.Path }
            }
        }
    } catch { }
    $script:AppsFolderMap = $map
    return $map
}

function Resolve-ShellParsingName([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if (Test-Path -LiteralPath $path) { return $path }
    if ($path -like 'shell:*') { return $path }
    if ($path -match '!') { return "shell:AppsFolder\$path" }   # packaged app (AppUserModelID)
    if ($path -match '^([a-zA-Z][a-zA-Z0-9+.\-]*):') {
        $map = Get-AppsFolderMap
        $key = $null
        switch -Regex ($path) {
            '^ms-settings:'        { $key = 'settings' }
            '^ms-windows-store:'   { $key = 'store' }
            '^ms-clock:'           { $key = 'clock' }
            '^ms-calculator:'      { $key = 'calculator' }
            '^ms-photos:'          { $key = 'photos' }
            '^ms-get-started:'     { $key = 'tips' }
        }
        if ($key -and $map.ContainsKey($key)) { return "shell:AppsFolder\$($map[$key])" }
        if ($path -eq 'ms-settings:') { return 'shell:AppsFolder\windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel' }
        return $null
    }
    return $null
}

# ---------------- config ----------------
function Resolve-StartMenu([string]$baseName) {
    $roots = @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs")
    $sh = New-Object -ComObject WScript.Shell
    foreach ($r in $roots) {
        $f = Get-ChildItem -Path $r -Filter "$baseName.lnk" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) {
            $sc = $sh.CreateShortcut($f.FullName)
            if ($sc.TargetPath) { return @{ path = $sc.TargetPath; args = $sc.Arguments } }
        }
    }
    return $null
}

$seedNames = [ordered]@{
    'Yandex'                = $null
    'Microsoft Edge'        = $null
    'Discord'               = @{ path = "$env:LOCALAPPDATA\Discord\Discord.exe"; args = '' }
    'OpenCode'              = @{ path = "$env:LOCALAPPDATA\Programs\@opencodedesktop\OpenCode.exe"; args = '' }
    'Word'                  = $null
    'Excel'                 = $null
    'Outlook (classic)'     = $null
    'OneNote'               = $null
    'VMware Workstation Pro' = $null
    'TeamViewer'            = $null
    'Git Bash'              = $null
    'WinRAR'                = $null
}

function Get-DefaultApps {
    $apps = New-Object System.Collections.ArrayList
    foreach ($k in $seedNames.Keys) {
        $hit = $null
        if ($seedNames[$k]) {
            if (Test-Path -LiteralPath $seedNames[$k].path) { $hit = $seedNames[$k] }
        }
        if (-not $hit) { $hit = Resolve-StartMenu $k }
        if ($hit -and (Test-Path -LiteralPath $hit.path)) {
            [void]$apps.Add([pscustomobject]@{ name = ($k -replace '\s*\(classic\)', ''); path = $hit.path; args = [string]$hit.args })
        }
    }
    [void]$apps.Add([pscustomobject]@{ name = 'File Explorer'; path = "$env:WINDIR\explorer.exe"; args = '' })
    [void]$apps.Add([pscustomobject]@{ name = 'Task Manager';  path = "$env:WINDIR\System32\taskmgr.exe"; args = '' })
    [void]$apps.Add([pscustomobject]@{ name = 'Settings';      path = 'ms-settings:'; args = '' })
    return $apps
}

$script:widgetKeyList = @('hud', 'dock', 'music', 'clock', 'calendar', 'focus', 'notes', 'weather')

function New-WidgetStateMap([string[]]$trueKeys) {
    $m = [ordered]@{}
    foreach ($k in $script:widgetKeyList) { $m[$k] = [bool]($trueKeys -contains $k) }
    return $m
}

function Get-DefaultProfiles {
    return [ordered]@{
        work  = [ordered]@{ label = 'Work';  description = 'System HUD, music, clock and weather on the desk.'; visible = (New-WidgetStateMap @('hud', 'dock', 'music', 'clock', 'notes', 'weather')); topmost = (New-WidgetStateMap); locked = (New-WidgetStateMap) }
        focus = [ordered]@{ label = 'Focus'; description = 'Quiet desk: clock, focus timer and HUD only.'; visible = (New-WidgetStateMap @('hud', 'dock', 'clock', 'focus')); topmost = (New-WidgetStateMap @('focus')); locked = (New-WidgetStateMap) }
        night = [ordered]@{ label = 'Night'; description = 'Dim desk: clock, notes and weather, no HUD or music.'; visible = (New-WidgetStateMap @('dock', 'clock', 'notes', 'weather')); topmost = (New-WidgetStateMap); locked = (New-WidgetStateMap) }
        game  = [ordered]@{ label = 'Game';  description = 'Dock only. Fullscreen auto-hide clears the screen while playing.'; visible = (New-WidgetStateMap @('dock')); topmost = (New-WidgetStateMap); locked = (New-WidgetStateMap) }
    }
}

function Get-ThemePalette([string]$id) {
    switch ([string]$id) {
        'ocean' {
            return @{ id = 'ocean'; name = 'Ocean'; bg1 = '#F5081B2A'; bg2 = '#F5030D16'; accent1 = '#22D3EE'; accent2 = '#0EA5E9'; accent3 = '#2DD4BF'; glow = '#22D3EE' }
        }
        'amethyst' {
            return @{ id = 'amethyst'; name = 'Amethyst'; bg1 = '#F5160F2A'; bg2 = '#F5090714'; accent1 = '#C084FC'; accent2 = '#8B5CF6'; accent3 = '#F472B6'; glow = '#A78BFA' }
        }
        'ember' {
            return @{ id = 'ember'; name = 'Ember'; bg1 = '#F51B100D'; bg2 = '#F50C0605'; accent1 = '#FB923C'; accent2 = '#F97316'; accent3 = '#FBBF24'; glow = '#FB923C' }
        }
        'graphite' {
            return @{ id = 'graphite'; name = 'Graphite'; bg1 = '#F514161A'; bg2 = '#F508090B'; accent1 = '#E2E8F0'; accent2 = '#94A3B8'; accent3 = '#60A5FA'; glow = '#94A3B8' }
        }
        default {
            return @{ id = 'midnight'; name = 'Midnight'; bg1 = '#F50C1220'; bg2 = '#F5060A12'; accent1 = '#38BDF8'; accent2 = '#8B5CF6'; accent3 = '#34D399'; glow = '#5B8CFF' }
        }
    }
}

function New-DefaultConfig {
    return [ordered]@{
        hud        = [ordered]@{ enabled = $true;  visible = $true; topmost = $false; locked = $false; side = 'left'; maskIp = $false }
        dock       = [ordered]@{ enabled = $true;  visible = $true; topmost = $false; autohide = $false; effects = $true; apps = (Get-DefaultApps) }
        music      = [ordered]@{ enabled = $true;  visible = $true; topmost = $false; locked = $false }
        clock      = [ordered]@{ enabled = $true;  visible = $true; topmost = $false; locked = $false; h24 = $false; seconds = $true }
        calendar   = [ordered]@{ enabled = $true;  visible = $true; topmost = $false; locked = $false; monday = $false }
        focus      = [ordered]@{ enabled = $true;  visible = $true; topmost = $false; locked = $false; workMin = 25; breakMin = 5 }
        notes      = [ordered]@{ enabled = $true;  visible = $true; topmost = $false; locked = $false }
        weather    = [ordered]@{ enabled = $true;  visible = $true; topmost = $false; locked = $false; showPrayer = $true; city = 'Cairo'; country = 'Egypt'; lat = 30.0444; lon = 31.2357; method = 5 }
        appearance = [ordered]@{ theme = 'midnight'; opacity = 1.0; scale = 100; lowPower = $false; fullscreenHide = $true }
        profiles   = (Get-DefaultProfiles)
    }
}

if ($Reset -and (Test-Path -LiteralPath $ConfigPath)) { Remove-Item -LiteralPath $ConfigPath -Force }

if (Test-Path -LiteralPath $ConfigPath) {
    try { $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $cfg = $null }
}
if (-not $cfg -or -not $cfg.dock) {
    $cfg = New-DefaultConfig
    ($cfg | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    Write-Output "config created: $ConfigPath"
}

$script:cfg = $cfg
$cfgJson = @{ Path = $ConfigPath }
if (-not $cfg.music) {
    if ($cfg -is [System.Collections.IDictionary]) { $cfg['music'] = [ordered]@{ enabled = $true; topmost = $false } }
    else { $cfg | Add-Member -NotePropertyName music -NotePropertyValue ([pscustomobject]@{ enabled = $true; topmost = $false }) -Force }
}
function Save-Config {
    ($script:cfg | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $script:cfgJson.Path -Encoding UTF8
}
# config values can live in a hashtable or in a JSON (pscustomobject) — read/write both safely
function Get-Cfg($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IDictionary]) { if ($obj.Contains($name)) { return $obj[$name] } return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($p) { return $p.Value }
    return $null
}
function Set-Cfg($obj, [string]$name, $value) {
    if ($null -eq $obj) { return }
    if ($obj -is [System.Collections.IDictionary]) { $obj[$name] = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
}
# old config files may miss newer keys (side, maskIp, x, y...) — fill every known key once
$defCfg = New-DefaultConfig
$cfgChanged = $false
foreach ($sec in @('hud', 'dock', 'music', 'clock', 'calendar', 'focus', 'notes', 'weather', 'appearance')) {
    $cur = Get-Cfg $cfg $sec
    if ($null -eq $cur) { Set-Cfg $cfg $sec ([pscustomobject]@{}); $cur = Get-Cfg $cfg $sec; $cfgChanged = $true }
    foreach ($k in @($defCfg[$sec].Keys)) {
        if ($null -eq (Get-Cfg $cur $k)) { Set-Cfg $cur $k $defCfg[$sec][$k]; $cfgChanged = $true }
    }
}

# profiles are new in 1.3.0 - seed the four built-in layouts and repair incomplete ones
$defProfiles = Get-DefaultProfiles
$profilesCfg = Get-Cfg $cfg 'profiles'
if ($null -eq $profilesCfg) {
    Set-Cfg $cfg 'profiles' $defProfiles
    $profilesCfg = Get-Cfg $cfg 'profiles'
    $cfgChanged = $true
}
foreach ($pn in @($defProfiles.Keys)) {
    $p = Get-Cfg $profilesCfg $pn
    if ($null -eq $p) { Set-Cfg $profilesCfg $pn $defProfiles[$pn]; $p = Get-Cfg $profilesCfg $pn; $cfgChanged = $true }
    foreach ($fld in @('label', 'description')) {
        if ($null -eq (Get-Cfg $p $fld)) { Set-Cfg $p $fld $defProfiles[$pn][$fld]; $cfgChanged = $true }
    }
    foreach ($fld in @('visible', 'topmost', 'locked')) {
        $map = Get-Cfg $p $fld
        if ($null -eq $map) { Set-Cfg $p $fld (New-WidgetStateMap); $map = Get-Cfg $p $fld; $cfgChanged = $true }
        foreach ($k in $script:widgetKeyList) {
            if ($null -eq (Get-Cfg $map $k)) { Set-Cfg $map $k $false; $cfgChanged = $true }
        }
    }
}
if ($cfgChanged) { try { Save-Config } catch { } }

# ---------------- appearance / theme ----------------
$script:appearance = Get-Cfg $cfg 'appearance'
$script:themeId = [string](Get-Cfg $script:appearance 'theme')
if (@('midnight', 'ocean', 'amethyst', 'ember', 'graphite') -notcontains $script:themeId) { $script:themeId = 'midnight' }
$script:theme = Get-ThemePalette $script:themeId
$appOpacity = Get-Cfg $script:appearance 'opacity'
if ($null -eq $appOpacity) { $appOpacity = 1.0 }
$script:appOpacity = [math]::Max(0.55, [math]::Min(1.0, [double]$appOpacity))
$appScale = Get-Cfg $script:appearance 'scale'
if ($null -eq $appScale) { $appScale = 100 }
$appScale = [int]$appScale
if (@(85, 100, 115) -notcontains $appScale) { $appScale = 100 }
$script:appScale = $appScale
$script:lowPower = [bool](Get-Cfg $script:appearance 'lowPower')
$script:fullscreenHide = [bool](Get-Cfg $script:appearance 'fullscreenHide')

if ($MakeConfig) { exit 0 }

# ---------------- widget controls: show / hide, pin, lock and move ----------------
$script:widgetKeys = @('hud', 'dock', 'music', 'clock', 'weather', 'calendar', 'focus', 'notes')
$script:wmg = $null
$script:moveState = $null

function Get-WidgetWindow([string]$key) {
    switch ($key) {
        'hud'      { return $script:hudWin }
        'dock'     { return $script:dockWin }
        'music'    { return $script:musicWin }
        'clock'    { return $script:clockWin }
        'weather'  { return $script:weatherWin }
        'calendar' { return $script:calendarWin }
        'focus'    { return $script:focusWin }
        'notes'    { return $script:notesWin }
    }
    return $null
}

function Get-WidgetSection([string]$key) {
    if (-not $script:cfg) { return $null }
    switch ($key) {
        'hud'      { return $script:cfg.hud }
        'dock'     { return $script:cfg.dock }
        'music'    { return $script:cfg.music }
        'clock'    { return $script:cfg.clock }
        'weather'  { return $script:cfg.weather }
        'calendar' { return $script:cfg.calendar }
        'focus'    { return $script:cfg.focus }
        'notes'    { return $script:cfg.notes }
    }
    return $null
}

function Get-WidgetLabel([string]$key) {
    switch ($key) {
        'hud'      { return 'System HUD' }
        'dock'     { return 'Dock' }
        'music'    { return 'Music' }
        'clock'    { return 'Clock' }
        'weather'  { return 'Weather & prayer' }
        'calendar' { return 'Calendar' }
        'focus'    { return 'Focus timer' }
        'notes'    { return 'Quick notes' }
    }
    return $key
}

function Get-WidgetAccent([string]$key) {
    switch ($key) {
        'hud'      { return '#4CC2FF' }
        'dock'     { return '#8B5CF6' }
        'music'    { return '#F472B6' }
        'clock'    { return '#4CC2FF' }
        'weather'  { return '#22D3EE' }
        'calendar' { return '#38BDF8' }
        'focus'    { return '#34D399' }
        'notes'    { return '#FBBF24' }
    }
    return '#7C8CA3'
}

function Test-WidgetWanted([string]$key) {
    $sec = Get-WidgetSection $key
    if (-not $sec) { return $false }
    $v = Get-Cfg $sec 'visible'
    if ($null -eq $v) { return $true }
    return [bool]$v
}

function Test-WidgetShown([string]$key) {
    $sec = Get-WidgetSection $key
    if ($key -eq 'dock' -and [bool](Get-Cfg $sec 'autohide')) { return (Test-WidgetWanted $key) }
    $w = Get-WidgetWindow $key
    return [bool]($w -and $w.IsVisible)
}

function Set-WidgetVisible([string]$key, [bool]$show, [switch]$NoSave) {
    try {
        $w = Get-WidgetWindow $key
        $sec = Get-WidgetSection $key
        if (-not $w -or -not $sec) { return }
        if ($show) {
            $w.Show()
            if ($key -eq 'dock') {
                try { Set-DockPosition } catch { }
                if ([bool](Get-Cfg $sec 'autohide')) { Set-DockAutoHide $true }
            }
            Set-Cfg $sec 'visible' $true
        } else {
            if ($key -eq 'notes') { try { Save-Notes } catch { } }
            if ($key -eq 'dock' -and $script:dockAutoTimer) { $script:dockAutoTimer.Stop() }
            $w.Hide()
            Set-Cfg $sec 'visible' $false
        }
        if (-not $NoSave) { Save-Config }
        Update-WidgetManager
    } catch { Write-WidgetError $_ 'widget visibility' }
}

function Set-WidgetPinned([string]$key, [bool]$on) {
    try {
        $w = Get-WidgetWindow $key
        $sec = Get-WidgetSection $key
        if (-not $sec) { return }
        if ($w) { $w.Topmost = $on }
        Set-Cfg $sec 'topmost' $on
        Save-Config
        Update-WidgetManager
    } catch { }
}

function Set-WidgetLocked([string]$key, [bool]$on) {
    try {
        $sec = Get-WidgetSection $key
        if (-not $sec) { return }
        Set-Cfg $sec 'locked' $on
        Save-Config
        Update-WidgetManager
    } catch { }
}

function Add-WidgetMenuItems($menu, [string]$key) {
    try {
        $lock = New-Object System.Windows.Controls.MenuItem
        $lock.Header = 'Lock position'
        $lock.IsCheckable = $true
        $lock.IsChecked = [bool](Get-Cfg (Get-WidgetSection $key) 'locked')
        $lock.Tag = $key
        $lock.Add_Click({ param($s, $e) try { Set-WidgetLocked ([string]$s.Tag) ([bool]$s.IsChecked) } catch { } })
        [void]$menu.Items.Add($lock)

        $move = New-Object System.Windows.Controls.MenuItem
        $move.Header = 'Move widget…'
        $move.Tag = $key
        $move.Add_Click({ param($s, $e) try { Start-WidgetMove ([string]$s.Tag) } catch { } })
        [void]$menu.Items.Add($move)
    } catch { }
}

function Update-WidgetManager {
    try {
        if (-not $script:wmg -or -not $script:wmg.rows) { return }
        $visCount = 0
        $pinCount = 0
        foreach ($key in $script:widgetKeys) {
            $row = $script:wmg.rows[$key]
            if (-not $row) { continue }
            $w = Get-WidgetWindow $key
            $sec = Get-WidgetSection $key
            $enabled = $true
            if ($sec) {
                $ev = Get-Cfg $sec 'enabled'
                if ($null -ne $ev) { $enabled = [bool]$ev }
            }
            if (-not $enabled -or -not $w) {
                $row.state.Text = 'DISABLED IN CONFIG'
                $row.hide.Content = 'OFF'
                $row.hide.IsEnabled = $false
                $row.move.IsEnabled = $false
                $row.lock.IsEnabled = $false
                $row.top.IsEnabled = $false
                continue
            }
            $locked = [bool](Get-Cfg $sec 'locked')
            $top = [bool](Get-Cfg $sec 'topmost')
            $vis = $false
            if ($key -eq 'dock' -and [bool](Get-Cfg $sec 'autohide')) { $vis = [bool](Get-Cfg $sec 'visible') }
            else { $vis = [bool]$w.IsVisible }
            if ($vis) { $visCount++ }
            if ($top) { $pinCount++ }
            $state = if ($vis) { 'VISIBLE' } else { 'HIDDEN' }
            if ($locked) { $state += '  ·  LOCKED' }
            if ($top) { $state += '  ·  ON TOP' }
            $row.state.Text = $state
            $row.hide.Content = if ($vis) { 'HIDE' } else { 'SHOW' }
            $row.lock.Content = if ($locked) { 'UNLOCK' } else { 'LOCK' }
            $row.top.Content = if ($top) { 'TOP ON' } else { 'TOP OFF' }
            $row.hide.Style = if ($vis) { $script:btnStyle } else { $script:btnAccentStyle }
            $row.lock.Style = if ($locked) { $script:btnAccentStyle } else { $script:btnStyle }
            $row.top.Style = if ($top) { $script:btnAccentStyle } else { $script:btnStyle }
            try {
                $lbl = Get-WidgetLabel $key
                [System.Windows.Automation.AutomationProperties]::SetName($row.hide, $(if ($vis) { 'Hide ' + $lbl } else { 'Show ' + $lbl }))
                [System.Windows.Automation.AutomationProperties]::SetName($row.lock, $(if ($locked) { 'Unlock ' + $lbl } else { 'Lock ' + $lbl }))
                [System.Windows.Automation.AutomationProperties]::SetName($row.top, $(if ($top) { 'Disable always on top for ' + $lbl } else { 'Enable always on top for ' + $lbl }))
                [System.Windows.Automation.AutomationProperties]::SetName($row.move, ('Move ' + $lbl))
            } catch { }
            $row.hide.IsEnabled = $true
            $row.move.IsEnabled = ($key -ne 'dock')
            $row.lock.IsEnabled = ($key -ne 'dock')
            $row.top.IsEnabled = $true
        }
        if ($script:wmg.count) {
            $script:wmg.count.Text = ('{0} of {1} widgets visible  ·  {2} on top' -f $visCount, $script:widgetKeys.Count, $pinCount)
        }
    } catch { }
}

# ---------------- appearance settings in manager ----------------
function Update-ThemePreview($selectedId) {
    $p = Get-ThemePalette $selectedId
    $preview = New-Object System.Windows.Controls.Border
    $preview.Width = 60; $preview.Height = 60
    $preview.CornerRadius = CR 12
    $preview.Background = New-ThemeGlass 0.1 0 0.9 1
    $accent = New-Object System.Windows.Controls.Border
    $accent.Height = 3; $accent.CornerRadius = CR 1.5
    $accent.Background = New-ThemeAccent3
    $preview.Child = $accent
    return $preview
}

function Save-Appearance {
    try {
        $a = Get-Cfg $script:cfg 'appearance'
        Set-Cfg $a 'theme' $script:themeId
        Set-Cfg $a 'opacity' ([math]::Round([double]$script:appOpacity, 2))
        Set-Cfg $a 'scale' ([int]$script:appScale)
        Set-Cfg $a 'lowPower' ([bool]$script:lowPower)
        Set-Cfg $a 'fullscreenHide' ([bool]$script:fullscreenHide)
        Save-Config
    } catch { Write-WidgetError $_ 'save appearance' }
}

function Set-SegmentStyle($buttons, $selectedKey) {
    foreach ($k in @($buttons.Keys)) {
        if ([string]$k -eq [string]$selectedKey) { $buttons[$k].Style = $script:btnAccentStyle }
        else { $buttons[$k].Style = $script:btnStyle }
    }
}

function New-SmallButton($content, $tag) {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $content
    $b.Style = $script:btnStyle
    $b.FontSize = 10.5
    $b.Padding = Th 10 5 10 5
    $b.MinWidth = 0
    $b.Margin = Th 0 0 6 0
    $b.Tag = $tag
    return $b
}

# builds the Appearance card shown under the widget list in the manager
function New-AppearanceSection {
    $card = New-Object System.Windows.Controls.Border
    $card.CornerRadius = CR 12
    $card.Background = Br '#0AFFFFFF'
    $card.BorderBrush = Br '#12FFFFFF'
    $card.BorderThickness = Th 1 1 1 1
    $card.Padding = Th 12 10 12 10
    $card.Margin = Th 0 6 0 6
    $sp = New-Object System.Windows.Controls.StackPanel
    $card.Child = $sp
    $ap = @{ themeBtns = @{}; scaleBtns = @{}; profileBtns = @{} }

    $head = Txt 'APPEARANCE' 9.5 '#7C8CA3' 'SemiBold'
    $head.Margin = Th 0 0 0 8
    [void]$sp.Children.Add($head)

    # theme
    $l1 = Txt 'Theme' 11 '#C9D4E6' 'SemiBold'
    $l1.Margin = Th 0 0 0 4
    [void]$sp.Children.Add($l1)
    $r1 = New-Object System.Windows.Controls.WrapPanel
    foreach ($tid in @('midnight', 'ocean', 'amethyst', 'ember', 'graphite')) {
        $pal = Get-ThemePalette $tid
        $b = New-SmallButton $null $tid
        $in = New-Object System.Windows.Controls.StackPanel
        $in.Orientation = 'Horizontal'
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 9; $dot.Height = 9
        $dot.Fill = Br $pal.accent1
        $dot.Margin = Th 0 0 6 0
        $dot.VerticalAlignment = 'Center'
        [void]$in.Children.Add($dot)
        [void]$in.Children.Add((Txt $pal.name 10.5 '#E8EEF8'))
        $b.Content = $in
        $b.Add_Click({
            param($s, $e)
            try {
                $id = [string]$s.Tag
                if ($id -eq $script:themeId) { return }
                $script:themeId = $id
                $script:theme = Get-ThemePalette $id
                Save-Appearance
                Update-AppearanceSection
                $script:wmg.appearance.note.Text = 'Theme saved. Use tray > Restart widgets to apply it everywhere.'
            } catch { Write-WidgetError $_ 'theme click' }
        })
        $ap.themeBtns[$tid] = $b
        [void]$r1.Children.Add($b)
    }
    [void]$sp.Children.Add($r1)

    # opacity
    $l2 = Txt 'Opacity' 11 '#C9D4E6' 'SemiBold'
    $l2.Margin = Th 0 6 0 2
    [void]$sp.Children.Add($l2)
    $r2 = New-Object System.Windows.Controls.DockPanel
    $lab = Txt '100%' 10.5 '#9FB0C8'
    $lab.Width = 44
    $lab.TextAlignment = 'Right'
    $lab.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($lab, 'Right')
    [void]$r2.Children.Add($lab)
    $sl = New-Object System.Windows.Controls.Slider
    $sl.Minimum = 55; $sl.Maximum = 100; $sl.SmallChange = 1; $sl.LargeChange = 5
    $sl.IsMoveToPointEnabled = $true
    $sl.VerticalAlignment = 'Center'
    $sl.Add_ValueChanged({
        param($s, $e)
        try {
            if ($script:appearanceSyncing) { return }
            $script:appOpacity = [math]::Max(0.55, [math]::Min(1.0, [double]$s.Value / 100))
            $script:wmg.appearance.opacityLabel.Text = ('{0:N0}%' -f ($script:appOpacity * 100))
            Apply-Opacity
        } catch { }
    })
    $sl.Add_PreviewMouseLeftButtonUp({ try { Save-Appearance } catch { } })
    $sl.Add_PreviewKeyUp({ try { Save-Appearance } catch { } })
    [void]$r2.Children.Add($sl)
    [void]$sp.Children.Add($r2)
    $ap.opacitySlider = $sl
    $ap.opacityLabel = $lab

    # scale
    $l3 = Txt 'Widget size' 11 '#C9D4E6' 'SemiBold'
    $l3.Margin = Th 0 6 0 4
    [void]$sp.Children.Add($l3)
    $r3 = New-Object System.Windows.Controls.WrapPanel
    foreach ($sc in @(85, 100, 115)) {
        $b = New-SmallButton ([string]$sc + '%') $sc
        $b.Add_Click({
            param($s, $e)
            try {
                $script:appScale = [int]$s.Tag
                Save-Appearance
                Apply-Opacity
                Update-AppearanceSection
            } catch { Write-WidgetError $_ 'scale click' }
        })
        $ap.scaleBtns[$sc] = $b
        [void]$r3.Children.Add($b)
    }
    [void]$sp.Children.Add($r3)

    # toggles
    $r4 = New-Object System.Windows.Controls.WrapPanel
    $r4.Margin = Th 0 6 0 0
    $lp = New-SmallButton 'OFF' 'lp'
    $lp.MinWidth = 44
    $lp.Add_Click({
        param($s, $e)
        try {
            $script:lowPower = -not $script:lowPower
            Save-Appearance
            Apply-LowPower
            Update-AppearanceSection
        } catch { Write-WidgetError $_ 'low power click' }
    })
    $ap.lpBtn = $lp
    $lpl = Txt 'Low power mode' 11 '#C9D4E6'
    $lpl.VerticalAlignment = 'Center'
    $lpl.Margin = Th 0 0 18 0
    [void]$r4.Children.Add($lp)
    [void]$r4.Children.Add($lpl)
    $fs = New-SmallButton 'OFF' 'fs'
    $fs.MinWidth = 44
    $fs.Add_Click({
        param($s, $e)
        try {
            $script:fullscreenHide = -not $script:fullscreenHide
            Save-Appearance
            Update-AppearanceSection
            Update-FullscreenHide
        } catch { Write-WidgetError $_ 'fullscreen click' }
    })
    $ap.fsBtn = $fs
    $fsl = Txt 'Hide during fullscreen apps / games' 11 '#C9D4E6'
    $fsl.VerticalAlignment = 'Center'
    [void]$r4.Children.Add($fs)
    [void]$r4.Children.Add($fsl)
    [void]$sp.Children.Add($r4)

    # profiles
    $l5 = Txt 'Profiles' 11 '#C9D4E6' 'SemiBold'
    $l5.Margin = Th 0 6 0 4
    [void]$sp.Children.Add($l5)
    $r5 = New-Object System.Windows.Controls.WrapPanel
    $profs = Get-Cfg $script:cfg 'profiles'
    foreach ($pn in @('work', 'focus', 'night', 'game')) {
        $pr = Get-Cfg $profs $pn
        if ($null -eq $pr) { continue }
        $lbl = [string](Get-Cfg $pr 'label')
        if (-not $lbl) { $lbl = $pn }
        $b = New-SmallButton $lbl $pn
        $b.ToolTip = [string](Get-Cfg $pr 'description')
        $b.Add_Click({
            param($s, $e)
            try {
                $p = Get-Cfg (Get-Cfg $script:cfg 'profiles') ([string]$s.Tag)
                if ($p) { Apply-Profile $p }
            } catch { Write-WidgetError $_ 'profile click' }
        })
        $ap.profileBtns[$pn] = $b
        [void]$r5.Children.Add($b)
    }
    [void]$sp.Children.Add($r5)

    $note = Txt '' 9.5 '#5F6F86'
    $note.Margin = Th 0 6 0 0
    $note.TextWrapping = 'Wrap'
    [void]$sp.Children.Add($note)
    $ap.note = $note

    $script:wmg.appearance = $ap
    return $card
}

# syncs every control of the Appearance card with the current state
function Update-AppearanceSection {
    try {
        if (-not $script:wmg -or -not $script:wmg.appearance) { return }
        $ap = $script:wmg.appearance
        $script:appearanceSyncing = $true
        try {
            Set-SegmentStyle $ap.themeBtns $script:themeId
            Set-SegmentStyle $ap.scaleBtns $script:appScale
            $ap.opacitySlider.Value = [math]::Round($script:appOpacity * 100)
            $ap.opacityLabel.Text = ('{0:N0}%' -f ($script:appOpacity * 100))
        } finally { $script:appearanceSyncing = $false }
        $ap.lpBtn.Content = $(if ($script:lowPower) { 'ON' } else { 'OFF' })
        $ap.lpBtn.Style = $(if ($script:lowPower) { $script:btnAccentStyle } else { $script:btnStyle })
        $ap.fsBtn.Content = $(if ($script:fullscreenHide) { 'ON' } else { 'OFF' })
        $ap.fsBtn.Style = $(if ($script:fullscreenHide) { $script:btnAccentStyle } else { $script:btnStyle })
    } catch { Write-WidgetError $_ 'update appearance' }
}

# opacity applies to every widget window; size scales the content of all widgets except the dock
function Apply-Opacity {
    try {
        $opacity = $script:appOpacity
        $scale = $script:appScale / 100.0
        $widgets = @($script:hudWin, $script:musicWin, $script:clockWin, $script:weatherWin, $script:calendarWin, $script:focusWin, $script:notesWin, $script:dockWin)
        foreach ($w in $widgets) {
            if (-not $w) { continue }
            try { $w.Opacity = $opacity } catch { }
            if ($w -eq $script:dockWin) { continue }
            try {
                $c = $w.Content
                if ($c -is [System.Windows.FrameworkElement]) {
                    if ($scale -ne 1.0 -or $c.LayoutTransform -is [System.Windows.Media.ScaleTransform]) {
                        $c.LayoutTransform = New-Object System.Windows.Media.ScaleTransform($scale, $scale)
                        $w.SizeToContent = 'WidthAndHeight'
                    }
                }
            } catch { }
        }
    } catch { }
}

# low power: slow the 1 Hz HUD refresh
function Apply-LowPower {
    try {
        if ($script:mainTimer) {
            if ($script:lowPower) { $script:mainTimer.Interval = [TimeSpan]::FromMilliseconds(3000) }
            else { $script:mainTimer.Interval = [TimeSpan]::FromMilliseconds(900) }
        }
    } catch { }
}

# fullscreen auto-hide: hides the widgets while a game / fullscreen app is running
function Update-FullscreenHide {
    try {
        $state = 0
        [void][UDWin]::SHQueryUserNotificationState([ref]$state)
        $full = ($script:fullscreenHide -and ($state -eq 3 -or $state -eq 4))
        if ($full -and -not $script:fsHidden) {
            $script:fsHidden = @()
            foreach ($k in $script:widgetKeys) {
                $w = Get-WidgetWindow $k
                if ($w -and $w.IsVisible) { $script:fsHidden += $k; $w.Hide() }
            }
        } elseif (-not $full -and $script:fsHidden) {
            foreach ($k in $script:fsHidden) {
                $w = Get-WidgetWindow $k
                if ($w) { $w.Show() }
            }
            $script:fsHidden = $null
        }
    } catch { }
}

function Apply-Profile($profile) {
    try {
        if (-not $profile -or -not $profile.visible) { return }
        foreach ($k in $script:widgetKeys) {
            $vis = [bool]$profile.visible[$k]
            $top = [bool]$profile.topmost[$k]
            $lock = [bool]$profile.locked[$k]
            $w = Get-WidgetWindow $k
            $sec = Get-WidgetSection $k
            if ($w) { $w.Topmost = $top }
            if ($sec) {
                Set-Cfg $sec 'visible' $vis
                Set-Cfg $sec 'topmost' $top
                Set-Cfg $sec 'locked' $lock
            }
        }
        Save-Config
        Update-WidgetManager
    } catch { Write-WidgetError $_ 'apply profile' }
}

function New-WidgetRow([string]$key) {
    $row = New-Object System.Windows.Controls.Border
    $row.CornerRadius = CR 10
    $row.Background = Br '#0EFFFFFF'
    $row.BorderBrush = Br '#10FFFFFF'
    $row.BorderThickness = Th 1 1 1 1
    $row.Padding = Th 10 6 10 6
    $row.Margin = Th 0 0 0 6

    $dp = New-Object System.Windows.Controls.DockPanel

    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 7; $dot.Height = 7
    $dot.Fill = Br (Get-WidgetAccent $key)
    $dot.Margin = Th 2 0 9 0
    $dot.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($dot, 'Left')
    [void]$dp.Children.Add($dot)

    $btns = New-Object System.Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'
    $btns.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($btns, 'Right')
    [void]$dp.Children.Add($btns)

    $bHide = New-Object System.Windows.Controls.Button
    $bHide.Content = 'HIDE'
    $bHide.Style = $script:btnStyle
    $bHide.FontSize = 9.5
    $bHide.Padding = Th 8 4 8 4
    $bHide.MinWidth = 0
    $bHide.Margin = Th 4 0 0 0
    $bHide.Tag = $key
    $bHide.ToolTip = 'Show or hide this widget'
    try { [System.Windows.Automation.AutomationProperties]::SetName($bHide, ('Hide ' + (Get-WidgetLabel $key))) } catch { }
    $bHide.Add_Click({
        param($s, $e)
        try {
            $k = [string]$s.Tag
            Set-WidgetVisible $k (-not (Test-WidgetShown $k))
        } catch { Write-WidgetError $_ 'widget manager visibility' }
    })
    [void]$btns.Children.Add($bHide)

    $bMove = New-Object System.Windows.Controls.Button
    $bMove.Content = 'MOVE'
    $bMove.Style = $script:btnStyle
    $bMove.FontSize = 9.5
    $bMove.Padding = Th 8 4 8 4
    $bMove.MinWidth = 0
    $bMove.Margin = Th 4 0 0 0
    $bMove.Tag = $key
    $bMove.ToolTip = 'Click, then move the mouse and click again to place it'
    try { [System.Windows.Automation.AutomationProperties]::SetName($bMove, ('Move ' + (Get-WidgetLabel $key))) } catch { }
    $bMove.Add_Click({ param($s, $e) try { Start-WidgetMove ([string]$s.Tag) } catch { } })
    [void]$btns.Children.Add($bMove)

    $bLock = New-Object System.Windows.Controls.Button
    $bLock.Content = 'LOCK'
    $bLock.Style = $script:btnStyle
    $bLock.FontSize = 9.5
    $bLock.Padding = Th 8 4 8 4
    $bLock.MinWidth = 0
    $bLock.Margin = Th 4 0 0 0
    $bLock.Tag = $key
    $bLock.ToolTip = 'Lock the position so it cannot be dragged by accident'
    try { [System.Windows.Automation.AutomationProperties]::SetName($bLock, ('Lock ' + (Get-WidgetLabel $key))) } catch { }
    $bLock.Add_Click({
        param($s, $e)
        try {
            $k = [string]$s.Tag
            Set-WidgetLocked $k (-not [bool](Get-Cfg (Get-WidgetSection $k) 'locked'))
        } catch { }
    })
    [void]$btns.Children.Add($bLock)

    $bTop = New-Object System.Windows.Controls.Button
    $bTop.Content = 'TOP OFF'
    $bTop.Style = $script:btnStyle
    $bTop.FontSize = 9.5
    $bTop.Padding = Th 8 4 8 4
    $bTop.MinWidth = 0
    $bTop.Margin = Th 4 0 0 0
    $bTop.Tag = $key
    $bTop.ToolTip = 'Keep this widget above the other windows'
    try { [System.Windows.Automation.AutomationProperties]::SetName($bTop, ('Enable always on top for ' + (Get-WidgetLabel $key))) } catch { }
    $bTop.Add_Click({
        param($s, $e)
        try {
            $k = [string]$s.Tag
            Set-WidgetPinned $k (-not [bool](Get-Cfg (Get-WidgetSection $k) 'topmost'))
        } catch { }
    })
    [void]$btns.Children.Add($bTop)

    $txts = New-Object System.Windows.Controls.StackPanel
    $txts.VerticalAlignment = 'Center'
    $n = Txt (Get-WidgetLabel $key) 13 '#E8EEF8' 'SemiBold'
    $n.HorizontalAlignment = 'Left'
    $state = Txt 'VISIBLE' 9 '#6F7F97' 'SemiBold'
    $state.HorizontalAlignment = 'Left'
    [void]$txts.Children.Add($n)
    [void]$txts.Children.Add($state)
    [void]$dp.Children.Add($txts)

    $row.Child = $dp
    return @{ row = $row; hide = $bHide; move = $bMove; lock = $bLock; top = $bTop; state = $state }
}

function Show-WidgetManager {
    try {
        if ($script:wmg -and $script:wmg.win) {
            try {
                $script:wmg.win.Show()
                $script:wmg.win.Activate()
                Update-WidgetManager
                return
            } catch { $script:wmg = $null }
        }
        $w = New-Object System.Windows.Window
        $w.Title = 'UD Widgets'
        $w.WindowStyle = 'None'
        $w.AllowsTransparency = $true
        $w.Background = $null
        $w.ShowInTaskbar = $false
        $w.ResizeMode = 'NoResize'
        $w.WindowStartupLocation = 'CenterScreen'
        $w.Topmost = $true
        $w.Width = 600
        $w.Height = 760

        $root = New-Object System.Windows.Controls.Border
        $root.CornerRadius = CR 18
        $root.BorderThickness = Th 1 1 1 1
        $root.BorderBrush = Br '#26FFFFFF'
        $root.Padding = Th 16 14 16 14
        $root.Background = New-ThemeGlass 0 0 0 1
        $shd = New-Object System.Windows.Media.Effects.DropShadowEffect
        $shd.BlurRadius = 28; $shd.ShadowDepth = 0; $shd.Opacity = 0.65; $shd.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#000000')
        $root.Effect = $shd

        $stack = New-Object System.Windows.Controls.DockPanel
        $root.Child = $stack

        $hdr = New-Object System.Windows.Controls.DockPanel
        $hdr.Margin = Th 0 0 0 12
        [System.Windows.Controls.DockPanel]::SetDock($hdr, 'Top')
        $close = New-Object System.Windows.Controls.Button
        $close.Content = [string][char]0x2715
        $close.Style = $script:btnStyle
        $close.Padding = Th 9 4 9 4
        $close.MinWidth = 0
        [System.Windows.Controls.DockPanel]::SetDock($close, 'Right')
        $close.Add_Click({ try { $script:wmg.win.Hide() } catch { } })
        [void]$hdr.Children.Add($close)
        $ttl = New-Object System.Windows.Controls.StackPanel
        $t1 = Txt 'Widgets' 17 '#F1F6FC' 'SemiBold'
        $cnt = Txt '' 10.5 '#7C8CA3'
        [void]$ttl.Children.Add($t1)
        [void]$ttl.Children.Add($cnt)
        [void]$hdr.Children.Add($ttl)
        $hdr.Add_MouseLeftButtonDown({ param($s, $e) try { $script:wmg.win.DragMove() } catch { } })
        [void]$stack.Children.Add($hdr)

        $footer = New-Object System.Windows.Controls.StackPanel
        $footer.Orientation = 'Horizontal'
        $footer.Margin = Th 0 10 0 0
        [System.Windows.Controls.DockPanel]::SetDock($footer, 'Bottom')
        $bAll = New-Object System.Windows.Controls.Button
        $bAll.Content = 'Show all'
        $bAll.Style = $script:btnStyle
        $bAll.FontSize = 10.5
        $bAll.Padding = Th 10 5 10 5
        $bAll.MinWidth = 0
        $bAll.Add_Click({
            try {
                foreach ($k in $script:widgetKeys) { Set-WidgetVisible $k $true -NoSave }
                Save-Config
                Update-WidgetManager
            } catch { }
        })
        [void]$footer.Children.Add($bAll)
        $bRst = New-Object System.Windows.Controls.Button
        $bRst.Content = 'Reset positions'
        $bRst.Style = $script:btnStyle
        $bRst.FontSize = 10.5
        $bRst.Padding = Th 10 5 10 5
        $bRst.MinWidth = 0
        $bRst.Margin = Th 6 0 0 0
        $bRst.Add_Click({ try { Reset-WidgetPositions; Update-WidgetManager } catch { } })
        [void]$footer.Children.Add($bRst)
        $bDone = New-Object System.Windows.Controls.Button
        $bDone.Content = 'Done'
        $bDone.Style = $script:btnAccentStyle
        $bDone.FontSize = 10.5
        $bDone.Padding = Th 10 5 10 5
        $bDone.MinWidth = 0
        $bDone.Margin = Th 6 0 0 0
        $bDone.Add_Click({ try { $script:wmg.win.Hide() } catch { } })
        [void]$footer.Children.Add($bDone)
        $tip = Txt 'drag a widget to move it  ·  MOVE = click-to-place' 9.2 '#5F6F86'
        $tip.Margin = Th 10 0 0 0
        $tip.VerticalAlignment = 'Center'
        [void]$footer.Children.Add($tip)
        [void]$stack.Children.Add($footer)

        $sv = New-Object System.Windows.Controls.ScrollViewer
        $sv.VerticalScrollBarVisibility = 'Auto'
        $sv.HorizontalScrollBarVisibility = 'Disabled'
        $rowsPanel = New-Object System.Windows.Controls.StackPanel
        $sv.Content = $rowsPanel
        [void]$stack.Children.Add($sv)

        $w.Content = $root
        $script:wmg = @{ win = $w; rows = @{}; count = $cnt }
        $script:appearanceSyncing = $false
        foreach ($key in $script:widgetKeys) {
            $r = New-WidgetRow $key
            $script:wmg.rows[$key] = $r
            [void]$rowsPanel.Children.Add($r.row)
        }
        [void]$rowsPanel.Children.Add((New-AppearanceSection))
        Update-AppearanceSection
        $w.Add_Closing({
            param($s, $e)
            try {
                if (-not $script:exiting) { $e.Cancel = $true; $s.Hide() }
            } catch { }
        })
        $w.Show()
        $w.Activate()
        try { Set-WidgetWindowStyle $w -Interactive } catch { }
        Update-WidgetManager
    } catch { Write-WidgetError $_ 'show widget manager' }
}

function Restore-MoveWidget([bool]$save) {
    try {
        $m = $script:moveState
        if (-not $m) { return }
        $st = $m.state
        try { $m.timer.Stop() } catch { }
        if ($st.win) {
            try { $st.win.IsHitTestVisible = $true } catch { }
            if ($save) {
                try { Save-WidgetPos ([string]$st.key) $st.win.Left $st.win.Top } catch { }
            } else {
                try { $st.win.Left = [double]$st.ox; $st.win.Top = [double]$st.oy } catch { }
            }
            try { $st.win.Topmost = [bool]$st.wasTop } catch { }
        }
        try { [System.Windows.Input.Mouse]::OverrideCursor = $null } catch { }
        $script:moveState = $null
        if ($st.mgr) { Show-WidgetManager } else { Update-WidgetManager }
        try {
            if ($script:tray) {
                $msg = if ($save) { 'Widget placed. Position saved.' } else { 'Move cancelled.' }
                $script:tray.ShowBalloonTip(2500, 'UNLOCK DIGITAL Widgets', $msg, [System.Windows.Forms.ToolTipIcon]::Info)
            }
        } catch { }
    } catch { }
}

function Start-WidgetMove([string]$key) {
    try {
        if ($key -eq 'dock') { return }
        $w = Get-WidgetWindow $key
        if (-not $w) { return }
        if ($script:moveState) { Restore-MoveWidget $true }
        $sec = Get-WidgetSection $key
        if ($sec) { Set-Cfg $sec 'locked' $false; Save-Config }
        if (-not $w.IsVisible) { Set-WidgetVisible $key $true -NoSave }
        $wasTop = [bool]$w.Topmost
        $w.Topmost = $true
        $mgrWas = [bool]($script:wmg -and $script:wmg.win -and $script:wmg.win.IsVisible)
        if ($mgrWas) { try { $script:wmg.win.Hide() } catch { } }
        $state = @{
            key = $key; win = $w; wasTop = $wasTop; mgr = $mgrWas
            ox = [double]$w.Left; oy = [double]$w.Top
            armed = $false; done = $false
        }
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(16)
        $t.Tag = $state
        $t.Add_Tick({
            param($s, $e)
            try {
                $m = $s.Tag
                if (-not $m -or $m.done) { $s.Stop(); return }
                if (-not $m.armed) {
                    # wait until the button that started the mode is released
                    if (([UDWin]::GetAsyncKeyState(0x01) -band 0x8000) -eq 0) { $m.armed = $true }
                    return
                }
                if (([UDWin]::GetAsyncKeyState(0x1B) -band 0x8000) -ne 0) {
                    $m.done = $true
                    Restore-MoveWidget $false
                    return
                }
                if (([UDWin]::GetAsyncKeyState(0x02) -band 0x8000) -ne 0) {
                    $m.done = $true
                    Restore-MoveWidget $false
                    return
                }
                $p = [System.Windows.Forms.Cursor]::Position
                $dpi = [System.Windows.Media.VisualTreeHelper]::GetDpi($m.win)
                $vx = [double][System.Windows.SystemParameters]::VirtualScreenLeft
                $vy = [double][System.Windows.SystemParameters]::VirtualScreenTop
                $vw = [double][System.Windows.SystemParameters]::VirtualScreenWidth
                $vh = [double][System.Windows.SystemParameters]::VirtualScreenHeight
                $x = ($p.X / $dpi.DpiScaleX) - ($m.win.ActualWidth / 2)
                $y = ($p.Y / $dpi.DpiScaleY) - ($m.win.ActualHeight / 2)
                if ($x -lt $vx) { $x = $vx }
                if ($y -lt $vy) { $y = $vy }
                if ($x -gt ($vx + $vw - $m.win.ActualWidth)) { $x = $vx + $vw - $m.win.ActualWidth }
                if ($y -gt ($vy + $vh - $m.win.ActualHeight)) { $y = $vy + $vh - $m.win.ActualHeight }
                $m.win.Left = [double]$x
                $m.win.Top = [double]$y
                if (([UDWin]::GetAsyncKeyState(0x01) -band 0x8000) -ne 0) {
                    $m.done = $true
                    Restore-MoveWidget $true
                }
            } catch { }
        })
        $script:moveState = @{ timer = $t; state = $state }
        $w.IsHitTestVisible = $false
        try { [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::SizeAll } catch { }
        $t.Start()
        try { $script:tray.ShowBalloonTip(4000, 'Move widget', 'Move the mouse to place it, then click. Esc cancels.', [System.Windows.Forms.ToolTipIcon]::Info) } catch { }
    } catch { Write-WidgetError $_ 'start widget move' }
}

# ---------------- shared state filled by background collector ----------------
$state = [hashtable]::Synchronized(@{
    cpu = 0.0; ramPct = 0.0; ramUsedGb = 0.0; ramTotalGb = 0.0
    diskFreeGb = 0.0; diskTotalGb = 0.0
    rxBps = 0.0; txBps = 0.0
    pingMs = -1; online = $false; adapters = ''; wifiSignal = -1
    localIp = ''; publicIp = ''
    samplesDown = New-Object System.Collections.ArrayList
    samplesUp = New-Object System.Collections.ArrayList
})

# ---------------- HUD window ----------------
$hudWin = $null; $hudCtl = @{}
$script:copyTimers = New-Object System.Collections.ArrayList
if ($cfg.hud.enabled -and -not $NoHud) {
    $hudWin = New-Object System.Windows.Window
    $hudWin.Title = 'UD System HUD'
    $hudWin.WindowStyle = 'None'
    $hudWin.AllowsTransparency = $true
    $hudWin.Background = $null
    $hudWin.ShowInTaskbar = $false
    $hudWin.ResizeMode = 'NoResize'
    $hudWin.SizeToContent = 'WidthAndHeight'
    $hudWin.WindowStartupLocation = 'Manual'
    $hudWin.Topmost = [bool]$cfg.hud.topmost

    # --- panel shell (vertical stack, top-left) ----------------------
    $hudW = 214.0
    $hudInnerW = $hudW - 30

    $root = New-Object System.Windows.Controls.Border
    $root.CornerRadius = CR 16
    $root.BorderThickness = Th 1 1 1 1
    $root.BorderBrush = Br '#22FFFFFF'
    $root.Width = $hudW
    $root.Background = New-ThemeGlass 0.1 0 0.9 1
    $sh = New-Object System.Windows.Media.Effects.DropShadowEffect
    $sh.BlurRadius = 26; $sh.ShadowDepth = 0; $sh.Opacity = 0.6; $sh.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#000000')
    $root.Effect = $sh

    $outer = New-Object System.Windows.Controls.Grid
    $rd0 = New-Object System.Windows.Controls.RowDefinition
    $rd0.Height = New-Object System.Windows.GridLength(2.5)
    $rd1 = New-Object System.Windows.Controls.RowDefinition
    $rd1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    [void]$outer.RowDefinitions.Add($rd0)
    [void]$outer.RowDefinitions.Add($rd1)

    $accent = New-Object System.Windows.Controls.Border
    $accent.Height = 2.5
    $accent.CornerRadius = New-Object System.Windows.CornerRadius(15, 15, 0, 0)
    $accent.Background = New-ThemeAccent3
    [System.Windows.Controls.Grid]::SetRow($accent, 0)
    [void]$outer.Children.Add($accent)

    $body = New-Object System.Windows.Controls.StackPanel
    $body.Margin = Th 14 11 14 12
    [System.Windows.Controls.Grid]::SetRow($body, 1)
    [void]$outer.Children.Add($body)
    $root.Child = $outer

    # --- row / bar helpers -------------------------------------------
    function New-HudRow([string]$key, [string]$label, [string]$value, [string]$color, [double]$gap = 8, [string]$dotColor = '', [bool]$copy = $false) {
        $g = New-Object System.Windows.Controls.Grid
        $c1 = New-Object System.Windows.Controls.ColumnDefinition
        $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition
        $c2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
        [void]$g.ColumnDefinitions.Add($c1)
        [void]$g.ColumnDefinitions.Add($c2)

        $left = New-Object System.Windows.Controls.StackPanel
        $left.Orientation = 'Horizontal'
        $dot = $null
        if ($dotColor -ne '') {
            $dot = New-Object System.Windows.Shapes.Ellipse
            $dot.Width = 7; $dot.Height = 7
            $dot.Fill = Br $dotColor
            $dot.VerticalAlignment = 'Center'
            $dot.Margin = Th 0 0 7 0
            [void]$left.Children.Add($dot)
        }
        $lbl = Txt $label 10.5 '#8494AB'
        [void]$left.Children.Add($lbl)
        [System.Windows.Controls.Grid]::SetColumn($left, 0)
        [void]$g.Children.Add($left)

        $v = Txt $value 12.5 $color 'SemiBold'
        $v.TextAlignment = 'Right'
        $v.HorizontalAlignment = 'Right'
        [System.Windows.Controls.Grid]::SetColumn($v, 1)
        [void]$g.Children.Add($v)

        $wrap = New-Object System.Windows.Controls.StackPanel
        $wrap.Margin = Th 0 0 0 $gap
        [void]$wrap.Children.Add($g)
        $hudCtl[$key] = [pscustomobject]@{ value = $v; dot = $dot; bar = $null; barW = $hudInnerW; barColor = $color }
        if ($copy) {
            $g.Cursor = 'Hand'
            $g.ToolTip = 'Click to copy'
            $g.Tag = $v
            $g.Add_MouseLeftButtonUp({
                param($s, $e)
                $tb = $s.Tag
                try {
                    $txt = [string]$tb.Text
                    if ($txt -and $txt -ne '--' -and $txt -notmatch '^[•*]+$') {
                        for ($try = 0; $try -lt 6; $try++) {
                            try { [System.Windows.Clipboard]::SetText($txt); break } catch { Start-Sleep -Milliseconds 70 }
                        }
                        $tb.Text = 'copied'
                        $restore = {
                            param($s2, $e2)
                            $s2.Stop()
                            try { $tb.Text = $txt } catch { }
                        }.GetNewClosure()
                        $t2 = New-Object System.Windows.Threading.DispatcherTimer
                        $t2.Interval = [TimeSpan]::FromMilliseconds(1100)
                        $t2.Add_Tick($restore)
                        $t2.Start()
                        [void]$script:copyTimers.Add($t2)
                    }
                } catch { }
            })
        }
        return $wrap
    }

    function New-HudBar([string]$key, [string]$color) {
        $fill = New-Object System.Windows.Controls.Border
        $fill.Height = 3.5
        $fill.CornerRadius = CR 2
        $fill.Background = Br $color
        $fill.HorizontalAlignment = 'Left'
        $fill.Width = 0.0
        $track = New-Object System.Windows.Controls.Border
        $track.Height = 3.5
        $track.CornerRadius = CR 2
        $track.Background = Br '#14FFFFFF'
        $track.ClipToBounds = $true
        $track.Margin = Th 0 0 0 11
        $track.Child = $fill
        $hudCtl[$key].bar = $fill
        $hudCtl[$key].barColor = $color
        return $track
    }

    function New-HudSep {
        $b = New-Object System.Windows.Controls.Border
        $b.Height = 1
        $b.Background = Br '#10FFFFFF'
        $b.Margin = Th 0 1 0 11
        return $b
    }

    # --- header ------------------------------------------------------
    $hdr = New-Object System.Windows.Controls.DockPanel
    $hdr.Margin = Th 0 0 0 11
    $brand = Txt 'UNLOCK DIGITAL' 8.5 '#4E5D73'
    $brand.TextAlignment = 'Right'
    [System.Windows.Controls.DockPanel]::SetDock($brand, 'Right')
    [void]$hdr.Children.Add($brand)
    $hdot = New-Object System.Windows.Shapes.Ellipse
    $hdot.Width = 7; $hdot.Height = 7
    $hdot.Fill = Br '#4ADE80'
    $hdot.VerticalAlignment = 'Center'
    $hdot.Margin = Th 0 0 7 0
    $hsp = New-Object System.Windows.Controls.StackPanel
    $hsp.Orientation = 'Horizontal'
    [void]$hsp.Children.Add($hdot)
    [void]$hsp.Children.Add((Txt 'SYSTEM STATUS' 10.5 '#CBD8E8' 'SemiBold'))
    [void]$hdr.Children.Add($hsp)
    [void]$body.Children.Add($hdr)
    $hudCtl['HEAD'] = [pscustomobject]@{ value = $null; dot = $hdot; bar = $null }

    # --- network -----------------------------------------------------
    [void]$body.Children.Add((New-HudRow 'NET' 'NETWORK' 'checking…' '#FBBF24' 7 '#FBBF24'))
    [void]$body.Children.Add((New-HudRow 'DOWN' 'DOWNLOAD' '--' '#67E8F9' 6))
    [void]$body.Children.Add((New-HudRow 'UP' 'UPLOAD' '--' '#C4B5FD' 8))

    $spark = New-Object System.Windows.Controls.Canvas
    $spark.Width = $hudInnerW; $spark.Height = 42
    $spark.Margin = Th 0 0 0 12
    $sparkArea = New-Object System.Windows.Shapes.Polygon
    $sg = New-Object System.Windows.Media.LinearGradientBrush
    $sg.StartPoint = New-Object System.Windows.Point(0, 0)
    $sg.EndPoint = New-Object System.Windows.Point(0, 1)
    $sg.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString('#4A38BDF8'), 0)))
    $sg.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString('#021F6FE0'), 1)))
    $sparkArea.Fill = $sg
    $sparkLineDown = New-Object System.Windows.Shapes.Polyline
    $sparkLineDown.Stroke = Br '#38BDF8'; $sparkLineDown.StrokeThickness = 1.7
    $sparkLineUp = New-Object System.Windows.Shapes.Polyline
    $sparkLineUp.Stroke = Br '#A78BFA'; $sparkLineUp.StrokeThickness = 1.2; $sparkLineUp.Opacity = 0.9
    $base = New-Object System.Windows.Controls.Border
    $base.Height = 1; $base.Background = Br '#14FFFFFF'
    $base.VerticalAlignment = 'Bottom'
    [void]$spark.Children.Add($sparkArea)
    [void]$spark.Children.Add($base)
    [void]$spark.Children.Add($sparkLineDown)
    [void]$spark.Children.Add($sparkLineUp)
    [void]$body.Children.Add($spark)
    $hudCtl['sparkDown'] = $sparkLineDown
    $hudCtl['sparkUp'] = $sparkLineUp
    $hudCtl['sparkArea'] = $sparkArea

    [void]$body.Children.Add((New-HudSep))

    # --- local machine ----------------------------------------------
    [void]$body.Children.Add((New-HudRow 'CPU' 'CPU' '--' '#93C5FD' 4))
    [void]$body.Children.Add((New-HudBar 'CPU' '#38BDF8'))
    $hudCtl['CPU'].value.Text = '--'
    [void]$body.Children.Add((New-HudRow 'RAM' 'MEMORY' '--' '#93C5FD' 4))
    $hudCtl['RAM'].bar = $null
    [void]$body.Children.Add((New-HudBar 'RAM' '#8B5CF6'))
    [void]$body.Children.Add((New-HudRow 'DISK' 'DISK FREE' '--' '#A7F3D0' 4))
    [void]$body.Children.Add((New-HudBar 'DISK' '#34D399'))

    [void]$body.Children.Add((New-HudSep))

    # --- ip addresses (click to copy) --------------------------------
    [void]$body.Children.Add((New-HudRow 'LIP' 'LOCAL IP' '--' '#DCE6F2' -gap 6 -copy $true))
    [void]$body.Children.Add((New-HudRow 'PIP' 'PUBLIC IP' '--' '#DCE6F2' -gap 9 -copy $true))

    # --- footer ------------------------------------------------------
    $ftr = New-Object System.Windows.Controls.DockPanel
    $ftr.Margin = Th 0 0 0 7
    $fLink = Txt '--' 10.5 '#8494AB'
    $fLink.TextAlignment = 'Right'
    [System.Windows.Controls.DockPanel]::SetDock($fLink, 'Right')
    [void]$ftr.Children.Add($fLink)
    $fPing = Txt 'PING --' 10.5 '#A7F3D0'
    [void]$ftr.Children.Add($fPing)
    [void]$body.Children.Add($ftr)
    $hudCtl['PING'] = [pscustomobject]@{ value = $fPing; dot = $null; bar = $null }
    $hudCtl['LINK'] = [pscustomobject]@{ value = $fLink; dot = $null; bar = $null }

    $ftr2 = New-Object System.Windows.Controls.DockPanel
    $fUp = Txt 'up --' 9 '#5D6C82'
    $fUp.TextAlignment = 'Right'
    [System.Windows.Controls.DockPanel]::SetDock($fUp, 'Right')
    [void]$ftr2.Children.Add($fUp)
    $fClock = Txt '--' 9 '#5D6C82'
    [void]$ftr2.Children.Add($fClock)
    [void]$body.Children.Add($ftr2)
    $hudCtl['CLOCK'] = [pscustomobject]@{ value = $fClock; dot = $null; bar = $null }
    $hudCtl['UPTIME'] = [pscustomobject]@{ value = $fUp; dot = $null; bar = $null }

    $hudMenu = New-Object System.Windows.Controls.ContextMenu
    $hudMenu.Background = Br '#12161F'
    $hudMenu.Foreground = Br '#E8EEF8'
    $hudMenu.BorderBrush = Br '#2A3140'
    $mHDrag = New-Object System.Windows.Controls.MenuItem
    $mHDrag.Header = '✥  Drag the panel to move it'
    $mHDrag.IsEnabled = $false
    [void]$hudMenu.Items.Add($mHDrag)
    [void]$hudMenu.Items.Add((New-Object System.Windows.Controls.Separator))
    $mHTop = New-Object System.Windows.Controls.MenuItem
    $mHTop.Header = 'Keep on top'
    $mHTop.IsCheckable = $true
    $mHTop.IsChecked = [bool]$cfg.hud.topmost
    $mHTop.Add_Click({ param($s, $e) $script:cfg.hud.topmost = $s.IsChecked; $script:hudWin.Topmost = $s.IsChecked; Save-Config })
    [void]$hudMenu.Items.Add($mHTop)
    Add-WidgetMenuItems $hudMenu 'hud'
    $mHSide = New-Object System.Windows.Controls.MenuItem
    $mHSide.Header = 'Pin to the right side'
    $mHSide.IsCheckable = $true
    $mHSide.IsChecked = ([string]$cfg.hud.side -eq 'right')
    $mHSide.Add_Click({
        param($s, $e)
        $script:cfg.hud.side = $(if ($s.IsChecked) { 'right' } else { 'left' })
        Save-Config
        Reset-HudPosition
    })
    [void]$hudMenu.Items.Add($mHSide)
    $mHIP = New-Object System.Windows.Controls.MenuItem
    $mHIP.Header = 'Hide public IP'
    $mHIP.IsCheckable = $true
    $mHIP.IsChecked = [bool]$cfg.hud.maskIp
    $mHIP.Add_Click({ param($s, $e) $script:cfg.hud.maskIp = $s.IsChecked; Save-Config })
    [void]$hudMenu.Items.Add($mHIP)
    $mHHide = New-Object System.Windows.Controls.MenuItem
    $mHHide.Header = 'Hide HUD'
    $mHHide.Add_Click({ param($s, $e) try { Set-WidgetVisible 'hud' $false } catch { } })
    [void]$hudMenu.Items.Add($mHHide)
    $mHEx = New-Object System.Windows.Controls.MenuItem
    $mHEx.Header = 'Exit widgets'
    $mHEx.Add_Click({
        $script:exiting = $true
        try { $script:tray.Visible = $false; $script:tray.Dispose() } catch { }
        [System.Windows.Application]::Current.Dispatcher.InvokeShutdown()
    })
    [void]$hudMenu.Items.Add($mHEx)
    $root.ContextMenu = $hudMenu

    $hudWin.Content = $root
    $hudWin.Left = 16.0       # anchored by Reset-WidgetPositions (DIP units)
    $hudWin.Top = 14.0
}

# ---------------- Dock window ----------------
$dockWin = $null; $dockPanel = $null
$script:mgr = $null
$script:btnStyle = $null; $script:btnDangerStyle = $null
$script:dockTiles = New-Object System.Collections.ArrayList
$script:dockAddTile = $null
$script:dockCycle = @{}
$script:dockDotTimer = $null
$script:dockFx = $true
try { if ($null -ne (Get-Cfg $script:cfg.dock 'effects')) { $script:dockFx = [bool](Get-Cfg $script:cfg.dock 'effects') } } catch { }

# dock hover glow (soft blue, matches the shell accent)
$script:dockGlow = New-Object System.Windows.Media.Effects.DropShadowEffect
$script:dockGlow.BlurRadius = 18
$script:dockGlow.ShadowDepth = 0
$script:dockGlow.Opacity = 0.85
$script:dockGlow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($script:theme.glow)
try { $script:dockGlow.Freeze() } catch { }

# launchers whose process name differs from the exe on the dock
$script:procAlias = @{
    'wt'              = @('WindowsTerminal')
    'windowsterminal' = @('WindowsTerminal')
    'code'            = @('Code')
    'code - insiders' = @('Code - Insiders')
    'cmd'             = @('cmd', 'WindowsTerminal')
}

function Get-AppProcNames($app) {
    $names = New-Object System.Collections.ArrayList
    $p = [string]$app.path
    if (-not $p -or $p -like 'shell:*' -or $p -match '!') { return , $names }
    $n = [System.IO.Path]::GetFileNameWithoutExtension($p)
    if (-not $n) { return , $names }
    $lower = $n.ToLower()
    if ($script:procAlias.ContainsKey($lower)) {
        foreach ($x in @($script:procAlias[$lower])) { [void]$names.Add($x) }
    } else {
        [void]$names.Add($n)
    }
    return , $names
}

function Get-AppProcessList($app) {
    $out = New-Object System.Collections.ArrayList
    foreach ($n in (Get-AppProcNames $app)) {
        try {
            foreach ($pr in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) { [void]$out.Add($pr) }
        } catch { }
    }
    return $out.ToArray()
}

function Get-AppWindowHandles($app) {
    $wins = New-Object System.Collections.ArrayList
    foreach ($pr in (Get-AppProcessList $app)) {
        try {
            foreach ($h in @([UDWin]::GetProcessWindows([uint32]$pr.Id))) {
                if (-not $wins.Contains($h)) { [void]$wins.Add($h) }
            }
        } catch { }
    }
    return $wins.ToArray()
}

# click a dock icon -> if the app already has a window, restore + focus it (repeat clicks cycle windows)
function Activate-AppWindow($app) {
    try {
        $wins = @(Get-AppWindowHandles $app)
        if ($wins.Count -lt 1) { return $false }
        $key = [string]$app.path
        $idx = 0
        if ($script:dockCycle.ContainsKey($key)) { $idx = [int]$script:dockCycle[$key] }
        if ($idx -ge $wins.Count) { $idx = 0 }
        $ok = [UDWin]::ForceForeground([IntPtr]$wins[$idx])
        if ($ok -and $wins.Count -gt 1) { $script:dockCycle[$key] = ($idx + 1) % $wins.Count }
        return [bool]$ok
    } catch { return $false }
}

function Launch-App($a, [switch]$NewWindow) {
    try {
        $p = [string]$a.path
        if (-not $NewWindow -and -not $a.args) {
            if (Activate-AppWindow $a) { return }
        }
        $isFile = Test-Path -LiteralPath $p
        if ($isFile) {
            if ($a.args) { Start-Process -FilePath $p -ArgumentList $a.args }
            else { Start-Process -FilePath $p }
        }
        elseif ($p -like 'shell:*' -or $p -match '!') {
            Start-Process $(if ($p -like 'shell:*') { $p } else { "shell:AppsFolder\$p" })
        }
        elseif ($p -match '^[a-zA-Z][a-zA-Z0-9+.\-]*:') {
            # protocol like ms-settings: - let explorer hand it to the shell
            Start-Process explorer.exe -ArgumentList $p
        }
        else { Start-Process -FilePath $p }
    } catch { }
}

# ---------------- dock animations ----------------
function Anim-DockTile($tile, [double]$scale, [double]$lift, [int]$ms = 130) {
    try {
        if (-not $script:dockFx -or -not $tile) { return }
        $tg = $tile.RenderTransform
        if (-not $tg -or $tg.Children.Count -lt 2) { return }
        $st = $tg.Children[0]; $tt = $tg.Children[1]
        $dur = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($ms))
        $ease = New-Object System.Windows.Media.Animation.CubicEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $a1 = New-Object System.Windows.Media.Animation.DoubleAnimation([double]$st.ScaleX, $scale, $dur)
        $a1.EasingFunction = $ease
        $st.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $a1)
        $a2 = New-Object System.Windows.Media.Animation.DoubleAnimation([double]$st.ScaleY, $scale, $dur)
        $a2.EasingFunction = $ease
        $st.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $a2)
        $a3 = New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tt.Y, $lift, $dur)
        $a3.EasingFunction = $ease
        $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $a3)
    } catch { }
}

# macOS-ish magnification: hovered icon grows, its neighbours follow a little
function Set-DockHover([int]$hover) {
    if (-not $script:dockFx) { return }
    try {
        $count = $script:dockTiles.Count
        for ($i = 0; $i -lt $count; $i++) {
            $tile = $script:dockTiles[$i].tile
            $d = 99
            if ($hover -ge 0) { $d = [math]::Abs($i - $hover) }
            $tile.Background = $(if ($d -eq 0) { Br '#1FFFFFFF' } else { Br '#00FFFFFF' })
            switch ($d) {
                0 { Anim-DockTile $tile 1.18 -7 130; $tile.Effect = $script:dockGlow }
                1 { Anim-DockTile $tile 1.08 -3 130; $tile.Effect = $null }
                2 { Anim-DockTile $tile 1.03 -1 130; $tile.Effect = $null }
                default { Anim-DockTile $tile 1.0 0 140; $tile.Effect = $null }
            }
        }
        if ($script:dockAddTile) {
            if ($hover -eq $count) { Anim-DockTile $script:dockAddTile 1.1 -3 130; $script:dockAddTile.Effect = $script:dockGlow }
            else { Anim-DockTile $script:dockAddTile 1.0 0 140; $script:dockAddTile.Effect = $null }
        }
    } catch { }
}

# little jump when an app is launched from the dock
function Bounce-DockTile($tile) {
    try {
        if (-not $script:dockFx -or -not $tile) { return }
        $tg = $tile.RenderTransform
        if (-not $tg -or $tg.Children.Count -lt 2) { return }
        $tt = $tg.Children[1]
        $anim = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        $points = @(
            @(0.00, 0.0), @(0.24, -13.0), @(0.50, 2.0), @(0.72, -6.0), @(1.00, 0.0)
        )
        foreach ($pt in $points) {
            $k = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame
            $k.KeyTime = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds([double]$pt[0]))
            $k.Value = [double]$pt[1]
            $e = New-Object System.Windows.Media.Animation.CubicEase
            $e.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
            $k.EasingFunction = $e
            [void]$anim.KeyFrames.Add($k)
        }
        $anim.Duration = [System.Windows.Duration]::Automatic
        $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
    } catch { }
}

# icons slide up + fade in, one after another
function Invoke-DockIntro {
    if (-not $script:dockFx) { return }
    try {
        $items = @($script:dockTiles)
        if ($script:dockAddTile) { $items += [pscustomobject]@{ tile = $script:dockAddTile } }
        for ($i = 0; $i -lt $items.Count; $i++) {
            $tile = $items[$i].tile
            $tg = $tile.RenderTransform
            if (-not $tg -or $tg.Children.Count -lt 2) { continue }
            $tt = $tg.Children[1]
            $delay = [TimeSpan]::FromMilliseconds(38 * $i)
            $dur = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(340))
            $ease = New-Object System.Windows.Media.Animation.CubicEase
            $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
            $tt.Y = 16
            $fade = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, 1.0, $dur)
            $fade.BeginTime = $delay
            $fade.EasingFunction = $ease
            $tile.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
            $slide = New-Object System.Windows.Media.Animation.DoubleAnimation(16.0, 0.0, $dur)
            $slide.BeginTime = $delay
            $slide.EasingFunction = $ease
            $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $slide)
        }
    } catch { }
}

# small dot under every icon whose app currently has an open window
function Update-DockDots {
    try {
        if (-not $script:dockWin -or -not $script:dockWin.IsVisible) { return }
        if ($script:dockTiles.Count -lt 1) { return }
        $names = New-Object System.Collections.ArrayList
        foreach ($e in $script:dockTiles) {
            foreach ($nm in (Get-AppProcNames $e.app)) { if (-not $names.Contains($nm)) { [void]$names.Add($nm) } }
        }
        if ($names.Count -lt 1) { return }
        $counts = [UDWin]::GetVisibleWindowCounts()
        $byName = @{}
        foreach ($pr in @(Get-Process -Name @($names) -ErrorAction SilentlyContinue)) {
            $n = $pr.ProcessName.ToLower()
            if (-not $byName.ContainsKey($n)) { $byName[$n] = New-Object System.Collections.ArrayList }
            [void]$byName[$n].Add($pr.Id)
        }
        foreach ($e in $script:dockTiles) {
            $running = $false
            foreach ($nm in (Get-AppProcNames $e.app)) {
                $k = $nm.ToLower()
                if (-not $byName.ContainsKey($k)) { continue }
                foreach ($id in $byName[$k]) {
                    $c = 0
                    if ($counts.ContainsKey([uint32]$id)) { $c = $counts[[uint32]$id] }
                    if ($c -gt 0) { $running = $true; break }
                }
                if ($running) { break }
            }
            $target = $(if ($running) { 1.0 } else { 0.0 })
            $dot = $e.dot
            if (-not $dot) { continue }
            if ([math]::Abs([double]$dot.Opacity - $target) -gt 0.03) {
                $dur = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(220))
                $a = New-Object System.Windows.Media.Animation.DoubleAnimation([double]$dot.Opacity, $target, $dur)
                $dot.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a)
            }
        }
    } catch { }
}

function Start-DockDots {
    if (-not $script:dockWin) { return }
    if ($script:dockDotTimer) { $script:dockDotTimer.Stop(); return }
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromSeconds(2)
    $t.Add_Tick({ Update-DockDots })
    $script:dockDotTimer = $t
    $t.Start()
    Update-DockDots
}

function Update-DockWindows {
    try { Save-Config } catch { Write-WidgetError $_ 'save config' }
    try { Build-DockTiles } catch { Write-WidgetError $_ 'build dock tiles' }
    try { Set-DockPosition } catch { Write-WidgetError $_ 'set dock position' }
    try { Refresh-Manager } catch { Write-WidgetError $_ 'refresh manager' }
}

function New-DockTile($app, [int]$index) {
    $tile = New-Object System.Windows.Controls.Border
    $tile.Width = 46; $tile.Height = 46
    $tile.CornerRadius = CR 13
    $tile.Background = Br '#00FFFFFF'
    $tile.Margin = Th 3 0 3 0
    $tile.Cursor = 'Hand'
    $tile.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.85)
    $tg = New-Object System.Windows.Media.TransformGroup
    $st = New-Object System.Windows.Media.ScaleTransform(1, 1)
    $tt = New-Object System.Windows.Media.TranslateTransform(0, 0)
    [void]$tg.Children.Add($st)
    [void]$tg.Children.Add($tt)
    $tile.RenderTransform = $tg

    $grid = New-Object System.Windows.Controls.Grid

    $img = New-Object System.Windows.Controls.Image
    $icon = Get-FileIcon $app.path 32
    if ($icon) { $img.Source = $icon } else { $img.Source = $null }
    $img.Width = 30; $img.Height = 30
    $img.Stretch = 'Uniform'
    $img.HorizontalAlignment = 'Center'
    $img.VerticalAlignment = 'Center'
    [void]$grid.Children.Add($img)

    # running indicator
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 4; $dot.Height = 4
    $dot.Fill = Br '#8FB4FF'
    $dot.HorizontalAlignment = 'Center'
    $dot.VerticalAlignment = 'Bottom'
    $dot.Margin = Th 0 0 0 2
    $dot.Opacity = 0
    [void]$grid.Children.Add($dot)

    $tile.Child = $grid
    $tile.ToolTip = $app.name
    $tile.Tag = [pscustomobject]@{ App = $app; Index = $index }

    $tile.Add_MouseEnter({ param($s, $e) Set-DockHover ([int]$s.Tag.Index) })
    $tile.Add_MouseLeave({ param($s, $e) Set-DockHover -1 })
    $tile.Add_MouseLeftButtonDown({ param($s, $e) Anim-DockTile $s 0.92 1 90 })
    $tile.Add_MouseLeftButtonUp({
        param($s, $e)
        $app = $s.Tag.App
        $running = $false
        try { $running = (@(Get-AppWindowHandles $app)).Count -gt 0 } catch { }
        Anim-DockTile $s 1.18 -7 120
        if (-not $running) { Bounce-DockTile $s }
        Launch-App $app
    })

    $menu = New-Object System.Windows.Controls.ContextMenu
    $menu.Background = Br '#12161F'
    $menu.Foreground = Br '#E8EEF8'
    $menu.BorderBrush = Br '#2A3140'

    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = 'Open (focus if already running)'
    $mi.Tag = $app
    $mi.Add_Click({ param($s, $e) Launch-App $s.Tag })
    [void]$menu.Items.Add($mi)

    $miN = New-Object System.Windows.Controls.MenuItem
    $miN.Header = 'Open a new window'
    $miN.Tag = $app
    $miN.Add_Click({ param($s, $e) Launch-App $s.Tag -NewWindow })
    [void]$menu.Items.Add($miN)

    $miL = New-Object System.Windows.Controls.MenuItem
    $miL.Header = 'Move left'
    $miL.Tag = $index
    $miL.Add_Click({ param($s, $e) Move-DockApp ([int]$s.Tag) -1 })
    [void]$menu.Items.Add($miL)

    $miR2 = New-Object System.Windows.Controls.MenuItem
    $miR2.Header = 'Move right'
    $miR2.Tag = $index
    $miR2.Add_Click({ param($s, $e) Move-DockApp ([int]$s.Tag) 1 })
    [void]$menu.Items.Add($miR2)

    $miF = New-Object System.Windows.Controls.MenuItem
    $miF.Header = 'Open file location'
    $miF.Tag = $app.path
    $miF.Add_Click({
        param($s, $e)
        try {
            $p = $s.Tag
            if (Test-Path -LiteralPath $p) { Start-Process explorer.exe -ArgumentList ('/select,"' + $p + '"') }
        } catch { }
    })
    [void]$menu.Items.Add($miF)

    [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))

    $miD = New-Object System.Windows.Controls.MenuItem
    $miD.Header = 'Remove from dock'
    $miD.Tag = $index
    $miD.Add_Click({ param($s, $e) Remove-DockApp ([int]$s.Tag) })
    [void]$menu.Items.Add($miD)

    $tile.ContextMenu = $menu
    return [pscustomobject]@{ tile = $tile; img = $img; dot = $dot; app = $app }
}

function Build-DockTiles {
    if (-not $dockPanel) { return }
    $dockPanel.Children.Clear()
    $script:dockTiles.Clear()
    $i = 0
    foreach ($a in @($script:cfg.dock.apps)) {
        try {
            $entry = New-DockTile $a $i
            [void]$script:dockTiles.Add($entry)
            [void]$dockPanel.Children.Add($entry.tile)
        } catch {
            Write-WidgetError $_ "dock tile: $($a.name)"
        }
        $i++
    }
    # thin divider, then the "+" tile
    $div = New-Object System.Windows.Controls.Border
    $div.Width = 1; $div.Height = 30
    $div.Background = Br '#26FFFFFF'
    $div.Margin = Th 7 0 7 0
    [void]$dockPanel.Children.Add($div)

    $add = New-Object System.Windows.Controls.Border
    $add.Width = 46; $add.Height = 46
    $add.CornerRadius = CR 13
    $add.Background = Br '#0DFFFFFF'
    $add.Margin = Th 3 0 3 0
    $add.Cursor = 'Hand'
    $add.ToolTip = 'Manage apps (add / remove / reorder)'
    $add.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.85)
    $atg = New-Object System.Windows.Media.TransformGroup
    [void]$atg.Children.Add((New-Object System.Windows.Media.ScaleTransform(1, 1)))
    [void]$atg.Children.Add((New-Object System.Windows.Media.TranslateTransform(0, 0)))
    $add.RenderTransform = $atg
    $plus = Txt '+' 24 '#7C8CA3' 'SemiBold'
    $plus.HorizontalAlignment = 'Center'
    $add.Child = $plus
    $add.Add_MouseEnter({ param($s, $e) Set-DockHover ([int]$script:dockTiles.Count) })
    $add.Add_MouseLeave({ param($s, $e) Set-DockHover -1 })
    $add.Add_MouseLeftButtonUp({ param($s, $e) try { Show-AppsManager } catch { Write-WidgetError $_ 'show apps manager' } })
    [void]$dockPanel.Children.Add($add)
    $script:dockAddTile = $add
}

function Add-PathsToDock($paths) {
    $apps = New-Object System.Collections.ArrayList
    foreach ($a in @($script:cfg.dock.apps)) { [void]$apps.Add($a) }
    $added = 0
    foreach ($raw in @($paths)) {
        if ($null -eq $raw) { continue }
        try {
            $p = [string]$raw
            if (-not $p -or $p.Trim().Length -lt 2) { continue }
            $full = $p
            if ($p -like '*.lnk') {
                try {
                    $sh = New-Object -ComObject WScript.Shell
                    $sc = $sh.CreateShortcut($p)
                    $tp = [string]$sc.TargetPath
                    $ar = [string]$sc.Arguments
                    if ($tp) { $full = $tp }
                    # Store apps: shortcuts run explorer.exe with shell:AppsFolder\<AUMID>
                    if ($ar -match 'shell:AppsFolder\\(.+)$') { $full = $matches[1].Trim() }
                } catch { }
            }
            $exists = $false
            foreach ($a in $apps) { if ([string]$a.path -eq $full) { $exists = $true; break } }
            if ($exists) { continue }
            $nm = $full
            try {
                $base = [System.IO.Path]::GetFileNameWithoutExtension($full)
                if ($base) { $nm = $base }
            } catch { }
            [void]$apps.Add([pscustomobject]@{ name = $nm; path = $full; args = '' })
            $added++
        } catch {
            Write-WidgetError $_ "Add-PathsToDock ($raw)"
        }
    }
    if ($added -gt 0) {
        $script:cfg.dock.apps = $apps
        try { Update-DockWindows } catch { Write-WidgetError $_ 'Update-DockWindows' }
    }
    return $added
}

# pull real file paths out of a drag & drop payload (explorer / desktop / Start menu)
function Get-DroppedPaths($e) {
    $out = New-Object System.Collections.ArrayList
    try {
        if (-not $e -or -not $e.Data) { return $out.ToArray() }
        foreach ($f in @($e.Data.GetFormats())) {
            try {
                if ($f -eq [System.Windows.DataFormats]::FileDrop) {
                    foreach ($x in @($e.Data.GetData($f))) {
                        if ($x -is [string] -and $x.Trim()) { [void]$out.Add($x) }
                    }
                } elseif ($f -eq 'FileNameW' -or $f -eq 'FileName') {
                    $v = [string]$e.Data.GetData($f)
                    $v = $v.TrimEnd([char]0)
                    if ($v -and -not $out.Contains($v)) { [void]$out.Add($v) }
                }
            } catch { }
        }
    } catch { }
    return $out.ToArray()
}

function Add-AppToDock {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = 'Add applications to the dock'
    $dlg.Multiselect = $true
    $dlg.Filter = 'Applications (*.exe;*.lnk;*.bat;*.cmd)|*.exe;*.lnk;*.bat;*.cmd|All files (*.*)|*.*'
    $dlg.InitialDirectory = "$env:ProgramFiles"
    if ($dlg.ShowDialog() -eq $true) { [void](Add-PathsToDock $dlg.FileNames) }
}

function Remove-DockApp([int]$index) {
    $apps = @($script:cfg.dock.apps)
    if ($index -lt 0 -or $index -ge $apps.Count) { return }
    $list = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $apps.Count; $i++) { if ($i -ne $index) { [void]$list.Add($apps[$i]) } }
    $script:cfg.dock.apps = $list
    Update-DockWindows
}

function Move-DockApp([int]$index, [int]$dir) {
    $apps = @($script:cfg.dock.apps)
    $t = $index + $dir
    if ($index -lt 0 -or $index -ge $apps.Count) { return }
    if ($t -lt 0 -or $t -ge $apps.Count) { return }
    $list = New-Object System.Collections.ArrayList
    foreach ($a in $apps) { [void]$list.Add($a) }
    $tmp = $list[$index]; $list[$index] = $list[$t]; $list[$t] = $tmp
    $script:cfg.dock.apps = $list
    Update-DockWindows
}

function Restore-DefaultDock {
    $script:cfg.dock.apps = Get-DefaultApps
    Update-DockWindows
}

# ---------------- Music window (now playing: Spotify / Anghami / browsers) ----------------
$musicWin = $null; $musicCtl = @{}
$script:smtcMgr = $null; $script:smtcSession = $null; $script:artKey = ''; $script:artBmp = $null; $script:artTry = [datetime]::MinValue; $script:artCache = @{}; $script:artTitle = ''; $script:artMissSince = [datetime]::MinValue
$script:lastMusicState = ''
$script:musicTimer = $null

# WinRT bridge — the Windows "now playing" API (SMTC) that Spotify, browsers and players publish to
$script:winrtOk = $false; $script:asTaskGeneric = $null
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
    $script:asTaskGeneric = @([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]
    if ($script:asTaskGeneric) { $script:winrtOk = $true }
} catch { }

$script:SMTC_MGR = $null; $script:SMTC_PROPS = $null; $script:SMTC_STREAM = $null
try {
    $script:SMTC_MGR = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
    $script:SMTC_PROPS = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]
    $script:SMTC_STREAM = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
} catch { $script:winrtOk = $false }

function Await-WinRt($op, $type) {
    if (-not $script:winrtOk) { return $null }
    try {
        $m = $script:asTaskGeneric.MakeGenericMethod($type)
        $t = $m.Invoke($null, @($op))
        if (-not $t.Wait(4000)) { return $null }
        return $t.Result
    } catch { return $null }
}

function Get-MusicSourceName([string]$id) {
    if ([string]::IsNullOrWhiteSpace($id)) { return 'MEDIA' }
    $l = $id.ToLower()
    if ($l -like '*anghami*') { return 'ANGHAMI' }
    if ($l -like '*spotify*') { return 'SPOTIFY' }
    if ($l -match 'chrome|msedge|firefox|brave|opera|vivaldi') { return 'BROWSER' }
    if ($l -like '*zune*' -or $l -like '*mediaplayer*' -or $l -like '*music.ui*') { return 'MEDIA PLAYER' }
    if ($l -like '*vlc*') { return 'VLC' }
    $n = ($id -split '[\\!]' | Where-Object { $_ } | Select-Object -Last 1)
    if (-not $n) { $n = $id }
    return (($n -replace '\.exe$', '').ToUpper())
}

function Format-MusicTime([double]$sec) {
    if ($sec -le 0 -or [double]::IsNaN($sec)) { return '0:00' }
    $s = [int][math]::Floor($sec)
    return ('{0}:{1:00}' -f [int]($s / 60), ($s % 60))
}

function Get-SmtcArtwork($props) {
    try {
        $ref = $props.Thumbnail
        if ($null -eq $ref) { return $null }
        $stream = Await-WinRt ($ref.OpenReadAsync()) $script:SMTC_STREAM
        if ($null -eq $stream) { return $null }
        $net = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.StreamSource = $net
        $bmp.EndInit()
        $bmp.Freeze()
        $net.Dispose()
        return $bmp
    } catch { return $null }
}

# --- browser tabs via UI Automation: reads the title of EVERY tab (Yandex, Chrome, Edge, Firefox...) ---
$script:uiaOk = $false
try {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
    Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
    $script:uiaOk = $true
} catch { }
$script:musicTabIdx = -1
$script:lastTabScan = [datetime]::MinValue
$script:lastGoodTab = [datetime]::MinValue
$script:tabNowCache = $null

# fallback for when the browser window is minimized (Chromium hides its tab strip) — read the window title
function Get-BrowserWindowNowPlaying {
    $res = @{ ok = $false; source = ''; srcName = ''; title = ''; artist = ''; album = ''; playing = $false; pos = 0.0; dur = 0.0; art = $null; fromWindow = $true }
    $titles = New-Object System.Collections.ArrayList
    try {
        if ($script:uiaOk) {
            $AE = [System.Windows.Automation.AutomationElement]
            foreach ($w in $AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
                $pn = ''
                try { $pn = (Get-Process -Id $w.Current.ProcessId -ErrorAction SilentlyContinue).ProcessName } catch { }
                if ($pn -notmatch '(?i)^(browser|chrome|msedge|firefox|opera|brave|vivaldi)$') { continue }
                $nm = ''
                try { $nm = [string]$w.Current.Name } catch { }
                if ($nm) { [void]$titles.Add($nm) }
            }
        } else {
            foreach ($t in [UDWin]::GetVisibleWindowTitles()) { [void]$titles.Add([string]$t) }
        }
    } catch { }
    try {
        foreach ($raw in $titles) {
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $marked = ($raw -match '^\s*[▶►⏵\u25B6]')
            $bullet = ($raw -match '\u2022')
            $site = ''
            if ($raw -match '(?i)(anghami|أنغامي)') { $site = 'ANGHAMI' }
            elseif ($raw -match '(?i)(spotify|سبوتيفاي)') { $site = 'SPOTIFY' }
            elseif ($raw -match '(?i)soundcloud') { $site = 'SOUNDCLOUD' }
            elseif ($raw -match '(?i)(youtube music|يوتيوب)') { $site = 'YOUTUBE' }
            $clean = $raw -replace '^\s*[▶►⏵⏸⏹\u25B6\u23F8\u23F9]\s*', ''
            $clean = $clean -replace '(?i),\s*profile\s+[^,–—-]+(?=\s*[-–—|]|$)', ''
            $clean = $clean -replace '(?i)\s*[\|\-–—•·]\s*(Anghami|أنغامي|Spotify( Web Player)?|سبوتيفاي|YouTube Music|SoundCloud|Deezer|Apple Music|Yandex\s*Browser|Google Chrome|Microsoft.{0,3}Edge|Mozilla Firefox|Brave|Opera|Vivaldi).*$', ''
            $clean = $clean -replace '(?i)[,–—-]\s*profile\s+.*$', ''
            $clean = $clean.Trim()
            if ([string]::IsNullOrWhiteSpace($clean)) { continue }
            # a bare window title is trusted only when the browser marks it as playing audio or it names a music service
            if (-not $marked -and -not $site -and -not $bullet) { continue }
            if ($clean -match '(?i)liked songs|web player|sign in|log in|playlist|browse|search|library|premium|download|queue|inbox|whatsapp|facebook|autodesk|gmail|leads|^profile') { continue }
            $parts = @($clean -split '\s*[•·]\s*|\s{2,}|\s+[-–—]\s+')
            if ($parts.Count -lt 2) { continue }
            $song = ([string]$parts[0]).Trim()
            $artist = ([string]$parts[1]).Trim()
            if ($song.Length -lt 2 -or $artist.Length -lt 2) { continue }
            if ($song -match '(?i)^(spotify|anghami|أنغامي|youtube( music)?|soundcloud|deezer|apple music|music)$') { continue }
            $res.ok = $true
            $res.title = $song
            $res.artist = $artist
            $res.srcName = $(if ($site) { $site } else { 'BROWSER' })
            $res.playing = $true
            return $res
        }
    } catch { }
    return $res
}

function Get-BrowserTabsNowPlaying {
    $res = @{ ok = $false; source = ''; srcName = ''; title = ''; artist = ''; album = ''; playing = $false; pos = 0.0; dur = 0.0; art = $null; fromWindow = $true }
    if (-not $script:uiaOk) { return (Get-BrowserWindowNowPlaying) }
    try {
        $AE = [System.Windows.Automation.AutomationElement]
        $tabCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::TabItem)
        $mediaCondA = New-Object System.Windows.Automation.PropertyCondition($AE::ClassNameProperty, 'MediaIndicatorButtonDeprecated')
        $mediaCondB = New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, 'media indicator')
        $tabs = New-Object System.Collections.ArrayList
        foreach ($w in $AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
            $pn = ''
            try { $pn = (Get-Process -Id $w.Current.ProcessId -ErrorAction SilentlyContinue).ProcessName } catch { }
            if ($pn -notmatch '(?i)^(browser|chrome|msedge|firefox|opera|brave|vivaldi)$') { continue }
            try {
                foreach ($t in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCond)) {
                    $n = ''
                    try { $n = [string]$t.Current.Name } catch { }
                    if ([string]::IsNullOrWhiteSpace($n)) { continue }
                    $hasMedia = $false
                    try {
                        if ($t.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $mediaCondA)) { $hasMedia = $true }
                        elseif ($t.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $mediaCondB)) { $hasMedia = $true }
                    } catch { }
                    [void]$tabs.Add([pscustomobject]@{ name = $n; media = $hasMedia })
                }
            } catch { }
        }
        if ($tabs.Count -eq 0) { return (Get-BrowserWindowNowPlaying) }

        function Parse-TabTitle([string]$raw, [bool]$trusted) {
            if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
            $clean = $raw -replace '^\s*[▶►⏵⏸⏹\u25B6\u23F8\u23F9]\s*', ''
            $clean = $clean -replace '(?i),\s*profile\s+[^,–—-]+(?=\s*[-–—|]|$)', ''
            $clean = $clean -replace '(?i)\s*[\|\-–—•·]\s*(Anghami|أنغامي|Spotify( Web Player)?|سبوتيفاي|YouTube Music|SoundCloud|Deezer|Apple Music|Yandex\s*Browser|Google Chrome|Microsoft.{0,3}Edge|Mozilla Firefox|Brave|Opera|Vivaldi).*$', ''
            $clean = $clean.Trim()
            if ([string]::IsNullOrWhiteSpace($clean)) { return $null }
            if ($clean -match '(?i)^(spotify|anghami|أنغامي|youtube( music)?|soundcloud|deezer|apple music|music)$') { return $null }
            if ($clean -match '(?i)liked songs|profile|web player|sign in|log in|playlist|browse|search|library|premium|download|home|queue|inbox|whatsapp|facebook|autodesk|gmail|leads') { return $null }
            $sep = '\s*[•·]\s*|\s{2,}|\s+[–—]\s+'
            if ($trusted) { $sep = '\s*[•·]\s*|\s{2,}|\s+[-–—]\s+' }
            $parts = @($clean -split $sep)
            if ($parts.Count -lt 2) { return $null }
            $song = ([string]$parts[0]).Trim()
            $artist = ([string]$parts[1]).Trim()
            if ($song.Length -lt 2 -or $artist.Length -lt 2) { return $null }
            if ($song -match '(?i)^(spotify|anghami|أنغامي|youtube|soundcloud|deezer|apple music)$') { return $null }
            return @{ title = $song; artist = $artist }
        }

        # 1) the browser marks the tab that is playing audio (speaker icon) — the most reliable signal
        for ($i = 0; $i -lt $tabs.Count; $i++) {
            if ($tabs[$i].media) {
                $h = Parse-TabTitle ([string]$tabs[$i].name) $true
                if ($h) {
                    $script:musicTabIdx = $i
                    $res.ok = $true
                    $res.title = $h.title
                    $res.artist = $h.artist
                    $res.srcName = 'BROWSER'
                    $res.playing = $true
                    return $res
                }
            }
        }

        # 2) the tab whose title carries a music-site name (idle or playing)
        $siteIdx = -1; $siteTag = ''
        for ($i = 0; $i -lt $tabs.Count; $i++) {
            if ($tabs[$i].name -match '(?i)(spotify|anghami|أنغامي|سبوتيفاي|youtube music|soundcloud|deezer|apple music)') {
                $siteIdx = $i
                $siteTag = ([string]$matches[1]).ToUpper()
                break
            }
        }
        if ($siteIdx -ge 0) { $script:musicTabIdx = $siteIdx }

        # 3) the tab we already learned -> read its title (trust it even after the site name disappears while playing)
        $hit = $null
        $idx = $script:musicTabIdx
        if ($idx -ge 0 -and $idx -lt $tabs.Count) {
            $hit = Parse-TabTitle ([string]$tabs[$idx].name) $true
        }

        # 4) nothing learned yet: look for a "song • artist" tab
        if (-not $hit) {
            for ($i = 0; $i -lt $tabs.Count; $i++) {
                $h = Parse-TabTitle ([string]$tabs[$i].name) ($siteIdx -eq $i)
                if ($h) { $hit = $h; $script:musicTabIdx = $i; break }
            }
        }
        if (-not $hit) { return (Get-BrowserWindowNowPlaying) }

        $res.ok = $true
        $res.title = $hit.title
        $res.artist = $hit.artist
        $res.srcName = $(if ($siteTag) { $siteTag } else { 'BROWSER' })
        $res.playing = $true
    } catch { }
    return $res
}
# album art by artist/title (iTunes public search — no key, no install)
function Get-TrackArtwork([string]$artist, [string]$title) {
    try {
        $term = [uri]::EscapeDataString("$artist $title")
        $r = Invoke-RestMethod -Uri "https://itunes.apple.com/search?term=$term&media=music&limit=10" -TimeoutSec 10
        if (-not $r -or $r.resultCount -lt 1) { return $null }
        $norm = {
            param($s)
            $t = ([string]$s).ToLower()
            $t = $t -replace '\([^)]*\)|\[[^\]]*\]', ' '
            $t = $t -replace '[^\p{L}\p{Nd}\s]', ' '
            return ($t -replace '\s+', ' ').Trim()
        }
        $wantT = & $norm $title
        $wantA = & $norm $artist
        $pick = $null
        foreach ($it in @($r.results)) {
            $tn = & $norm $it.trackName
            $an = & $norm $it.artistName
            $artistOk = ($wantA -ne '' -and ($an -like "*$wantA*" -or $wantA -like "*$an*"))
            if ($tn -eq $wantT -and $artistOk) { $pick = $it; break }
            if (-not $pick -and $tn -eq $wantT) { $pick = $it }
        }
        if (-not $pick) { $pick = $r.results[0] }
        $u = [string]$pick.artworkUrl100
        if (-not $u) { return $null }
        $u = $u -replace '/\d+x\d+bb', '/600x600bb'
        # download the bytes first: a UriSource bitmap stays asynchronously "unfreezable"
        $req = [System.Net.HttpWebRequest]::Create($u)
        $req.Timeout = 6000
        $req.ReadWriteTimeout = 6000
        $req.UserAgent = 'Mozilla/5.0'
        $resp = $req.GetResponse()
        $ms = New-Object System.IO.MemoryStream
        try {
            $st = $resp.GetResponseStream()
            $st.CopyTo($ms)
        } finally { $resp.Close() }
        $bytes = $ms.ToArray()
        $ms.Dispose()
        if (-not $bytes -or $bytes.Length -lt 1000) { return $null }
        $ms = New-Object System.IO.MemoryStream(, $bytes)
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.StreamSource = $ms
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.EndInit()
        $bmp.Freeze()
        $ms.Dispose()
        return $bmp
    } catch { return $null }
}

# keep downloaded covers in memory (per track) so pausing / re-detecting shows them instantly
function Get-CachedArtwork([string]$key, [scriptblock]$fetch) {
    $now = Get-Date
    if ($script:artCache.ContainsKey($key) -and $script:artCache[$key]) { return $script:artCache[$key] }
    $due = ($script:artKey -ne $key) -or (($now - $script:artTry).TotalSeconds -gt 20)
    if ($due) {
        $script:artKey = $key
        $script:artTry = $now
        $bmp = $null
        try { $bmp = & $fetch } catch { $bmp = $null }
        if ($bmp) {
            if ($script:artCache.Count -ge 30) { $script:artCache.Clear() }
            $script:artCache[$key] = $bmp
            return $bmp
        }
    }
    # the same song sometimes reports a slightly different artist string -> reuse the cover we already have
    $tk = @($key -split '\|')
    if ($tk.Count -ge 2) {
        foreach ($k in @($script:artCache.Keys)) {
            $pk = @($k -split '\|')
            if ($pk.Count -ge 2 -and $pk[1] -eq $tk[1] -and $script:artCache[$k]) { return $script:artCache[$k] }
        }
    }
    return $null
}

function Get-NowPlaying {
    $res = @{ ok = $false; source = ''; srcName = ''; title = ''; artist = ''; album = ''; playing = $false; pos = 0.0; dur = 0.0; art = $null; fromWindow = $false }
    if ($script:winrtOk) {
        try {
            if (-not $script:smtcMgr) { $script:smtcMgr = Await-WinRt ($script:SMTC_MGR::RequestAsync()) $script:SMTC_MGR }
            if ($script:smtcMgr) {
                $sessions = @($script:smtcMgr.GetSessions())
                if ($sessions.Count -gt 0) {
                    $pick = $null
                    foreach ($s in $sessions) {
                        try { if ([string]$s.GetPlaybackInfo().PlaybackStatus -eq 'Playing') { $pick = $s; break } } catch { }
                    }
                    if (-not $pick) { $pick = $sessions[0] }
                    $script:smtcSession = $pick
                    $props = Await-WinRt ($pick.TryGetMediaPropertiesAsync()) $script:SMTC_PROPS
                    if ($props -and -not [string]::IsNullOrWhiteSpace([string]$props.Title)) {
                        $info = $pick.GetPlaybackInfo()
                        $tl = $pick.GetTimelineProperties()
                        $res.ok = $true
                        $res.title = [string]$props.Title
                        $res.artist = [string]$props.Artist
                        $res.album = [string]$props.AlbumTitle
                        $res.playing = ([string]$info.PlaybackStatus -eq 'Playing')
                        $res.pos = [double]$tl.Position.TotalSeconds
                        $res.dur = [double]$tl.EndTime.TotalSeconds
                        $res.source = [string]$pick.SourceAppUserModelId
                        $res.srcName = Get-MusicSourceName $res.source
                        $key = "$($res.source)|$($res.title)|$($res.artist)"
                        $res.art = Get-CachedArtwork $key { Get-SmtcArtwork $props }
                    }
                }
            }
        } catch { }
    }
    if (-not $res.ok) {
        $now = Get-Date
        if ($null -eq $script:tabNowCache -or ($now - $script:lastTabScan).TotalSeconds -ge 1.6) {
            $script:lastTabScan = $now
            $fresh = Get-BrowserTabsNowPlaying
            if ($fresh.ok) {
                $script:tabNowCache = $fresh
                $script:lastGoodTab = $now
            } elseif ($script:tabNowCache -and $script:tabNowCache.ok -and ($now - $script:lastGoodTab).TotalSeconds -lt 3) {
                # the browser drops its accessibility tree for a moment while pausing / switching tabs — keep the last track briefly
            } else {
                $script:tabNowCache = $fresh
            }
        }
        $res = @{} + $script:tabNowCache
        if ($res.ok) {
            $key = "tab|$($res.title)|$($res.artist)"
            $res.art = Get-CachedArtwork $key { Get-TrackArtwork $res.artist $res.title }
        }
    }
    return $res
}

function Invoke-MusicAction([string]$action) {
    $done = $false
    $s = $script:smtcSession
    if ($s) {
        try {
            switch ($action) {
                'play' { [void](Await-WinRt ($s.TryTogglePlayPauseAsync()) ([bool])); $done = $true }
                'next' { [void](Await-WinRt ($s.TrySkipNextAsync()) ([bool])); $done = $true }
                'prev' { [void](Await-WinRt ($s.TrySkipPreviousAsync()) ([bool])); $done = $true }
            }
        } catch { $done = $false }
    }
    if (-not $done) {
        switch ($action) {
            'play' { [UDWin]::MediaKey(0xB3) }
            'next' { [UDWin]::MediaKey(0xB0) }
            'prev' { [UDWin]::MediaKey(0xB1) }
        }
    }
    try { if ($script:musicTimer) { $script:musicTimer.Stop(); $script:musicTimer.Start() } } catch { }
}

function Update-MusicWidget {
    if (-not $script:musicWin) { return }
    try {
        $np = Get-NowPlaying
        $sig = "$($np.ok)|$($np.srcName)|$($np.title)|$($np.artist)|$($np.playing)"
        $changed = ($sig -ne $script:lastMusicState)
        if ($changed) {
            $script:lastMusicState = $sig
            try {
                $dbg = @{} + $np
                $dbg.art = $(if ($np.art) { 'yes' } else { $null })
                ($dbg | ConvertTo-Json -Compress) | Set-Content -LiteralPath (Join-Path $PreviewDir 'music-state.json') -Encoding UTF8
            } catch { }
        }
        if ($np.ok) {
            $musicCtl['title'].Text = $np.title
            $musicCtl['artist'].Text = $(if ($np.artist) { $np.artist } else { $np.album })
            $musicCtl['src'].Text = $np.srcName
            $musicCtl['dot'].Background = Br $(if ($np.playing) { '#34D399' } else { '#64748B' })
            if ($np.dur -gt 1) {
                $musicCtl['progRow'].Visibility = 'Visible'
                $w = [double]$musicCtl['track'].ActualWidth
                if ([double]::IsNaN($w) -or $w -le 0) { $w = 206.0 }
                $frac = [math]::Max(0.0, [math]::Min(1.0, $np.pos / $np.dur))
                $musicCtl['fill'].Width = [double]($w * $frac)
                $musicCtl['cur'].Text = Format-MusicTime $np.pos
                $musicCtl['tot'].Text = Format-MusicTime $np.dur
            } else {
                $musicCtl['progRow'].Visibility = 'Collapsed'
            }
            $musicCtl['playGlyph'].Data = [System.Windows.Media.Geometry]::Parse($(if ($np.playing) { 'M1,0 H4 V12 H1 Z M8,0 H11 V12 H8 Z' } else { 'M1,0 L12,6.5 L1,13 Z' }))
            if ($np.art) {
                if (-not [object]::ReferenceEquals($musicCtl['img'].Source, $np.art)) {
                    $musicCtl['img'].Source = $np.art
                    $musicCtl['ph'].Visibility = 'Collapsed'
                }
                $script:artTitle = [string]$np.title
                $script:artMissSince = [datetime]::MinValue
            } elseif ([string]$script:artTitle -ne [string]$np.title) {
                # a different song with no cover yet -> drop the previous one
                $musicCtl['img'].Source = $null
                $musicCtl['ph'].Visibility = 'Visible'
            }
        } else {
            $musicCtl['title'].Text = 'Nothing playing'
            $musicCtl['artist'].Text = 'Play a song from Anghami or Spotify'
            $musicCtl['src'].Text = 'BROWSER'
            $musicCtl['dot'].Background = Br '#475569'
            $musicCtl['progRow'].Visibility = 'Collapsed'
            $musicCtl['playGlyph'].Data = [System.Windows.Media.Geometry]::Parse('M1,0 L12,6.5 L1,13 Z')
            if ($script:artMissSince -eq [datetime]::MinValue) { $script:artMissSince = Get-Date }
            if (((Get-Date) - $script:artMissSince).TotalSeconds -gt 8) {
                $musicCtl['img'].Source = $null
                $musicCtl['ph'].Visibility = 'Visible'
                $script:artTitle = ''
            }
        }
    } catch { }
}

function New-MusicButton([string]$kind, [double]$size, [string]$bg, [string]$fg, [string]$hoverBg) {
    $b = New-Object System.Windows.Controls.Border
    $b.Width = $size; $b.Height = $size
    $b.CornerRadius = CR ($size / 2)
    $b.Background = Br $bg
    $b.Margin = Th 6 0 6 0
    $b.Cursor = [System.Windows.Input.Cursors]::Hand
    $p = New-Object System.Windows.Shapes.Path
    $p.Fill = Br $fg
    $p.Stretch = [System.Windows.Media.Stretch]::Uniform
    $p.HorizontalAlignment = 'Center'
    $p.VerticalAlignment = 'Center'
    switch ($kind) {
        'prev' { $p.Width = 11; $p.Height = 11; $p.Data = [System.Windows.Media.Geometry]::Parse('M1,0 H3.4 V12 H1 Z M11.4,0 L3.8,6 L11.4,12 Z') }
        'next' { $p.Width = 11; $p.Height = 11; $p.Data = [System.Windows.Media.Geometry]::Parse('M8.6,0 H11 V12 H8.6 Z M0.6,0 L8.2,6 L0.6,12 Z') }
        'play' { $p.Width = 12; $p.Height = 13; $p.Data = [System.Windows.Media.Geometry]::Parse('M1,0 L12,6.5 L1,13 Z') }
    }
    $b.Child = $p
    $b.Tag = $p
    $b.Add_MouseEnter({ param($s, $e) $s.Background = (Br $hoverBg) }.GetNewClosure())
    $b.Add_MouseLeave({ param($s, $e) $s.Background = (Br $bg) }.GetNewClosure())
    $b.Add_MouseLeftButtonUp({ param($s, $e) Invoke-MusicAction $kind }.GetNewClosure())
    return $b
}

if ($cfg.music.enabled -and -not $NoMusic) {
    $musicW = 236.0
    $artS = $musicW - 30

    $musicWin = New-Object System.Windows.Window
    $musicWin.Title = 'UD Music'
    $musicWin.WindowStyle = 'None'
    $musicWin.AllowsTransparency = $true
    $musicWin.Background = $null
    $musicWin.ShowInTaskbar = $false
    $musicWin.ResizeMode = 'NoResize'
    $musicWin.SizeToContent = 'WidthAndHeight'
    $musicWin.WindowStartupLocation = 'Manual'
    $musicWin.Topmost = [bool]$cfg.music.topmost

    $mRoot = New-Object System.Windows.Controls.Border
    $mRoot.CornerRadius = CR 16
    $mRoot.BorderThickness = Th 1 1 1 1
    $mRoot.BorderBrush = Br '#22FFFFFF'
    $mRoot.Width = $musicW
    $mRoot.Background = New-ThemeGlass 0.1 0 0.9 1
    $msh = New-Object System.Windows.Media.Effects.DropShadowEffect
    $msh.BlurRadius = 26; $msh.ShadowDepth = 0; $msh.Opacity = 0.6; $msh.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#000000')
    $mRoot.Effect = $msh

    $mOuter = New-Object System.Windows.Controls.Grid
    $mr0 = New-Object System.Windows.Controls.RowDefinition
    $mr0.Height = New-Object System.Windows.GridLength(2.5)
    $mr1 = New-Object System.Windows.Controls.RowDefinition
    $mr1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    [void]$mOuter.RowDefinitions.Add($mr0)
    [void]$mOuter.RowDefinitions.Add($mr1)

    $mAccent = New-Object System.Windows.Controls.Border
    $mAccent.Height = 2.5
    $mAccent.CornerRadius = New-Object System.Windows.CornerRadius(15, 15, 0, 0)
    $mAccent.Background = New-ThemeAccent3
    [System.Windows.Controls.Grid]::SetRow($mAccent, 0)
    [void]$mOuter.Children.Add($mAccent)

    $mBody = New-Object System.Windows.Controls.StackPanel
    $mBody.Margin = Th 15 11 15 14
    [System.Windows.Controls.Grid]::SetRow($mBody, 1)
    [void]$mOuter.Children.Add($mBody)
    $mRoot.Child = $mOuter

    # header
    $mHead = New-Object System.Windows.Controls.Grid
    $mhc1 = New-Object System.Windows.Controls.ColumnDefinition
    $mhc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $mhc2 = New-Object System.Windows.Controls.ColumnDefinition
    $mhc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
    [void]$mHead.ColumnDefinitions.Add($mhc1)
    [void]$mHead.ColumnDefinitions.Add($mhc2)

    $mHeadL = New-Object System.Windows.Controls.StackPanel
    $mHeadL.Orientation = 'Horizontal'
    $mDot = New-Object System.Windows.Controls.Border
    $mDot.Width = 6; $mDot.Height = 6; $mDot.CornerRadius = CR 3
    $mDot.Background = Br '#475569'
    $mDot.Margin = Th 0 0 7 0
    [void]$mHeadL.Children.Add($mDot)
    [void]$mHeadL.Children.Add((Txt 'NOW PLAYING' 9 '#B9C6DA' 'SemiBold'))
    [System.Windows.Controls.Grid]::SetColumn($mHeadL, 0)
    [void]$mHead.Children.Add($mHeadL)

    $mBrand = Txt 'UNLOCK DIGITAL' 8 '#5A6C86' 'SemiBold'
    $mBrand.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($mBrand, 1)
    [void]$mHead.Children.Add($mBrand)
    [void]$mBody.Children.Add($mHead)
    $musicCtl['dot'] = $mDot

    # artwork
    $mArt = New-Object System.Windows.Controls.Border
    $mArt.Width = $artS; $mArt.Height = $artS
    $mArt.CornerRadius = CR 13
    $mArt.ClipToBounds = $true
    $mArt.Margin = Th 0 12 0 0
    $mArt.Background = Br '#0B1220'
    $mArtGrid = New-Object System.Windows.Controls.Grid

    $mPh = New-Object System.Windows.Controls.Border
    $mphg = New-Object System.Windows.Media.LinearGradientBrush
    $mphg.StartPoint = New-Object System.Windows.Point(0, 0)
    $mphg.EndPoint = New-Object System.Windows.Point(1, 1)
    $mphg.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString('#16233B'), 0)))
    $mphg.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString('#0B1220'), 1)))
    $mPh.Background = $mphg
    $mNote = New-Object System.Windows.Controls.TextBlock
    $mNote.Text = [string][char]0x266B
    $mNote.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Symbol')
    $mNote.FontSize = 46
    $mNote.Foreground = Br '#2C4160'
    $mNote.HorizontalAlignment = 'Center'
    $mNote.VerticalAlignment = 'Center'
    $mPh.Child = $mNote
    [void]$mArtGrid.Children.Add($mPh)

    $mImg = New-Object System.Windows.Controls.Image
    $mImg.Stretch = 'UniformToFill'
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($mImg, [System.Windows.Media.BitmapScalingMode]::HighQuality)
    [void]$mArtGrid.Children.Add($mImg)
    $mArt.Child = $mArtGrid
    [void]$mBody.Children.Add($mArt)
    $musicCtl['img'] = $mImg
    $musicCtl['ph'] = $mPh

    # title / artist
    $mTitle = Txt 'Nothing playing' 13.5 '#EDF3FB' 'SemiBold'
    $mTitle.MaxWidth = $artS
    $mTitle.TextTrimming = 'CharacterEllipsis'
    $mTitle.Margin = Th 0 3 0 0
    [void]$mBody.Children.Add($mTitle)
    $mArtist = Txt 'Play a song from Anghami or Spotify' 10.5 '#8494AB'
    $mArtist.MaxWidth = $artS
    $mArtist.TextTrimming = 'CharacterEllipsis'
    [void]$mBody.Children.Add($mArtist)
    $musicCtl['title'] = $mTitle
    $musicCtl['artist'] = $mArtist

    # source pill
    $mPill = New-Object System.Windows.Controls.Border
    $mPill.CornerRadius = CR 7
    $mPill.Background = Br '#12FFFFFF'
    $mPill.Padding = Th 7 2 7 2
    $mPill.HorizontalAlignment = 'Left'
    $mPill.Margin = Th 0 9 0 0
    $mSrc = Txt 'BROWSER' 8 '#93A4BC' 'SemiBold'
    $mPill.Child = $mSrc
    [void]$mBody.Children.Add($mPill)
    $musicCtl['src'] = $mSrc

    # progress
    $mProgRow = New-Object System.Windows.Controls.StackPanel
    $mProgRow.Margin = Th 0 2 0 0
    $mProgRow.Visibility = 'Collapsed'
    $mTrackG = New-Object System.Windows.Controls.Grid
    $mTrack = New-Object System.Windows.Controls.Border
    $mTrack.Height = 4
    $mTrack.CornerRadius = CR 2
    $mTrack.Background = Br '#1AFFFFFF'
    [void]$mTrackG.Children.Add($mTrack)
    $mFill = New-Object System.Windows.Controls.Border
    $mFill.Height = 4
    $mFill.CornerRadius = CR 2
    $mFill.HorizontalAlignment = 'Left'
    $mFill.Background = New-ThemeAccent2
    $mFill.Width = 0
    [void]$mTrackG.Children.Add($mFill)
    [void]$mProgRow.Children.Add($mTrackG)

    $mTimes = New-Object System.Windows.Controls.Grid
    $mtc1 = New-Object System.Windows.Controls.ColumnDefinition
    $mtc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $mtc2 = New-Object System.Windows.Controls.ColumnDefinition
    $mtc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
    [void]$mTimes.ColumnDefinitions.Add($mtc1)
    [void]$mTimes.ColumnDefinitions.Add($mtc2)
    $mCur = Txt '0:00' 9 '#6E7F96'
    $mTot = Txt '0:00' 9 '#6E7F96'
    $mTot.TextAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($mCur, 0)
    [System.Windows.Controls.Grid]::SetColumn($mTot, 1)
    [void]$mTimes.Children.Add($mCur)
    [void]$mTimes.Children.Add($mTot)
    $mTimes.Margin = Th 0 5 0 0
    [void]$mProgRow.Children.Add($mTimes)
    [void]$mBody.Children.Add($mProgRow)
    $musicCtl['progRow'] = $mProgRow
    $musicCtl['track'] = $mTrackG
    $musicCtl['stage'] = $mProgRow
    $musicCtl['fill'] = $mFill
    $musicCtl['cur'] = $mCur
    $musicCtl['tot'] = $mTot

    # controls
    $mBtns = New-Object System.Windows.Controls.StackPanel
    $mBtns.Orientation = 'Horizontal'
    $mBtns.HorizontalAlignment = 'Center'
    $mBtns.Margin = Th 0 9 0 0
    $mPrev = New-MusicButton 'prev' 34 '#12FFFFFF' '#D7E3F4' '#22FFFFFF'
    $mPlay = New-MusicButton 'play' 46 '#EAF2FB' '#0A101C' '#FFFFFF'
    $mNext = New-MusicButton 'next' 34 '#12FFFFFF' '#D7E3F4' '#22FFFFFF'
    [void]$mBtns.Children.Add($mPrev)
    [void]$mBtns.Children.Add($mPlay)
    [void]$mBtns.Children.Add($mNext)
    [void]$mBody.Children.Add($mBtns)
    $musicCtl['playGlyph'] = $mPlay.Tag

    # right-click menu
    $mMenu = New-Object System.Windows.Controls.ContextMenu
    $mMenu.Background = Br '#12161F'
    $mMenu.Foreground = Br '#E8EEF8'
    $mMenu.BorderBrush = Br '#2A3140'
    $mMDrag = New-Object System.Windows.Controls.MenuItem
    $mMDrag.Header = '✥  Drag the panel to move it'
    $mMDrag.IsEnabled = $false
    [void]$mMenu.Items.Add($mMDrag)
    [void]$mMenu.Items.Add((New-Object System.Windows.Controls.Separator))
    $miA = New-Object System.Windows.Controls.MenuItem
    $miA.Header = 'Open Anghami (web)'
    $miA.Add_Click({ Start-Process 'https://www.anghami.com' })
    [void]$mMenu.Items.Add($miA)
    $miS = New-Object System.Windows.Controls.MenuItem
    $miS.Header = 'Open Spotify (web)'
    $miS.Add_Click({ Start-Process 'https://open.spotify.com' })
    [void]$mMenu.Items.Add($miS)
    [void]$mMenu.Items.Add((New-Object System.Windows.Controls.Separator))
    $miT = New-Object System.Windows.Controls.MenuItem
    $miT.Header = 'Keep on top'
    $miT.IsCheckable = $true
    $miT.IsChecked = [bool]$cfg.music.topmost
    $miT.Add_Click({ param($s, $e) $script:cfg.music.topmost = $s.IsChecked; $script:musicWin.Topmost = $s.IsChecked; Save-Config })
    [void]$mMenu.Items.Add($miT)
    Add-WidgetMenuItems $mMenu 'music'
    $miH = New-Object System.Windows.Controls.MenuItem
    $miH.Header = 'Hide music widget'
    $miH.Add_Click({ try { Set-WidgetVisible 'music' $false } catch { } })
    [void]$mMenu.Items.Add($miH)
    $mRoot.ContextMenu = $mMenu

    $musicWin.Content = $mRoot

    $script:musicTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:musicTimer.Interval = [TimeSpan]::FromMilliseconds(1100)
    $script:musicTimer.Add_Tick({ Update-MusicWidget })
    $script:musicTimer.Start()
}

# ---------------- dark button styles ----------------
function Get-ButtonStyle([string]$bg, [string]$hover, [string]$pressed, [string]$fg, [string]$border) {
    $xaml = @"
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
  <Setter Property="Foreground" Value="$fg"/>
  <Setter Property="FontFamily" Value="Segoe UI"/>
  <Setter Property="FontSize" Value="12"/>
  <Setter Property="Padding" Value="10,6"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="bd" CornerRadius="9" Background="$bg" BorderBrush="$border" BorderThickness="1" Padding="{TemplateBinding Padding}">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="$hover"/></Trigger>
          <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Background" Value="$pressed"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
"@
    $s = [System.Windows.Markup.XamlReader]::Parse($xaml)
    return $s
}
if (-not $script:btnStyle) {
    $script:btnStyle       = Get-ButtonStyle '#16FFFFFF' '#28FFFFFF' '#38FFFFFF' '#E8EEF8' '#26FFFFFF'
    $script:btnDangerStyle = Get-ButtonStyle '#1FF87171' '#33F87171' '#4DF87171' '#FCA5A5' '#4DF87171'
    $script:btnAccentStyle = Get-ButtonStyle '#2E5B8DEF' '#4A5B8DEF' '#665B8DEF' '#EAF2FF' '#4D5B8DEF'
}

# ---------------- apps manager window ----------------
function New-MgrRow($app, [int]$index, [int]$total) {
    $row = New-Object System.Windows.Controls.Border
    $row.CornerRadius = CR 10
    $row.Background = Br '#0EFFFFFF'
    $row.Padding = Th 10 6 10 6
    $row.Margin = Th 0 0 0 6

    $dp = New-Object System.Windows.Controls.DockPanel

    $img = New-Object System.Windows.Controls.Image
    $icon = Get-FileIcon $app.path 32
    if ($icon) { $img.Source = $icon }
    $img.Width = 26; $img.Height = 26
    $img.Margin = Th 0 0 10 0
    [System.Windows.Controls.DockPanel]::SetDock($img, 'Left')
    [void]$dp.Children.Add($img)

    $btns = New-Object System.Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'
    [System.Windows.Controls.DockPanel]::SetDock($btns, 'Right')
    [void]$dp.Children.Add($btns)

    $bUp = New-Object System.Windows.Controls.Button
    $bUp.Content = '▲'; $bUp.Style = $script:btnStyle; $bUp.Padding = Th 7 4 7 4; $bUp.Margin = Th 4 0 0 0
    $bUp.Tag = $index
    $bUp.ToolTip = 'Move up'
    $bUp.IsEnabled = ($index -gt 0)
    $bUp.Add_Click({ param($s, $e) Move-DockApp ([int]$s.Tag) -1 })
    [void]$btns.Children.Add($bUp)

    $bDn = New-Object System.Windows.Controls.Button
    $bDn.Content = '▼'; $bDn.Style = $script:btnStyle; $bDn.Padding = Th 7 4 7 4; $bDn.Margin = Th 4 0 0 0
    $bDn.Tag = $index
    $bDn.ToolTip = 'Move down'
    $bDn.IsEnabled = ($index -lt ($total - 1))
    $bDn.Add_Click({ param($s, $e) Move-DockApp ([int]$s.Tag) 1 })
    [void]$btns.Children.Add($bDn)

    $bDel = New-Object System.Windows.Controls.Button
    $bDel.Content = '✕ Remove'; $bDel.Style = $script:btnDangerStyle; $bDel.Margin = Th 8 0 0 0
    $bDel.Tag = $index
    $bDel.ToolTip = 'Remove from dock'
    $bDel.Add_Click({ param($s, $e) Remove-DockApp ([int]$s.Tag) })
    [void]$btns.Children.Add($bDel)

    $txts = New-Object System.Windows.Controls.StackPanel
    $n = Txt $app.name 12.5 '#E8EEF8' 'SemiBold'
    $n.HorizontalAlignment = 'Left'
    $pth = Txt $app.path 10 '#7C8CA3'
    $pth.HorizontalAlignment = 'Left'
    $pth.TextTrimming = 'CharacterEllipsis'
    $pth.MaxWidth = 330
    [void]$txts.Children.Add($n)
    [void]$txts.Children.Add($pth)
    [void]$dp.Children.Add($txts)

    $row.Child = $dp
    return $row
}

function Refresh-Manager {
    if (-not $script:mgr) { return }
    $panel = $script:mgr.list
    $panel.Children.Clear()
    $apps = @($script:cfg.dock.apps)
    if ($apps.Count -eq 0) {
        $empty = Txt 'No apps yet - add one below, or drop an .exe / .lnk here.' 12 '#7C8CA3'
        $empty.Margin = Th 4 10 0 10
        [void]$panel.Children.Add($empty)
    }
    for ($i = 0; $i -lt $apps.Count; $i++) {
        [void]$panel.Children.Add((New-MgrRow $apps[$i] $i $apps.Count))
    }
    if ($script:mgr.count) { $script:mgr.count.Text = ("{0} apps in the dock" -f $apps.Count) }
}

function Show-AppsManager {
    if ($script:mgr -and $script:mgr.win -and $script:mgr.win.IsVisible) {
        $script:mgr.win.Activate()
        Refresh-Manager
        return
    }
    $w = New-Object System.Windows.Window
    $w.WindowStyle = 'None'
    $w.AllowsTransparency = $true
    $w.Background = $null
    $w.ShowInTaskbar = $false
    $w.ResizeMode = 'NoResize'
    $w.WindowStartupLocation = 'CenterScreen'
    $w.Topmost = $true
    $w.Width = 620
    $w.Height = 620

    $root = New-Object System.Windows.Controls.Border
    $root.CornerRadius = CR 18
    $root.BorderThickness = Th 1 1 1 1
    $root.BorderBrush = Br '#26FFFFFF'
    $root.Padding = Th 16 14 16 14
    $lg = New-Object System.Windows.Media.LinearGradientBrush
    $lg.StartPoint = New-Object System.Windows.Point(0, 0)
    $lg.EndPoint = New-Object System.Windows.Point(0, 1)
    $lg.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString('#FA0A0E16'), 0)))
    $lg.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString('#FA05070C'), 1)))
    $root.Background = $lg
    $shd = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shd.BlurRadius = 28; $shd.ShadowDepth = 0; $shd.Opacity = 0.65; $shd.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#000000')
    $root.Effect = $shd

    $stack = New-Object System.Windows.Controls.DockPanel
    $root.Child = $stack

    # header
    $hdr = New-Object System.Windows.Controls.DockPanel
    $hdr.Margin = Th 0 0 0 12
    [System.Windows.Controls.DockPanel]::SetDock($hdr, 'Top')
    $close = New-Object System.Windows.Controls.Button
    $close.Content = '✕'
    $close.Style = $script:btnStyle
    $close.Padding = Th 9 4 9 4
    [System.Windows.Controls.DockPanel]::SetDock($close, 'Right')
    $close.Add_Click({ param($s, $e) $script:mgr.win.Hide() })
    [void]$hdr.Children.Add($close)
    $ttl = New-Object System.Windows.Controls.StackPanel
    $t1 = Txt 'Dock apps' 17 '#F1F6FC' 'SemiBold'
    $t1.HorizontalAlignment = 'Left'
    $cnt = Txt '' 11 '#7C8CA3'
    $cnt.HorizontalAlignment = 'Left'
    [void]$ttl.Children.Add($t1)
    [void]$ttl.Children.Add($cnt)
    [void]$hdr.Children.Add($ttl)
    $hdr.Add_MouseLeftButtonDown({ param($s, $e) try { $script:mgr.win.DragMove() } catch { } })
    [void]$stack.Children.Add($hdr)

    # footer buttons
    $footer = New-Object System.Windows.Controls.StackPanel
    $footer.Orientation = 'Horizontal'
    $footer.Margin = Th 0 12 0 0
    [System.Windows.Controls.DockPanel]::SetDock($footer, 'Bottom')
    $bAdd = New-Object System.Windows.Controls.Button
    $bAdd.Content = '＋ Add app…'; $bAdd.Style = $script:btnAccentStyle
    $bAdd.Add_Click({ try { Add-AppToDock } catch { Write-WidgetError $_ 'add app from file' } })
    [void]$footer.Children.Add($bAdd)
    $bMenu = New-Object System.Windows.Controls.Button
    $bMenu.Content = '≡ From Start Menu'; $bMenu.Style = $script:btnStyle; $bMenu.Margin = Th 8 0 0 0
    $bMenu.Add_Click({ try { Show-StartMenuPicker } catch { Write-WidgetError $_ 'start menu picker' } })
    [void]$footer.Children.Add($bMenu)
    $bRst = New-Object System.Windows.Controls.Button
    $bRst.Content = '↺ Defaults'; $bRst.Style = $script:btnStyle; $bRst.Margin = Th 8 0 0 0
    $bRst.ToolTip = 'Restore the suggested app list'
    $bRst.Add_Click({ Restore-DefaultDock })
    [void]$footer.Children.Add($bRst)
    $hintTxt = Txt 'tip: you can drag files onto the dock or this window' 10.5 '#7C8CA3'
    $hintTxt.Margin = Th 12 0 0 0
    [void]$footer.Children.Add($hintTxt)
    [void]$stack.Children.Add($footer)

    # list
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'
    $sv.HorizontalScrollBarVisibility = 'Disabled'
    $listPanel = New-Object System.Windows.Controls.StackPanel
    $sv.Content = $listPanel
    [void]$stack.Children.Add($sv)

    $w.Content = $root
    $root.AllowDrop = $true
    $root.Add_DragOver({
        param($s, $e)
        try {
            if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop) -or $e.Data.GetDataPresent('FileNameW')) { $e.Effects = 'Copy' }
        } catch { }
    })
    $root.Add_Drop({
        param($s, $e)
        try {
            $files = @(Get-DroppedPaths $e)
            if ($files.Count -gt 0) { [void](Add-PathsToDock $files) }
        } catch { Write-WidgetError $_ 'manager drop' }
    })

    $script:mgr = @{ win = $w; list = $listPanel; count = $cnt }
    Refresh-Manager
    $w.Show()
    $w.Activate()
}

# ---------------- start menu picker ----------------
function Get-StartMenuApps {
    $roots = @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs")
    $sh = New-Object -ComObject WScript.Shell
    $seen = @{}
    $list = New-Object System.Collections.ArrayList
    $skip = 'uninstall|help|manual|documentation|release notes|faq|what is new|revision history|readme|install additional|license|copyright|safe mode|website|support|console rar'
    foreach ($r in $roots) {
        foreach ($f in (Get-ChildItem -Path $r -Filter *.lnk -Recurse -ErrorAction SilentlyContinue)) {
            try {
                $nm = $f.BaseName
                if ($nm -match $skip) { continue }
                $sc = $sh.CreateShortcut($f.FullName)
                $tp = $sc.TargetPath
                if (-not $tp -or -not (Test-Path -LiteralPath $tp)) { continue }
                if ($tp -notmatch '\.(exe|bat|cmd|com)$') { continue }
                $key = ($tp + '|' + $sc.Arguments).ToLower()
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                [void]$list.Add([pscustomobject]@{ name = $nm; path = $tp; args = [string]$sc.Arguments })
            } catch { }
        }
    }
    # packaged (Store / UWP) apps exposed by the shell
    try {
        $names = @{}
        foreach ($a in $list) { $names[$a.name.ToLower()] = $true }
        $sh2 = New-Object -ComObject Shell.Application
        foreach ($it in @($sh2.NameSpace('shell:AppsFolder').Items())) {
            $nm = $null; $pp = $null
            try { $nm = [string]$it.Name; $pp = [string]$it.Path } catch { continue }
            if (-not $nm -or -not $pp) { continue }
            if ($nm -match $skip) { continue }
            $isAumid = ($pp -match '!' -and $pp -notmatch '[\\/]')
            $isExe = ($pp -match '\.(exe|bat|cmd|com)$' -and (Test-Path -LiteralPath $pp -ErrorAction SilentlyContinue))
            if (-not ($isAumid -or $isExe)) { continue }
            $key = $nm.ToLower()
            if ($names.ContainsKey($key)) { continue }
            $names[$key] = $true
            [void]$list.Add([pscustomobject]@{ name = $nm; path = $pp; args = '' })
        }
    } catch { }
    return ($list | Sort-Object name)
}

function Render-StartMenuPicker($ctx) {
    $listPanel = $ctx.List
    $all = $ctx.All
    $q = [string]$ctx.Query
    $listPanel.Children.Clear()
    $n = 0
    foreach ($a in @($all)) {
        try {
            if ($q -and ($a.name -notmatch [regex]::Escape($q))) { continue }
            $n++
            $row = New-Object System.Windows.Controls.Border
            $row.CornerRadius = CR 10
            $row.Background = Br '#0EFFFFFF'
            $row.Padding = Th 10 6 10 6
            $row.Margin = Th 0 0 0 6
            $dp = New-Object System.Windows.Controls.DockPanel
            $img = New-Object System.Windows.Controls.Image
            $ic = Get-FileIcon $a.path 32
            if ($ic) { $img.Source = $ic }
            $img.Width = 24; $img.Height = 24; $img.Margin = Th 0 0 10 0
            [System.Windows.Controls.DockPanel]::SetDock($img, 'Left')
            [void]$dp.Children.Add($img)
            $b = New-Object System.Windows.Controls.Button
            $b.Content = 'Add'; $b.Style = $script:btnStyle
            $b.Tag = $a
            [System.Windows.Controls.DockPanel]::SetDock($b, 'Right')
            $b.Add_Click({
                param($s, $e)
                try {
                    $app = $s.Tag
                    $apps = New-Object System.Collections.ArrayList
                    foreach ($x in @($script:cfg.dock.apps)) { [void]$apps.Add($x) }
                    $dup = $false
                    foreach ($x in $apps) { if ($x.path -eq $app.path -and $x.args -eq $app.args) { $dup = $true; break } }
                    if (-not $dup) { [void]$apps.Add([pscustomobject]@{ name = $app.name; path = $app.path; args = $app.args }) }
                    $script:cfg.dock.apps = $apps
                    Update-DockWindows
                    $s.Content = 'Added'; $s.Style = $script:btnAccentStyle
                } catch {
                    Write-WidgetError $_ 'start menu picker: add'
                }
            })
            [void]$dp.Children.Add($b)
            $tx = New-Object System.Windows.Controls.StackPanel
            $nm = Txt $a.name 12.5 '#E8EEF8'
            $nm.HorizontalAlignment = 'Left'
            $pt = Txt $a.path 10 '#7C8CA3'
            $pt.HorizontalAlignment = 'Left'
            $pt.TextTrimming = 'CharacterEllipsis'
            $pt.MaxWidth = 300
            [void]$tx.Children.Add($nm)
            [void]$tx.Children.Add($pt)
            [void]$dp.Children.Add($tx)
            $row.Child = $dp
            [void]$listPanel.Children.Add($row)
        } catch {
            Write-WidgetError $_ "picker row: $($a.name)"
        }
    }
    if ($n -eq 0) {
        $empty = Txt 'no matches' 12 '#7C8CA3'
        [void]$listPanel.Children.Add($empty)
    }
}

function Show-StartMenuPicker {
    $w = New-Object System.Windows.Window
    $w.WindowStyle = 'None'
    $w.AllowsTransparency = $true
    $w.Background = $null
    $w.ShowInTaskbar = $false
    $w.ResizeMode = 'NoResize'
    $w.WindowStartupLocation = 'CenterScreen'
    $w.Topmost = $true
    $w.Width = 560
    $w.Height = 620

    $root = New-Object System.Windows.Controls.Border
    $root.CornerRadius = CR 18
    $root.BorderThickness = Th 1 1 1 1
    $root.BorderBrush = Br '#26FFFFFF'
    $root.Padding = Th 16 14 16 14
    $lg = New-Object System.Windows.Media.LinearGradientBrush
    $lg.StartPoint = New-Object System.Windows.Point(0, 0)
    $lg.EndPoint = New-Object System.Windows.Point(0, 1)
    $lg.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString('#FA0A0E16'), 0)))
    $lg.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString('#FA05070C'), 1)))
    $root.Background = $lg
    $shd = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shd.BlurRadius = 28; $shd.ShadowDepth = 0; $shd.Opacity = 0.65; $shd.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#000000')
    $root.Effect = $shd
    $stack = New-Object System.Windows.Controls.DockPanel
    $root.Child = $stack

    $hdr = New-Object System.Windows.Controls.DockPanel
    $hdr.Margin = Th 0 0 0 12
    [System.Windows.Controls.DockPanel]::SetDock($hdr, 'Top')
    $close = New-Object System.Windows.Controls.Button
    $close.Content = '✕'; $close.Style = $script:btnStyle; $close.Padding = Th 9 4 9 4
    [System.Windows.Controls.DockPanel]::SetDock($close, 'Right')
    $close.Add_Click({ param($s, $e) $s.Tag.Hide() })
    $close.Tag = $w
    [void]$hdr.Children.Add($close)
    $t1 = Txt 'Add from Start Menu' 16 '#F1F6FC' 'SemiBold'
    $t1.HorizontalAlignment = 'Left'
    [void]$hdr.Children.Add($t1)
    $hdr.Tag = $w
    $hdr.Add_MouseLeftButtonDown({ param($s, $e) try { $s.Tag.DragMove() } catch { } })
    [void]$stack.Children.Add($hdr)

    $search = New-Object System.Windows.Controls.TextBox
    $search.Height = 34
    $search.FontSize = 13
    $search.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
    $search.Background = Br '#14FFFFFF'
    $search.Foreground = Br '#E8EEF8'
    $search.CaretBrush = Br '#8AB4F8'
    $search.BorderBrush = Br '#26FFFFFF'
    $search.Padding = Th 10 6 10 6
    $search.Margin = Th 0 0 0 10
    $search.VerticalContentAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($search, 'Top')
    [void]$stack.Children.Add($search)

    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'
    $listPanel = New-Object System.Windows.Controls.StackPanel
    $sv.Content = $listPanel
    [void]$stack.Children.Add($sv)
    $w.Content = $root

    $all = @(Get-StartMenuApps)
    $ctx = [pscustomobject]@{ List = $listPanel; All = $all; Query = '' }
    $search.Tag = $ctx
    $search.Add_TextChanged({
        param($s, $e)
        try {
            $c = $s.Tag
            $c.Query = [string]$s.Text
            Render-StartMenuPicker $c
        } catch { Write-WidgetError $_ 'start menu picker: search' }
    })
    Render-StartMenuPicker $ctx
    $w.Show()
    $w.Activate()
    $search.Focus() | Out-Null
}

if ($cfg.dock.enabled -and -not $NoDock) {
    $dockWin = New-Object System.Windows.Window
    $dockWin.Title = 'UD Dock'
    $dockWin.WindowStyle = 'None'
    $dockWin.AllowsTransparency = $true
    $dockWin.Background = $null
    $dockWin.ShowInTaskbar = $false
    $dockWin.ResizeMode = 'NoResize'
    $dockWin.SizeToContent = 'WidthAndHeight'
    $dockWin.WindowStartupLocation = 'Manual'
    $dockWin.Topmost = [bool]$cfg.dock.topmost

    $dockRoot = New-Object System.Windows.Controls.Border
    $dockRoot.CornerRadius = CR 20
    $dockRoot.BorderThickness = Th 1 1 1 1
    $dockRoot.BorderBrush = Br '#26FFFFFF'
    $dockRoot.Padding = Th 12 18 12 10
    $dockRoot.Background = New-ThemeGlass 0 0 0 1
    $sh2 = New-Object System.Windows.Media.Effects.DropShadowEffect
    $sh2.BlurRadius = 26; $sh2.ShadowDepth = 0; $sh2.Opacity = 0.6; $sh2.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#000000')
    $dockRoot.Effect = $sh2

    $dockPanel = New-Object System.Windows.Controls.StackPanel
    $dockPanel.Orientation = 'Horizontal'
    $dockRoot.Child = $dockPanel

    $dockMenu = New-Object System.Windows.Controls.ContextMenu
    $dockMenu.Background = Br '#12161F'
    $dockMenu.Foreground = Br '#E8EEF8'
    $dockMenu.BorderBrush = Br '#2A3140'
    $mWM = New-Object System.Windows.Controls.MenuItem; $mWM.Header = 'Manage widgets…'; $mWM.Add_Click({ try { Show-WidgetManager } catch { Write-WidgetError $_ 'show widget manager' } }); [void]$dockMenu.Items.Add($mWM)
    [void]$dockMenu.Items.Add((New-Object System.Windows.Controls.Separator))
    $mMgr = New-Object System.Windows.Controls.MenuItem; $mMgr.Header = 'Manage apps (add / remove / reorder)…'; $mMgr.Add_Click({ try { Show-AppsManager } catch { Write-WidgetError $_ 'show apps manager' } }); [void]$dockMenu.Items.Add($mMgr)
    $mAdd = New-Object System.Windows.Controls.MenuItem; $mAdd.Header = 'Add app from file…'; $mAdd.Add_Click({ try { Add-AppToDock } catch { Write-WidgetError $_ 'add app from file' } }); [void]$dockMenu.Items.Add($mAdd)
    [void]$dockMenu.Items.Add((New-Object System.Windows.Controls.Separator))
    $mOnTop = New-Object System.Windows.Controls.MenuItem; $mOnTop.Header = 'Always on top'; $mOnTop.IsCheckable = $true; $mOnTop.IsChecked = [bool]$cfg.dock.topmost
    $mOnTop.Add_Click({ param($s, $e) $script:cfg.dock.topmost = $s.IsChecked; $script:dockWin.Topmost = $s.IsChecked; Save-Config })
    [void]$dockMenu.Items.Add($mOnTop)
    $mAuto = New-Object System.Windows.Controls.MenuItem; $mAuto.Header = 'Auto-hide (show when mouse reaches the bottom)'; $mAuto.IsCheckable = $true; $mAuto.IsChecked = [bool]$cfg.dock.autohide
    $mAuto.Add_Click({ param($s, $e) Toggle-DockAutoHide $s.IsChecked })
    [void]$dockMenu.Items.Add($mAuto)
    $mFx = New-Object System.Windows.Controls.MenuItem; $mFx.Header = 'Hover animations'; $mFx.IsCheckable = $true; $mFx.IsChecked = [bool]$script:dockFx
    $mFx.Add_Click({
        param($s, $e)
        $script:dockFx = [bool]$s.IsChecked
        Set-Cfg $script:cfg.dock 'effects' $script:dockFx
        Save-Config
        if (-not $script:dockFx) {
            foreach ($en in @($script:dockTiles)) {
                try {
                    $tg = $en.tile.RenderTransform
                    $tg.Children[0].BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $null)
                    $tg.Children[0].BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $null)
                    $tg.Children[1].BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
                    $en.tile.Effect = $null
                } catch { }
            }
        }
    })
    [void]$dockMenu.Items.Add($mFx)
    $mHide = New-Object System.Windows.Controls.MenuItem; $mHide.Header = 'Hide dock'; $mHide.Add_Click({ param($s, $e) try { Set-WidgetVisible 'dock' $false } catch { } }); [void]$dockMenu.Items.Add($mHide)
    $dockRoot.ContextMenu = $dockMenu

    # drop app files straight onto the dock
    $dockRoot.AllowDrop = $true
    $dockRoot.Add_DragOver({
        param($s, $e)
        try {
            if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop) -or $e.Data.GetDataPresent('FileNameW')) { $e.Effects = 'Copy' }
        } catch { }
    })
    $dockRoot.Add_Drop({
        param($s, $e)
        try {
            $files = @(Get-DroppedPaths $e)
            if ($files.Count -gt 0) { [void](Add-PathsToDock $files) }
        } catch { Write-WidgetError $_ 'dock drop' }
    })

    $dockWin.Content = $dockRoot
    Build-DockTiles
}

# ---------------- Clock window ----------------
$clockWin = $null
$script:clockCtl = @{}
$script:clockTimer = $null
$script:clockCulture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')

function Update-ClockWidget {
    try {
        if (-not $script:clockWin -or -not $script:clockCtl.time) { return }
        $now = Get-Date
        $h24 = [bool](Get-Cfg $script:cfg.clock 'h24')
        $showSec = [bool](Get-Cfg $script:cfg.clock 'seconds')
        $t = if ($h24) { $now.ToString('HH:mm', $script:clockCulture) } else { $now.ToString('h:mm', $script:clockCulture) }
        if ($script:clockCtl.time.Text -ne $t) { $script:clockCtl.time.Text = $t }
        $secVis = if ($showSec) { 'Visible' } else { 'Collapsed' }
        if ([string]$script:clockCtl.sec.Visibility -ne $secVis) { $script:clockCtl.sec.Visibility = $secVis }
        if ($showSec) { $script:clockCtl.sec.Text = $now.ToString('ss', $script:clockCulture) }
        $apVis = if ($h24) { 'Collapsed' } else { 'Visible' }
        if ([string]$script:clockCtl.ampm.Visibility -ne $apVis) { $script:clockCtl.ampm.Visibility = $apVis }
        $ap = $now.ToString('tt', $script:clockCulture)
        if (-not $h24 -and $script:clockCtl.ampm.Text -ne $ap) { $script:clockCtl.ampm.Text = $ap }
        $d = $now.ToString('dddd, d MMMM yyyy', $script:clockCulture)
        if ($script:clockCtl.date.Text -ne $d) { $script:clockCtl.date.Text = $d }
        $tz = 'UTC' + $now.ToString('zzz', $script:clockCulture)
        if ($script:clockCtl.tz.Text -ne $tz) { $script:clockCtl.tz.Text = $tz }
        $frac = [double]$now.Second + ($now.Millisecond / 1000.0)
        $script:clockCtl.fill.RenderTransform.ScaleX = [math]::Max(0.0, [math]::Min(1.0, $frac / 60.0))
    } catch { }
}

# ---------------- Weather widget with Hijri date and prayer times ----------------
$script:weatherWin = $null; $script:weatherCtl = @{}
$script:weatherTimer = $null

function Update-HijriDate {
    try {
        if (-not $script:weatherCtl.hijri) { return }
        $now = Get-Date
        $c = [System.Globalization.CultureInfo]::GetCultureInfo('ar-SA-u-ca-islamic')
        $hijri = $now.ToString('dddd, dd MMMM yyyy', $c)
        if ($script:weatherCtl.hijri.Text -ne $hijri) { $script:weatherCtl.hijri.Text = $hijri }
    } catch { }
}

function Get-LocalPrayerTimes([datetime]$curDate, [double]$lat, [double]$lon, [double]$tz) {
    try {
        $y = $curDate.Year; $m = $curDate.Month; $dVal = $curDate.Day
        if ($m -le 2) { $y -= 1; $m += 12 }
        $A = [math]::Floor($y / 100)
        $B = 2 - $A + [math]::Floor($A / 4)
        $jd = [math]::Floor(365.25 * ($y + 4716)) + [math]::Floor(30.6001 * ($m + 1)) + $dVal + $B - 1524.5
        $diffDays = $jd - 2451545.0

        $g = (357.529 + 0.98560028 * $diffDays) % 360.0
        $q = (280.459 + 0.98564736 * $diffDays) % 360.0
        $L = ($q + 1.915 * [math]::Sin($g * [math]::PI / 180.0) + 0.020 * [math]::Sin(2.0 * $g * [math]::PI / 180.0)) % 360.0
        $e = 23.439 - 0.00000036 * $diffDays
        $RA = [math]::Atan2([math]::Cos($e * [math]::PI / 180.0) * [math]::Sin($L * [math]::PI / 180.0), [math]::Cos($L * [math]::PI / 180.0)) * 180.0 / [math]::PI
        $RA = ($RA / 15.0 + 24.0) % 24.0
        $decl = [math]::Asin([math]::Sin($e * [math]::PI / 180.0) * [math]::Sin($L * [math]::PI / 180.0))
        $EqT = ($q / 15.0) - $RA

        $noon = (12.0 + $tz - ($lon / 15.0) - $EqT + 24.0) % 24.0
        
        function HA([double]$angle, [double]$dec, [double]$lt, [bool]$dep = $true) {
            $rad = [math]::PI / 180.0
            $sinAngle = if ($dep) { [math]::Sin(-$angle * $rad) } else { [math]::Sin($angle * $rad) }
            $cosH = ($sinAngle - [math]::Sin($lt * $rad) * [math]::Sin($dec)) / ([math]::Cos($lt * $rad) * [math]::Cos($dec))
            if ($cosH -gt 1.0 -or $cosH -lt -1.0) { return 0 }
            return [math]::Acos($cosH) * 180.0 / [math]::PI / 15.0
        }

        $fajrHA = HA 19.5 $decl $lat $true
        $sunHA  = HA 0.833 $decl $lat $true
        $ishaHA = HA 17.5 $decl $lat $true

        $rad = [math]::PI / 180.0
        $asrAlt = [math]::Atan(1.0 / (1.0 + [math]::Tan([math]::Abs($lat * $rad - $decl)))) * 180.0 / [math]::PI
        $asrHA  = HA $asrAlt $decl $lat $false
        function TT([double]$h) {
            $h = ($h + 24.0) % 24.0
            $hh = [math]::Floor($h)
            $mm = [math]::Round(($h - $hh) * 60)
            if ($mm -ge 60) { $hh += 1; $mm -= 60 }
            return ("{0:D2}:{1:D2}" -f [int]$hh, [int]$mm)
        }

        return @{
            Fajr    = TT ($noon - $fajrHA)
            Sunrise = TT ($noon - $sunHA)
            Dhuhr   = TT $noon
            Asr     = TT ($noon + $asrHA)
            Maghrib = TT ($noon + $sunHA)
            Isha    = TT ($noon + $ishaHA)
        }
    } catch { return $null }
}

function Update-PrayerTimes {
    try {
        if (-not $script:weatherCtl.prayerTimes) { return }
        $cfg = Get-WidgetSection 'weather'
        if (-not $cfg -or -not [bool](Get-Cfg $cfg 'showPrayer')) {
            $script:weatherCtl.prayerTimes.Visibility = 'Collapsed'
            return
        }
        $script:weatherCtl.prayerTimes.Visibility = 'Visible'
        $tz = [System.TimeZoneInfo]::Local.GetUtcOffset([datetime]::Now).TotalHours
        $lat = if ($cfg.lat) { [double]$cfg.lat } else { 30.0444 }
        $lon = if ($cfg.lon) { [double]$cfg.lon } else { 31.2357 }
        $t = Get-LocalPrayerTimes (Get-Date) $lat $lon $tz
        if ($t) {
            if ($script:weatherCtl.fajr) { $script:weatherCtl.fajr.Text = $t.Fajr }
            if ($script:weatherCtl.dhuhr) { $script:weatherCtl.dhuhr.Text = $t.Dhuhr }
            if ($script:weatherCtl.asr) { $script:weatherCtl.asr.Text = $t.Asr }
            if ($script:weatherCtl.maghrib) { $script:weatherCtl.maghrib.Text = $t.Maghrib }
            if ($script:weatherCtl.isha) { $script:weatherCtl.isha.Text = $t.Isha }
        }
    } catch { }
}

function Apply-WeatherData($resp) {
    try {
        if (-not $resp -or -not $script:weatherCtl.temp) { return }
        $cur = $resp.current
        $temp = [math]::Round($cur.temperature_2m)
        $humid = $cur.relative_humidity_2m
        $code = $cur.weather_code
        $max = [math]::Round($resp.daily.temperature_2m_max[0])
        $min = [math]::Round($resp.daily.temperature_2m_min[0])
        $wDesc = Get-WeatherDesc $code

        if ($script:weatherCtl.temp) { $script:weatherCtl.temp.Text = "$tempÂ°" }
        if ($script:weatherCtl.humid) { $script:weatherCtl.humid.Text = "$humid% humidity" }
        if ($script:weatherCtl.desc) { $script:weatherCtl.desc.Text = $wDesc }
        if ($script:weatherCtl.range) { $script:weatherCtl.range.Text = "$minÂ°â€¦$maxÂ°" }
    } catch { }
}

function Update-WeatherWidget {
    try {
        if (-not $script:weatherWin -or -not $script:weatherCtl.temp) { return }
        $cfg = Get-WidgetSection 'weather'
        $lat = if ($cfg.lat) { [double]$cfg.lat } else { 30.0444 }
        $lon = if ($cfg.lon) { [double]$cfg.lon } else { 31.2357 }
        $url = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto"
        if ($Preview) {
            try {
                $resp = Invoke-RestMethod -Uri $url -TimeoutSec 4 -UseBasicParsing
                Apply-WeatherData $resp
            } catch { }
            return
        }
        [UDWin]::FetchWeatherAsync($url)
    } catch { }
}

function Update-AllWeatherData {
    try {
        Update-HijriDate
        Update-PrayerTimes
        Update-WeatherWidget
    } catch { }
}


function Get-WeatherDesc($code) {
    $map = @{
        0 = 'Clear sky'
        1 = 'Mainly clear'
        2 = 'Partly cloudy'
        3 = 'Overcast'
        45 = 'Fog'
        48 = 'Depositing rime fog'
        51 = 'Light drizzle'
        53 = 'Moderate drizzle'
        55 = 'Dense drizzle'
        61 = 'Slight rain'
        63 = 'Moderate rain'
        65 = 'Heavy rain'
        71 = 'Slight snow'
        73 = 'Moderate snow'
        75 = 'Heavy snow'
        77 = 'Snow grains'
        80 = 'Slight rain showers'
        81 = 'Moderate rain showers'
        82 = 'Violent rain showers'
        85 = 'Slight snow showers'
        86 = 'Heavy snow showers'
        95 = 'Thunderstorm'
        96 = 'Thunderstorm with hail'
        99 = 'Thunderstorm with heavy hail'
    }
    if ($map.ContainsKey($code)) { return $map[$code] } else { return 'Unknown' }
}

if ($cfg.clock -and [bool](Get-Cfg $cfg.clock 'enabled') -and -not $NoClock) {
    $clockW = 300.0
    $clockWin = New-Object System.Windows.Window
    $clockWin.Title = 'UD Clock'
    $clockWin.WindowStyle = 'None'
    $clockWin.AllowsTransparency = $true
    $clockWin.Background = $null
    $clockWin.ShowInTaskbar = $false
    $clockWin.ResizeMode = 'NoResize'
    $clockWin.SizeToContent = 'WidthAndHeight'
    $clockWin.WindowStartupLocation = 'Manual'
    $clockWin.Topmost = [bool](Get-Cfg $cfg.clock 'topmost')

    $cRoot = New-Object System.Windows.Controls.Border
    $cRoot.CornerRadius = CR 16
    $cRoot.BorderThickness = Th 1 1 1 1
    $cRoot.BorderBrush = Br '#22FFFFFF'
    $cRoot.Width = $clockW
    $cRoot.Background = New-ThemeGlass 0.1 0 0.9 1
    $csh = New-Object System.Windows.Media.Effects.DropShadowEffect
    $csh.BlurRadius = 26; $csh.ShadowDepth = 0; $csh.Opacity = 0.6; $csh.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#000000')
    $cRoot.Effect = $csh

    $cOuter = New-Object System.Windows.Controls.Grid
    $cr0 = New-Object System.Windows.Controls.RowDefinition
    $cr0.Height = New-Object System.Windows.GridLength(2.5)
    $cr1 = New-Object System.Windows.Controls.RowDefinition
    $cr1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    [void]$cOuter.RowDefinitions.Add($cr0)
    [void]$cOuter.RowDefinitions.Add($cr1)

    $cAccent = New-Object System.Windows.Controls.Border
    $cAccent.Height = 2.5
    $cAccent.CornerRadius = New-Object System.Windows.CornerRadius(15, 15, 0, 0)
    $cAccent.Background = New-ThemeAccent3
    [System.Windows.Controls.Grid]::SetRow($cAccent, 0)
    [void]$cOuter.Children.Add($cAccent)

    $cBody = New-Object System.Windows.Controls.StackPanel
    $cBody.Margin = Th 16 11 16 13
    [System.Windows.Controls.Grid]::SetRow($cBody, 1)
    [void]$cOuter.Children.Add($cBody)

    # header: LOCAL TIME + UTC offset
    $cHead = New-Object System.Windows.Controls.Grid
    $chc1 = New-Object System.Windows.Controls.ColumnDefinition
    $chc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $chc2 = New-Object System.Windows.Controls.ColumnDefinition
    $chc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
    [void]$cHead.ColumnDefinitions.Add($chc1)
    [void]$cHead.ColumnDefinitions.Add($chc2)
    $cLbl = New-Object System.Windows.Controls.StackPanel
    $cLbl.Orientation = 'Horizontal'
    $cDot = New-Object System.Windows.Shapes.Ellipse
    $cDot.Width = 6; $cDot.Height = 6
    $cDot.Fill = Br '#4CC2FF'
    $cDot.VerticalAlignment = 'Center'
    $cDot.Margin = Th 0 0 7 0
    [void]$cLbl.Children.Add($cDot)
    [void]$cLbl.Children.Add((Txt 'LOCAL TIME' 10 '#8494AB' 'SemiBold'))
    [void]$cHead.Children.Add($cLbl)
    $cTz = Txt '' 10 '#6F7F97'
    $cTz.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($cTz, 1)
    [void]$cHead.Children.Add($cTz)
    [void]$cBody.Children.Add($cHead)

    # big time + seconds + am/pm
    $cRow = New-Object System.Windows.Controls.StackPanel
    $cRow.Orientation = 'Horizontal'
    $cTime = Txt '00:00' 44 '#F2F6FF' 'Bold'
    $cTime.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Variable Display, Segoe UI')
    $cTime.VerticalAlignment = 'Bottom'
    try { $cTime.Typography.NumeralAlignment = [System.Windows.Documents.FontNumeralAlignment]::Tabular } catch { }
    [void]$cRow.Children.Add($cTime)
    $cSec = Txt '00' 15 '#4CC2FF' 'SemiBold'
    $cSec.VerticalAlignment = 'Bottom'
    $cSec.Margin = Th 7 0 0 9
    [void]$cRow.Children.Add($cSec)
    $cAmpm = Txt 'PM' 11 '#8494AB' 'SemiBold'
    $cAmpm.VerticalAlignment = 'Bottom'
    $cAmpm.Margin = Th 5 0 0 11
    [void]$cRow.Children.Add($cAmpm)
    [void]$cBody.Children.Add($cRow)

    $cDate = Txt '' 12 '#A9B7CC'
    $cDate.Margin = Th 0 1 0 0
    [void]$cBody.Children.Add($cDate)

    # seconds progress line
    $cTrack = New-Object System.Windows.Controls.Grid
    $cTrack.Height = 3
    $cTrack.Margin = Th 0 11 0 0
    $cTrackBg = New-Object System.Windows.Controls.Border
    $cTrackBg.CornerRadius = CR 1.5
    $cTrackBg.Background = Br '#14FFFFFF'
    [void]$cTrack.Children.Add($cTrackBg)
    $cFill = New-Object System.Windows.Controls.Border
    $cFill.CornerRadius = CR 1.5
    $cFill.Background = New-ThemeAccent2
    $cFill.RenderTransformOrigin = New-Object System.Windows.Point(0, 0.5)
    $cFill.RenderTransform = New-Object System.Windows.Media.ScaleTransform(0, 1)
    [void]$cTrack.Children.Add($cFill)
    [void]$cBody.Children.Add($cTrack)

    $cRoot.Child = $cOuter
    $clockWin.Content = $cRoot

    # right-click menu
    $cMenu = New-Object System.Windows.Controls.ContextMenu
    $cMenu.Background = Br '#12161F'
    $cMenu.Foreground = Br '#E8EEF8'
    $cMenu.BorderBrush = Br '#2A3140'

    $mSec = New-Object System.Windows.Controls.MenuItem
    $mSec.Header = 'Show seconds'
    $mSec.IsCheckable = $true
    $mSec.IsChecked = [bool](Get-Cfg $cfg.clock 'seconds')
    $mSec.Add_Click({
        param($s, $e)
        try { Set-Cfg $script:cfg.clock 'seconds' ([bool]$s.IsChecked); Save-Config; Update-ClockWidget } catch { }
    })
    [void]$cMenu.Items.Add($mSec)

    $m24 = New-Object System.Windows.Controls.MenuItem
    $m24.Header = '24-hour clock'
    $m24.IsCheckable = $true
    $m24.IsChecked = [bool](Get-Cfg $cfg.clock 'h24')
    $m24.Add_Click({
        param($s, $e)
        try { Set-Cfg $script:cfg.clock 'h24' ([bool]$s.IsChecked); Save-Config; Update-ClockWidget } catch { }
    })
    [void]$cMenu.Items.Add($m24)

    $mCt = New-Object System.Windows.Controls.MenuItem
    $mCt.Header = 'Always on top'
    $mCt.IsCheckable = $true
    $mCt.IsChecked = [bool](Get-Cfg $cfg.clock 'topmost')
    $mCt.Add_Click({
        param($s, $e)
        try {
            Set-Cfg $script:cfg.clock 'topmost' ([bool]$s.IsChecked)
            $script:clockWin.Topmost = [bool]$s.IsChecked
            Save-Config
        } catch { }
    })
    [void]$cMenu.Items.Add($mCt)
    Add-WidgetMenuItems $cMenu 'clock'

    [void]$cMenu.Items.Add((New-Object System.Windows.Controls.Separator))

    $mCr = New-Object System.Windows.Controls.MenuItem
    $mCr.Header = 'Reset position'
    $mCr.Add_Click({ try { Reset-ClockPosition } catch { } })
    [void]$cMenu.Items.Add($mCr)

    $mCh = New-Object System.Windows.Controls.MenuItem
    $mCh.Header = 'Hide clock'
    $mCh.Add_Click({ try { Set-WidgetVisible 'clock' $false } catch { } })
    [void]$cMenu.Items.Add($mCh)

    $cRoot.ContextMenu = $cMenu

    $script:clockCtl = @{
        time = $cTime
        sec  = $cSec
        ampm = $cAmpm
        date = $cDate
        tz   = $cTz
        fill = $cFill
    }

    $script:clockTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:clockTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:clockTimer.Add_Tick({ try { Update-ClockWidget } catch { } })
    Update-ClockWidget
}

# ---------------- shared card chrome for the optional widgets ----------------
function New-CardTitle([string]$text, [string]$dotColor) {
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 6; $dot.Height = 6
    $dot.Fill = Br $dotColor
    $dot.VerticalAlignment = 'Center'
    $dot.Margin = Th 0 0 7 0
    [void]$sp.Children.Add($dot)
    [void]$sp.Children.Add((Txt $text 10 '#8494AB' 'SemiBold'))
    return $sp
}

function New-GlassCard([double]$width, [string]$accent1, [string]$accent2) {
    $w = New-Object System.Windows.Window
    $w.WindowStyle = 'None'
    $w.AllowsTransparency = $true
    $w.Background = $null
    $w.ShowInTaskbar = $false
    $w.ResizeMode = 'NoResize'
    $w.SizeToContent = 'WidthAndHeight'
    $w.WindowStartupLocation = 'Manual'

    $root = New-Object System.Windows.Controls.Border
    $root.CornerRadius = CR 16
    $root.BorderThickness = Th 1 1 1 1
    $root.BorderBrush = Br '#22FFFFFF'
    $root.Width = $width
    $root.Background = New-ThemeGlass 0.1 0 0.9 1
    $sh = New-Object System.Windows.Media.Effects.DropShadowEffect
    $sh.BlurRadius = 26; $sh.ShadowDepth = 0; $sh.Opacity = 0.6; $sh.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#000000')
    $root.Effect = $sh

    $outer = New-Object System.Windows.Controls.Grid
    $r0 = New-Object System.Windows.Controls.RowDefinition
    $r0.Height = New-Object System.Windows.GridLength(2.5)
    $r1 = New-Object System.Windows.Controls.RowDefinition
    $r1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    [void]$outer.RowDefinitions.Add($r0)
    [void]$outer.RowDefinitions.Add($r1)

    $accent = New-Object System.Windows.Controls.Border
    $accent.Height = 2.5
    $accent.CornerRadius = New-Object System.Windows.CornerRadius(15, 15, 0, 0)
    $ag = New-Object System.Windows.Media.LinearGradientBrush
    $ag.StartPoint = New-Object System.Windows.Point(0, 0)
    $ag.EndPoint = New-Object System.Windows.Point(1, 0)
    $ag.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($accent1), 0)))
    $ag.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString($accent2), 1)))
    $accent.Background = $ag
    [System.Windows.Controls.Grid]::SetRow($accent, 0)
    [void]$outer.Children.Add($accent)

    $body = New-Object System.Windows.Controls.StackPanel
    $body.Margin = Th 14 12 14 13
    [System.Windows.Controls.Grid]::SetRow($body, 1)
    [void]$outer.Children.Add($body)

    $root.Child = $outer
    $w.Content = $root
    return @{ win = $w; root = $root; body = $body }
}

# ---------------- optional widget: Calendar ----------------
$script:calendarWin = $null
$script:calCtl = @{}
$script:calTimer = $null
$script:calCulture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')

function Update-CalendarCell($cell, [bool]$hover) {
    try {
        $t = $cell.Tag
        if (-not $t) { return }
        $cell.BorderThickness = Th 1 1 1 1
        $fg = '#C9D6E8'
        $weight = 'Normal'
        if ($t['today']) {
            $cell.Background = Br '#4CC2FF'
            $cell.BorderBrush = Br '#004CC2FF'
            $fg = '#06121F'
            $weight = 'Bold'
        } elseif ($t['selected']) {
            $cell.Background = Br '#1F4CC2FF'
            $cell.BorderBrush = Br '#804CC2FF'
            $fg = '#F2F6FF'
            $weight = 'SemiBold'
        } elseif (-not $t['inMonth']) {
            $cell.Background = Br '#00FFFFFF'
            $cell.BorderBrush = Br '#00FFFFFF'
            $fg = '#3E4C61'
        } elseif ($hover) {
            $cell.Background = Br '#14FFFFFF'
            $cell.BorderBrush = Br '#00FFFFFF'
            $fg = '#F2F6FF'
        } else {
            $cell.Background = Br '#00FFFFFF'
            $cell.BorderBrush = Br '#00FFFFFF'
        }
        if ($cell.Child) {
            $cell.Child.Foreground = Br $fg
            $cell.Child.FontWeight = switch ($weight) {
                'Bold' { [System.Windows.FontWeights]::Bold }
                'SemiBold' { [System.Windows.FontWeights]::SemiBold }
                default { [System.Windows.FontWeights]::Normal }
            }
        }
    } catch { }
}

function Update-CalendarFooter {
    try {
        $c = $script:calCtl
        if (-not $c.footLeft) { return }
        $sel = [datetime]$c.selected
        $week = $script:calCulture.Calendar.GetWeekOfYear($sel, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
        $total = if ([datetime]::IsLeapYear($sel.Year)) { 366 } else { 365 }
        if ($sel.Date -eq (Get-Date).Date) {
            $c.footLeft.Text = 'TODAY  •  WEEK ' + $week
        } else {
            $c.footLeft.Text = $sel.ToString('ddd, d MMM', $script:calCulture).ToUpper() + '  •  WEEK ' + $week
        }
        $c.footRight.Text = 'DAY ' + $sel.DayOfYear + ' / ' + $total
    } catch { }
}

function Render-CalendarMonth {
    try {
        $c = $script:calCtl
        if (-not $c.win -or -not $c.days) { return }
        $month = [datetime]$c.month
        $first = [datetime]::new($month.Year, $month.Month, 1)
        $c.month = $first
        $monday = [bool](Get-Cfg $script:cfg.calendar 'monday')
        $c.title.Text = $first.ToString('MMMM yyyy', $script:calCulture)

        $c.dow.Children.Clear()
        $names = if ($monday) { @('MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN') } else { @('SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT') }
        for ($i = 0; $i -lt 7; $i++) {
            $lbl = Txt $names[$i] 8.5 '#6F7F97' 'SemiBold'
            $lbl.HorizontalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($lbl, $i)
            [void]$c.dow.Children.Add($lbl)
        }

        $c.days.Children.Clear()
        $offset = if ($monday) { (([int]$first.DayOfWeek) + 6) % 7 } else { [int]$first.DayOfWeek }
        $start = $first.AddDays(-$offset)
        $today = (Get-Date).Date
        $c.today = $today
        $selDate = ([datetime]$c.selected).Date
        for ($i = 0; $i -lt 42; $i++) {
            $d = $start.AddDays($i)
            $cell = New-Object System.Windows.Controls.Border
            $cell.CornerRadius = CR 8
            $cell.Margin = Th 1 1 1 1
            $cell.Cursor = 'Hand'
            $tb = Txt ([string]$d.Day) 11.5 '#C9D6E8'
            $tb.HorizontalAlignment = 'Center'
            $tb.VerticalAlignment = 'Center'
            $cell.Child = $tb
            $cell.Tag = @{
                date = $d
                today = ($d.Date -eq $today)
                selected = ($d.Date -eq $selDate)
                inMonth = ($d.Month -eq $first.Month -and $d.Year -eq $first.Year)
            }
            [System.Windows.Controls.Grid]::SetRow($cell, [int][math]::Floor($i / 7))
            [System.Windows.Controls.Grid]::SetColumn($cell, ($i % 7))
            $cell.Add_MouseEnter({ param($s, $e) try { Update-CalendarCell $s $true } catch { } })
            $cell.Add_MouseLeave({ param($s, $e) try { Update-CalendarCell $s $false } catch { } })
            $cell.Add_MouseLeftButtonUp({ param($s, $e) try { Select-CalendarDay ([datetime]$s.Tag['date']) } catch { } })
            [void]$c.days.Children.Add($cell)
            Update-CalendarCell $cell $false
        }
        Update-CalendarFooter
    } catch { Write-WidgetError $_ 'calendar render' }
}

function Select-CalendarDay([datetime]$d) {
    try {
        $c = $script:calCtl
        $c.selected = $d.Date
        if (([datetime]$c.month).Month -ne $d.Month -or ([datetime]$c.month).Year -ne $d.Year) {
            $c.month = [datetime]::new($d.Year, $d.Month, 1)
        }
        Render-CalendarMonth
    } catch { }
}

function Go-CalendarToday {
    try {
        $now = Get-Date
        $c = $script:calCtl
        $c.selected = $now.Date
        $c.month = [datetime]::new($now.Year, $now.Month, 1)
        Render-CalendarMonth
    } catch { }
}

if ($cfg.calendar -and [bool](Get-Cfg $cfg.calendar 'enabled') -and -not $NoCalendar) {
    $calCard = New-GlassCard 300 '#4CC2FF' '#8B5CF6'
    $calWin = $calCard.win
    $calWin.Title = 'UD Calendar'
    $calWin.Topmost = [bool](Get-Cfg $cfg.calendar 'topmost')
    $calBody = $calCard.body

    $calHead = New-Object System.Windows.Controls.Grid
    $hc1 = New-Object System.Windows.Controls.ColumnDefinition
    $hc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $hc2 = New-Object System.Windows.Controls.ColumnDefinition
    $hc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
    [void]$calHead.ColumnDefinitions.Add($hc1)
    [void]$calHead.ColumnDefinitions.Add($hc2)
    [void]$calHead.Children.Add((New-CardTitle 'CALENDAR' '#4CC2FF'))
    $calToday = New-Object System.Windows.Controls.Button
    $calToday.Content = 'TODAY'
    $calToday.Style = $script:btnAccentStyle
    $calToday.FontSize = 9
    $calToday.Padding = Th 7 3 7 3
    $calToday.Height = 22
    $calToday.MinWidth = 0
    $calToday.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($calToday, 1)
    [void]$calHead.Children.Add($calToday)
    [void]$calBody.Children.Add($calHead)

    $calMonthRow = New-Object System.Windows.Controls.Grid
    $calMonthRow.Margin = Th 0 9 0 0
    for ($i = 0; $i -lt 3; $i++) {
        $mc = New-Object System.Windows.Controls.ColumnDefinition
        if ($i -eq 0) { $mc.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) }
        else { $mc.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto) }
        [void]$calMonthRow.ColumnDefinitions.Add($mc)
    }
    $calMonth = Txt '' 17 '#F2F6FF' 'SemiBold'
    [void]$calMonthRow.Children.Add($calMonth)
    $calPrev = New-Object System.Windows.Controls.Button
    $calPrev.Content = [string][char]0x2039
    $calPrev.Style = $script:btnStyle
    $calPrev.FontSize = 16
    $calPrev.Padding = Th 0 0 0 0
    $calPrev.Width = 25; $calPrev.Height = 25
    $calPrev.MinWidth = 0
    [System.Windows.Controls.Grid]::SetColumn($calPrev, 1)
    [void]$calMonthRow.Children.Add($calPrev)
    $calNext = New-Object System.Windows.Controls.Button
    $calNext.Content = [string][char]0x203A
    $calNext.Style = $script:btnStyle
    $calNext.FontSize = 16
    $calNext.Padding = Th 0 0 0 0
    $calNext.Width = 25; $calNext.Height = 25
    $calNext.MinWidth = 0
    $calNext.Margin = Th 6 0 0 0
    [System.Windows.Controls.Grid]::SetColumn($calNext, 2)
    [void]$calMonthRow.Children.Add($calNext)
    [void]$calBody.Children.Add($calMonthRow)

    $calDow = New-Object System.Windows.Controls.Grid
    $calDow.Margin = Th 0 9 0 2
    for ($i = 0; $i -lt 7; $i++) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        [void]$calDow.ColumnDefinitions.Add($cd)
    }
    [void]$calBody.Children.Add($calDow)

    $calDays = New-Object System.Windows.Controls.Grid
    $calDays.Margin = Th 0 2 0 0
    for ($i = 0; $i -lt 7; $i++) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        [void]$calDays.ColumnDefinitions.Add($cd)
    }
    for ($i = 0; $i -lt 6; $i++) {
        $rd = New-Object System.Windows.Controls.RowDefinition
        $rd.Height = New-Object System.Windows.GridLength(30)
        [void]$calDays.RowDefinitions.Add($rd)
    }
    [void]$calBody.Children.Add($calDays)

    $calFoot = New-Object System.Windows.Controls.Grid
    $calFoot.Margin = Th 0 7 0 0
    $fc1 = New-Object System.Windows.Controls.ColumnDefinition
    $fc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $fc2 = New-Object System.Windows.Controls.ColumnDefinition
    $fc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
    [void]$calFoot.ColumnDefinitions.Add($fc1)
    [void]$calFoot.ColumnDefinitions.Add($fc2)
    $calFootLeft = Txt '' 8.5 '#6F7F97' 'SemiBold'
    [void]$calFoot.Children.Add($calFootLeft)
    $calFootRight = Txt '' 8.5 '#6F7F97'
    $calFootRight.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($calFootRight, 1)
    [void]$calFoot.Children.Add($calFootRight)
    [void]$calBody.Children.Add($calFoot)

    $script:calCtl = @{
        win = $calWin
        month = [datetime]::new((Get-Date).Year, (Get-Date).Month, 1)
        selected = (Get-Date).Date
        today = (Get-Date).Date
        title = $calMonth
        dow = $calDow
        days = $calDays
        footLeft = $calFootLeft
        footRight = $calFootRight
    }

    $calToday.Add_Click({ try { Go-CalendarToday } catch { } })
    $calPrev.Add_Click({
        try {
            $script:calCtl.month = ([datetime]$script:calCtl.month).AddMonths(-1)
            Render-CalendarMonth
        } catch { }
    })
    $calNext.Add_Click({
        try {
            $script:calCtl.month = ([datetime]$script:calCtl.month).AddMonths(1)
            Render-CalendarMonth
        } catch { }
    })

    $calMenu = New-Object System.Windows.Controls.ContextMenu
    $calMenu.Background = Br '#12161F'
    $calMenu.Foreground = Br '#E8EEF8'
    $calMenu.BorderBrush = Br '#2A3140'

    $calMt = New-Object System.Windows.Controls.MenuItem
    $calMt.Header = 'Start week on Monday'
    $calMt.IsCheckable = $true
    $calMt.IsChecked = [bool](Get-Cfg $cfg.calendar 'monday')
    $calMt.Add_Click({
        param($s, $e)
        try { Set-Cfg $script:cfg.calendar 'monday' ([bool]$s.IsChecked); Save-Config; Render-CalendarMonth } catch { }
    })
    [void]$calMenu.Items.Add($calMt)

    $calMtop = New-Object System.Windows.Controls.MenuItem
    $calMtop.Header = 'Always on top'
    $calMtop.IsCheckable = $true
    $calMtop.IsChecked = [bool](Get-Cfg $cfg.calendar 'topmost')
    $calMtop.Add_Click({
        param($s, $e)
        try {
            Set-Cfg $script:cfg.calendar 'topmost' ([bool]$s.IsChecked)
            $script:calendarWin.Topmost = [bool]$s.IsChecked
            Save-Config
        } catch { }
    })
    [void]$calMenu.Items.Add($calMtop)
    Add-WidgetMenuItems $calMenu 'calendar'

    $calMgo = New-Object System.Windows.Controls.MenuItem
    $calMgo.Header = 'Go to today'
    $calMgo.Add_Click({ try { Go-CalendarToday } catch { } })
    [void]$calMenu.Items.Add($calMgo)
    [void]$calMenu.Items.Add((New-Object System.Windows.Controls.Separator))

    $calMr = New-Object System.Windows.Controls.MenuItem
    $calMr.Header = 'Reset position'
    $calMr.Add_Click({ try { Reset-CalendarPosition } catch { } })
    [void]$calMenu.Items.Add($calMr)

    $calMh = New-Object System.Windows.Controls.MenuItem
    $calMh.Header = 'Hide calendar'
    $calMh.Add_Click({ try { Set-WidgetVisible 'calendar' $false } catch { } })
    [void]$calMenu.Items.Add($calMh)

    $calCard.root.ContextMenu = $calMenu

    $script:calTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:calTimer.Interval = [TimeSpan]::FromSeconds(30)
    $script:calTimer.Add_Tick({
        try {
            $c = $script:calCtl
            if (-not $c.win -or -not $c.win.IsVisible) { return }
            if ((Get-Date).Date -ne $c.today) { Render-CalendarMonth } else { Update-CalendarFooter }
        } catch { }
    })

    $script:calendarWin = $calWin
    Render-CalendarMonth
}

# ---------------- optional widget: Focus timer ----------------
$script:focusWin = $null
$script:focusCtl = @{}
$script:focusTimer = $null

function Get-FocusMinutes([string]$mode) {
    $v = if ($mode -eq 'break') { Get-Cfg $script:cfg.focus 'breakMin' } else { Get-Cfg $script:cfg.focus 'workMin' }
    $n = 0
    if ([int]::TryParse([string]$v, [ref]$n) -and $n -ge 1 -and $n -le 180) { return $n }
    if ($mode -eq 'break') { return 5 }
    return 25
}

function Update-FocusVisuals {
    try {
        $c = $script:focusCtl
        if (-not $c.chip) { return }
        $isBreak = ([string]$c.mode -eq 'break')
        $accent = if ($isBreak) { '#34D399' } else { '#4CC2FF' }
        $c.chipText.Text = if ($isBreak) { 'BREAK' } else { 'WORK' }
        $c.chipText.Foreground = Br $accent
        $c.chip.Background = Br $(if ($isBreak) { '#2034D399' } else { '#204CC2FF' })
        $c.chip.BorderBrush = Br $(if ($isBreak) { '#5034D399' } else { '#504CC2FF' })
        $c.modeLbl.Text = if ($isBreak) { 'Short break' } else { 'Deep work' }
        $c.modeLbl.Foreground = Br $accent
        $c.fill.Background = if ($isBreak) { Br '#34D399' } else { $c.workBrush }
    } catch { }
}

function Update-FocusWidget {
    try {
        $c = $script:focusCtl
        if (-not $c.time) { return }
        if ($c.running) {
            $left = [int][math]::Ceiling(($c.endAt - (Get-Date)).TotalSeconds)
            if ($left -lt 0) { $left = 0 }
            $c.remaining = $left
        }
        $secs = [int][math]::Max(0, [math]::Round([double]$c.remaining))
        $mm = [int][math]::Floor($secs / 60)
        $ss = [int]($secs % 60)
        $txt = '{0:00}:{1:00}' -f $mm, $ss
        if ($c.time.Text -ne $txt) { $c.time.Text = $txt }
        $frac = if ($c.total -gt 0) { [double]$c.remaining / [double]$c.total } else { 0 }
        $c.fill.RenderTransform.ScaleX = [math]::Max(0.0, [math]::Min(1.0, $frac))
        if ($c.running -and $secs -le 0) { Complete-FocusSession }
    } catch { Write-WidgetError $_ 'focus update' }
}

function Set-FocusMode([string]$mode, [bool]$start = $false) {
    try {
        $c = $script:focusCtl
        if (-not $c.time) { return }
        $c.mode = if ($mode -eq 'break') { 'break' } else { 'work' }
        $c.total = (Get-FocusMinutes $c.mode) * 60
        $c.remaining = $c.total
        $c.running = $false
        $c.btn.Content = 'START'
        $c.status.Text = 'READY'
        Update-FocusVisuals
        Update-FocusWidget
        if ($start) { Start-PauseFocus }
    } catch { Write-WidgetError $_ 'focus mode' }
}

function Start-PauseFocus {
    try {
        $c = $script:focusCtl
        if (-not $c.time) { return }
        if ($c.running) {
            $left = [int][math]::Ceiling(($c.endAt - (Get-Date)).TotalSeconds)
            $c.remaining = [math]::Max(0, $left)
            $c.running = $false
            $c.btn.Content = 'RESUME'
            $c.status.Text = 'PAUSED'
        } else {
            if ([double]$c.remaining -le 0) { $c.remaining = $c.total }
            $c.endAt = (Get-Date).AddSeconds([double]$c.remaining)
            $c.running = $true
            $c.btn.Content = 'PAUSE'
            $c.status.Text = 'IN SESSION'
        }
        Update-FocusWidget
    } catch { Write-WidgetError $_ 'focus start' }
}

function Reset-FocusTimer {
    try {
        $c = $script:focusCtl
        if (-not $c.time) { return }
        $c.running = $false
        $c.total = (Get-FocusMinutes $c.mode) * 60
        $c.remaining = $c.total
        $c.btn.Content = 'START'
        $c.status.Text = 'READY'
        Update-FocusWidget
    } catch { }
}

function Complete-FocusSession {
    try {
        $c = $script:focusCtl
        $wasWork = ([string]$c.mode -eq 'work')
        $c.running = $false
        try {
            if ($script:tray) {
                $msg = if ($wasWork) { 'Focus session complete. Time for a short break.' } else { 'Break finished. Ready for the next focus session.' }
                $script:tray.ShowBalloonTip(6000, 'UNLOCK DIGITAL Focus', $msg, [System.Windows.Forms.ToolTipIcon]::Info)
            }
        } catch { }
        Set-FocusMode $(if ($wasWork) { 'break' } else { 'work' }) $false
    } catch { Write-WidgetError $_ 'focus complete' }
}

if ($cfg.focus -and [bool](Get-Cfg $cfg.focus 'enabled') -and -not $NoFocus) {
    $fCard = New-GlassCard 300 '#4CC2FF' '#8B5CF6'
    $fWin = $fCard.win
    $fWin.Title = 'UD Focus'
    $fWin.Topmost = [bool](Get-Cfg $cfg.focus 'topmost')
    $fBody = $fCard.body

    $fHead = New-Object System.Windows.Controls.Grid
    $fhc1 = New-Object System.Windows.Controls.ColumnDefinition
    $fhc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $fhc2 = New-Object System.Windows.Controls.ColumnDefinition
    $fhc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
    [void]$fHead.ColumnDefinitions.Add($fhc1)
    [void]$fHead.ColumnDefinitions.Add($fhc2)
    [void]$fHead.Children.Add((New-CardTitle 'FOCUS' '#4CC2FF'))
    $fChip = New-Object System.Windows.Controls.Border
    $fChip.CornerRadius = CR 8
    $fChip.Padding = Th 7 2 7 2
    $fChip.BorderThickness = Th 1 1 1 1
    $fChip.VerticalAlignment = 'Center'
    $fChipText = Txt 'WORK' 8.5 '#4CC2FF' 'Bold'
    $fChip.Child = $fChipText
    [System.Windows.Controls.Grid]::SetColumn($fChip, 1)
    [void]$fHead.Children.Add($fChip)
    [void]$fBody.Children.Add($fHead)

    $fTime = Txt '25:00' 46 '#F2F6FF' 'Bold'
    $fTime.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Variable Display, Segoe UI')
    $fTime.Margin = Th 0 4 0 0
    try { $fTime.Typography.NumeralAlignment = [System.Windows.Documents.FontNumeralAlignment]::Tabular } catch { }
    [void]$fBody.Children.Add($fTime)

    $fSub = New-Object System.Windows.Controls.Grid
    $fSub.Margin = Th 0 1 0 0
    $fsc1 = New-Object System.Windows.Controls.ColumnDefinition
    $fsc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $fsc2 = New-Object System.Windows.Controls.ColumnDefinition
    $fsc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
    [void]$fSub.ColumnDefinitions.Add($fsc1)
    [void]$fSub.ColumnDefinitions.Add($fsc2)
    $fMode = Txt 'Deep work' 11 '#4CC2FF' 'SemiBold'
    [void]$fSub.Children.Add($fMode)
    $fStatus = Txt 'READY' 9 '#6F7F97' 'SemiBold'
    $fStatus.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($fStatus, 1)
    [void]$fSub.Children.Add($fStatus)
    [void]$fBody.Children.Add($fSub)

    $fTrack = New-Object System.Windows.Controls.Grid
    $fTrack.Height = 4
    $fTrack.Margin = Th 0 11 0 0
    $fTrackBg = New-Object System.Windows.Controls.Border
    $fTrackBg.CornerRadius = CR 2
    $fTrackBg.Background = Br '#14FFFFFF'
    [void]$fTrack.Children.Add($fTrackBg)
    $fFill = New-Object System.Windows.Controls.Border
    $fFill.CornerRadius = CR 2
    $fFill.Background = New-ThemeAccent2
    $fFill.RenderTransformOrigin = New-Object System.Windows.Point(0, 0.5)
    $fFill.RenderTransform = New-Object System.Windows.Media.ScaleTransform(1, 1)
    [void]$fTrack.Children.Add($fFill)
    [void]$fBody.Children.Add($fTrack)

    $fButtons = New-Object System.Windows.Controls.Grid
    $fButtons.Margin = Th 0 12 0 0
    for ($i = 0; $i -lt 3; $i++) {
        $bc = New-Object System.Windows.Controls.ColumnDefinition
        if ($i -eq 0) { $bc.Width = New-Object System.Windows.GridLength(1.6, [System.Windows.GridUnitType]::Star) }
        else { $bc.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) }
        [void]$fButtons.ColumnDefinitions.Add($bc)
    }
    $fBtn = New-Object System.Windows.Controls.Button
    $fBtn.Content = 'START'
    $fBtn.Style = $script:btnAccentStyle
    $fBtn.Height = 32
    $fBtn.FontSize = 10.5
    $fBtn.FontWeight = 'SemiBold'
    $fBtn.MinWidth = 0
    [void]$fButtons.Children.Add($fBtn)
    $fReset = New-Object System.Windows.Controls.Button
    $fReset.Content = 'RESET'
    $fReset.Style = $script:btnStyle
    $fReset.Height = 32
    $fReset.FontSize = 10.5
    $fReset.MinWidth = 0
    $fReset.Margin = Th 6 0 0 0
    [System.Windows.Controls.Grid]::SetColumn($fReset, 1)
    [void]$fButtons.Children.Add($fReset)
    $fSkip = New-Object System.Windows.Controls.Button
    $fSkip.Content = 'SKIP'
    $fSkip.Style = $script:btnStyle
    $fSkip.Height = 32
    $fSkip.FontSize = 10.5
    $fSkip.MinWidth = 0
    $fSkip.Margin = Th 6 0 0 0
    [System.Windows.Controls.Grid]::SetColumn($fSkip, 2)
    [void]$fButtons.Children.Add($fSkip)
    [void]$fBody.Children.Add($fButtons)

    $script:focusCtl = @{
        win = $fWin
        mode = 'work'
        total = 25 * 60
        remaining = 25 * 60
        running = $false
        endAt = (Get-Date)
        time = $fTime
        chip = $fChip
        chipText = $fChipText
        modeLbl = $fMode
        status = $fStatus
        btn = $fBtn
        fill = $fFill
        workBrush = $fWorkBrush
    }

    $fBtn.Add_Click({ try { Start-PauseFocus } catch { } })
    $fReset.Add_Click({ try { Reset-FocusTimer } catch { } })
    $fSkip.Add_Click({
        try {
            $next = if ([string]$script:focusCtl.mode -eq 'work') { 'break' } else { 'work' }
            Set-FocusMode $next $false
        } catch { }
    })

    $fMenu = New-Object System.Windows.Controls.ContextMenu
    $fMenu.Background = Br '#12161F'
    $fMenu.Foreground = Br '#E8EEF8'
    $fMenu.BorderBrush = Br '#2A3140'

    $fP25 = New-Object System.Windows.Controls.MenuItem
    $fP25.Header = '25 / 5'
    $fP25.Add_Click({
        try {
            Set-Cfg $script:cfg.focus 'workMin' 25; Set-Cfg $script:cfg.focus 'breakMin' 5; Save-Config
            if (-not $script:focusCtl.running) { Set-FocusMode ([string]$script:focusCtl.mode) $false }
        } catch { }
    })
    [void]$fMenu.Items.Add($fP25)

    $fP50 = New-Object System.Windows.Controls.MenuItem
    $fP50.Header = '50 / 10'
    $fP50.Add_Click({
        try {
            Set-Cfg $script:cfg.focus 'workMin' 50; Set-Cfg $script:cfg.focus 'breakMin' 10; Save-Config
            if (-not $script:focusCtl.running) { Set-FocusMode ([string]$script:focusCtl.mode) $false }
        } catch { }
    })
    [void]$fMenu.Items.Add($fP50)

    $fP90 = New-Object System.Windows.Controls.MenuItem
    $fP90.Header = '90 / 15'
    $fP90.Add_Click({
        try {
            Set-Cfg $script:cfg.focus 'workMin' 90; Set-Cfg $script:cfg.focus 'breakMin' 15; Save-Config
            if (-not $script:focusCtl.running) { Set-FocusMode ([string]$script:focusCtl.mode) $false }
        } catch { }
    })
    [void]$fMenu.Items.Add($fP90)
    [void]$fMenu.Items.Add((New-Object System.Windows.Controls.Separator))

    $fMtop = New-Object System.Windows.Controls.MenuItem
    $fMtop.Header = 'Always on top'
    $fMtop.IsCheckable = $true
    $fMtop.IsChecked = [bool](Get-Cfg $cfg.focus 'topmost')
    $fMtop.Add_Click({
        param($s, $e)
        try {
            Set-Cfg $script:cfg.focus 'topmost' ([bool]$s.IsChecked)
            $script:focusWin.Topmost = [bool]$s.IsChecked
            Save-Config
        } catch { }
    })
    [void]$fMenu.Items.Add($fMtop)
    Add-WidgetMenuItems $fMenu 'focus'

    $fMr = New-Object System.Windows.Controls.MenuItem
    $fMr.Header = 'Reset position'
    $fMr.Add_Click({ try { Reset-FocusPosition } catch { } })
    [void]$fMenu.Items.Add($fMr)

    $fMh = New-Object System.Windows.Controls.MenuItem
    $fMh.Header = 'Hide focus timer'
    $fMh.Add_Click({ try { Set-WidgetVisible 'focus' $false } catch { } })
    [void]$fMenu.Items.Add($fMh)

    $fCard.root.ContextMenu = $fMenu

    $script:focusTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:focusTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:focusTimer.Add_Tick({ try { Update-FocusWidget } catch { } })

    $script:focusWin = $fWin
    Set-FocusMode 'work' $false
}

# ---------------- optional widget: Quick notes ----------------
$script:notesWin = $null
$script:notesCtl = @{}
$script:notesTimer = $null

function Read-NotesFile {
    try {
        if (Test-Path -LiteralPath $NotesPath) { return [System.IO.File]::ReadAllText($NotesPath) }
    } catch { Write-WidgetError $_ 'notes read' }
    return ''
}

function Update-NotesPlaceholder {
    try {
        $c = $script:notesCtl
        if (-not $c.placeholder -or -not $c.box) { return }
        $n = ([string]$c.box.Text).Length
        $c.placeholder.Visibility = if ($n -eq 0 -and -not $c.box.IsKeyboardFocused) { 'Visible' } else { 'Collapsed' }
        if ($c.count) { $c.count.Text = if ($n -eq 1) { '1 CHAR' } else { [string]$n + ' CHARS' } }
    } catch { }
}

function Save-Notes {
    try {
        $c = $script:notesCtl
        if (-not $c.box) { return }
        $dir = Split-Path -Parent $NotesPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($NotesPath, [string]$c.box.Text, $enc)
        if ($c.status) { $c.status.Text = 'SAVED ' + (Get-Date).ToString('HH:mm') }
    } catch { Write-WidgetError $_ 'notes save' }
    try { if ($script:notesCtl.saveTimer) { $script:notesCtl.saveTimer.Stop() } } catch { }
}

function Show-NotesWidget {
    try {
        if (-not $script:notesWin) { return }
        $script:notesWin.Show()
        $script:notesWin.Activate()
        if ($script:notesCtl.box) {
            [void]$script:notesCtl.box.Focus()
            $script:notesCtl.box.CaretIndex = ([string]$script:notesCtl.box.Text).Length
        }
    } catch { }
}

if ($cfg.notes -and [bool](Get-Cfg $cfg.notes 'enabled') -and -not $NoNotes) {
    $nCard = New-GlassCard 300 $script:theme.accent1 $script:theme.accent2
    $nWin = $nCard.win
    $nWin.Title = 'UD Quick Notes'
    $nWin.Topmost = [bool](Get-Cfg $cfg.notes 'topmost')
    $nWin.ShowActivated = $false
    $nBody = $nCard.body

    $nHead = New-Object System.Windows.Controls.Grid
    $nHead.Background = [System.Windows.Media.Brushes]::Transparent
    $nHead.Cursor = [System.Windows.Input.Cursors]::SizeAll
    $nhc1 = New-Object System.Windows.Controls.ColumnDefinition
    $nhc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $nhc2 = New-Object System.Windows.Controls.ColumnDefinition
    $nhc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
    [void]$nHead.ColumnDefinitions.Add($nhc1)
    [void]$nHead.ColumnDefinitions.Add($nhc2)
    [void]$nHead.Children.Add((New-CardTitle 'QUICK NOTES' '#34D399'))
    $nCount = Txt '0 CHARS' 8.5 '#6F7F97' 'SemiBold'
    $nCount.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($nCount, 1)
    [void]$nHead.Children.Add($nCount)
    [void]$nBody.Children.Add($nHead)

    $nField = New-Object System.Windows.Controls.Border
    $nField.CornerRadius = CR 10
    $nField.Background = Br '#0AFFFFFF'
    $nField.BorderBrush = Br '#14FFFFFF'
    $nField.BorderThickness = Th 1 1 1 1
    $nField.Margin = Th 0 8 0 0
    $nField.Height = 138

    $nFieldGrid = New-Object System.Windows.Controls.Grid
    $nBox = New-Object System.Windows.Controls.TextBox
    $nBox.Background = Br '#00FFFFFF'
    $nBox.Foreground = Br '#DCE6F5'
    $nBox.BorderThickness = Th 0 0 0 0
    $nBox.Padding = Th 9 7 9 7
    $nBox.Margin = Th 1 1 1 1
    $nBox.FontSize = 12.5
    $nBox.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
    $nBox.AcceptsReturn = $true
    $nBox.TextWrapping = 'Wrap'
    $nBox.VerticalScrollBarVisibility = 'Auto'
    $nBox.CaretBrush = Br '#4CC2FF'
    $nBox.SelectionBrush = Br '#335B8DEF'
    [void]$nFieldGrid.Children.Add($nBox)
    $nPlaceholder = Txt 'Type a quick note...' 12.5 '#5A6A80'
    $nPlaceholder.IsHitTestVisible = $false
    $nPlaceholder.VerticalAlignment = 'Top'
    $nPlaceholder.Margin = Th 12 9 12 0
    $nPlaceholder.TextWrapping = 'Wrap'
    [void]$nFieldGrid.Children.Add($nPlaceholder)
    $nField.Child = $nFieldGrid
    [void]$nBody.Children.Add($nField)

    $nFoot = New-Object System.Windows.Controls.Grid
    $nFoot.Background = [System.Windows.Media.Brushes]::Transparent
    $nFoot.Cursor = [System.Windows.Input.Cursors]::SizeAll
    $nFoot.Margin = Th 0 7 0 0
    $nfc1 = New-Object System.Windows.Controls.ColumnDefinition
    $nfc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $nfc2 = New-Object System.Windows.Controls.ColumnDefinition
    $nfc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
    [void]$nFoot.ColumnDefinitions.Add($nfc1)
    [void]$nFoot.ColumnDefinitions.Add($nfc2)
    $nFootLeft = Txt 'AUTO-SAVE  •  NOTES.TXT' 8.5 '#5A6A80' 'SemiBold'
    [void]$nFoot.Children.Add($nFootLeft)
    $nStatus = Txt 'READY' 8.5 '#6F7F97' 'SemiBold'
    $nStatus.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($nStatus, 1)
    [void]$nFoot.Children.Add($nStatus)
    [void]$nBody.Children.Add($nFoot)

    $script:notesCtl = @{
        win = $nWin
        box = $nBox
        placeholder = $nPlaceholder
        count = $nCount
        status = $nStatus
        header = $nHead
        loading = $true
        saveTimer = $null
    }

    $script:notesTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:notesTimer.Interval = [TimeSpan]::FromMilliseconds(900)
    $script:notesTimer.Add_Tick({ try { Save-Notes } catch { } })
    $script:notesCtl.saveTimer = $script:notesTimer

    $nBox.Add_TextChanged({
        param($s, $e)
        try {
            $c = $script:notesCtl
            Update-NotesPlaceholder
            if ($c.loading) { return }
            if ($c.status) { $c.status.Text = 'SAVING...' }
            if ($c.saveTimer) { $c.saveTimer.Stop(); $c.saveTimer.Start() }
        } catch { }
    })
    $nBox.Add_GotKeyboardFocus({ try { Update-NotesPlaceholder } catch { } })
    $nBox.Add_LostKeyboardFocus({ try { Update-NotesPlaceholder } catch { } })
    $nBox.Add_KeyDown({
        param($s, $e)
        try {
            if ($e.Key -eq [System.Windows.Input.Key]::S -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
                Save-Notes
                $e.Handled = $true
            }
        } catch { }
    })

    $nMenu = New-Object System.Windows.Controls.ContextMenu
    $nMenu.Background = Br '#12161F'
    $nMenu.Foreground = Br '#E8EEF8'
    $nMenu.BorderBrush = Br '#2A3140'

    $nMtop = New-Object System.Windows.Controls.MenuItem
    $nMtop.Header = 'Always on top'
    $nMtop.IsCheckable = $true
    $nMtop.IsChecked = [bool](Get-Cfg $cfg.notes 'topmost')
    $nMtop.Add_Click({
        param($s, $e)
        try {
            Set-Cfg $script:cfg.notes 'topmost' ([bool]$s.IsChecked)
            $script:notesWin.Topmost = [bool]$s.IsChecked
            Save-Config
        } catch { }
    })
    [void]$nMenu.Items.Add($nMtop)
    Add-WidgetMenuItems $nMenu 'notes'

    $nMclear = New-Object System.Windows.Controls.MenuItem
    $nMclear.Header = 'Clear note'
    $nMclear.Add_Click({
        try {
            $r = [System.Windows.MessageBox]::Show('Clear the whole note? This cannot be undone.', 'UNLOCK DIGITAL', 'YesNo', 'Warning')
            if ($r -eq 'Yes') { $script:notesCtl.box.Text = ''; Save-Notes }
        } catch { }
    })
    [void]$nMenu.Items.Add($nMclear)
    [void]$nMenu.Items.Add((New-Object System.Windows.Controls.Separator))

    $nMr = New-Object System.Windows.Controls.MenuItem
    $nMr.Header = 'Reset position'
    $nMr.Add_Click({ try { Reset-NotesPosition } catch { } })
    [void]$nMenu.Items.Add($nMr)

    $nMh = New-Object System.Windows.Controls.MenuItem
    $nMh.Header = 'Hide notes'
    $nMh.Add_Click({
        try {
            Set-WidgetVisible 'notes' $false
        } catch { }
    })
    [void]$nMenu.Items.Add($nMh)

    # edit commands first (they act on the note text), then the usual widget options
    $nEditItems = @()
    foreach ($pair in @(@('Cut', [System.Windows.Input.ApplicationCommands]::Cut), @('Copy', [System.Windows.Input.ApplicationCommands]::Copy), @('Paste', [System.Windows.Input.ApplicationCommands]::Paste), @('Select all', [System.Windows.Input.ApplicationCommands]::SelectAll))) {
        $ei = New-Object System.Windows.Controls.MenuItem
        $ei.Header = $pair[0]
        $ei.Command = $pair[1]
        $ei.CommandTarget = $nBox
        $nEditItems += $ei
    }
    $nIdx = 0
    foreach ($ei in $nEditItems) { $nMenu.Items.Insert($nIdx, $ei); $nIdx++ }
    $nMenu.Items.Insert($nIdx, (New-Object System.Windows.Controls.Separator))

    # the menu works on the whole card (header, text area, footer), not only on the header
    $nHead.ContextMenu = $nMenu
    $nBox.ContextMenu = $nMenu
    try { if ($nCard -and $nCard.root) { $nCard.root.ContextMenu = $nMenu } } catch { }
    try { if ($nBody) { $nBody.ContextMenu = $nMenu } } catch { }

    $nWin.Add_IsVisibleChanged({
        param($s, $e)
        try { if (-not $s.IsVisible) { Save-Notes } } catch { }
    })

    $nBox.Text = Read-NotesFile
    $script:notesCtl.loading = $false
    $script:notesCtl.status.Text = 'READY'
    Update-NotesPlaceholder

    $script:notesWin = $nWin
}

# ---------------- optional widget: Weather & prayer times ----------------
if ($cfg.weather -and [bool](Get-Cfg $cfg.weather 'enabled') -and -not $NoWeather) {
    $wCard = New-GlassCard 300 $script:theme.accent1 $script:theme.accent3
    $wWin = $wCard.win
    $wWin.Title = 'UD Weather & Prayer'
    $wWin.Topmost = [bool](Get-Cfg $cfg.weather 'topmost')
    $wWin.ShowActivated = $false
    $wBody = $wCard.body

    # Header: WEATHER & PRAYER + CITY BADGE
    $wHead = New-Object System.Windows.Controls.Grid
    $wHead.Background = [System.Windows.Media.Brushes]::Transparent
    $wHead.Cursor = [System.Windows.Input.Cursors]::SizeAll
    $whc1 = New-Object System.Windows.Controls.ColumnDefinition; $whc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $whc2 = New-Object System.Windows.Controls.ColumnDefinition; $whc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
    [void]$wHead.ColumnDefinitions.Add($whc1)
    [void]$wHead.ColumnDefinitions.Add($whc2)
    [void]$wHead.Children.Add((New-CardTitle 'WEATHER & PRAYER' '#38BDF8'))
    $wCityBadge = Txt ([string](Get-Cfg $cfg.weather 'city')).ToUpper() 8.5 '#38BDF8' 'Bold'
    $wChip = New-Object System.Windows.Controls.Border
    $wChip.CornerRadius = CR 7; $wChip.Padding = Th 6 1 6 1; $wChip.BorderThickness = Th 1 1 1 1; $wChip.BorderBrush = Br '#2238BDF8'; $wChip.Background = Br '#1038BDF8'
    $wChip.Child = $wCityBadge
    [System.Windows.Controls.Grid]::SetColumn($wChip, 1)
    [void]$wHead.Children.Add($wChip)
    [void]$wBody.Children.Add($wHead)

    # Weather main row: Temp + Desc & details
    $wMain = New-Object System.Windows.Controls.DockPanel
    $wMain.Margin = Th 0 4 0 2
    $wTemp = Txt '—' 40 '#F2F6FF' 'Bold'
    $wTemp.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Variable Display, Segoe UI')
    $wTemp.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($wTemp, 'Left')
    [void]$wMain.Children.Add($wTemp)

    $wMeta = New-Object System.Windows.Controls.StackPanel
    $wMeta.Margin = Th 12 4 0 0
    $wMeta.VerticalAlignment = 'Center'
    $wDesc = Txt 'Loading...' 12 '#E2E8F0' 'SemiBold'
    $wSub = New-Object System.Windows.Controls.StackPanel; $wSub.Orientation = 'Horizontal'; $wSub.Margin = Th 0 2 0 0
    $wRange = Txt '—' 10 '#94A3B8'
    $wDot = Txt ' • ' 10 '#64748B'
    $wHumid = Txt '—' 10 '#94A3B8'
    [void]$wSub.Children.Add($wRange); [void]$wSub.Children.Add($wDot); [void]$wSub.Children.Add($wHumid)
    [void]$wMeta.Children.Add($wDesc)
    [void]$wMeta.Children.Add($wSub)
    [void]$wMain.Children.Add($wMeta)
    [void]$wBody.Children.Add($wMain)

    # Hijri Date bar
    $wHijri = Txt '' 10.5 '#34D399' 'SemiBold'
    $wHijri.Margin = Th 0 3 0 6
    $wHijri.HorizontalAlignment = 'Center'
    [void]$wBody.Children.Add($wHijri)

    # Prayer times table
    $pGrid = New-Object System.Windows.Controls.Primitives.UniformGrid
    $pGrid.Columns = 5
    $pGrid.Margin = Th 0 2 0 2

    function New-PrayerCell($name, $timeText) {
        $pnl = New-Object System.Windows.Controls.StackPanel
        $pnl.HorizontalAlignment = 'Center'
        $lbl = Txt $name 8 '#8494AB' 'SemiBold'; $lbl.HorizontalAlignment = 'Center'
        $val = Txt $timeText 10 '#F1F5F9' 'Bold'; $val.HorizontalAlignment = 'Center'
        [void]$pnl.Children.Add($lbl)
        [void]$pnl.Children.Add($val)
        return @{ panel = $pnl; val = $val }
    }

    $cellFajr    = New-PrayerCell 'FAJR' '—'
    $cellDhuhr   = New-PrayerCell 'DHUHR' '—'
    $cellAsr     = New-PrayerCell 'ASR' '—'
    $cellMaghrib = New-PrayerCell 'MAGHRIB' '—'
    $cellIsha    = New-PrayerCell 'ISHA' '—'

    [void]$pGrid.Children.Add($cellFajr.panel)
    [void]$pGrid.Children.Add($cellDhuhr.panel)
    [void]$pGrid.Children.Add($cellAsr.panel)
    [void]$pGrid.Children.Add($cellMaghrib.panel)
    [void]$pGrid.Children.Add($cellIsha.panel)
    [void]$wBody.Children.Add($pGrid)

    # Context Menu
    $wMenu = New-Object System.Windows.Controls.ContextMenu
    $wMenu.Background = Br '#12161F'; $wMenu.Foreground = Br '#E8EEF8'; $wMenu.BorderBrush = Br '#2A3140'
    $wMtop = New-Object System.Windows.Controls.MenuItem; $wMtop.Header = 'Always on top'; $wMtop.IsCheckable = $true
    $wMtop.IsChecked = [bool](Get-Cfg $cfg.weather 'topmost')
    $wMtop.Add_Click({ param($s, $e) try { Set-Cfg $script:cfg.weather 'topmost' ([bool]$s.IsChecked); $script:weatherWin.Topmost = [bool]$s.IsChecked; Save-Config } catch { } })
    [void]$wMenu.Items.Add($wMtop)
    Add-WidgetMenuItems $wMenu 'weather'
    $wMref = New-Object System.Windows.Controls.MenuItem; $wMref.Header = 'Refresh weather'; $wMref.Add_Click({ try { Update-AllWeatherData } catch { } })
    [void]$wMenu.Items.Add($wMref)
    [void]$wMenu.Items.Add((New-Object System.Windows.Controls.Separator))
    $wMr = New-Object System.Windows.Controls.MenuItem; $wMr.Header = 'Reset position'; $wMr.Add_Click({ try { Reset-WeatherPosition } catch { } })
    [void]$wMenu.Items.Add($wMr)
    $wMh = New-Object System.Windows.Controls.MenuItem; $wMh.Header = 'Hide weather'; $wMh.Add_Click({ try { Set-WidgetVisible 'weather' $false } catch { } })
    [void]$wMenu.Items.Add($wMh)
    $wCard.root.ContextMenu = $wMenu

    $script:weatherCtl = @{
        win     = $wWin
        temp    = $wTemp
        desc    = $wDesc
        humid   = $wHumid
        range   = $wRange
        city    = $wCityBadge
        hijri   = $wHijri
        prayerTimes = $pGrid
        fajr    = $cellFajr.val
        sunrise = (New-Object System.Windows.Controls.TextBlock)
        dhuhr   = $cellDhuhr.val
        asr     = $cellAsr.val
        maghrib = $cellMaghrib.val
        isha    = $cellIsha.val
    }

    $script:weatherTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:weatherTimer.Interval = [TimeSpan]::FromMinutes(15)
    $script:weatherTimer.Add_Tick({ try { Update-AllWeatherData } catch { } })

    $script:weatherPollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:weatherPollTimer.Interval = [TimeSpan]::FromSeconds(2)
    $script:weatherPollTimer.Add_Tick({
        try {
            $json = [UDWin]::PollWeatherResult()
            if ($json) {
                $resp = $json | ConvertFrom-Json
                Apply-WeatherData $resp
            }
        } catch { }
    })
    $script:weatherPollTimer.Start()

    $script:weatherWin = $wWin
}

# ---------------- show windows ----------------
$screenW = [System.Windows.SystemParameters]::WorkArea.Width      # WPF DIP units
$screenH = [System.Windows.SystemParameters]::WorkArea.Height
$screenX = [System.Windows.SystemParameters]::WorkArea.X
$screenY = [System.Windows.SystemParameters]::WorkArea.Y

if ($hudWin) {
    $hudWin.Show()
    $hudWin.UpdateLayout()
    $sxH = Get-Cfg $cfg.hud 'x'; $syH = Get-Cfg $cfg.hud 'y'
    if ($null -ne $sxH -and $null -ne $syH) {
        $hudWin.Left = [double]$sxH
        $hudWin.Top = [double]$syH
    } else {
        if ([string]$cfg.hud.side -eq 'right') { $hudWin.Left = [double]($screenX + $screenW - $hudWin.ActualWidth - 20) }
        else { $hudWin.Left = [double]($screenX + 16) }
        $hudWin.Top = [double]($screenY + 14)
    }
}
if ($dockWin) {
    $dockWin.Show()
    $dockWin.UpdateLayout()
    $dockWin.Left = [double]($screenX + (($screenW - $dockWin.ActualWidth) / 2))
    $dockWin.Top = [double]($screenY + $screenH - $dockWin.ActualHeight - 10)
    Invoke-DockIntro
    Start-DockDots
}
if ($musicWin) {
    $musicWin.Show()
    $musicWin.UpdateLayout()
    $sxM = Get-Cfg $cfg.music 'x'; $syM = Get-Cfg $cfg.music 'y'
    if ($null -ne $sxM -and $null -ne $syM) {
        $musicWin.Left = [double]$sxM
        $musicWin.Top = [double]$syM
    } else {
        $musicWin.Left = [double]($screenX + $screenW - $musicWin.ActualWidth - 16)
        $musicWin.Top = [double]($screenY + 14)
    }
}
if ($clockWin) {
    $clockWin.Show()
    $clockWin.UpdateLayout()
    $sxC = Get-Cfg $cfg.clock 'x'; $syC = Get-Cfg $cfg.clock 'y'
    if ($null -ne $sxC -and $null -ne $syC) {
        $clockWin.Left = [double]$sxC
        $clockWin.Top = [double]$syC
    } else {
        $clockWin.Left = [double]($screenX + (($screenW - $clockWin.ActualWidth) / 2))
        $clockWin.Top = [double]($screenY + 14)
    }
    try { $script:clockTimer.Start() } catch { }
}
function Set-DockPosition {
    try {
        if ($script:dockWin -and $script:dockWin.IsVisible) {
            $script:dockWin.Left = [double]($screenX + (($screenW - $script:dockWin.ActualWidth) / 2))
            $script:dockWin.Top = [double]($screenY + $screenH - $script:dockWin.ActualHeight - 10)
        }
    } catch { }
}
function Reset-HudPosition {
    try {
        if ($script:cfg.hud) { Set-Cfg $script:cfg.hud 'x' $null; Set-Cfg $script:cfg.hud 'y' $null }
        Save-Config
        if ($script:hudWin -and $script:hudWin.IsVisible) {
            if ([string]$script:cfg.hud.side -eq 'right') { $script:hudWin.Left = [double]($screenX + $screenW - $script:hudWin.ActualWidth - 20) }
            else { $script:hudWin.Left = [double]($screenX + 16) }
            $script:hudWin.Top = [double]($screenY + 14)
        }
    } catch { }
}
function Reset-MusicPosition {
    try {
        if ($script:cfg.music) { Set-Cfg $script:cfg.music 'x' $null; Set-Cfg $script:cfg.music 'y' $null }
        Save-Config
        if ($script:musicWin -and $script:musicWin.IsVisible) {
            $script:musicWin.Left = [double]($screenX + $screenW - $script:musicWin.ActualWidth - 16)
            $script:musicWin.Top = [double]($screenY + 14)
        }
    } catch { }
}
function Reset-ClockPosition {
    try {
        if ($script:cfg.clock) { Set-Cfg $script:cfg.clock 'x' $null; Set-Cfg $script:cfg.clock 'y' $null }
        Save-Config
        if ($script:clockWin -and $script:clockWin.IsVisible) {
            $script:clockWin.Left = [double]($screenX + (($screenW - $script:clockWin.ActualWidth) / 2))
            $script:clockWin.Top = [double]($screenY + 14)
        }
    } catch { }
}
function Reset-WeatherPosition {
    try {
        if ($script:cfg.weather) { Set-Cfg $script:cfg.weather 'x' $null; Set-Cfg $script:cfg.weather 'y' $null }
        Save-Config
        if ($script:weatherWin -and $script:weatherWin.IsVisible) { Set-WidgetDefaultPosition 'weather' }
    } catch { }
}
function Test-RectOverlap($a, $b, [double]$pad = 0) {
    if (-not $a -or -not $b) { return $false }
    return ($a.x -lt ($b.x + $b.w + $pad) -and ($a.x + $a.w + $pad) -gt $b.x -and $a.y -lt ($b.y + $b.h + $pad) -and ($a.y + $a.h + $pad) -gt $b.y)
}
# default spots for the optional widgets (kept clear of the other visible widgets)
function Set-WidgetDefaultPosition([string]$key) {
    try {
        $w = switch ($key) {
            'weather'  { $script:weatherWin }
            'calendar' { $script:calendarWin }
            'focus'    { $script:focusWin }
            'notes'    { $script:notesWin }
            default    { $null }
        }
        if (-not $w) { return }
        $dockTop = $screenY + $screenH - 86
        $rectClock = $null
        if ($script:clockWin -and $script:clockWin.IsVisible) {
            $rectClock = @{ x = $script:clockWin.Left; y = $script:clockWin.Top; w = $script:clockWin.ActualWidth; h = $script:clockWin.ActualHeight }
        }
        $rectMusic = $null
        if ($script:musicWin -and $script:musicWin.IsVisible) {
            $rectMusic = @{ x = $script:musicWin.Left; y = $script:musicWin.Top; w = $script:musicWin.ActualWidth; h = $script:musicWin.ActualHeight }
        }
        $rectHud = $null
        if ($script:hudWin -and $script:hudWin.IsVisible) {
            $rectHud = @{ x = $script:hudWin.Left; y = $script:hudWin.Top; w = $script:hudWin.ActualWidth; h = $script:hudWin.ActualHeight }
        }
        $rectDock = @{ x = $screenX; y = $dockTop; w = $screenW; h = 86 }
        switch ($key) {
            'calendar' {
                # prefer the free space at the top centre; if the clock sits there, drop below it
                $x = $screenX + (($screenW - $w.ActualWidth) / 2)
                $y = $screenY + 14
                $cand = @{ x = $x; y = $y; w = $w.ActualWidth; h = $w.ActualHeight }
                if ((Test-RectOverlap $cand $rectClock 8) -or (Test-RectOverlap $cand $rectMusic 8)) {
                    if ($rectClock) { $y = $rectClock.y + $rectClock.h + 10 }
                    elseif ($rectMusic) { $y = $rectMusic.y + $rectMusic.h + 10 }
                }
                if ($y -gt ($dockTop - $w.ActualHeight)) { $y = $dockTop - $w.ActualHeight }
                if ($y -lt ($screenY + 14)) { $y = $screenY + 14 }
                $w.Left = [double]$x
                $w.Top = [double]$y
            }
            'focus' {
                # under the system HUD, on the left edge
                $top = if ($rectHud) { $rectHud.y + $rectHud.h + 14 } else { $screenY + 400 }
                if ($top -gt ($dockTop - $w.ActualHeight)) { $top = $dockTop - $w.ActualHeight }
                if ($top -lt ($screenY + 14)) { $top = $screenY + 14 }
                $w.Left = [double]($screenX + 16)
                $w.Top = [double]$top
            }
            'weather' {
                $x = $screenX + $screenW - $w.ActualWidth - 16
                $top = if ($rectMusic) { $rectMusic.y + $rectMusic.h + 12 } else { $screenY + 392 }
                if ($script:notesWin -and $script:notesWin.IsVisible) {
                    $x = $screenX + (($screenW - $w.ActualWidth) / 2)
                    $top = if ($script:clockWin -and $script:clockWin.IsVisible) { $script:clockWin.Top + $script:clockWin.ActualHeight + 12 } else { $screenY + 120 }
                }
                if ($top -gt ($dockTop - $w.ActualHeight)) { $top = $dockTop - $w.ActualHeight }
                if ($top -lt ($screenY + 14)) { $top = $screenY + 14 }
                $w.Left = [double]$x
                $w.Top = [double]$top
            }
            'notes' {
                # under the calendar in the centre; otherwise under the music card on the right
                $x = $screenX + (($screenW - $w.ActualWidth) / 2)
                $top = $screenY + 392
                if ($script:calendarWin -and $script:calendarWin.IsVisible) { $top = $script:calendarWin.Top + $script:calendarWin.ActualHeight + 12 }
                $cand = @{ x = $x; y = $top; w = $w.ActualWidth; h = $w.ActualHeight }
                $blocked = (Test-RectOverlap $cand $rectClock 8) -or (Test-RectOverlap $cand $rectMusic 8) -or (Test-RectOverlap $cand $rectHud 8) -or (Test-RectOverlap $cand $rectDock 8)
                if ($blocked) {
                    $x = $screenX + $screenW - $w.ActualWidth - 16
                    $top = if ($rectMusic) { $rectMusic.y + $rectMusic.h + 12 } else { $screenY + 392 }
                }
                if ($top -gt ($dockTop - $w.ActualHeight)) { $top = $dockTop - $w.ActualHeight }
                if ($top -lt ($screenY + 14)) { $top = $screenY + 14 }
                $w.Left = [double]$x
                $w.Top = [double]$top
            }
        }
    } catch { }
}
function Reset-CalendarPosition {
    try {
        if ($script:cfg.calendar) { Set-Cfg $script:cfg.calendar 'x' $null; Set-Cfg $script:cfg.calendar 'y' $null }
        Save-Config
        if ($script:calendarWin -and $script:calendarWin.IsVisible) { Set-WidgetDefaultPosition 'calendar' }
    } catch { }
}
function Reset-FocusPosition {
    try {
        if ($script:cfg.focus) { Set-Cfg $script:cfg.focus 'x' $null; Set-Cfg $script:cfg.focus 'y' $null }
        Save-Config
        if ($script:focusWin -and $script:focusWin.IsVisible) { Set-WidgetDefaultPosition 'focus' }
    } catch { }
}
function Reset-NotesPosition {
    try {
        if ($script:cfg.notes) { Set-Cfg $script:cfg.notes 'x' $null; Set-Cfg $script:cfg.notes 'y' $null }
        if ($script:cfg.weather) { Set-Cfg $script:cfg.weather 'x' $null; Set-Cfg $script:cfg.weather 'y' $null }
        Save-Config
        if ($script:notesWin -and $script:notesWin.IsVisible) { Set-WidgetDefaultPosition 'notes' }
        if ($script:weatherWin -and $script:weatherWin.IsVisible) { Set-WidgetDefaultPosition 'weather' }
    } catch { }
}
function Reset-WidgetPositions {
    try {
        if ($script:cfg.hud) { Set-Cfg $script:cfg.hud 'x' $null; Set-Cfg $script:cfg.hud 'y' $null }
        if ($script:cfg.music) { Set-Cfg $script:cfg.music 'x' $null; Set-Cfg $script:cfg.music 'y' $null }
        if ($script:cfg.clock) { Set-Cfg $script:cfg.clock 'x' $null; Set-Cfg $script:cfg.clock 'y' $null }
        if ($script:cfg.calendar) { Set-Cfg $script:cfg.calendar 'x' $null; Set-Cfg $script:cfg.calendar 'y' $null }
        if ($script:cfg.focus) { Set-Cfg $script:cfg.focus 'x' $null; Set-Cfg $script:cfg.focus 'y' $null }
        if ($script:cfg.notes) { Set-Cfg $script:cfg.notes 'x' $null; Set-Cfg $script:cfg.notes 'y' $null }
        if ($script:cfg.weather) { Set-Cfg $script:cfg.weather 'x' $null; Set-Cfg $script:cfg.weather 'y' $null }
        Save-Config
        if ($script:hudWin -and $script:hudWin.IsVisible) {
            if ([string]$script:cfg.hud.side -eq 'right') { $script:hudWin.Left = [double]($screenX + $screenW - $script:hudWin.ActualWidth - 20) }
            else { $script:hudWin.Left = [double]($screenX + 16) }
            $script:hudWin.Top = [double]($screenY + 14)
        }
        if ($script:dockWin -and $script:dockWin.IsVisible) {
            $script:dockWin.Left = [double]($screenX + (($screenW - $script:dockWin.ActualWidth) / 2))
            $script:dockWin.Top = [double]($screenY + $screenH - $script:dockWin.ActualHeight - 10)
        }
        if ($script:musicWin -and $script:musicWin.IsVisible) {
            $script:musicWin.Left = [double]($screenX + $screenW - $script:musicWin.ActualWidth - 16)
            $script:musicWin.Top = [double]($screenY + 14)
        }
        if ($script:clockWin -and $script:clockWin.IsVisible) {
            $script:clockWin.Left = [double]($screenX + (($screenW - $script:clockWin.ActualWidth) / 2))
            $script:clockWin.Top = [double]($screenY + 14)
        }
        if ($script:calendarWin -and $script:calendarWin.IsVisible) { Set-WidgetDefaultPosition 'calendar' }
        if ($script:focusWin -and $script:focusWin.IsVisible) { Set-WidgetDefaultPosition 'focus' }
        if ($script:notesWin -and $script:notesWin.IsVisible) { Set-WidgetDefaultPosition 'notes' }
        if ($script:weatherWin -and $script:weatherWin.IsVisible) { Set-WidgetDefaultPosition 'weather' }
    } catch { }
}

# show the optional widgets
if ($script:calendarWin) {
    $script:calendarWin.Show()
    $script:calendarWin.UpdateLayout()
    $sxCal = Get-Cfg $cfg.calendar 'x'; $syCal = Get-Cfg $cfg.calendar 'y'
    if ($null -ne $sxCal -and $null -ne $syCal) {
        $script:calendarWin.Left = [double]$sxCal
        $script:calendarWin.Top = [double]$syCal
    } else {
        Set-WidgetDefaultPosition 'calendar'
    }
    try { $script:calTimer.Start() } catch { }
}
if ($script:focusWin) {
    $script:focusWin.Show()
    $script:focusWin.UpdateLayout()
    $sxF = Get-Cfg $cfg.focus 'x'; $syF = Get-Cfg $cfg.focus 'y'
    if ($null -ne $sxF -and $null -ne $syF) {
        $script:focusWin.Left = [double]$sxF
        $script:focusWin.Top = [double]$syF
    } else {
        Set-WidgetDefaultPosition 'focus'
    }
    try { $script:focusTimer.Start() } catch { }
}
if ($script:notesWin) {
    $script:notesWin.Show()
    $script:notesWin.UpdateLayout()
    $sxN = Get-Cfg $cfg.notes 'x'; $syN = Get-Cfg $cfg.notes 'y'
    if ($null -ne $sxN -and $null -ne $syN) {
        $script:notesWin.Left = [double]$sxN
        $script:notesWin.Top = [double]$syN
    } else {
        Set-WidgetDefaultPosition 'notes'
    }
    Update-NotesPlaceholder
}
if ($script:weatherWin) {
    $script:weatherWin.Show()
    $script:weatherWin.UpdateLayout()
    $sxW = Get-Cfg $cfg.weather 'x'; $syW = Get-Cfg $cfg.weather 'y'
    if ($null -ne $sxW -and $null -ne $syW) {
        $script:weatherWin.Left = [double]$sxW
        $script:weatherWin.Top = [double]$syW
    } else {
        Set-WidgetDefaultPosition 'weather'
    }
    Update-AllWeatherData
    try { $script:weatherTimer.Start() } catch { }
}

# restore the saved show / hide state (a hidden widget can always be shown again from the tray)
foreach ($key in $script:widgetKeys) {
    try {
        if (-not (Test-WidgetWanted $key)) {
            $w = Get-WidgetWindow $key
            if ($w) { $w.Hide() }
        }
    } catch { }
}

# optional: open the widgets manager right away
if ($WidgetsManager) {
    try { Show-WidgetManager } catch { Write-WidgetError $_ 'widgets manager startup' }
}

# ---------------- move the widgets by dragging them with the mouse ----------------
$script:dragStates = @{}
function Save-WidgetPos([string]$key, [double]$x, [double]$y) {
    try {
        if ($key -eq 'hud') { Set-Cfg $script:cfg.hud 'x' ([double]$x); Set-Cfg $script:cfg.hud 'y' ([double]$y) }
        elseif ($key -eq 'music') { Set-Cfg $script:cfg.music 'x' ([double]$x); Set-Cfg $script:cfg.music 'y' ([double]$y) }
        elseif ($key -eq 'clock') { Set-Cfg $script:cfg.clock 'x' ([double]$x); Set-Cfg $script:cfg.clock 'y' ([double]$y) }
        elseif ($key -eq 'calendar') { Set-Cfg $script:cfg.calendar 'x' ([double]$x); Set-Cfg $script:cfg.calendar 'y' ([double]$y) }
        elseif ($key -eq 'focus') { Set-Cfg $script:cfg.focus 'x' ([double]$x); Set-Cfg $script:cfg.focus 'y' ([double]$y) }
        elseif ($key -eq 'notes') { Set-Cfg $script:cfg.notes 'x' ([double]$x); Set-Cfg $script:cfg.notes 'y' ([double]$y) }
        Save-Config
    } catch { }
}
function Enable-WidgetDrag($w, [string]$key, $handle = $null, $exclude = $null) {
    if (-not $handle) { $handle = $w }
    $st = @{ on = $false; moved = $false; sx = 0.0; sy = 0.0; wx = 0.0; wy = 0.0; dx = 1.0; dy = 1.0 }
    $down = { param($s, $e)
        try {
            $sec = Get-WidgetSection $key
            if ($sec -and [bool](Get-Cfg $sec 'locked')) { return }
            if ($exclude) {
                $cur = $e.OriginalSource
                while ($cur -and $cur -ne $w) {
                    if ($cur -eq $exclude) { return }
                    if ($cur -is [System.Windows.Controls.TextBox] -or $cur -is [System.Windows.Controls.Primitives.TextBoxBase]) { return }
                    if ($cur -is [System.Windows.FrameworkElement] -and $cur.Parent) { $cur = $cur.Parent }
                    elseif ($cur -is [System.Windows.Media.Visual]) { $cur = [System.Windows.Media.VisualTreeHelper]::GetParent($cur) }
                    else { break }
                }
            }
            $p = [System.Windows.Forms.Cursor]::Position
            $dpi = [System.Windows.Media.VisualTreeHelper]::GetDpi($w)
            $st.on = $true; $st.moved = $false
            $st.dx = $dpi.DpiScaleX; $st.dy = $dpi.DpiScaleY
            $st.sx = $p.X / $st.dx; $st.sy = $p.Y / $st.dy
            $st.wx = $w.Left; $st.wy = $w.Top
        } catch { }
    }.GetNewClosure()
    $move = { param($s, $e)
        try {
            if (-not $st.on) { return }
            $p = [System.Windows.Forms.Cursor]::Position
            $dx = ($p.X / $st.dx) - $st.sx
            $dy = ($p.Y / $st.dy) - $st.sy
            if (-not $st.moved) {
                if (([math]::Abs($dx) + [math]::Abs($dy)) -lt 4) { return }
                $st.moved = $true
                [void]$w.CaptureMouse()
            }
            $w.Left = $st.wx + $dx
            $w.Top = $st.wy + $dy
        } catch { }
    }.GetNewClosure()
    $up = { param($s, $e)
        try {
            $wasMoved = $st.moved
            $st.on = $false; $st.moved = $false
            if ([System.Windows.Input.Mouse]::Captured -eq $w) { $w.ReleaseMouseCapture() }
            if ($wasMoved) { Save-WidgetPos $key $w.Left $w.Top }
        } catch { }
    }.GetNewClosure()
    $w.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent, [System.Windows.Input.MouseButtonEventHandler]$down, $true)
    $w.AddHandler([System.Windows.UIElement]::MouseMoveEvent, [System.Windows.Input.MouseEventHandler]$move, $true)
    $w.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent, [System.Windows.Input.MouseButtonEventHandler]$up, $true)
}
if ($hudWin) { Enable-WidgetDrag $hudWin 'hud' }
if ($musicWin) { Enable-WidgetDrag $musicWin 'music' }
if ($clockWin) { Enable-WidgetDrag $clockWin 'clock' }
if ($script:calendarWin) { Enable-WidgetDrag $script:calendarWin 'calendar' }
if ($script:focusWin) { Enable-WidgetDrag $script:focusWin 'focus' }
if ($script:notesWin) { Enable-WidgetDrag $script:notesWin 'notes' $null $script:notesCtl.box }
if ($script:weatherWin) { Enable-WidgetDrag $script:weatherWin 'weather' }

# ---------------- dock auto-hide (reveal when the mouse reaches the bottom) ----------------
$script:dockAutoTimer = $null
function Update-DockAutoHide {
    if (-not $script:dockWin) { return }
    try {
        $cur = New-Object UDWin+POINT
        [void][UDWin]::GetCursorPos([ref]$cur)
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($script:dockWin)).Handle
        $r = New-Object UDWin+RECT
        [void][UDWin]::GetWindowRect($h, [ref]$r)
        $physH = [UDWin]::GetSystemMetrics(1)
        $physW = [UDWin]::GetSystemMetrics(0)

        $overDock = ($cur.X -ge ($r.L - 4) -and $cur.X -le ($r.R + 4) -and $cur.Y -ge ($r.T - 30) -and $cur.Y -le ($r.B + 8))
        $atBottomEdge = ($cur.Y -ge ($physH - 3))
        $centerBand = ($cur.X -ge [int]($physW * 0.12) -and $cur.X -le [int]($physW * 0.88))

        if ($overDock -or ($atBottomEdge -and $centerBand)) {
            if (-not $script:dockWin.IsVisible) {
                $script:dockWin.Show()
                Set-DockPosition
            }
        } else {
            if ($script:dockWin.IsVisible) { $script:dockWin.Hide() }
        }
    } catch { }
}
function Set-DockAutoHide([bool]$on) {
    if ($on) {
        if (-not $script:dockAutoTimer) {
            $t = New-Object System.Windows.Threading.DispatcherTimer
            $t.Interval = [TimeSpan]::FromMilliseconds(220)
            $t.Add_Tick({ Update-DockAutoHide })
            $script:dockAutoTimer = $t
        }
        $script:dockAutoTimer.Start()
    } else {
        if ($script:dockAutoTimer) { $script:dockAutoTimer.Stop() }
        if ($script:dockWin -and -not $script:dockWin.IsVisible) { $script:dockWin.Show() }
        Set-DockPosition
    }
}
function Toggle-DockAutoHide([bool]$on) {
    $script:cfg.dock.autohide = $on
    if ($on) { Set-Cfg $script:cfg.dock 'visible' $true }
    try { Save-Config } catch { }
    Set-DockAutoHide $on
    Update-WidgetManager
}

# tool-window / no-activate for the widgets: never a taskbar tab, never in Alt+Tab / Task View
function Set-WidgetWindowStyle($w, [switch]$Interactive) {
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($w)
        $h = $helper.Handle
        $ex = [UDWin]::GetWindowLong($h, [UDWin]::GWL_EXSTYLE)
        $ex = $ex -bor [UDWin]::WS_EX_TOOLWINDOW
        if (-not $Interactive) { $ex = $ex -bor [UDWin]::WS_EX_NOACTIVATE }
        [void][UDWin]::SetWindowLong($h, [UDWin]::GWL_EXSTYLE, $ex)
    } catch { }
}
if ($hudWin) { Set-WidgetWindowStyle $hudWin }
if ($dockWin) { Set-WidgetWindowStyle $dockWin }
if ($musicWin) { Set-WidgetWindowStyle $musicWin }
if ($clockWin) { Set-WidgetWindowStyle $clockWin }
if ($script:calendarWin) { Set-WidgetWindowStyle $script:calendarWin }
if ($script:focusWin) { Set-WidgetWindowStyle $script:focusWin }
# notes must accept the keyboard, so no WS_EX_NOACTIVATE on that one
if ($script:notesWin) { Set-WidgetWindowStyle $script:notesWin -Interactive }

# closing a widget must never kill it: hide it instead (the tray icon brings it back)
$script:exiting = $false
function Protect-WidgetWindow($w) {
    $w.Add_Closing({
        param($s, $e)
        if (-not $script:exiting) {
            $e.Cancel = $true
            try { $s.Hide() } catch { }
        }
    })
}
if ($hudWin) { Protect-WidgetWindow $hudWin }
if ($dockWin) { Protect-WidgetWindow $dockWin }
if ($musicWin) { Protect-WidgetWindow $musicWin }
if ($clockWin) { Protect-WidgetWindow $clockWin }
if ($script:calendarWin) { Protect-WidgetWindow $script:calendarWin }
if ($script:focusWin) { Protect-WidgetWindow $script:focusWin }
if ($script:notesWin) { Protect-WidgetWindow $script:notesWin }

# dock auto-hide, if enabled in the config and the dock is not hidden
if ($dockWin -and $cfg.dock.autohide -and (Test-WidgetWanted 'dock')) { Set-DockAutoHide $true }

# ---------------- background metrics collector ----------------
$collectorSrc = @'
param($state, $nativeSrc)
Add-Type -TypeDefinition $nativeSrc -ReferencedAssemblies 'System.Drawing' -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Net.NetworkInformation

function Get-CpuTimes {
    $idle = New-Object UDWin+FILETIME; $kernel = New-Object UDWin+FILETIME; $user = New-Object UDWin+FILETIME
    [void][UDWin]::GetSystemTimes([ref]$idle, [ref]$kernel, [ref]$user)
    $i = ([uint64]$idle.High -shl 32) + $idle.Low
    $k = ([uint64]$kernel.High -shl 32) + $kernel.Low
    $u = ([uint64]$user.High -shl 32) + $user.Low
    return @{ idle = $i; total = ($k + $u) }
}

$prevCpu = Get-CpuTimes
$prevTick = Get-Date
$prevRx = 0L; $prevTx = 0L
$prevNetTick = Get-Date
$lastDiskTick = (Get-Date).AddSeconds(-120)
$lastWifiTick = (Get-Date).AddSeconds(-120)
$lastIpTick = (Get-Date).AddSeconds(-120)

function Get-LocalIPv4 {
    $best = ''
    foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($ni.OperationalStatus -ne 'Up') { continue }
        if ($ni.NetworkInterfaceType -eq 'Loopback') { continue }
        $desc = [string]$ni.Description + ' ' + [string]$ni.Name
        if ($desc -match 'VMware|VirtualBox|Hyper-V|vEthernet|Loopback|TAP-|Bluetooth|WAN Miniport|Virtual Adapter') { continue }
        $hasGw = $false
        try { $hasGw = ($ni.GetIPProperties().GatewayAddresses.Count -gt 0) } catch { }
        foreach ($ua in $ni.GetIPProperties().UnicastAddresses) {
            if ($ua.Address.AddressFamily -ne 'InterNetwork') { continue }
            $a = $ua.Address.IPAddressToString
            if ($a -match '^169\.254\.' -or $a -eq '127.0.0.1') { continue }
            if ($hasGw) { return $a }
            if (-not $best) { $best = $a }
        }
    }
    return $best
}

while ($true) {
    Start-Sleep -Milliseconds 1000
    try {
        # CPU
        $now = Get-CpuTimes
        $dIdle = $now.idle - $prevCpu.idle
        $dTot  = $now.total - $prevCpu.total
        if ($dTot -gt 0) { $state.cpu = [math]::Round((1 - ($dIdle / $dTot)) * 100, 1) }
        $prevCpu = $now

        # RAM
        $ms = New-Object UDWin+MEMORYSTATUSEX
        $ms.dwLength = [System.Runtime.InteropServices.Marshal]::SizeOf($ms)
        [void][UDWin]::GlobalMemoryStatusEx([ref]$ms)
        $state.ramPct = [double]$ms.dwMemoryLoad
        $state.ramTotalGb = [math]::Round($ms.ullTotalPhys / 1GB, 1)
        $state.ramUsedGb = [math]::Round(($ms.ullTotalPhys - $ms.ullAvailPhys) / 1GB, 1)

        # Network throughput
        $rx = 0L; $tx = 0L; $names = @(); $wifi = $false
        foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($ni.OperationalStatus -ne 'Up') { continue }
            if ($ni.NetworkInterfaceType -eq 'Loopback') { continue }
            $st = $ni.GetIPv4Statistics()
            $rx += $st.BytesReceived
            $tx += $st.BytesSent
            $names += $ni.Name
            if ($ni.NetworkInterfaceType -eq 'Wireless80211') { $wifi = $true }
        }
        $nowT = Get-Date
        $dt = ($nowT - $prevNetTick).TotalSeconds
        if ($dt -gt 0) {
            if ($prevRx -gt 0) {
                $state.rxBps = [math]::Round(($rx - $prevRx) / $dt, 0)
                $state.txBps = [math]::Round(($tx - $prevTx) / $dt, 0)
            }
            $prevRx = $rx; $prevTx = $tx
            $prevNetTick = $nowT
        }
        $state.adapters = ($names -join ', ')
        if ($wifi) { $state.adapters = 'Wi-Fi' }

        $samples = @($state.samplesDown)
        $samples += [double]$state.rxBps
        if ($samples.Count -gt 48) { $samples = $samples[($samples.Count - 48)..($samples.Count - 1)] }
        $state.samplesDown = $samples
        $samplesU = @($state.samplesUp)
        $samplesU += [double]$state.txBps
        if ($samplesU.Count -gt 48) { $samplesU = $samplesU[($samplesU.Count - 48)..($samplesU.Count - 1)] }
        $state.samplesUp = $samplesU

        # Disk (every 60 s)
        if (($nowT - $lastDiskTick).TotalSeconds -gt 60) {
            $d = Get-PSDrive -Name C -ErrorAction SilentlyContinue
            if ($d) {
                $state.diskFreeGb = [math]::Round($d.Free / 1GB, 1)
                $state.diskTotalGb = [math]::Round(($d.Free + $d.Used) / 1GB, 1)
            }
            $lastDiskTick = $nowT
        }

        # Local IPv4 (every 15 s)
        if (($nowT - $lastIpTick).TotalSeconds -gt 15) {
            $lip = Get-LocalIPv4
            if ($lip) { $state.localIp = $lip }
            $lastIpTick = $nowT
        }

        # Ping (every 4 s)
        if (([int](Get-Date).Second % 4) -eq 0) {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $ok = $false
            foreach ($target in @('1.1.1.1', '8.8.8.8')) {
                try {
                    $reply = $ping.Send($target, 1200)
                    if ($reply.Status -eq 'Success') { $state.pingMs = $reply.RoundtripTime; $state.online = $true; $ok = $true; break }
                } catch { }
            }
            if (-not $ok) { $state.online = $false; $state.pingMs = -1 }
            $ping.Dispose()

            if ($state.adapters -eq 'Wi-Fi' -and ($nowT - $lastWifiTick).TotalSeconds -gt 20) {
                try {
                    $out = & netsh wlan show interfaces 2>$null | Out-String
                    $m = [regex]::Match($out, 'Signal\s*:\s*(\d+)%')
                    if ($m.Success) { $state.wifiSignal = [int]$m.Groups[1].Value }
                } catch { }
                $lastWifiTick = $nowT
            }
        }
    } catch { }
}
'@

$ps = [powershell]::Create()
[void]$ps.AddScript($collectorSrc).AddArgument($state).AddArgument($native)
$collector = $ps.BeginInvoke()

# ---------------- public ip (own runspace: the HTTP call must not stall the metrics loop) ----------------
$ipSrc = @'
param($state)
while ($true) {
    $ip = $null
    foreach ($u in @('https://api.ipify.org', 'https://ifconfig.me/ip', 'https://ipinfo.io/ip')) {
        try {
            $r = Invoke-RestMethod -Uri $u -TimeoutSec 8 -Headers @{ 'User-Agent' = 'Mozilla/5.0' }
            $s = ([string]$r).Trim()
            if ($s -match '^\d{1,3}(\.\d{1,3}){3}$') { $ip = $s; break }
        } catch { }
    }
    if ($ip) { $state.publicIp = $ip }
    Start-Sleep -Seconds 300
}
'@
$psIp = [powershell]::Create()
[void]$psIp.AddScript($ipSrc).AddArgument($state)
$ipTask = $psIp.BeginInvoke()

# ---------------- render timer ----------------
function Format-Speed([double]$bps) {
    if ($bps -ge 1MB) { return ('{0:N1} MB/s' -f ($bps / 1MB)) }
    if ($bps -ge 1KB) { return ('{0:N0} KB/s' -f ($bps / 1KB)) }
    return ('{0:N0} B/s' -f $bps)
}
function Severity([double]$pct) {
    if ($pct -ge 90) { return '#F87171' }
    if ($pct -ge 75) { return '#FBBF24' }
    return '#93C5FD'
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(900)
$timer.Add_Tick({
    try {
        if ($hudWin -and $hudCtl.Count -gt 0) {
            $hudCtl['NET'].value.Text = $(if ($state.online) { 'online' } else { 'offline' })
            $hudCtl['NET'].value.Foreground = Br $(if ($state.online) { '#4ADE80' } else { '#F87171' })
            if ($hudCtl['NET'].dot) { $hudCtl['NET'].dot.Fill = Br $(if ($state.online) { '#4ADE80' } else { '#F87171' }) }

            $hudCtl['CPU'].value.Text = ('{0:N0}%' -f $state.cpu)
            $hudCtl['CPU'].value.Foreground = Br (Severity $state.cpu)
            $hudCtl['RAM'].value.Text = ('{0:N0}%' -f $state.ramPct)
            $hudCtl['RAM'].value.Foreground = Br (Severity $state.ramPct)
            $hudCtl['DISK'].value.Text = ('{0:N0} GB' -f $state.diskFreeGb)
            $hudCtl['DOWN'].value.Text = Format-Speed $state.rxBps
            $hudCtl['UP'].value.Text = Format-Speed $state.txBps

            # progress bars
            foreach ($k in @('CPU', 'RAM')) {
                $ctl = $hudCtl[$k]
                if ($ctl -and $ctl.bar) {
                    $pct = [double]$(if ($k -eq 'CPU') { $state.cpu } else { $state.ramPct })
                    if ($pct -lt 0) { $pct = 0 }; if ($pct -gt 100) { $pct = 100 }
                    $ctl.bar.Width = [double]($ctl.barW * ($pct / 100.0))
                    $ctl.bar.Background = Br $(if ($pct -ge 90) { '#F87171' } elseif ($pct -ge 75) { '#FBBF24' } else { $ctl.barColor })
                }
            }
            $dctl = $hudCtl['DISK']
            if ($dctl -and $dctl.bar -and $state.diskTotalGb -gt 0) {
                $pct = [double](100.0 * ($state.diskTotalGb - $state.diskFreeGb) / $state.diskTotalGb)
                if ($pct -lt 0) { $pct = 0 }; if ($pct -gt 100) { $pct = 100 }
                $dctl.bar.Width = [double]($dctl.barW * ($pct / 100.0))
                $dctl.bar.Background = Br $(if ($pct -ge 90) { '#F87171' } elseif ($pct -ge 75) { '#FBBF24' } else { $dctl.barColor })
            }

            # addresses
            if ($hudCtl['LIP']) {
                $txt = $(if ($state.localIp) { [string]$state.localIp } else { '--' })
                if ($hudCtl['LIP'].value.Text -ne 'copied') { $hudCtl['LIP'].value.Text = $txt }
            }
            if ($hudCtl['PIP']) {
                $txt = $(if ($state.publicIp) { [string]$state.publicIp } else { 'getting…' })
                if ([bool]$script:cfg.hud.maskIp -and $state.publicIp) { $txt = '•••.•••.•••.•••' }
                if ($hudCtl['PIP'].value.Text -ne 'copied') { $hudCtl['PIP'].value.Text = $txt }
            }

            # clock / uptime
            if ($hudCtl['CLOCK'] -and $hudCtl['CLOCK'].value) { $hudCtl['CLOCK'].value.Text = (Get-Date).ToString('ddd HH:mm') }
            if ($hudCtl['UPTIME'] -and $hudCtl['UPTIME'].value) {
                if (-not $script:bootTime) {
                    try { $script:bootTime = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime } catch { }
                }
                if ($script:bootTime) {
                    $up = (Get-Date) - $script:bootTime
                    $hudCtl['UPTIME'].value.Text = ('up {0}h {1:D2}m' -f [int]$up.TotalHours, $up.Minutes)
                }
            }
            if ($hudCtl['HEAD'] -and $hudCtl['HEAD'].dot) { $hudCtl['HEAD'].dot.Fill = Br $(if ($state.online) { '#4ADE80' } else { '#F87171' }) }
            if ($root) {
                $tip = @()
                $tip += 'MEMORY  {0:N1} / {1:N1} GB' -f $state.ramUsedGb, $state.ramTotalGb
                $tip += 'DISK    {0:N1} GB free of {1:N1} GB' -f $state.diskFreeGb, $state.diskTotalGb
                $tip += 'LINK    {0}' -f $(if ($state.adapters) { $state.adapters } else { '--' })
                $tip += 'LOCAL   {0}' -f $(if ($state.localIp) { $state.localIp } else { '--' })
                $tip += 'PUBLIC  {0}' -f $(if (-not $state.publicIp) { '--' } elseif ([bool]$script:cfg.hud.maskIp) { 'hidden' } else { $state.publicIp })
                $root.ToolTip = ($tip -join "`n")
            }

            if ($state.pingMs -ge 0) {
                $hudCtl['PING'].value.Text = ('{0:N0} ms' -f $state.pingMs)
                $pc = '#4ADE80'; if ($state.pingMs -gt 120) { $pc = '#F87171' } elseif ($state.pingMs -gt 50) { $pc = '#FBBF24' }
                $hudCtl['PING'].value.Foreground = Br $pc
            } else {
                $hudCtl['PING'].value.Text = '--'
            }
            $linkTxt = $state.adapters
            if ($state.wifiSignal -ge 0 -and $linkTxt -eq 'Wi-Fi') { $linkTxt = ('Wi-Fi {0}%' -f $state.wifiSignal) }
            $hudCtl['LINK'].value.Text = $(if ($linkTxt) { $linkTxt } else { '--' })

            $max = 1.0
            foreach ($s in @($state.samplesDown)) { if ($s -gt $max) { $max = $s } }
            foreach ($s in @($state.samplesUp)) { if ($s -gt $max) { $max = $s } }
            $w = [double]$hudInnerW; $h = 40.0
            $ptsD = New-Object System.Windows.Media.PointCollection
            $ptsU = New-Object System.Windows.Media.PointCollection
            $sd = @($state.samplesDown); $su = @($state.samplesUp)
            for ($i = 0; $i -lt $sd.Count; $i++) {
                $x = ($i / [math]::Max(1, ($sd.Count - 1))) * $w
                $y = $h - (($sd[$i] / $max) * ($h - 2)) - 1
                $ptsD.Add((New-Object System.Windows.Point($x, $y)))
            }
            for ($i = 0; $i -lt $su.Count; $i++) {
                $x = ($i / [math]::Max(1, ($su.Count - 1))) * $w
                $y = $h - (($su[$i] / $max) * ($h - 2)) - 1
                $ptsU.Add((New-Object System.Windows.Point($x, $y)))
            }
            $hudCtl['sparkDown'].Points = $ptsD
            $hudCtl['sparkUp'].Points = $ptsU
            if ($hudCtl['sparkArea'] -and $ptsD.Count -gt 1) {
                $pa = New-Object System.Windows.Media.PointCollection
                foreach ($p in $ptsD) { $pa.Add($p) }
                $pa.Add((New-Object System.Windows.Point($w, ($h + 2))))
                $pa.Add((New-Object System.Windows.Point(0, ($h + 2))))
                $hudCtl['sparkArea'].Points = $pa
            }
        }
        # widgets stay where the user put them (positions are handled on drag / reset only)
    } catch { }
})
$timer.Start()
$script:mainTimer = $timer
Apply-LowPower
Apply-Opacity
$script:fsTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:fsTimer.Interval = [TimeSpan]::FromSeconds(3)
$script:fsTimer.Add_Tick({ try { Update-FullscreenHide } catch { } })
$script:fsTimer.Start()

# ---------------- tray icon ----------------
$tray = New-Object System.Windows.Forms.NotifyIcon
$trayIcon = $null
try {
    # small brand mark: four rounded panes on a transparent background
    $tb = New-Object System.Drawing.Bitmap 32, 32
    $tg = [System.Drawing.Graphics]::FromImage($tb)
    $tg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $tg.Clear([System.Drawing.Color]::Transparent)
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $w1 = 13.0; $r1 = 2.6
    foreach ($pt in @(@(1, 1), @(16, 1), @(1, 16), @(16, 16))) {
        $gp.AddArc($pt[0], $pt[1], $r1 * 2, $r1 * 2, 180, 90)
        $gp.AddArc($pt[0] + $w1 - $r1 * 2, $pt[1], $r1 * 2, $r1 * 2, 270, 90)
        $gp.AddArc($pt[0] + $w1 - $r1 * 2, $pt[1] + $w1 - $r1 * 2, $r1 * 2, $r1 * 2, 0, 90)
        $gp.AddArc($pt[0], $pt[1] + $w1 - $r1 * 2, $r1 * 2, $r1 * 2, 90, 90)
        $gp.CloseFigure()
    }
    $tg.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#4CC2FF'))), $gp)
    $tg.Dispose()
    $trayIcon = [System.Drawing.Icon]::FromHandle($tb.GetHicon())
} catch { }
if (-not $trayIcon) { $trayIcon = [System.Drawing.SystemIcons]::Application }
$tray.Icon = $trayIcon
$tray.Text = 'UNLOCK DIGITAL — Widgets'
$tray.Visible = $true
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
function Add-TrayItem([string]$text, [scriptblock]$action, [bool]$checkable = $false, [bool]$checked = $false) {
    $it = New-Object System.Windows.Forms.ToolStripMenuItem($text)
    $it.CheckOnClick = $checkable
    $it.Checked = $checked
    # keep the scriptblock in Tag: a closure would lose $action after this function returns
    $it.Tag = $action
    $it.Add_Click({
        param($s, $e)
        try { if ($s.Tag) { & $s.Tag $s $e } } catch { Write-WidgetError $_ 'tray action' }
    })
    [void]$trayMenu.Items.Add($it)
    return $it
}
[void](Add-TrayItem 'Show all widgets' {
    try {
        foreach ($k in $script:widgetKeys) { Set-WidgetVisible $k $true -NoSave }
        Save-Config
        Update-WidgetManager
    } catch { Write-WidgetError $_ 'show all widgets' }
})
[void](Add-TrayItem 'Show / hide system HUD' { try { Set-WidgetVisible 'hud' (-not (Test-WidgetShown 'hud')) } catch { } })
[void](Add-TrayItem 'Show / hide dock' { try { Set-WidgetVisible 'dock' (-not (Test-WidgetShown 'dock')) } catch { } })
[void](Add-TrayItem 'Show / hide music widget' { try { Set-WidgetVisible 'music' (-not (Test-WidgetShown 'music')) } catch { } })
[void](Add-TrayItem 'Show / hide clock widget' { try { Set-WidgetVisible 'clock' (-not (Test-WidgetShown 'clock')) } catch { } })
[void](Add-TrayItem 'Show / hide calendar' { try { Set-WidgetVisible 'calendar' (-not (Test-WidgetShown 'calendar')) } catch { } })
[void](Add-TrayItem 'Show / hide focus timer' { try { Set-WidgetVisible 'focus' (-not (Test-WidgetShown 'focus')) } catch { } })
[void](Add-TrayItem 'Open quick notes' { try { Set-WidgetVisible 'notes' $true; Show-NotesWidget } catch { Write-WidgetError $_ 'tray notes' } })
[void](Add-TrayItem 'Start a focus session' {
    try {
        if ($script:focusWin) {
            $script:focusWin.Show()
            if (-not $script:focusCtl.running) {
                if ([string]$script:focusCtl.mode -ne 'work') { Set-FocusMode 'work' $false }
                Start-PauseFocus
            }
        }
    } catch { Write-WidgetError $_ 'tray focus' }
})
[void](Add-TrayItem 'Open Anghami (web)' { Start-Process 'https://www.anghami.com' })
[void](Add-TrayItem 'Open Spotify (web)' { Start-Process 'https://open.spotify.com' })
[void](Add-TrayItem 'Manage widgets…' { try { Show-WidgetManager } catch { Write-WidgetError $_ 'tray manage widgets' } })
[void](Add-TrayItem 'Manage dock apps…' { try { Show-AppsManager } catch { Write-WidgetError $_ 'tray manage apps' } })
[void](Add-TrayItem 'Reset widget positions' { Reset-WidgetPositions })
$tAuto = Add-TrayItem 'Dock: auto-hide (show at mouse bottom edge)' { param($s, $e) Toggle-DockAutoHide $s.Checked } $true ([bool]$cfg.dock.autohide)
$tOpen = Add-TrayItem 'Open apps config file' { Start-Process notepad.exe -ArgumentList $script:cfgJson.Path }
$tTop = Add-TrayItem 'Keep widgets on top' {
    param($s, $e)
    $v = [bool]$s.Checked
    foreach ($k in $script:widgetKeys) {
        $sec = Get-WidgetSection $k
        if ($sec) { Set-Cfg $sec 'topmost' $v }
        $w = Get-WidgetWindow $k
        if ($w) { $w.Topmost = $v }
    }
    Save-Config
    Update-WidgetManager
} $true ([bool]$cfg.hud.topmost)
[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void](Add-TrayItem 'Restart widgets' {
    $script:exiting = $true
    $exe = (Get-Process -Id $PID).Path
    Start-Process $exe -ArgumentList @('-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") -WindowStyle Hidden
    $script:tray.Visible = $false
    [System.Windows.Application]::Current.Dispatcher.InvokeShutdown()
})
[void](Add-TrayItem 'Exit' {
    $script:exiting = $true
    try { Save-Notes } catch { }
    $script:tray.Visible = $false
    $script:tray.Dispose()
    [System.Windows.Application]::Current.Dispatcher.InvokeShutdown()
})
$tray.ContextMenuStrip = $trayMenu
$tray.Add_MouseDoubleClick({ if ($hudWin) { if ($hudWin.IsVisible) { $hudWin.Hide() } else { $hudWin.Show() } } })

# ---------------- preview render (verification) ----------------
if ($Preview) {
    $timer.Start()
    function Pump([int]$seconds) {
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        $pt = New-Object System.Windows.Threading.DispatcherTimer
        $pt.Interval = [TimeSpan]::FromSeconds($seconds)
        $pt.Tag = $frame
        $pt.Add_Tick({
            param($s, $e)
            try { $s.Stop(); $s.Tag.Continue = $false } catch { }
        })
        $pt.Start()
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    }
    Pump 5
    function Save-Render($visual, [double]$w, [double]$h, [string]$file) {
        $dv = New-Object System.Windows.Media.DrawingVisual
        $dc = $dv.RenderOpen()
        $dc.DrawRectangle((Br '#0B0F18'), $null, (New-Object System.Windows.Rect(0, 0, $w, $h)))
        $dc.Close()
        $bg = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$w, [int]$h, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32))
        $bg.Render($dv)
        $fg = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$w, [int]$h, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32))
        $fg.Render($visual)
        $dv2 = New-Object System.Windows.Media.DrawingVisual
        $dc2 = $dv2.RenderOpen()
        $dc2.DrawImage($bg, (New-Object System.Windows.Rect(0, 0, $w, $h)))
        $dc2.DrawImage($fg, (New-Object System.Windows.Rect(0, 0, $w, $h)))
        $dc2.Close()
        $final = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$w, [int]$h, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32))
        $final.Render($dv2)
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($final))
        $fs = [System.IO.File]::Create($file)
        $enc.Save($fs)
        $fs.Close()
    }
    if ($hudWin) { Save-Render $hudWin.Content ([math]::Ceiling($hudWin.ActualWidth) + 40) ([math]::Ceiling($hudWin.ActualHeight) + 40) (Join-Path $PreviewDir 'hud-preview.png') }
    if ($dockWin) { Save-Render $dockWin.Content ([math]::Ceiling($dockWin.ActualWidth) + 80) ([math]::Ceiling($dockWin.ActualHeight) + 80) (Join-Path $PreviewDir 'dock-preview.png') }
if ($musicWin) { Save-Render $musicWin.Content ([math]::Ceiling($musicWin.ActualWidth) + 40) ([math]::Ceiling($musicWin.ActualHeight) + 40) (Join-Path $PreviewDir 'music-preview.png') }
    if ($clockWin) { Save-Render $clockWin.Content ([math]::Ceiling($clockWin.ActualWidth) + 40) ([math]::Ceiling($clockWin.ActualHeight) + 40) (Join-Path $PreviewDir 'clock-preview.png') }
    if ($script:calendarWin) { Save-Render $script:calendarWin.Content ([math]::Ceiling($script:calendarWin.ActualWidth) + 40) ([math]::Ceiling($script:calendarWin.ActualHeight) + 40) (Join-Path $PreviewDir 'calendar-preview.png') }
    if ($script:focusWin) { Save-Render $script:focusWin.Content ([math]::Ceiling($script:focusWin.ActualWidth) + 40) ([math]::Ceiling($script:focusWin.ActualHeight) + 40) (Join-Path $PreviewDir 'focus-preview.png') }
    if ($script:notesWin) { Save-Render $script:notesWin.Content ([math]::Ceiling($script:notesWin.ActualWidth) + 40) ([math]::Ceiling($script:notesWin.ActualHeight) + 40) (Join-Path $PreviewDir 'notes-preview.png') }
    if ($script:weatherWin) { Save-Render $script:weatherWin.Content ([math]::Ceiling($script:weatherWin.ActualWidth) + 40) ([math]::Ceiling($script:weatherWin.ActualHeight) + 40) (Join-Path $PreviewDir 'weather-preview.png') }
    if ($dockWin) {
        Show-AppsManager
        Pump 3
        if ($script:mgr) { Save-Render $script:mgr.win.Content ([math]::Ceiling($script:mgr.win.ActualWidth) + 40) ([math]::Ceiling($script:mgr.win.ActualHeight) + 40) (Join-Path $PreviewDir 'manager-preview.png') }
        Show-WidgetManager
        Pump 3
        if ($script:wmg) { Save-Render $script:wmg.win.Content ([math]::Ceiling($script:wmg.win.ActualWidth) + 40) ([math]::Ceiling($script:wmg.win.ActualHeight) + 40) (Join-Path $PreviewDir 'widgets-manager-preview.png') }
    }
    Write-Output 'previews saved'
    $tray.Visible = $false
    $tray.Dispose()
    $collector.AsyncWaitHandle.Close()
    exit
}

# ---------------- run ----------------
$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'
# last line of defence: one bad UI call must never close HUD + dock + music
$app.Add_DispatcherUnhandledException({
    param($s, $e)
    try { Write-WidgetError $e.Exception 'dispatcher' } catch { }
    $e.Handled = $true
})
$app.Add_Exit({
    try { Save-Notes } catch { }
    try { Save-Config } catch { }
    try { if ($script:moveState) { $script:moveState.timer.Stop(); $script:moveState = $null } } catch { }
    try { [System.Windows.Input.Mouse]::OverrideCursor = $null } catch { }
    try { $tray.Visible = $false; $tray.Dispose() } catch { }
    try { $ps.Stop() } catch { }
    try { $mutex.ReleaseMutex() } catch { }
})
[void]$app.Run()
