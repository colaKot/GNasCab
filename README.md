# GNasCab

> [简体中文](README.cn.md) | **English**

GNasCab is a cross-platform NAS software that lets you remotely manage your photos, videos, music, books, and files. It also supports file sharing, Transmission downloads, Docker management, remote terminal, multi-device folder sync, and more.

Official website: <https://nas.cab>

## Built-in Apps

Every feature in GNasCab is a **standalone app**: its own icon, its own page stack and its own
server-side API namespace, and on desktop it can be opened in a separate window apart from the
main shell. The default app list is served by the backend (`defaultApps` in
`electron_server/src/config/config.js`); users can hide or reorder apps in Settings.

| App | key | Description |
| --- | --- | --- |
| Files | `folder` | Browse, upload/download and share files |
| Photos | `photo` | Timeline, albums, smart albums, collections, face & scene recognition, similar-photo grouping, GPS geotagging, footprint map, "On this day", trash |
| Movies | `movie` | Movies and TV shows, common video formats, multiple libraries (movie / TV / photo / mixed) |
| Books | `book` | E-book reader supporting EPUB / MOBI / AZW3 / PDF / TXT |
| Music | `music` | Songs, albums, artists, playlists, collections and favorites, with a built-in full-screen player (dynamic lyrics, disc animation, background playback) |
| Notes | `note` | Rich-text notes |
| Encrypted | `encrypted` | AES-encrypted storage; the password is stored encrypted in the local database |
| Media Tool | `media_tool` | Batch image compression and video conversion |
| Sync | `sync` | Folder sync between your computer and the NAS: two-way / download-only / upload-only, with filter rules |
| Terminal | `terminal` | Remote terminal with sensitive commands (rm, unlink, ...) blocked |
| Transmission | `transmission` | BitTorrent download management |
| Docker | `docker` | Images, containers and tasks on the host |
| Backup | `backup` | Phone photo and file backup |
| Mounts | `mounts` | Mount network disks into server directories |
| Share | `share` | Share disks over WebDAV / FTP / SFTP |
| Monitor | `monitor` | Real-time hardware usage |
| Task Center | `task_center` | Background jobs |
| Security | `security` | Login and security settings |
| Users | `user` | Users and permissions |
| Process | `process` | Process viewer |
| Service | `nascab_service` | Server status and account |
| Settings | `setting` | Global settings |

> `transmission`, `terminal`, `user`, `mounts`, `docker`, `nascab_service`, `monitor` and `process`
> are hidden from regular users by default and visible only to administrators. If an app is missing
> from the home screen, it is most likely filtered out by the "hidden apps" setting — restore it in
> Settings.

## Changes From Upstream

> This repository is a **modified version** of [NasCabOS](https://github.com/nascab/NasCabOS),
> released under GPL-3.0. Listed below are the changes relative to upstream (2026-10; see the commit history).

- **Renamed**: the project and every client display name is now **GNasCab** (GNasCabServer for the Windows server, GNasCab TV for the TV clients); the Flutter package name changed from `NasCabOS` to `GNasCab`.
- **Backward compatible**: application identifiers such as `applicationId`, the iOS Bundle ID and the HarmonyOS `bundleName` are **left unchanged**, so existing installs can upgrade in place; network protocols, device fingerprints and encrypted data formats are untouched.
- **New multi-device folder sync**: a standalone Windows sync client (`sync_client`) plus a shared core package (`packages/nascab_sync_core`), so the desktop client and the standalone client run the same sync engine and transfer protocol.
- **New sub-account permission system**: an app-level access policy (`appAccessGuard`) together with fine-grained path permissions, letting you restrict each user's accessible folders and operations. See `docs/子账号权限方案.md`.
- **Multi-library media support**: a new `video_library` entity allows separate movie / TV / photo / mixed libraries.
- **Slimmed repository**: third-party runtime binaries (sftpgo, openlist, ffmpeg, ffprobe, rclone, transmission), AI models (`onnx_models`) and the geonames database are no longer bundled; run `tool/fetch_nascab_assets.py` to fetch them from the official manifest.
- **Contact & donations**: updated to the maintainer's QR code and email.

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

<img src="qrcode-wechat.webp" width="200" alt="WeChat donation QR code" />

</div>

Business cooperation / Contact us: cola23@126.com

## License

Released under the [GNU General Public License v3.0](LICENSE).
Copyright (C) Beijing Yunpiao Piao Technology Co., Ltd.
