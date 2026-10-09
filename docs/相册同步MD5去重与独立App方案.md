# 相册同步 MD5 去重 + 独立 App（相册 / 音乐）方案

> 状态：方案待确认，尚未动代码。所有行号基于当前工作区代码。

---

## 0. 一句话结论

- **现状**：相册备份**没有内容 MD5 去重**，唯一的跳过依据是「目标路径下同名文件已存在」。
  ⇒ 后果 A：同一张图改了名或换了目录，会**重复上传**；后果 B：同名但内容已变，会被**误跳过**。
- **能做**：完全可以。推荐**先做客户端侧「大小 + 内容 MD5」双条件去重**（服务端零改动，复用现成的
  `/api/file/md5` 接口与 `decideSmartUpload` 判定），跑顺后再按需升级成**服务端内容索引**（做到跨文件名去重）。
- **独立 App**：参照已有样板 `sync_client`，把相册 / 音乐代码抽成共享包，新建 `photo_client/`、`music_client/`。

---

## 1. 现状盘点：所谓「相册同步」目前其实是三条互不相干的链路

| 链路 | 代码入口 | 方向 | 跳过判据 | 有内容 MD5？ |
|---|---|---|---|---|
| **相册备份** `photoBackup` | `flutter_client/lib/modules/photoBackup/controller/photo_backup_controller.dart` | 手机相册 → NAS | 服务端「同名文件已存在」→ 409 | ❌ |
| **目录同步** `sync` | `flutter_client/lib/modules/sync/` + `packages/nascab_sync_core` | 电脑目录 ↔ NAS | `size` + `mtime`（±2s） | ❌ |
| **PC 本机备份** `fileBackup/localBackup` | `flutter_client/lib/modules/fileBackup/localBackup/local_backup_controller.dart` | 电脑目录 → NAS | `size` + **内容 MD5** | ✅ **全仓唯一** |

关键实现定位：

- 上传统一入口：`UploadCore.processFile`（`transfer/controllers/upload_parts/upload_core.dart:143`）；
  check 请求体在 `:200-211`，续传 / 同名跳过判定在 `:225-238`。
- 服务端 check：`electron_server/src/api/modules/file/upload/uploadController.js:192-246`。
  逻辑仅两条——`strategy==='skip'` 且目标同名文件已存在 → `409 file.FILE_EXISTS`；否则返回已上传分片号。
- 请求里的 `hash` **不是内容哈希**，是上传会话标识：
  `photo_backup_controller.dart:378-384` = `sha256('${sourceUniqueId}|${size}|${fileMtimeMs}')`。
- 服务端**已有**内容 MD5 接口 `GET /api/file/md5`（`api/modules/file/list/fileListController.js:648-690`，
  小文件全量、大文件头 1MB + 尾 1MB），PC 本机备份已经在用（`local_backup_controller.dart:1302-1336`）。
- 相册自己的 `photo_index.file_hash` **不是内容 MD5**，是 `md5(basename_size_birthtime)` 元数据指纹
  （`src/utils/fileUtil.js:9-17`，`src/workers/photoIndex/photoIndexIndexUtil.js:271`），只用于相似照片分组。

**结论**：相册备份现在是「同名就跳过、换名必重复、同名换内容会漏传」。你说的「MD5 一致就不上传」，当前
**完全没有实现**，但底层零件（`/api/file/md5` + 客户端 `computeFileMd5` / `decideSmartUpload`）已经齐全，
只是**没接到相册备份链路上**。

---

## 2. 目标

- G1：相册备份时，**目标端已存在内容相同的图片 → 不上传**（跳过，不计入失败）。
- G2：内容不同 → 正常上传并覆盖，不因同名而丢图。
- G3：二次运行不重复计算 MD5（大相册性能）。
- G4：先落**主客户端**，同一套逻辑再带到**新增的独立相册 App**（逻辑放共享包则自动生效）。

---

## 3. 方案：相册同步 MD5 去重

### 3.1 判定规则（复用已经验证过的现成逻辑）

直接调用现成的两件套，不自造轮子：

