@echo off
setlocal

REM =========================================================
REM ShareBridge Publisher Launcher
REM Opens the publisher UI in the default browser.
REM Usually launched via PublishApp.hta so this window stays hidden.
REM =========================================================

set "RootDir=%~dp0"
if "%RootDir:~-1%"=="\" set "RootDir=%RootDir:~0,-1%"

set "SHAREBRIDGE_FRAMEWORK_DIR=%RootDir%"
set "APP_DIR=%RootDir%\build\publisher_ui"
set "PUBLISH_LOG_DIR=%RootDir%\logs\publisher"

if not exist "%APP_DIR%\app.R" (
  echo ERROR: Publisher app not found at "%APP_DIR%"
  echo Make sure build\publisher_ui\app.R exists.
  pause
  exit /b 1
)

REM =========================================================
REM Prepare publisher log folder
REM =========================================================
if not exist "%PUBLISH_LOG_DIR%" mkdir "%PUBLISH_LOG_DIR%" >nul 2>&1

REM Delete publisher logs older than 30 days
powershell -NoProfile -Command ^
  "Get-ChildItem -Path '%PUBLISH_LOG_DIR%' -Filter '*.log' -ErrorAction SilentlyContinue | " ^
  "Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | " ^
  "Remove-Item -Force -ErrorAction SilentlyContinue" >nul 2>&1

REM =========================================================
REM Find R
REM =========================================================
set "RS="

REM Check portable R first
for %%P in (
  "%RootDir%\R-portable\bin\Rscript.exe"
  "%RootDir%\R-portable\bin\x64\Rscript.exe"
) do (
  if exist "%%~fP" (
    set "RS=%%~fP"
    goto :run
  )
)

REM Check system R
for %%d in ("C:\Program Files\R" "C:\Program Files (x86)\R") do (
  for /d %%i in (%%d\R-*) do (
    if exist "%%i\bin\Rscript.exe" (
      set "RS=%%i\bin\Rscript.exe"
      goto :run
    )
  )
)

REM Check PATH
where Rscript.exe >nul 2>&1
if %errorlevel%==0 (
  set "RS=Rscript.exe"
  goto :run
)

echo ERROR: R was not found.
echo Install R or place R-portable in the framework folder.
pause
exit /b 1

:run
echo Starting ShareBridge Publisher...
echo.
"%RS%" --vanilla -e "shiny::runApp('%APP_DIR:\=/%', launch.browser = TRUE, host = '127.0.0.1', port = httpuv::randomPort())"

if not %errorlevel%==0 (
  echo.
  echo Publisher failed to start. Check that shiny and httpuv are installed.
  pause
)

exit /b %errorlevel%
