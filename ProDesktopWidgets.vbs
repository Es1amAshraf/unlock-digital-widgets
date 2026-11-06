' UNLOCK DIGITAL - silent launcher for the desktop widgets
' Starts ProDesktopWidgets.ps1 with no console window at all.
Option Explicit

Dim sh, fso, dir, ps1, cmd, svc, col, it, found

Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = dir & "\ProDesktopWidgets.ps1"

If Not fso.FileExists(ps1) Then WScript.Quit 1

' already running? do nothing
found = False
On Error Resume Next
Set svc = GetObject("winmgmts:\\.\root\cimv2")
Set col = svc.ExecQuery("select ProcessId, CommandLine from Win32_Process where Name='powershell.exe' and CommandLine like '%-File%ProDesktopWidgets.ps1%'")
If Err.Number = 0 Then
    For Each it In col
        If InStr(1, it.CommandLine, "-Command", 1) = 0 Then found = True
    Next
End If
Err.Clear
On Error GoTo 0
If found Then WScript.Quit 0

cmd = "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1 & """"
sh.Run cmd, 0, False