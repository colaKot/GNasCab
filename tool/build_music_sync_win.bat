@echo off
rem Build music + sync desktop clients (main is already built, so it is skipped).
rem
rem Scope (2026-10-09, per Tie Zhu): main + music desktop, sync desktop-only.
rem photo_client is NOT built here -- only its Android app is wanted.
rem
rem Everything goes to a per-client log because the bridge buffers the child's
rem stdout until exit, so a stalled build prints nothing.
rem
rem Prerequisites that were fixed the hard way (do not undo):rem  - fvp's mdk-sdk must exist under hosted/pub.dev/fvp-0.38.1/{windows,android};
rem    the build bridge is outside the sandbox and sourceforge is unreachable, so a
rem    missing cache entry means configure hangs for minutes then dies with
rem    "Failure when receiving data from the peer".
rem  - never "set RC=..." in a .bat here; CMake reads RC as the resource compiler.
setlocal

set FLUTTER=G:\work\_toolchain\flutter-sdk\flutter\bin\flutter.bat
set LOGDIR=G:\work\_patch_backup\logs
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

call :build_one music   G:\work\nascab\music_client windows
call :build_one sync    G:\work\nascab\sync_client  windows

echo.
echo ==== desktop summary (music, sync) ====
exit /b 0

:build_one
set NAME=%~1
set DIR=%~2
set PLATFORM=%~3
set LOG=%LOGDIR%\build_%NAME%.log
echo ==== [%NAME%] %PLATFORM start %DATE% %TIME% ====
> "%LOG%" echo ==== %NAME% %PLATFORM %DATE% %TIME% ====
pushd "%DIR%"
REM Drop the CMake cache so a stale FVP_DEPS_SHA256 entry cannot reappear and so
REM configure re-runs; without it the cached SDK is never consulted.
del /q build\windows\x64\CMakeCache.txt 2>nul
call "%FLUTTER%" build %PLATFORM% --release >> "%LOG%" 2>&1
set BUILD_RC=%ERRORLEVEL%
popd
if "%BUILD_RC%"=="0" (
  >> "%LOG%" echo BUILD_OK %NAME% %PLATFORM%
  echo   [%NAME%] %PLATFORM% OK
) else (
  >> "%LOG%" echo BUILD_FAIL %NAME% %PLATFORM% rc=%BUILD_RC%
  echo   [%NAME%] %PLATFORM% FAILED rc=%BUILD_RC%
)
exit /b 0