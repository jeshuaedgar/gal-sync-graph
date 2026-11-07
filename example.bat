@echo off
rem Paths are relative to this file, so the "Start in" folder of the scheduled task does not matter

pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass ^
-File "%~dp0Sync-Contacts.ps1" ^
-ConfigFile "%~dp0Sync-Contacts.settings.json" ^
-LogPath "%~dp0Logs"

exit /b %ERRORLEVEL%
