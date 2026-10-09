@echo off
REM ============================================================
REM  GNasCab External Build Bridge
REM
REM  START THIS FROM A NORMAL cmd WINDOW (Start menu > cmd).
REM  Do NOT start it from an IDE / WorkBuddy integrated terminal:
REM  such a terminal lives inside WorkBuddy's Job Object, and Dart
REM  cannot create piped child processes there (CreateFile 231),
REM  so flutter would still fail. The bridge prints a loud
REM  'Dart can spawn: no' warning when that happens.
REM
REM  While it runs, the agent can send build commands to it over
REM  127.0.0.1. It executes arbitrary commands - close the window
REM  when you are done.
REM ============================================================
setlocal
cd /d "%~dp0.."
set "PY=C:\Users\cola\.workbuddy\binaries\python\versions\3.13.12\python.exe"
if not exist "%PY%" set "PY=python"
"%PY%" "%~dp0build_bridge.py" %*
echo.
echo [bridge exited]
pause
