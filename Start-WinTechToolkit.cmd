@echo off
rem Starts WinTech Toolkit (the script asks for administrator rights by itself)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0WinTechToolkit.ps1"
