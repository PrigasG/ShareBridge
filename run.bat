@echo off
setlocal enabledelayedexpansion

REM =========================================================
REM Base directory
REM =========================================================
set "RootDir=%~dp0"
if "%RootDir:~-1%"=="\" set "RootDir=%RootDir:~0,-1%"

REM =========================================================
REM Defaults
REM =========================================================
set "APP_NAME=Shiny App"
set "APP_ID=ShinyApp"
set "LTC_PORT=3402"
set "LTC_HOST=127.0.0.1"

REM =========================================================
REM Read metadata from app_meta.cfg if present
REM =========================================================
if exist "%RootDir%\app_meta.cfg" (
  for /f "usebackq tokens=1,* delims==" %%A in ("%RootDir%\app_meta.cfg") do (
    if /I "%%A"=="APP_NAME" set "APP_NAME=%%B"
    if /I "%%A"=="APP_ID" set "APP_ID=%%B"
    if /I "%%A"=="PREFERRED_PORT" set "LTC_PORT=%%B"
    if /I "%%A"=="HOST" set "LTC_HOST=%%B"
  )
)

set "APP_ID_SAFE=%APP_ID: =_%"

REM =========================================================
REM Bundled Pandoc
REM =========================================================
set "PANDOC_DIR=%RootDir%\pandoc"
if exist "%PANDOC_DIR%\pandoc.exe" (
  set "PATH=%PANDOC_DIR%;%PATH%"
  set "RSTUDIO_PANDOC=%PANDOC_DIR%"
)

REM =========================================================
REM App folder
REM =========================================================
set "AppDir=%RootDir%\app"
if not exist "%AppDir%" (
  echo ERROR: App folder not found at "%AppDir%".
  pause
  exit /b 1
)

REM =========================================================
REM Logging: local logs first, fallback to TEMP
REM =========================================================
set "LogDir=%RootDir%\logs"
if not exist "%LogDir%" mkdir "%LogDir%" >nul 2>&1

set "LogTest=%LogDir%\__write_test.tmp"
break > "%LogTest%" 2>nul

if exist "%LogTest%" (
  del "%LogTest%" >nul 2>&1
) else (
  set "LogDir=%TEMP%\%APP_ID_SAFE%_logs"
  if not exist "%LogDir%" mkdir "%LogDir%" >nul 2>&1
)

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "stamp=%%I"
set "LOG=%LogDir%\app_%stamp%.log"

REM =========================================================
REM Delete logs older than 7 days
REM =========================================================
powershell -NoProfile -Command ^
  "Get-ChildItem -Path '%LogDir%' -Filter '*.log' -ErrorAction SilentlyContinue | " ^
  "Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | " ^
  "Remove-Item -Force -ErrorAction SilentlyContinue" >nul 2>&1

(
  echo [START] %date% %time%
  echo APP_NAME="%APP_NAME%"
  echo APP_ID="%APP_ID%"
  echo RootDir="%RootDir%"
  echo AppDir="%AppDir%"
  echo LogDir="%LogDir%"
  echo LTC_HOST="%LTC_HOST%"
  echo LTC_PORT="%LTC_PORT%"
) > "%LOG%" 2>&1

if not exist "%LOG%" (
  echo [FATAL] Could not create log file.
  pause
  exit /b 1
)

REM =========================================================
REM R detection
REM =========================================================
set "RPathFound=false"
set "RS="
set "R="

for %%P in (
  "%RootDir%\R\bin\Rscript.exe"
  "%RootDir%\R\bin\x64\Rscript.exe"
  "%RootDir%\R-Portable\bin\Rscript.exe"
  "%RootDir%\R-Portable\bin\x64\Rscript.exe"
  "%RootDir%\R-Portable\App\R-Portable\bin\Rscript.exe"
  "%RootDir%\R-Portable\App\R-Portable\bin\x64\Rscript.exe"
) do (
  if exist "%%~fP" (
    set "RS=%%~fP"
    set "RPathFound=true"
    goto :prep
  )
)

if exist "%RootDir%\R\bin\x64\R.exe" (
  set "R=%RootDir%\R\bin\x64\R.exe"
  set "RPathFound=true"
  goto :prep
)

for %%d in ("C:\Program Files\R" "C:\Program Files (x86)\R") do (
  for /d %%i in (%%d\R-*) do (
    if exist "%%i\bin\Rscript.exe" (
      set "RS=%%i\bin\Rscript.exe"
      set "RPathFound=true"
      goto :prep
    ) else (
      if exist "%%i\bin\x64\R.exe" (
        set "R=%%i\bin\x64\R.exe"
        set "RPathFound=true"
        goto :prep
      )
    )
  )
)

if not "%RPathFound%"=="true" (
  echo R was not detected automatically. >> "%LOG%"
  set /p "R=Enter full path to R.exe: "
  if not exist "%R%" (
    echo The specified path does not exist.
    echo [ERROR] Invalid R path provided: "%R%" >> "%LOG%"
    pause
    exit /b 1
  )
)

:prep
set "APP_NAME=%APP_NAME%"
set "APP_ID=%APP_ID%"
set "LTC_PORT=%LTC_PORT%"
set "LTC_HOST=%LTC_HOST%"

REM =========================================================
REM Run app
REM =========================================================
if defined RS (
  echo Launching with Rscript... >> "%LOG%"
  "%RS%" --vanilla "%RootDir%\run.R" "%AppDir%" >> "%LOG%" 2>&1
) else (
  echo Launching with R.exe... >> "%LOG%"
  "%R%" --no-save --slave -f "%RootDir%\run.R" --args "%AppDir%" >> "%LOG%" 2>&1
)

set "RC=%errorlevel%"
echo [END] %date% %time% (exitcode=%RC%) >> "%LOG%"

if not "%RC%"=="0" (
  echo.
  echo %APP_NAME% did not launch successfully.
  echo Check log:
  echo "%LOG%"
  pause
)

exit /b %RC%
