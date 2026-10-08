# GNasCab

> **简体中文** | [English](README.md)

GNasCab 是一款跨平台 NAS 软件，支持远程管理照片、影音、音乐、图书和文件，还支持文件分享、Transmission 下载、Docker 管理、远程终端、多端目录同步等功能。

官方网站：<https://nas.cab>


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

| 微信扫码捐助 | PayPal |
| --- | --- |
| <img src="qrcode-wx.webp" width="200" alt="微信捐助二维码" /> | [PayPal.Me/nascabos](https://paypal.me/nascabos) |

</div>

商务合作/联系我们：cola23@126.com

## 许可证

本项目以 [GNU General Public License v3.0](LICENSE) 发布，版权归 Beijing Yunpiao Piao Technology Co., Ltd. 所有。
