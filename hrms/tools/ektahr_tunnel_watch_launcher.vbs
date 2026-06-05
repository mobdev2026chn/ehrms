' Launches the EktaHR adb-reverse tunnel watcher fully hidden (no console window).
' A copy of this file is placed in the user's Startup folder so the watcher
' starts automatically at every login. Edit the path below if the repo moves.
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""d:\ehrms-main\ehrms\hrms\tools\ektahr_tunnel_watch.ps1""", 0, False
