# Builds the distributable installer package under System-Setup\dist
param([switch]$NoZip)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot          # System-Setup
$pkg = $PSScriptRoot
$dist = Join-Path $root 'dist'
$name = 'UNLOCK-DIGITAL-Widgets-v1.3.0'
$stage = Join-Path $dist $name

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage 'setup') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage 'payload') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage 'extras') -Force | Out-Null

# installer / uninstaller
Copy-Item -LiteralPath (Join-Path $pkg 'setup\Install.ps1') -Destination (Join-Path $stage 'setup') -Force
Copy-Item -LiteralPath (Join-Path $pkg 'setup\Uninstall.ps1') -Destination (Join-Path $stage 'setup') -Force
Copy-Item -LiteralPath (Join-Path $pkg 'setup\Install.vbs') -Destination (Join-Path $stage 'setup') -Force

# payload
foreach ($f in @('ProDesktopWidgets.ps1', 'ProDesktopWidgets.vbs')) {
    Copy-Item -LiteralPath (Join-Path $root $f) -Destination (Join-Path $stage 'payload') -Force
}
$wall = Join-Path $env:USERPROFILE 'OneDrive\Pictures\Wallpapers\win11-azure.png'
if (-not (Test-Path -LiteralPath $wall)) { $wall = 'C:\Users\eslam\OneDrive\Pictures\Wallpapers\win11-azure.png' }
if (Test-Path -LiteralPath $wall) {
    Copy-Item -LiteralPath $wall -Destination (Join-Path $stage 'payload\wallpaper.png') -Force
} else {
    Write-Warning "wallpaper not found: $wall"
}

# icon
& (Join-Path $pkg 'build\New-AppIcon.ps1') -Png (Join-Path $stage 'payload\UNLOCK-DIGITAL.png') -Ico (Join-Path $stage 'payload\UNLOCK-DIGITAL.ico')

# extras (optional taskbar / theme)
foreach ($f in @('Set-ProDesktop.ps1', 'Undo-ProDesktop.cmd')) {
    $src = Join-Path $root $f
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $stage 'extras') -Force }
}

# launcher + readme
Copy-Item -LiteralPath (Join-Path $pkg 'Install.cmd') -Destination $stage -Force
$readme = Get-Content -LiteralPath (Join-Path $pkg 'README.txt') -Raw -Encoding UTF8
[System.IO.File]::WriteAllText((Join-Path $stage 'README.txt'), $readme, (New-Object System.Text.UTF8Encoding($true)))

# zip
if (-not $NoZip) {
    $zip = Join-Path $dist "$name.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -LiteralPath $stage -DestinationPath $zip -CompressionLevel Optimal
    Write-Output "zip: $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 2)) MB)"
}

Write-Output "package: $stage"
Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object { "{0,10:N0}  {1}" -f $_.Length, $_.FullName.Substring($stage.Length + 1) }