- `UploadTransferHelper.computeFileMd5()`（`upload_transfer_helper.dart:235`）
  —— `< 50MB` 全量 MD5；`≥ 50MB` 取「头 1MB + 尾 1MB」。图片基本都 < 50MB，即真实全量 MD5。
- `UploadTransferHelper.decideSmartUpload()`（`upload_transfer_helper.dart:221`）
  —— 判定表：

| 远端状态 | 判定 |
|---|---|
| 不存在 | 上传 |
| 存在但不是文件 | 报错 |
| 大小不同 | 上传（覆盖） |
| 大小相同 + MD5 相同 | **跳过** |
| 大小相同 + MD5 不同 | 上传（覆盖） |
| 远端大小读不到 | 上传（保守） |

> ⚠️ 头/尾 MD5 只在**大小相同**时才有意义，所以必须「大小 + MD5」**双条件**，绝不能只比 MD5。

### 3.2 分三步走（P0 立即可用 → P2 才算真正「内容级」）

#### P0　客户端侧「双条件」跳过（服务端零改动）

- 改动点：`photo_backup_controller.dart` 三个上传点统一加一层判定——
  `:386`（album 流式）、`:520`（folder 常规）、`:673`（album 增量）。
- 流程：
  1. 先 resolve 出远端的最终路径 `finalPath`（要复刻服务端的 `saveType` 年/月/日归档子目录 + `relativePath` 规则）。
     参考 PC 备份的做法：调 `/api/file/list` 拿到 `{exists, isFile, size, path}`（`local_backup_controller.dart:739, 1291-1300`）。
  2. `size` 相同 → 本地 `computeFileMd5` + `GET /api/file/md5?path=finalPath` 取远端 MD5。
  3. `decideSmartUpload()` 出结论；`skip` 记为 `skipped`（沿用现有 file_record 的 `skipped` 状态），否则照常
     `processFile` 上传（需要覆盖时用 `nameStrategy: 'overwrite'`，服务端已支持，见 `uploadController.js:376`）。
- 抽一个 helper（如 `PhotoBackupRemoteResolver`）封装「resolve 最终路径 + 取远端 MD5」，三个上传点共用。
- 代价：每张图多 2 个请求（resolve + md5）。首次全量会明显变慢 ⇒ **建议 P0 与 P1 一起上**。
- 局限：只能发现「同名同路径」的重复；**改名 / 换目录的同一张图仍会重复传**。

#### P1　本地 MD5 缓存（性能，强烈建议与 P0 同批）

- `photo_backup_storage.dart` 新增表 `photo_backup_hash_cache(source_unique_id, size, mtime_ms, md5, updated_at)`。
- key = `sourceUniqueId + size + mtimeMs`，命中直接取 md5，**不再重算**；未命中才算并回写。
- 效果：首次全量仍需算一遍 MD5；之后每次备份几乎零额外开销。

#### P2　服务端内容索引（可选，做到「已经有的图片内容」真正意义的去重）

- 新增内容哈希表，例如 `photo_content_index(id, uid, md5, size, path, create_time)`，`md5` 建索引；
  （或直接在 `tablePhotoIndex.js` 的 `photo_index` 上加一列 `content_md5`）。
- 新能力二选一：
  - **扩展 check**：`/api/file/upload/check` 增加可选字段 `clientMd5` 与新策略 `skip_same_content`
    —— 命中同名时由服务端比 MD5（同 → 跳过 / 不同 → 覆盖）；无同名但库内已有同 MD5 → 按开关跳过。
  - **独立查询接口**：`GET /api/photo/content-md5?md5=xxx&scope=<targetDir|sourceId>`，客户端查完再决定。
- 安全性：`res_type` 必须是 `'file'`；查询结果必须过 `getValidPaths(user)` 过滤（只返回用户可见路径）；
  service 写操作 `uid` 必填；**不改** `/api/file/upload/check` 现有 `skip` 语义（其他链路在用）。
- 需处理的边界：同一 MD5 多条路径（保留首个，其余记引用）、并发写入、跨用户隐私（只比对自己可见范围）。

### 3.3 风险与坑（实施前必读）

