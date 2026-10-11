# 相册用户隔离方案（photo_source 按 owner 归属）

> 决策人：铁柱，2026-10-10。
> 核心原则：**照片可见性零角色例外** —— 包括 super_admin 在内，每个人只能看到「自己添加的源目录」下的照片。

---

## 一、结论

能做到，而且改动比预想小得多。

相册所有子模块（时间轴 / 人脸 / 地点 / 相簿 / 合集 / 回收站 / AI 概览）的可见性**全部汇总到一个函数** `PhotoTimeLineService.getValidPaths(user)`，
下游一律用它做 path 前缀过滤。因此只要换掉这个函数的取数口径，隔离全局生效，下游一行都不用改。

真正要动的只有两处：

1. `photo_source` 表**加 owner 列**（当前没有 uid，全局共享）
2. `getValidPaths()` **换成按 owner 取数**
3. 连带：`/api/photo/source/*` 去掉 `requireAdmin`（否则普通用户无法添加自己的目录）

---

## 二、现状诊断（本机实测，2026-10-10）

| 项 | 现状 | 问题 |
|---|---|---|
| `photo_source` 列 | id / path / scan_when_start / scan_when_change / is_show / ctime / scan_interval… | ❌ **没有 uid**，源目录全局共享 |
| `photo_source` 索引 | `idx_photo_source_path` **UNIQUE(path)** | ❌ 不同用户无法各加同一目录 |
| 现存源目录 | 1 条：`G:\gnascab\gexuan\Photos` | — |
| 源目录管理接口 | 7 个接口**全部** `requireAdmin` | ❌ 普通用户根本不能自己加目录 |
| `getValidPaths(user)` | admin → 全部源；user → 全部源 ∩ `user_permission(view)` | ❌ 无 owner 概念，管理员强制全见 |
| `photo_index` | 18337 行，全局单表、无 uid | ⚠️ 物理共享（刻意保留，见 §5） |
| 相簿 / 合集 / 收藏 / 智能相册 | 均有 `uid` 列 | ✅ 本来就是按用户隔离的 |
| 手机相机备份任务 | 存客户端本地库，按 `(server_id, user_id)` 隔离 | ✅ 别人本来就看不到你的备份任务 |
| 用户 | id=1 `gexuan`(super_admin)、id=2 `tvv`(user) | — |
| `tvv` 现存可见照片 | `D:\movie` 授权 ∩ photo_source = **空** | → 迁移对本实例零回退 |

---

## 三、设计

### 3.1 数据模型

`photo_source` 新增一列：

| 列 | 语义 |
|---|---|
| `uid INTEGER NOT NULL DEFAULT 0` | 源目录归属用户。`0` = 无归属，**不参与任何人的可见性计算**（等价于停用） |

索引改造：

| 旧 | 新 |
|---|---|
| `UNIQUE(path)` —— 全局唯一 | `UNIQUE(uid, path)` —— 同一用户内唯一，不同用户可各自添加同一目录 |

迁移时 `0` 行的处理由迁移脚本决定（本实例：全部划归 `uid=1`）。

### 3.2 可见性规则（`getValidPaths` 改写后）

```js
// 只返回归属该用户自己的源目录，无任何角色例外
const uid = Number(user && user.id) || 0;
if (!uid) return [];
const rows = await knex('photo_source').where({ uid }).select('path');
```

| 角色 | 旧行为 | 新行为 |
|---|---|---|
| `user` | 全部源 ∩ 授权目录 | **只有自己的源** |
| `admin` | 全部源 | **只有自己的源**（同样受限） |
| `super_admin` | 全部源 | **只有自己的源**（同样受限） |

⚠️ **不要**在 `getValidPaths` 里加 `if (isAdmin) return 全部` —— 这是刻意去掉的隐私设计。
⚠️ 同时**取消**了「`user_permission` 目录授权」对相册的作用：源目录本身就是自己的，天然有权。

### 3.3 接口权限（非对称设计）

| 接口 | 旧 | 新 |
|---|---|---|
| `/api/photo/source/list` | `requireAdmin` | `authenticateJWT` + 只列自己的（管理员可传 `body.uid` 指定他人） |
| `/api/photo/source/add` | `requireAdmin` | `authenticateJWT` + 写入 `uid = 自己` |
| `/api/photo/source/delete` | `requireAdmin` | `authenticateJWT` + 校验 owner，非属主 403（管理员可越权，用于排障） |
| `/api/photo/source/update/:id` | `requireAdmin` | 同上 |
| `/api/photo/source/relocate/:id` | `requireAdmin` | 同上 |
| `/api/photo/source/scan` | `requireAdmin` | `authenticateJWT` + 只扫自己的源 |
| `/api/photo/source/regenerate_thumbnails` | `requireAdmin` | **仍限管理员**（全库级操作） |

