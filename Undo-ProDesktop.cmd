@echo off
title Undo - Pro Desktop Setup
echo Restoring default Windows look (theme, taskbar, desktop icons)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-ProDesktop.ps1" -Undo
echo.
echo Done. To restore the old wallpaper, right-click the desktop
echo and pick Personalize, or rebuild it with New-ProWallpaper.ps1.
pause
