@echo off
REM ============================================================
REM  GNasCab dev environment (project-local, NOT written to system env)
REM  Usage:  call G:\work\nascab\tool\env.bat
REM ============================================================
set "TOOLCHAIN=G:\work\_toolchain"
set "FLUTTER_ROOT=%TOOLCHAIN%\flutter-3.38.10\flutter"
set "JAVA_HOME=%TOOLCHAIN%\jdk17\jdk-17.0.20.1+1"
set "ANDROID_HOME=%TOOLCHAIN%\android-sdk"
set "ANDROID_SDK_ROOT=%TOOLCHAIN%\android-sdk"

REM China mirrors: avoid pub.dev / storage.googleapis.com timeouts
set "PUB_HOSTED_URL=https://pub.flutter-io.cn"
set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"
set "FLUTTER_SUPPRESS_ANALYTICS=true"

set "PATH=%FLUTTER_ROOT%\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

echo [GNasCab] Flutter : %FLUTTER_ROOT%
echo [GNasCab] Dart    : %FLUTTER_ROOT%\bin\cache\dart-sdk
echo [GNasCab] JDK     : %JAVA_HOME%
echo [GNasCab] Android : %ANDROID_HOME%