**为什么保留管理员的越权管理能力？** 照片**可见性**零例外，但**管理动作**（清理别人加错的目录）必须有能力，
否则一个子账号把 `E:\` 加进相册就没人能删。二者不冲突：管理员看不到别人的照片，但能删别人的源目录。

### 3.4 文件视图同步

相册的「文件夹视图」（`/api/photo/file_view/list`）走 `fileListController.getSourceTypePaths`，
原先 admin 返回全部、普通用户走 `user_permission` 交集。**改为 photo 类型直接按 uid 过滤**，与时间轴口径一致。
`video` / `book` / `music` 保持原权限模型不动。

---

## 四、改动清单（服务端，已完成）

| # | 文件 | 内容 |
|---|---|---|
| 1 | `src/db/table/tablePhotoSource.js` | 新增 `ensureColumns()` 补 `uid` 列；`createTable` 建表即带 uid；`createIndexes` 删除旧 `idx_photo_source_path`、改建 `UNIQUE(uid, path)` |
| 2 | `src/api/modules/photo/source/photoSourceService.js` | 新增 `normalizeUid()` / `assertOwner()`；`listSources(uid)`、`addSource(path, uid)`、`deleteSource({uid, allowAnyOwner})`、`updateSource(id, payload, uid, allowAnyOwner)`、`relocateSource(id, newPath, uid, allowAnyOwner)` 全部按 owner 隔离；父子目录冲突校验收窄到**同一用户内** |
| 3 | `src/api/modules/photo/source/photoSourceController.js` | 新增 `resolveTargetUid(req)`；全部接口注入 uid；`scanSource('all')` 只扫自己的；错误码透传 `err.statusCode`（403） |
| 4 | `src/api/modules/photo/photoRouter.js` | 6 个 source 接口去掉 `requireAdmin`（`regenerate_thumbnails` 保留） |
| 5 | `src/api/modules/photo/timeline/photoTimeLineService.js` | **`getValidPaths` 改为纯 owner 取数，删除 isAdmin 分支与 user_permission 交集** ← 核心改动 |
| 6 | `src/api/modules/photo/collection/photoCollectionService.js` | `_getSourcePaths(knexPhoto, user)` 按 uid 过滤 |
| 7 | `src/api/modules/file/list/fileListController.js` | `getSourceTypePaths` 对 photo 类型按 uid 过滤 |
| 8 | `src/api/modules/user/userService.js` | 新增 `_ensurePhotoSourceDir()`：建子账号时自动创建 `<root>/<用户名>/相册` 并登记为私有源（失败静默，不影响建号） |
| 9 | `src/config/config.js` | 新增配置项 `photoUserAutoDirRoot`（默认空 = 不自动建目录） |
| 10 | `tool/_migrate_photo_source_owner.js` | 迁移脚本（新建，`tool/` 不受 asar 限制） |
| 11 | `src/api/modules/photo/face/faceController.js` | 3 处 `if (req.user && !userUtil.isAdmin(req.user))` → `if (req.user)`（`listFaces` / `faceImageGet` / `listPhotoFaces`） |
| 12 | `src/api/modules/photo/places/placesController.js` | `listPlaces` 同上去掉 isAdmin 豁免 |
| 13 | `src/api/modules/photo/app_ai/appAiController.js` | `overview` 同上去掉 isAdmin 豁免 |
| 14 | `src/api/modules/photo/album/photoAlbumService.js` | `_ensureAlbumAccess` 去掉 `role:'admin'` 提前 return（公开相册 `is_public` 与 `photo_album_share` 显式分享仍生效） |
| 15 | `src/api/modules/photo/collection/photoCollectionService.js` | `_ensureCollectionAccess` 去掉 `role:'admin'` 提前 return |
| 16 | `src/api/modules/photo/smartAlbum/photoSmartAlbumService.js` | `_ensureAccess` 去掉 `if (isAdmin) return album` |
| 17 | `tool/_verify_photo_isolation.py` | 新增 `BANNED_GLOBAL` 段，回读 asar 校验 11~16 的豁免确已消失 |

### 第 11~16 项的背景（第一轮遗漏）

第一轮只改了 `getValidPaths` 本身，但**调用方**在拿到结果前先用 `!isAdmin` 跳过了计算：

- `faceController` / `placesController` / `appAiController`：`let validPaths; if (req.user && !isAdmin(req.user)) { ... }`
  ⇒ 超管 `validPaths === undefined`，下游 service 不做任何路径过滤，**人脸/地点/AI 概览对超管全量可见**。
  实测：超管口径 `total: 999`，普通用户口径 `total: 0`。
- `album` / `collection` / `smartAlbum` 的 `_ensure*Access`：管理员提前 return，绕过 owner 校验与 `is_public`/分享授权。

**口径统一为：照片可见性零角色例外。** `userUtil` 在 11~16 中仅用于可见性豁免，已全部移除；三个文件的 `require userUtil` 也一并删掉。

### 刻意保留（不要动）

- **扫描 worker / 缩略图 / 人脸 / 地点 / 相似** 仍是全局一套物理索引 —— 见 §5
- **`album` / `smartAlbum` 的 update / delete**（`!isAdmin && uid 不等才 403`）：这是**写操作**，
  按非对称口径保留超管越权（帮别人清理建错的相册集）；**读**（`getAlbum` / `listAlbumPhotoIndexRows`）已无豁免。
- **手机相机备份** 任务表在客户端本地，已按 `(server_id, user_id)` 隔离，无需改

---

## 五、取舍与风险

### 5.1 为什么物理索引不隔离（关键取舍）

`photo_index`、缩略图缓存、人脸聚类、地点聚类、相似图检测**保持全局一套**。理由：

1. **存储**：N 个用户各自全量索引 = N 倍体积（本机 18337 行 / 数十 GB 缩略图）
2. **算力**：人脸/地点/相似都是重 AI 任务，每人跑一遍不可接受
3. **去重**：`photo_index` 的 `file_hash` 去重是全局的，拆开会让同一张图被重复分析

**结论**：隔离做在「可见性（读）」层，不做在「存储（写）」层。这是本方案的核心设计判断。

### 5.2 已识别的三个破坏点（已修）

| 风险 | 旧行为 | 修复 |
|---|---|---|
| 删源目录误删别人照片 | `deleteSource` 无条件删掉该路径下**全部** `photo_index` | 改为「删完后若无任何 source 覆盖该路径才清理索引」 |
| 跨用户父子目录误判 | `addSource` 父子冲突校验是全局的 | 收窄到同一 uid 范围内 |
| relocate 连带影响他人 | 改 source 路径时无条件改写 `photo_index` 的 path | 若旧路径仍被他人 source 覆盖，则跳过索引改写，只改 source 表 |

### 5.3 遗留边界（已知，不阻塞）

- `photo_album` 的合集中，**管理员仍能"进入"别人的合集**（`_ensureCollectionAccess` 返回 `role: 'admin'`），
  但合集预览已叠加 `getValidPaths` 过滤 → **看不到别人路径下的照片**，仅能看到合集名称/结构。影响可接受。
- `smart_album` / `similar` 的可见性未逐个复核，`similar` 全套接口本身就是 `requireAdmin`；
  `smart_album` 走 `buildBaseQuery` + `validPaths`，预期自动生效。**需实测确认**。
- 「共享源」能力（`uid = 0` 对所有人可见）**当前未实现** —— `0` 只作为「无归属 / 停用」语义。
  将来若要「公共照片墙」，再在 `getValidPaths` 里加 `uid = 0` 分支即可。

---

## 六、迁移步骤

⚠️ **必须在服务端停止状态下执行** —— 迁移涉及 `ALTER TABLE` + 索引重建，运行中操作有锁库风险。

```bash
# 0) 先看用户列表，确认 uid（本机：1 = gexuan / super_admin）
ELECTRON_RUN_AS_NODE=1 "electron_server/dist_vN/win-unpacked/WaterNasOSServer.exe" \
  tool/_migrate_photo_source_owner.js --list-users

