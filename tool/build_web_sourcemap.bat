@echo off
rem Diagnostic build: same as build_web.bat but also emits main.dart.js.map
rem so minified release stack frames can be resolved back to Dart files.
setlocal
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set LOG=G:\work\_patch_backup\logs\flutter_web_sourcemap.log
cd /d G:\work\nascab\flutter_client
echo ==== build start %DATE% %TIME% ==== > "%LOG%"
call "G:\work\_toolchain\flutter-sdk\flutter\bin\flutter.bat" build web --release --no-web-resources-cdn --no-pub --pwa-strategy=none --source-maps >> "%LOG%" 2>&1
set RC=%ERRORLEVEL%
echo ==== EXITCODE=%RC% %DATE% %TIME% ==== >> "%LOG%"
endlocal & exit /b %RC%
