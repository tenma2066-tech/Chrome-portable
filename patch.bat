@echo off
setlocal
cd /d "%~dp0"

echo [STATUS] Running patch.ps1...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch.ps1"

if %errorLevel% neq 0 (
    echo.
    echo [ERROR] patch.ps1 failed with error level %errorLevel%.
    pause
)
endlocal
