@echo off
title EASY HLLV Seeding Helper v1.1.1
cd /d %~dp0
echo EASY HLLV Seeding Helper v1.1.1
echo.
echo First run will ask for your Steam name letter-for-letter.
echo Keep this window open while seeding.
echo.
Powershell.exe -STA -ExecutionPolicy Bypass -File ".\HLLVSeeding.ps1"
echo.
echo Seeder stopped. You can close this window.
pause
