@echo off
rem Build the Flutter web bundle for the WaterNasOS server web UI.
rem Output is redirected to a log file on purpose: when this script is launched
rem through tool/bridge_cli.py the bridge buffers the child's stdout/stderr in
rem pipes until it exits, so a build that stalls shows nothing at all.
rem The *.flutter-io.cn mirrors are set because the default Google endpoints are
rem unreliable from this network.
rem --pwa-strategy=none: do NOT emit flutter_service_worker.js. With the default
rem (offline-first) the browser keeps serving the previously cached bundle from the
rem registered service worker, so a freshly copied web/main keeps looking unchanged
rem until the user clears site data. This UI is served by the NAS itself over LAN,
rem so offline startup buys nothing here.
setlocal
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set LOG=G:\work\_patch_backup\logs\flutter_web_build.log
cd /d G:\work\nascab\flutter_client
echo ==== build start %DATE% %TIME% ==== > "%LOG%"
call "G:\work\_toolchain\flutter-sdk\flutter\bin\flutter.bat" build web --release --no-web-resources-cdn --no-pub --pwa-strategy=none >> "%LOG%" 2>&1
set RC=%ERRORLEVEL%
echo ==== EXITCODE=%RC% %DATE% %TIME% ==== >> "%LOG%"
rem --- 必须 exit /b 把真实退出码带出去：只写 endlocal 会把 ERRORLEVEL 重置成 0，
rem     于是「编译失败但 tool/bridge_cli.py 仍返回 rc=0」。判成功一定要看日志的 EXITCODE=。
endlocal & exit /b %RC%
