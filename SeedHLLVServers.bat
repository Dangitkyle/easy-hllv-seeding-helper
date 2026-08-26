@echo off
cd /d "%~dp0"
start "" "%SystemRoot%\System32\conhost.exe" --headless Powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\EASYHLLVSeedingUI.ps1"