1. 头/尾 MD5 只在尺寸相同时可比 —— 必须双条件，否则会误判。
2. `saveType` 归档会让「同名文件落在不同日期目录」⇒ 客户端 resolve 规则**必须与服务端一致**
   （服务端规则见 `uploadController.js:336-348`），否则会出现「服务端认为已存在、客户端算出的路径不存在」。
3. 相册量级大（几万张），P0 每张 2 个请求可能拖慢首次备份 ⇒ 必须配 P1 缓存。
4. 现在跳过依赖服务端 409（`upload_core.dart:227` 识别 `file.FILE_EXISTS`）；改成客户端判定后，
   **保留 409 兜底**（并发/边界情况仍可能命中）。
5. `nameStrategy` 取值为 `skip | rename | overwrite`（`uploadController.js:361-381`）；覆盖上传用 `overwrite`。
6. 逻辑只改客户端即可满足 G1/G2/G3；**不要**顺手改 `/api/file/upload/check` 的默认行为。

---

## 4. 方案：独立 App（相册 / 音乐）

### 4.1 形态（**需要你拍板**）

- **解读 A（推荐）**：真正的独立程序 —— `photo_client/`（相册）、`music_client/`（音乐），
  参照 `sync_client/` 的单体结构，各自一个 exe。
- **解读 B**：只是主客户端内新增一个 appKey 入口（不是真独立）。

下面按 **解读 A** 展开。

### 4.2 代码复用策略（关键难点）

`sync_client` 之所以能直接复用，是因为同步逻辑在**纯 Dart 包** `packages/nascab_sync_core`。
相册 / 音乐模块是 **Flutter UI + GetX**，散在主 App 里，**无法被另一个 Flutter 工程 path 依赖**。
所以必须先把要复用的代码「抽出包」。三种做法：

| 方案 | 做法 | 优点 | 代价 |
|---|---|---|---|
| **1（推荐，标准做法）** | 抽 3 个包：`nascab_app_core`（API/鉴权、i18n、主题、上传核心、通用 model、目录选择等公共基建）、`nascab_photo_module`（photo + photoBackup + gallery）、`nascab_music_module`；主客户端与新 App 都 path 依赖 | 单一代码源，日后同步零成本 | 大重构，涉及海量 import 改写（注意：`lib/` 本就有 ~40 处相对 import 断链，属于既有问题，别混进来一起改） |
| 2（务实折中） | 新 App 工程直接复制主客户端 `lib/`，只改入口与 app 列表 | 一周内能出东西 | 两份代码，每次改动要手动同步（正是你想避免的） |
| 3（最省事） | 不建独立 App，只把相册/音乐作为新 appKey 加进主客户端 | 改动最小 | 不是「独立 App」 |

> 注意：独立 App 场景下，服务端 `defaultApps` **不用动**（该列表只服务主客户端的 `GET /api/apps/getApps`）。

### 4.3 独立 App 落地清单（按方案 1）

1. 建 `photo_client/`，`pubspec.yaml` `name: nascab_photo`，path 依赖 `packages/nascab_app_core` +
   `nascab_photo_module`（照抄 `sync_client/pubspec.yaml:39-41` 的 path 依赖写法）。
2. `lib/main.dart`：登录态 → 装配 → `runApp`；相册端不涉及同步，无需 `SyncHost`。
3. **平台工程三坑（照 `sync_client/README.md`，否则与主客户端冲突）**：
   - `windows/runner/utils.cpp`：单实例 mutex / 窗口类名 / 单实例消息名 / exe 名**必须全改**；
   - `windows/flutter/generated_plugins.cmake` 与 `generated_plugin_registrant.cc` **清空**；
   - `windows/CMakeLists.txt` 的 `project` / `BINARY_NAME`、`Runner.rc` 产品名、`app_icon.ico` 换专属。
4. 路由只保留相册相关（`/app_photo_*`）。
5. 图标 / 显示名 / 版本号。

### 4.4 音乐独立端同理

