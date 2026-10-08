# GNasCab

> **简体中文** | [English](README.md)

GNasCab 是一款跨平台 NAS 软件，支持远程管理照片、影音、音乐、图书和文件，还支持文件分享、Transmission 下载、Docker 管理、远程终端、多端目录同步等功能。

官方网站：<https://nas.cab>


## 内置应用

GNasCab 的每一项功能都是**独立的 App**：有自己的图标、独立页面栈和独立的服务端 API 命名空间，
PC 端还可以从主窗口单独打开。默认应用列表由服务端下发（见 `electron_server/src/config/config.js`
的 `defaultApps`），用户可在设置中隐藏或重新排序。

| 应用 | key | 说明 |
| --- | --- | --- |
| 文件管理 | `folder` | 文件浏览、上传下载、分享 |
| 照片管理 | `photo` | 时间线、自建相册、智能相册、照片合集、人脸/场景识别、相似照片、GPS 补录、足迹地图、那年今日、回收站 |
| 影视库 | `movie` | 电影与电视剧管理，支持常见视频格式，可建电影/电视剧/图片/混合多库 |
| 图书馆 | `book` | 电子书阅读，支持 EPUB / MOBI / AZW3 / PDF / TXT 等格式 |
| 音乐库 | `music` | 歌曲、专辑、歌手、播放列表、合集、收藏，内置全屏播放器（动态歌词、唱片动效、后台播放） |
| 笔记 | `note` | 富文本笔记 |
| 加密空间 | `encrypted` | AES 加密保存文件，密码加密后存于本机数据库 |
| 媒体工具 | `media_tool` | 批量压缩图片、视频转换 |
| 同步管理 | `sync` | 电脑文件夹与 NAS 目录同步，支持双向 / 仅下载 / 仅上传与过滤规则 |
| 终端 | `terminal` | 远程终端，屏蔽 rm、unlink 等敏感命令 |
| Transmission | `transmission` | BT 下载管理 |
| Docker | `docker` | 宿主机镜像、容器、任务管理 |
| 备份 | `backup` | 手机相册与文件备份 |
| 远程挂载 | `mounts` | 把网络磁盘挂载到服务器目录 |
| 分享管理 | `share` | 通过 WebDAV / FTP / SFTP 等协议分享磁盘 |
| 系统监控 | `monitor` | 实时查看服务器硬件使用情况 |
| 任务中心 | `task_center` | 后台任务查看 |
| 安全中心 | `security` | 登录与安全设置 |
| 用户管理 | `user` | 用户与权限管理 |
| 进程 | `process` | 进程查看 |
| 服务 | `nascab_service` | 服务端状态与账户 |
| 配置中心 | `setting` | 全局设置 |

> `transmission`、`terminal`、`user`、`mounts`、`docker`、`nascab_service`、`monitor`、`process`
> 默认对普通用户隐藏，仅管理员可见。若首页看不到某个应用，多半是被「隐藏应用」挡住了，
> 在设置里恢复即可。

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
