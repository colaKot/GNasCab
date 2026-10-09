@echo off
rem Main client windows build -- fully offline.
rem
rem WHY THE PUBCACHE COPY MATTERS (2026-10-09):rem fvp 0.38.1's cmake/deps.cmake downloads mdk-sdk from sourceforge on every
rem configure, and the build bridge runs outside the sandbox where sourceforge is
rem unreachable (curl rc=28). Configure then hangs for minutes and dies with
rem "Failure when receiving data from the peer". Never the Dart kernel.
rem
rem deps.cmake caches the extracted SDK next to ITSELF, i.e.
rem   <pub-cache>/fvp-0.38.1/windows/mdk-sdk
rem and that pub-cache is whichever host the plugin resolved from. This machine has
rem TWO pub caches:rem   hosted/pub.flutter-io.cn/fvp-0.38.1/windows  <- had mdk-sdk + .7z
rem   hosted/pub.dev/fvp-0.38.1/windows            <- what .plugin_symlinks/fvp
rem                                                    actually points at, and it
rem                                                    had neither
rem so the archive was present all along but invisible to the build. Copying the
rem verified archive + extracted tree into the pub.dev cache fixes it at the source.
rem
rem No -D flag here on purpose: `flutter build windows` does not forward CMake
rem arguments, and the FVP_DEPS_SHA256 env var is overridden by the empty cache
rem entry that deps.cmake declares first. With the cache populated both are moot.
setlocal

set FLUTTER=G:\work\_toolchain\flutter-sdk\flutter\bin\flutter.bat
set LOG=G:\work\_patch_backup\logs\build_main_win.log

cd /d G:\work\nascab\flutter_client

echo ==== main windows build %DATE% %TIME% ====
> "%LOG%" echo ==== main windows %DATE% %TIME% (offline MDK in pub.dev cache) ====
call "%FLUTTER%" build windows --release >> "%LOG%" 2>&1
REM  Not named RC: CMake reads RC as the resource-compiler path (see
REM tool/build_desktop_clients.bat for the full explanation).
set BUILD_RC=%ERRORLEVEL%
>> "%LOG%" echo ==== EXITCODE=%BUILD_RC% %DATE% %TIME% ====
if "%BUILD_RC%"=="0" (echo BUILD_OK main windows) else (echo BUILD_FAIL main windows rc=%BUILD_RC%)
exit /b 0