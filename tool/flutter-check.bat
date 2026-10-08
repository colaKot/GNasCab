@echo off
REM ============================================================
REM  GNasCab Flutter toolchain self-check
REM  Run this in a NORMAL cmd / PowerShell window (NOT from a
REM  piped/redirected shell), double-click is fine.
REM ============================================================
setlocal
call "%~dp0env.bat"
pushd "%~dp0.."

echo.
echo ================ flutter --version ================
call flutter --version

echo.
echo ================ flutter doctor ================
call flutter doctor

echo.
echo ================ flutter_client : flutter pub get ================
pushd flutter_client
call flutter pub get

echo.
echo ================ flutter_client : flutter analyze ================
call flutter analyze
popd

echo.
echo ================ sync_client : flutter analyze ================
pushd sync_client
call flutter pub get
call flutter analyze
popd

popd
echo.
echo ==== Done ====
pause
