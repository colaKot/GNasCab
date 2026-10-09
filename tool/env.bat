@echo off
REM ============================================================
REM  GNasCab dev environment (project-local, NOT written to system env)
REM  Usage:  call G:\work\nascab\tool\env.bat
REM ============================================================
set "TOOLCHAIN=G:\work\_toolchain"
REM 2026-10-08 升级到 Flutter 3.47.5（Dart 3.13.4），旧版 3.38.10 仍在
REM G:\work\_toolchain\flutter-3.38.10\flutter，需要回退就改这一行。
REM 注意：新 SDK 解包后真身多一层，是 flutter-sdk\flutter，不是 flutter-sdk。
set "FLUTTER_ROOT=%TOOLCHAIN%\flutter-sdk\flutter"
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
