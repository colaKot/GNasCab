# GNasCab

> [简体中文](README.cn.md) | **English**

GNasCab is a cross-platform NAS software that lets you remotely manage your photos, videos, music, books, and files. It also supports file sharing, Transmission downloads, Docker management, remote terminal, multi-device folder sync, and more.

Official website: <https://nas.cab>

## Project Structure

This repository contains the following projects:

| Project | Description |
| --- | --- |
| electron_server | Backend, uses electron + express to provide local services |
| flutter_client | Android + iOS + Windows + Mac clients, built with flutter for cross-platform support |
| harmony_client | HarmonyOS client, in development |
| tv_android | Android TV client |
| tv_apple | Apple TV client |
| sync_client | Standalone Windows sync client |
| packages/nascab_sync_core | Shared sync core package used by the PC client and the standalone sync client |
| tool | Development environment scripts and static self-check scripts |

## Running

Server:

First, download the dependency libraries and plugins provided in the releases (<https://github.com/colaKot/GNasCab/releases>), then extract the `libs` and `onnx_models` of the corresponding platform to the root directory of `electron_server`. `libs` contains third-party plugins, and `onnx_models` contains OCR model files used for image recognition.

```bash
npm i;
npm start;
```

Client:

```bash
flutter pub get;
flutter run -d win/ios/android/mac
```

To serve the compiled web client from the server (static web access):

```bash
Build the flutter web version and place it under the electron_server/web/main directory.
```

## Donations

If GNasCab is helpful to you, we welcome your support:

<div align="center">

| WeChat Scan to Donate | PayPal |
| --- | --- |
| <img src="qrcode-wx.webp" width="200" alt="WeChat donation QR code" /> | [PayPal.Me/nascabos](https://paypal.me/nascabos) |

</div>

Business cooperation / Contact us: cola23@126.com

## License

Released under the [GNU General Public License v3.0](LICENSE).
Copyright (C) Beijing Yunpiao Piao Technology Co., Ltd.
