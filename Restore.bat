@echo off
setlocal

REM Self-elevate to admin (HKLM ACL changes require it).
fltmc >nul 2>&1
if %errorLevel% neq 0 (
    echo [STATUS] Requesting admin rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore.ps1"
if errorlevel 1 (
    echo.
    echo [ERROR] Restore.ps1 exited with errors.
    pause
)

endlocal
exit /b