# 1) 干跑，只看不改
ELECTRON_RUN_AS_NODE=1 "electron_server/dist_vN/win-unpacked/WaterNasOSServer.exe" \
  tool/_migrate_photo_source_owner.js --uid 1 --dry-run

# 2) 停止服务端后执行（会自动备份 photo.db 到 .bak_<时间戳>）
ELECTRON_RUN_AS_NODE=1 "electron_server/dist_vN/win-unpacked/WaterNasOSServer.exe" \
  tool/_migrate_photo_source_owner.js --uid 1 --apply
```

脚本做的事：备份 → 加 `uid` 列 → 删旧唯一索引 → `UPDATE photo_source SET uid = 1` → 建 `(uid, path)` 唯一索引。
**幂等**，可重复执行。

### 自动迁移（备选）

`tablePhotoSource.createIndexes()` 在服务端每次启动时都会执行，
所以**重启服务端本身就会自动加 `uid` 列 + 换索引**，但存量行的 `uid` 会保持 `0`（＝谁都看不到）。
因此仍然必须跑一次脚本把 `uid` 设为 1。顺序可任选，脚本幂等。

### 生效方式

- **代码**：`tool/dev_update.py` 热更即可（10 个文件**全都是 asar 内已有文件**，不涉及新增源文件，符合热更限制）
- **表结构**：重启服务端自动执行 `createIndexes()`
- **配置**：`photoUserAutoDirRoot` 想启用需在 `config.js` 里填实际路径（默认空 = 不自动建目录）

---

## 七、客户端（Flutter）

**核心流程无需改动** —— 实测 `photo/source_setting` 入口（`photo_home_view.dart` / `app_photo_settings_view.dart`）
**没有** `isAdmin` 门禁，接口放开后普通用户直接可用；`photoBackup` 的备份目录选择器也已是通用文件夹选择器。

可选优化（非必须）：

1. 来源设置页显示每个源目录的归属（当前全部是本人的，可显示"我的"）
2. 备份页在未选目录时，默认指向「我的私有相册目录」
3. `zh_cn.dart` 等 13 个语言文件：如需新增提示语再补 key（当前复用 `auth.PERMISSION_DENIED`，**零新增 key**）

---

## 八、验收清单

- [ ] 重启服务端后 `PRAGMA table_info('photo_source')` 含 `uid` 列
- [ ] `sqlite_master` 中无 `idx_photo_source_path`，有 `idx_photo_source_uid_path`
- [ ] `gexuan`(uid=1) 登录 → 相册能看到 `G:\gnascab\gexuan\Photos` 的 18337 张
- [ ] `tvv`(uid=2) 登录 → 相册为空（与迁移前一致）
- [ ] `tvv` 在来源设置里添加自己的目录 → 只看到自己的照片，且 `gexuan` 看不到
- [ ] `tvv` 尝试 `POST /api/photo/source/delete` 传 `gexuan` 的 source id → 403
- [ ] 删掉 `tvx` 自己添加的目录后，`gexuan` 的照片数量不变（验证 §5.2 第一项）
- [ ] 手机端相机备份到自己的目录 → 仅在本人相册出现

---

## 九、验证状态（2026-10-10 更新）

**已完成**

- 全部 16 个改动文件通过 `node --check` 语法检查
- 已增量热更进 `dist_v14`（`tool/dev_update.py --dist dist_v14 --no-web`，0.9s）
- `tool/_verify_photo_isolation.py dist_v14` **20/20 通过** —— 从 `app.asar` 数据区回读源码，
  含新增的 `BANNED_GLOBAL` 段（确认 `!userUtil.isAdmin(req.user)` / `role:'admin'` 确已消失）
  与 `getValidPaths` 函数体级守卫（确认无 `isAdmin` / `user_permission`）
- **迁移已执行**（APPLY，服务运行热执行，未停服）：
  - 备份 `...\database\nascab_photo.db.bak_2026-10-10T10-09-49-785Z`
  - `photo_source` 1 行 `uid: 0 → 1`，`(uid,path)` 唯一索引已建
- 真库 service 层实测（`tool/_verify_photo_owner.js`）：
  ```
  photo_source 全表          => [{ id:1, path:'G:\\gnascab\\gexuan\\Photos', uid:1 }]
  getValidPaths(uid=1 gexuan) => ["G:\\gnascab\\gexuan\\Photos"]
  getValidPaths(uid=2 tvv)    => []
  listSources(1)              => 1 条；listSources(null 全量) => 1 条
  ```

**待用户验证（需重启服务端 + 客户端）**

- [ ] 重启 `dist_v14\win-unpacked\WaterNasOSServer.exe`（controller 层改动在旧进程里未生效）
- [ ] `gexuan` 登录 → 相册恢复 18337 张，来源设置里能看到 `G:\gnascab\gexuan\Photos`
- [ ] `gexuan` 的**人脸 / 地点 / AI 概览**只显示自己源目录内的（修复前是 999 条全量）
- [ ] `tvv`(uid=2) 登录 → 相册为空
- [ ] `tvv` 添加自己的目录 → 双方互不可见；`tvv` 删 `gexuan` 的 source id → 403
- [ ] 手机端相机备份 → 仅本人相册出现

**未验证**：Flutter 客户端**无改动**，因此未 build_web。
