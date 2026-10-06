@echo off
setlocal
title Driver Extractor Toolkit

rem Runs Driver-Extractor-Toolkit.ps1 from the folder this launcher lives in,
rem asking for administrator rights first if needed. The execution policy is
rem bypassed for this run only, so no system settings are changed.

set "TOOLKIT=%~dp0Driver-Extractor-Toolkit.ps1"

if not exist "%TOOLKIT%" (
    echo Could not find Driver-Extractor-Toolkit.ps1.
    echo Keep this launcher in the same folder as the script.
    pause
    exit /b 1
)

rem net session only succeeds from an elevated prompt. If it fails, relaunch
rem this file through UAC and close this window. The path is passed through
rem an environment variable so quotes or spaces in it can't break the command.
net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator rights...
    set "LAUNCHER=%~f0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath $env:LAUNCHER -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
    if errorlevel 1 (
        echo.
        echo The toolkit needs administrator rights to run.
        echo Run this launcher again and choose Yes when Windows asks for permission.
        pause
        exit /b 1
    )
    exit /b 0
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TOOLKIT%"

rem Keep the window open if the script stopped with an error, so the
rem message can be read. A normal exit from the menu closes the window.
if errorlevel 1 (
    echo.
    echo The toolkit stopped with an error. Review the message above.
    pause
)