- `music` 模块体量较大（≈62 个文件），含 `play_service`（just_audio / 视频双引擎）、
  `cache/music_audio_cache_io.dart` + `_stub.dart`（平台条件导入）⇒ 抽包时注意条件导入要一起搬。
- 抽成 `nascab_music_module` 后，`music_client/` 与主客户端共用播放引擎代码。

---

## 5. 建议推进顺序

1. **【本轮可做】主客户端相册备份 P0 + P1**（MD5 双条件 + 本地缓存）——服务端零改动，收益立竿见影。
2. 抽 `packages/nascab_app_core` + `packages/nascab_photo_module`（较大，建议单独一轮做，先跑全自检脚本）。
3. 建 `photo_client/`，此时 P0/P1 成果**已在共享包里，自动生效**。
4. 同理处理 `music_client/`。
5. （可选）P2 服务端内容索引，把去重升级到「跨文件名」。

---

## 6. 已拍板（2026-10-08 铁柱确认）

1. **独立 App 的形态** → **独立 exe**（`photo_client/`、`music_client/`）。
2. **MD5 去重深度** → **P0「同名 + 同内容即跳过」**（服务端零改动）；P2 内容级跨名去重暂不做。
3. **代码复用** → **抽共享包 / 共享代码源**（不复制业务代码）。

---

## 7. 已落地实现（2026-10-08）

### 7.1 相册备份内容级去重（主客户端 P0 + P1）

改动文件：

- `flutter_client/lib/modules/photoBackup/controller/photo_backup_controller.dart`
  - 三处重复的上传块（原 :385 / :519 / :672）抽成统一方法 `_uploadEntry()`，去重逻辑只写一份。
  - 新增 `_shouldSkipExistingContent()`：`GET /api/file/attributes/resolve`
    （带 `targetDir` + `relativePath`）取远端同名文件 → 比对 `size` →
    本地算 MD5 与 `GET /api/file/md5` 的远端 MD5 比对 → 相同返回 `true`（跳过）。
  - 新增 `_computeLocalMd5()`：进程内 Map 缓存 → sqlite 缓存 → 实算回写；
    算法与服务端一致（`< 50MB` 全量，`>= 50MB` 头/尾各 1MB），与服务端默认阈值严格对齐。
  - 新增 `_getJson()` / `_asIntOrNull()` 两个小工具。
- `flutter_client/lib/modules/photoBackup/storage/photo_backup_storage.dart`
  - 数据库 `version 2 → 3`；新增表 `photo_backup_hash_cache(source_unique_id, size, mtime_ms, md5, updated_at_ms)`；
    `onCreate` + `onUpgrade(<3)` 双路径建表。
  - 新增 `loadHashCache()` / `upsertHashCache()`。

行为约定：

- 命中内容一致 → 记 `success`（与既有「服务端 409 同名跳过」的成功语义保持一致），并推进 cursor。
- **`saveType`（按年月日归档）不为空时不启用客户端判定** —— 该模式下最终路径由服务端
  依据 EXIF 拍摄时间计算，客户端无法可靠复现，回退到原有「同名 409 跳过」行为。
- 任何异常（网络 / 无 view 权限 / 读取失败）一律返回 `false`：**宁可多传一次，不可漏传**。

### 7.2 独立 exe（`photo_client/` + `music_client/`）

**复用方式（= 方案 1 的落地形态）**：独立端通过 `path: ../flutter_client` 依赖主客户端
（包名 `GNasCab`），**不复制任何业务代码**；主客户端新增一个启动开关：

- 新增 `flutter_client/lib/core/bootstrap/app_launch.dart`：`AppLaunchMode { full, photo, music }`
  + `AppLaunch`（`appTitle` / `allowedAppKeys` / `isAppAllowed()` / `autoOpenAppKey`）。
- `flutter_client/lib/main.dart`：`main()` → `runGNasCabApp({launchMode})` 共享入口；
  `title` 改用 `AppLaunch.appTitle`；独立端只需 3 行代码调用。
- `flutter_client/lib/modules/home/views/app_home_controller.dart` + `pc_home_controller.dart`：
  `showApps` / `_effectiveAllApps` 按 `AppLaunch.isAppAllowed()` 过滤（只留目标应用）。
