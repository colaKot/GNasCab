# nascab_sync_core

GNasCab 目录同步核心。**PC 主客户端与 Windows 独立同步客户端共用这一份实现。**

## 为什么要抽出来

抽包之前，`flutter_client/lib/modules/sync/` 与 `sync_client/lib/sync/` 是两份代码：
6 个核心文件约 1744 行，其中 4 个文件是**逐行复制**的（差异只有 49 行，其中 44 行还是各自新增的功能）。
第一次复制就已经发生漂移——独立端加了 `clearAll()` 和 `pause()/resume()`，主客户端没有。
同步逻辑一旦两边不一致，后果不是"功能少了"，而是**双方对同一批文件做出不同判定，导致误删或反复重传**。

## 分层

```
┌─────────────────────────┐   ┌─────────────────────────┐
│ flutter_client（PC 端）  │   │ sync_client（独立端）    │
│  FlutterSyncHost        │   │  DesktopSyncHost        │
│  ApiController          │   │  SessionController      │
│  UploadCore             │   │  SyncUploader           │
│  BaseApiService         │   │  SyncHttp               │
│  SyncApiService         │   │  SyncApiService         │
└───────────┬─────────────┘   └───────────┬─────────────┘
            │        SyncHost 接口         │
            └──────────────┬──────────────┘
                           ▼
              packages/nascab_sync_core
        ┌──────────────────────────────────────┐
        │ sync_models      数据模型 / DTO       │
        │ sync_local_scanner 本地目录扫描        │
        │ sync_local_store   基线库（sqlite）    │
        │ sync_scheduler     实时监听 + 定时触发  │
        │ sync_protocol      路由与请求体定义     │
        │ sync_engine        三向比对执行引擎     │
        │ sync_host          宿主接口（唯一接缝）  │
        └──────────────────────────────────────┘
```

## 唯一接缝：`SyncHost`

引擎需要的宿主能力只有 7 个方法：

| 方法 | 说明 | 主客户端实现 | 独立端实现 |
|---|---|---|---|
| `baseUrl` | NAS 地址 | `ApiController.instance.baseUrl` | `SyncHttp.baseUrl` |
| `resolveAccessToken()` | 取/刷新 token | `ApiController` 自动刷新 | `SessionController.refresh()` |
| `message(key)` | i18n 翻译 | `key.tr` | `key.tr` |
| `uploadFile(...)` | 分块上传 | `UploadCore.processFile` | `SyncUploader.upload` |
| `sendDownload(...)` | 下载通道 | 直连 / P2P 二选一 | 直连 |
| `plan/deleteRemote/report` | 协议调用 | `SyncApiService`（`ApiResponse`→`SyncApiResult`） | 同上 |

装配方式（在各自 `main()` 里，`runApp` 之前）：

```dart
import 'package:nascab_sync_core/nascab_sync_core.dart';

SyncHostHolder.instance = FlutterSyncHost.instance;  // 或 DesktopSyncHost.instance
```

未装配时 `SyncHostHolder.instance` 是 `UnboundSyncHost`，调用即抛 `StateError`，不会静默跑出错误结果。

## 改代码时的规矩

- **同步语义（比对规则、路径处理、mtime 对齐、删除传播、分块大小）只能改这里**，改完两个客户端同时生效。
- **不要**为了某个客户端方便在这加分支（`if (isDesktop)` 之类）。有差异就加 `SyncHost` 方法。
- 新增宿主能力时：先改 `sync_host.dart`，再给两个客户端各补一个实现，最后跑两边的静态检查。
- `SyncEndpoint` 里的字段名（`local_dir` / `rel_paths` / `mtime_ms` …）是**服务端契约**，改之前先确认后端。

## 关键约定（别踩）

- **mtime 必须对齐**：上传带 `fileMtimeMs`、下载后 `setLastModified`。不对齐会被误判为"内容被修改"，导致每轮重传。
- **分块大小参与服务端会话 hash**（`'${fileHash}_$chunkSize'`），两端必须一致，否则断点续传失效。
- **删除传播很危险**：`deleteExtra` 未开启时绝不删；没有基线时绝不删。
- **POSIX 相对路径**：远端一律 `/` 分隔，落地本地时再用 `p.join` 交给平台。
- 基线库 `sync.db` 存在应用支持目录，属于「某账号 + 某设备」，**换账号必须清空**。
