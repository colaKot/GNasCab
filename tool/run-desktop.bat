@echo off
REM ============================================================
REM  GNasCab desktop debug launcher
REM
REM  IMPORTANT: run this in a NORMAL cmd / PowerShell window.
REM             Double-clicking is fine too.
REM             It will NOT work from inside an IDE/agent piped
REM             shell (Dart cannot create subprocess pipes there).
REM
REM  Usage:  run-desktop.bat photo|music|sync|full
REM          no argument -> will prompt
REM ============================================================
setlocal
call "%~dp0env.bat"

set "APP=%~1"
if "%APP%"=="" set /p APP=Which app? (photo/music/sync/full):

if /i "%APP%"=="photo" set "PROJDIR=photo_client"
if /i "%APP%"=="music" set "PROJDIR=music_client"
if /i "%APP%"=="sync"  set "PROJDIR=sync_client"
if /i "%APP%"=="full"  set "PROJDIR=flutter_client"

if "%PROJDIR%"=="" (
  echo [ERROR] unknown app: "%APP%"
  echo         expected one of: photo / music / sync / full
  exit /b 1
)

pushd "%~dp0..\%PROJDIR%"

echo.
echo ================ %PROJDIR% : flutter pub get ================
call flutter pub get

echo.
echo ================ %PROJDIR% : flutter run -d windows ================
echo   r = hot reload    R = hot restart    q = quit
echo.
call flutter run -d windows

popd
endlocal