- `flutter_client/lib/modules/home/views/pc_home_page.dart`：非 `full` 模式下 **在 `build()` 里
  直接返回目标应用视图**（`builtinAppViewBuilder(AppLaunch.autoOpenAppKey)`），
  不再渲染虚拟桌面 / dock / 启动器 ⇒ **登录后整屏即相册/音乐，不存在「在主程序里选」这一步**。
  `full` 模式下 `autoOpenAppKey` 恒为 `null`，桌面行为完全不变。
- `flutter_client/lib/utils/app_window_title.dart`：`defaultTitle` 改为跟随
  `AppLaunch.appTitle`（`GNasCab` / `GNasCab 相册` / `GNasCab 音乐`），避免标题被重置。
- `flutter_client/lib/modules/home/views/app_home_controller.dart`：移动端同样自动进入目标应用
  （桌面独立端走上面的 `pc_home_page` 分支）。

独立端工程（各自包含 `pubspec.yaml` / `lib/main.dart` / `windows/` / `android/` / `assets/` / `README.md`）：

- 产物：`NasCabPhoto.exe` / `NasCabMusic.exe`，**与主客户端可同时运行、互不干扰**。
- 平台工程三坑已处理：单实例 mutex（`Global\NasCabPhoto_SingleInstance`）、窗口类名
  （`NASACB_PHOTO_WIN32_WINDOW`）、单实例消息名、exe 名全部独立；
  `generated_plugins.cmake` 与 `generated_plugin_registrant.cc` 已清空。
- **图标独立**：`windows/runner/resources/app_icon.ico`、`assets/app_icon.ico`、
  `assets/tray_icon_round.ico` 均由 `assets/app_icons/{photo,music}.webp` 生成
  —— exe 图标 = 黄蓝相机 / 红色音符，与主客户端的蓝色箭头完全不同。

#### 7.2.1 两个「依赖方拿不到」的坑（都已补）

`path:` 依赖**不会**把主客户端的下面两样东西带过来，必须各自声明：

| 项 | 现象 | 处理 |
|---|---|---|
| `dependency_overrides` | 静默退回 pub 版 `audio_service` ⇒ 桌面 `MediaSession.onPlayPause` 不转发、播放/暂停键无响应（音乐端最明显） | 两个独立端 pubspec 各写一遍，路径 `../flutter_client/packages/audio_service`、`.../dchs_motion_sensors` |
| `assets:` | 主客户端的 `assets/...` 键在独立端**不存在**（依赖包的资源只在 `packages/<pkg>/assets/...` 下）⇒ 图片全丢 | 各自复制子集并各自声明 |

而且 Flutter 的 **`assets:` 目录条目不递归** —— 只写 `- assets/icons/` 拿不到
`icons/home/`、`icons/file/` 等子目录；`music/musicCover96~384/` 这五个分档封面目录
也必须逐条列出，否则播放页缺图。

有意不打包（对应模块在独立端不可达）：`assets/music/`（相册端）、
`assets/book/` + `assets/web/`（阅读器，两端都排除）。

新增两个自检脚本（静态比对，**不替代** `flutter build` 的资产校验）：

```bash
python tool/_check_standalone_pubspec.py   # assets / dependency_overrides / fonts 是否都落地
python tool/_check_standalone_assets.py    # lib 里引用的 assets 是否都拷到了
```

实测结果：pubspec 校验 `FAIL 0`；资源比对「非预期缺失 0 条」，
排除项全部落在 `book/` `web/` `music/`（相册端）这几个不可达模块上。

### 7.3 Android 独立 App（2026-10-08 追加）

Windows 只是「独立端」的一半 —— 手机上要三个 App 并存，靠的是 **applicationId 必须各不相同**。

做法与 Windows 同源：从 `flutter_client/android` **整棵复制**后打补丁
（生成器 `tool/_gen_standalone_android.py`），而不是 `flutter create` 一个新工程
（后者会丢掉主客户端里所有 Android 定制）。

