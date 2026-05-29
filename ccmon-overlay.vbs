' Hidden launcher for ccmon-overlay.ps1 — no console flash.
' Resolves sibling .ps1 by its own folder so install path is portable.
Dim sScriptFull, sDir, sCmd
sScriptFull = WScript.ScriptFullName
sDir = Left(sScriptFull, InStrRev(sScriptFull, "\"))
sCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & sDir & "ccmon-overlay.ps1"""
CreateObject("Wscript.Shell").Run sCmd, 0, False
