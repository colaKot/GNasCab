# GNasCab

> **简体中文** | [English](README.md)

GNasCab 是一款跨平台 NAS 软件，支持远程管理照片、影音、音乐、图书和文件，还支持文件分享、Transmission 下载、Docker 管理、远程终端、多端目录同步等功能。

官方网站：<https://nas.cab>


## 本仓库改动说明

> 本仓库是 [NasCabOS](https://github.com/nascab/NasCabOS) 的**修改版**，依据 GPL-3.0 发布。
> 以下为相对上游的改动（变更时间：2026-10，详见提交记录）。

- **项目更名**：项目名与各端显示名统一改为 **GNasCab**（Windows 服务端显示为 GNasCabServer，TV 端为 GNasCab TV）；Flutter 包名由 `NasCabOS` 改为 `GNasCab`。
- **保持兼容**：`applicationId`、iOS Bundle ID、鸿蒙 `bundleName` 等应用标识**保持不变**，已安装用户可正常覆盖升级；网络协议、设备指纹与加密数据格式均未改动。
- **新增多端目录同步**：新增 Windows 独立同步客户端 `sync_client` 与共享核心包 `packages/nascab_sync_core`，PC 主客户端与独立同步端共用同一套同步引擎与传输协议。
- **新增子账号权限体系**：新增应用级访问白名单（`appAccessGuard`）与路径级细粒度权限，可按用户限定可访问目录与操作范围，详见 `docs/子账号权限方案.md`。
- **影视库支持多库**：新增 `video_library` 实体，可分别建立电影 / 电视剧 / 图片 / 混合媒体库。
- **仓库精简**：不再随仓库提供第三方运行时二进制（sftpgo、openlist、ffmpeg、ffprobe、rclone、transmission）与 AI 模型（`onnx_models`）、地名库；可运行 `tool/fetch_nascab_assets.py` 从官方资源清单获取。
- **联系与捐助**：更新为本仓库维护者的微信收款二维码与邮箱。

## 项目结构

本代码包含主要以下几个项目：

| 项目 | 说明 |
| --- | --- |
| electron_server | 后端，使用 electron + express 实现本地服务功能 |
| flutter_client | Android + iOS + Windows + Mac 客户端，使用 flutter 实现跨平台客户端 |
| harmony_client | 鸿蒙端，开发中 |
| tv_android | Android TV 端 |
| tv_apple | Apple TV 端 |
| sync_client | Windows 独立同步客户端 |
| packages/nascab_sync_core | 目录同步核心共享包，PC 主客户端与独立同步端共用 |
| tool | 开发环境脚本与静态自检脚本 |

## 运行方式

服务端运行方式：
先要将 releases 中提供的依赖库和插件（https://github.com/colaKot/GNasCab/releases）下载到本地，然后将对应平台的 libs 以及 onnx_models 解压缩后放到 electron_server 根目录下，libs 中是第三方相关插件，onnx_models 中是 ocr 相关模型文件，用于图像识别

```bash
npm i;
npm start;
```

客户端运行方式：

```bash
flutter pub get;
flutter run -d win/ios/android/mac
```

如何把网页端编译后放到服务端下，实现静态网页端的访问：

```bash
将flutter打包web端后放入electron_server/web/main目录下
```

## 捐助支持

如果 GNasCab 对您有帮助，欢迎捐助支持我们：

<div align="center">

<img src="qrcode-wechat.webp" width="200" alt="微信捐助二维码" />

</div>

商务合作/联系我们：cola23@126.com

## 许可证

本项目以 [GNU General Public License v3.0](LICENSE) 发布，版权归 Beijing Yunpiao Piao Technology Co., Ltd. 所有。
