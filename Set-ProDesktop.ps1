# Applies a clean "professional" desktop setup on Windows 11.
# Run without parameters to apply, or with -Undo to restore defaults.
# Usage: powershell -ExecutionPolicy Bypass -File Set-ProDesktop.ps1 [-Undo]

param([switch]$Undo)

$ErrorActionPreference = 'Continue'
$EXPL = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$ADV  = "$EXPL\Advanced"
$PERS = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'

function Set-Value([string]$Path, [string]$Key, $Value, [string]$Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Key -Value $Value -Type $Type
    Write-Output ("  {0}\{1} = {2}" -f $Path, $Key, $Value)
}

# ---- Backup current taskbar blob before touching it ----
$srPath = "$EXPL\StuckRects3"
$backupPath = Join-Path $PSScriptRoot 'stuckrects3-backup.txt'
if ((Test-Path $srPath) -and -not (Test-Path $backupPath)) {
    $cur = (Get-ItemProperty $srPath).Settings
    ($cur -join ',') | Set-Content -LiteralPath $backupPath -Encoding ASCII
    Write-Output "Taskbar blob backed up to $backupPath"
}

if ($Undo) {
    Write-Output 'Restoring default look...'
    Set-Value $ADV 'HideIcons' 0
    Set-Value $ADV 'TaskbarSi' 1
    Set-Value $ADV 'TaskbarAl' 1
    Set-Value $ADV 'TaskbarDa' 1
    Set-Value $ADV 'TaskbarMn' 1
    Set-Value $PERS 'AppsUseLightTheme' 1
    Set-Value $PERS 'SystemUsesLightTheme' 1
    Set-Value "$EXPL\Search" 'SearchboxTaskbarMode' 1
    if (Test-Path $backupPath) {
        $bytes = (Get-Content -LiteralPath $backupPath -Raw).Trim() -split ',' | ForEach-Object { [byte]$_ }
        Set-ItemProperty $srPath -Name Settings -Value ([byte[]]$bytes) -Type Binary
        Write-Output '  Taskbar blob restored from backup.'
    }
} else {
    Write-Output 'Applying professional desktop setup...'

    # Dark theme
    Set-Value $PERS 'AppsUseLightTheme' 0
    Set-Value $PERS 'SystemUsesLightTheme' 0

    # Clean taskbar: no search box, no widgets, no chat, small icons, left-aligned
    Set-Value "$EXPL\Search" 'SearchboxTaskbarMode' 0
    Set-Value $ADV 'TaskbarSi' 0
    Set-Value $ADV 'TaskbarAl' 0
    Set-Value $ADV 'TaskbarDa' 0
    Set-Value $ADV 'TaskbarMn' 0

    # Hide desktop icons (keeps the files/shortcuts where they are)
    Set-Value $ADV 'HideIcons' 1

    # Cleaner Start menu: no "recently opened" noise
    Set-Value $ADV 'Start_TrackDocs' 0

    # Show hidden files in Explorer? (left as-is on purpose)
    Write-Output 'Done applying settings.'
}

# Restart Explorer so the taskbar/desktop changes take effect
Write-Output 'Restarting Explorer...'
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
Write-Output 'Explorer restarted.'
