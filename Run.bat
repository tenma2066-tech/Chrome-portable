@echo off
setlocal
set "OUTLOG=%TEMP%\GoogleChromePortable-Run.out"
set "ERRLOG=%TEMP%\GoogleChromePortable-Run.err"
set "SCRIPT=%~dp0Run.ps1"
set "ELEVATED_CMD=%TEMP%\GoogleChromePortable-Elevated.cmd"

REM Self-elevate to admin (HKLM policy keys require it).
fltmc >nul 2>&1
if %errorLevel% neq 0 (
    echo [STATUS] Requesting admin rights...
    if exist "%ELEVATED_CMD%" del "%ELEVATED_CMD%" >nul 2>&1
    >"%ELEVATED_CMD%" echo @echo off
    >>"%ELEVATED_CMD%" echo powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode "%~1" ^> "%OUTLOG%" 2^> "%ERRLOG%"
    powershell -NoProfile -Command "Start-Process -FilePath '%ELEVATED_CMD%' -Verb RunAs"
    if errorlevel 1 (
        echo.
        echo [ERROR] Failed to request admin rights.
        pause
    )
    timeout /t 1 /nobreak >nul
    set "HAS_OUT=0"
    set "HAS_ERR=0"
    if exist "%OUTLOG%" for %%I in ("%OUTLOG%") do if %%~zI gtr 0 set "HAS_OUT=1"
    if exist "%ERRLOG%" for %%I in ("%ERRLOG%") do if %%~zI gtr 0 set "HAS_ERR=1"
    if "%HAS_OUT%"=="1" (
        echo.
        type "%OUTLOG%"
    )
    if "%HAS_ERR%"=="1" (
        echo.
        echo [ERROR] Elevated Run.ps1 reported errors:
        type "%ERRLOG%"
        echo.
        pause
    )
    if exist "%OUTLOG%" del "%OUTLOG%" >nul 2>&1
    if exist "%ERRLOG%" del "%ERRLOG%" >nul 2>&1
    if exist "%ELEVATED_CMD%" del "%ELEVATED_CMD%" >nul 2>&1
    exit /b
)

if exist "%OUTLOG%" del "%OUTLOG%" >nul 2>&1
if exist "%ERRLOG%" del "%ERRLOG%" >nul 2>&1
if exist "%ELEVATED_CMD%" del "%ELEVATED_CMD%" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode "%~1" 2>"%ERRLOG%"
set "PS_EXIT=%ERRORLEVEL%"

set "HAS_ERR=0"
if exist "%ERRLOG%" for %%I in ("%ERRLOG%") do if %%~zI gtr 0 set "HAS_ERR=1"

if "%HAS_ERR%"=="1" (
    echo.
    echo [ERROR] Run.ps1 reported errors:
    type "%ERRLOG%"
    echo.
    pause
) else if not "%PS_EXIT%"=="0" (
    echo.
    echo [ERROR] Run.ps1 exited with code %PS_EXIT%.
    pause
)

if exist "%ERRLOG%" del "%ERRLOG%" >nul 2>&1
if exist "%ELEVATED_CMD%" del "%ELEVATED_CMD%" >nul 2>&1

endlocal
exit /b