| 项 | 主客户端 | 相册端 | 音乐端 |
|---|---|---|---|
| applicationId / namespace | `com.nascabos.mobile` | **`com.nascabos.photo`** | **`com.nascabos.music`** |
| Kotlin 包目录 | `com/nascabos/mobile/` | **`com/nascabos/photo/`** | **`com/nascabos/music/`** |
| 桌面名 `android:label` | `GNasCab` | **`GNasCab 相册`** | **`GNasCab 音乐`** |
| 启动图标（15 张） | 主端图标 | **黄蓝相机** | **红色音符** |

必须跟着一起带走、**不能**用 `flutter create` 重建的定制件：

- `app/src/main/kotlin/.../playback/`（Media3 播放器 PlatformView / 会话 / 方法通道）
- `MainActivity : AudioServiceActivity` 与 manifest 里的 `AudioService` / `MediaForegroundService`
  / `MediaButtonReceiver` 声明（后台播放、通知栏、锁屏控制全靠它）
- `zxing_android_embedded_patched/`（**合规补丁**：替换 `com.journeyapps:zxing-android-embedded`，
  避免 OrientationEventListener 传感器访问被应用商店判违规）+ `settings.gradle.kts` 里的
  `include(":zxing_android_embedded_patched")` 与 `dependencySubstitution`
- `app/libs/lib-decoder-ffmpeg-release.aar`（万能软解）+ media3 三件套 + desugaring
- 根 `build.gradle.kts` 的国内 maven 镜像、`ndkVersion 28.2.13676358`、`gradle.properties`

刻意**没动**的两处：

- MethodChannel 名 `com.nascabos/playback` / `com.nascabos/playback_events/*`
  —— Dart 侧 `media3_playback_engine.dart` 写死了同样的串，跟着包名改会直接失联；
- manifest 其余部分与主客户端**逐行一致**（只有 `android:label` 不同）
  —— 权限集（INTERNET / CAMERA / 媒体读取 / FOREGROUND_SERVICE_*）两端都留着，
  差异化裁剪留给后续按需处理。

顺手修正一处**潜伏 bug**：`lib/core/config/app_build_config.dart` 里
`androidApplicationId` 原本是写死的 `const 'com.nascabos.mobile'`
（全项目当前无人引用，但独立端一旦用到就会报错的身份），已改为跟随 `AppLaunch.mode`。

自检脚本 `tool/_check_standalone_android.py` 覆盖：applicationId 三端唯一且不同于主端、
namespace 一致、Kotlin 包目录已改名且无 `com.nascabos.mobile` 残留、label 正确、
channel 名未被动过、`GeneratedPluginRegistrant.java` 已排除、15 张图标齐全且与主端不同、
gradlew/wrapper/local.properties/ffmpeg aar/zxing 模块在位。实测 **FAIL 0**。

### 7.4 遗留 / 待办

- [ ] **未编译验证**：本机 Dart 无法创建子进程，`flutter pub get` / `flutter build windows` /
  `flutter build apk` 都跑不起来，需在装有 Flutter SDK 的机器上首次构建（两个工程都要先 `pub get`）。
- [ ] 独立端暂未做安装包（Windows 同 `sync_client` 整目录分发；Android 是 apk/aab）。
- [ ] Android 发布签名 `android/key.properties` **未创建**（被 `.gitignore` 排除，且属机密），
  需自行创建；可与主客户端共用同一个 keystore。无它时 release 构建会因 keystore 为空而失败。
- [ ] Android 各端权限集当前与主客户端**完全一致**（含音乐端用不到的媒体读取权限），
  若在意商店合规扫描可后续按端裁剪。
- [ ] P2 服务端内容索引（跨文件名去重）未做 —— 若日后需要「改了名也不重复传」，再做这一层。
- [x] 独立端 `dependency_overrides` 已各自声明（见 7.2.1）。
- [x] 独立端 `assets/` 已按「逐个子目录声明」补齐，并加了两个自检脚本。
      日后在主客户端新增资源引用时，跑一次自检脚本即可发现遗漏。
- [x] Android 平台工程已生成（见 7.3），并有 `tool/_check_standalone_android.py` 自检。
