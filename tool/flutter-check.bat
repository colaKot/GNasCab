@echo off
REM ============================================================
REM  WaterNasOS Flutter toolchain + project self-check
REM
REM  Run this in a NORMAL cmd / PowerShell window.
REM  It will NOT work from an IDE/agent piped shell, because Dart
REM  cannot create subprocess pipes there. Double-clicking is fine.
REM
REM  For each client project it runs 3 steps:
REM    1. flutter pub get      - pubspec syntax + dependency resolution
REM                              (also validates dependency_overrides paths)
REM    2. flutter analyze      - static analysis, run with
REM                              --no-fatal-infos --no-fatal-warnings so only
REM                              real ERRORS fail this step (lint noise should
REM                              not). NOTE: analyze only looks at the current
REM                              package, so it does NOT report issues inside
REM                              path dependencies. Do not trust it alone.
REM    3. flutter build bundle - the REAL gate. Compiles the whole app graph
REM                              (including path deps such as nascab_sync_core)
REM                              and VALIDATES the assets: list. Needs neither
REM                              Visual Studio nor accepted Android licenses.
REM
REM  IF ANALYZE FAILS ONLY INSIDE a vendored sub-package's example/ or test/:
REM   those are separate packages this repo never runs pub get for, so their
REM   package: self-imports cannot resolve and the analyzer emits ERRORS that
REM   --no-fatal-infos cannot suppress. Add an analyzer.exclude to THAT
REM   sub-package's own analysis_options.yaml - an exclude in the parent
REM   flutter_client/analysis_options.yaml does NOT reach it, because the
REM   nearest analysis config wins. Already done for packages/audio_service.
REM
REM  A failing step is non-fatal - the script keeps going so you get the
REM  whole picture in one run, then prints a summary at the end.
REM
REM  NOTE: keep this file pure ASCII. CRLF endings are the house style.
REM ============================================================
setlocal enabledelayedexpansion
call "%~dp0env.bat"
pushd "%~dp0.."

set /a FAILED=0

echo.
echo ================ flutter --version ================
call flutter --version
if errorlevel 1 echo [WARN] flutter --version failed - check env.bat / FLUTTER_ROOT

echo.
echo ================ flutter doctor ================
call flutter doctor

for %%P in (flutter_client photo_client music_client sync_client) do (
  echo.
  echo ============================================================
  echo  %%P
  echo ============================================================
  pushd %%P

  echo.
  echo [1/3] %%P  flutter pub get
  call flutter pub get
  if errorlevel 1 (set /a FAILED+=1 & echo [FAIL] pub get) else (echo [OK] pub get)

  echo.
  echo [2/3] %%P  flutter analyze --no-fatal-infos --no-fatal-warnings
  call flutter analyze --no-fatal-infos --no-fatal-warnings
  if errorlevel 1 (set /a FAILED+=1 & echo [FAIL] analyze - real errors) else (echo [OK] analyze)

  echo.
  echo [3/3] %%P  flutter build bundle    asset check
  call flutter build bundle
  if errorlevel 1 (set /a FAILED+=1 & echo [FAIL] build bundle) else (echo [OK] build bundle)

  popd
  echo ------------------------------------------------------------
)

popd
echo.
echo ====================== SUMMARY ======================
if %FAILED%==0 (
  echo  all steps passed
) else (
  echo  failed steps: %FAILED%
)
echo ====================================================
pause
