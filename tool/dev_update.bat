@echo off
rem ============================================================
rem  WaterNasOS 开发期快速更新（服务端 app.asar + web 产物）
rem
rem  比 build_server_pack.bat 快约 100 倍：只重写真正会变的两个东西
rem  （resources\app.asar 和 web\main），完全不碰那 1.3 GB 固定内容
rem  （Electron 运行时 / libs / onnx_models / geonames 地理库）。
rem
rem  用法（双击即可）：
rem     dev_update.bat            自动选版本号最大的 dist_vN
rem     dev_update.bat v14        指定 dist_v14
rem
rem  前提：目录里已经有 dist_vN（首次请跑 tool\build_server_pack.bat）；
rem        前端要先有 flutter_client\build\web（首次请跑 tool\build_web.bat）。
rem
rem  ⚠️ 只用于开发验证；正式发布仍然走 tool\build_server_pack.bat。
rem ============================================================
setlocal
cd /d "%~dp0.."
set "PY=C:\Users\cola\.workbuddy\binaries\python\versions\3.13.12\python.exe"
if not exist "%PY%" set "PY=python"

set "DISTARG="
if not "%~1"=="" set "DISTARG=--dist dist_%~1"

"%PY%" "tool\dev_update.py" %DISTARG%
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo [dev_update 完成] 直接启动 ^<dist^>\win-unpacked\WaterNasOSServer.exe 即可
) else (
  echo [dev_update 失败，退出码 %RC%]
)
if /I not "%~2"=="nopause" pause
endlocal & exit /b %RC%
