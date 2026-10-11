# 足迹地图缩放粒度 + 人脸 GPU 加速 —— 改动说明

日期：2026-10-09
状态：**已打包，需你手动启动 `dist_v3` 的 exe 验证**

------------

## 一、足迹地图：缩放时自动合并 / 拆分

### 你提的问题（诊断结论）

> 「缩小地图后，照片集也应该是把附近的照片集全部整合到一起，
> 这个应该有个显示粒度和照片的对应关系」

查证后确认，你的感觉是对的，但根因不是「代码写死了 10 张」——
**全库搜 `10` 只有 UI 尺寸**。真机制是：

1. marker = **一个 geohash 网格**，每格只取 1 张代表图当 marker
   ⛔ **照片总数从来没被 SELECT**，客户端模型里也没有 count 字段
   ⇒ UI 拿不到「这个点代表几张照片」，只能画个缩略图
2. 网格精度**确实随 zoom 换挡**（z≤4 用 2 位 ≈150km，z>14 用 6 位 ≈1.2km）
3. ⛔ **点开反查恒用 6 位**（`nearbyRangeKm=2` 写死）
   ⇒ 缩小后 marker 代表 150km，点开只列 1.2km 内的照片 —— **这就是你说的「丢失」**

### 改动内容

| 层 | 文件 | 改了什么 |
|---|---|---|
| 服务端 | `photoMapService.js` | 分组查询加 `count(photo_index.id) as photo_count` |
| 服务端 | `photoMapService.js` | 新增 `_cellCenter()`，用 `ngeohash.decode()` 求格心 |
| 服务端 | `photoMapService.js` | 每条 marker 附 `photo_count` / `cell_precision` / `cell_lat` / `cell_lng` |
| 客户端 | `photo_map_models.dart` | 加 `cellLat/cellLng/photoCount/cellPrecision` + `isCluster` |
| 客户端 | `photo_footprint_map_controller.dart` | marker 定位优先用**格心**，缩放换挡不再漂移 |
| 客户端 | `photo_footprint_map_view.dart` | marker 尺寸改按 `item.photoCount`（原来传全屏总数） |
| 客户端 | `photo_footprint_map_view.dart` | 新增 `_ClusterCountBadge` 右上角数字气泡 |

**顺带修了一处真 bug**：marker 之前落在「网格里 id 最大（最新）的那张照片」坐标上，
位置随机 ⇒ 缩放换挡时同一区域的 marker 会跳来跳去。落到格心后稳定。

**修了一处一致性问题**：点开 marker 的反查精度现在**跟随该 marker 的档位**，
不再固定用 2km。这条链路由铁柱要求的粒度一致性一路透传到
`PhotoTimelineController.geohashForRequest`。

### 你会看到的变化

- 缩小地图 → 附近的照片合成一个大点，**右上角显示总张数**（超过 9999 显示 1.2k）
- 放大 → 数字角标自动消失，回到单张照片的 marker
- 点开 → 列出的照片数与地图上那个点代表的范围一致

------------

## 二、人脸识别：GPU 加速（实测快 2.1倍）

### 根因：一处硬编码

`faceUtil.js` 里 `executionProviders: ['cpu']`写死了。
而同一个仓库的 `placesUtil.js`（场景识别）和 `ocrOnnxUtil.js`（OCR）
**早就在用 `getBestExecutionProviders()`** ⇒ 三处不一致，
人脸是唯一没吃上 GPU 的。而 `DirectML.dll` 白打包了 35MB 一直在用不上。

### 改法

优先 GPU，**失败自动退回纯 CPU**（DML 在驱动异常的机器上会直接抛异常，
不能让整个 AI 功能挂掉）。

```js
const wanted = getBestExecutionProviders();
if (wanted.length > 1) {
  try { loaded = await buildSessions(wanted); }
  catch (e) { Logger.warn(`... fallback to CPU`); loaded = null; }
}
if (!loaded) loaded = await buildSessions(['cpu']);
```

### 实测数据（本机）

| 项 | CPU | DirectML |
|---|---|---|
| ArcFace 单张推理 | 52.7 ms | **24.7 ms（快 2.1 倍）** |
| 引擎初始化 | 1148 ms | 1951 ms |

- `listSupportedBackends()` 实测返回 `[{cpu},{dml}]` ⇒ DML 可用
- 设置里关掉 GPU（`AI_GPU_PREFER=0`）→ 正确降级为 `Selected providers: cpu`
- **打包后的 exe 内已验证**：`Selected providers: dml, cpu`

---

## 三、模型量化：**实测不划算，已否决**

你说「这个 int8 模型不能下载吗」—— 能，网络是通的。
我装到隔离 venv 里真跑了，结果如下：

| 项 | fp32 | INT8 量化 |
|---|---|---|
| 体积 | 248.6 MB | **62.5 MB（省 186 MB）** |
| 推理速度（CPU EP） | 75.4 ms | **1267 ms（慢 16.8 倍）** |
| 同一张图 fp32↔int8 相似度 | — | 0.9706 |

⛔ **两个问题导致没接入**：

1. **精度无法验证**。我用随机噪声做测试，发现 fp32 类间相似度就有0.92——
   说明这个测法无效。而你本地的 `photo_faces` / `photo_face_samples`
   **都是 0 行**，没有真实人脸数据。所以我不能拍胸脯说「精度没问题」。
2. **INT8 在 CPU 上反而慢 16 倍**。动态量化的算子没有优化，
   省了体积却换了速度，不划算。

量化产物留在 `_patch_backup/2026-10-09_足迹地图粒度/model_int8.onnx`，
没有接入代码，你可以随时取用或让我删掉。

### ⭐ 顺带查到一条更优路线（**没实施，等你定**）

比量化更值得考虑的**换模型**方案（都是 112×112 输入 / 512 维输出，接口一致）：

| 模型 | 体积 | LFW 精度 | 说明 |
|---|---|---|---|
| 现状 ArcFace R50 | 249 MB | 99.83% | IJB-C 97.25% |
| **EdgeFace XXS** | **5 MB** | 99.57% | IEEE T-BIOM 2024，1.24M 参数 |
| EdgeFace XS_GAMMA_06 | 7 MB | 99.73% | |
| MobileFace MNET_V2 | 4 MB | 99.55% | |
| AdaFace IR_18 | 92 MB | — | IJB-C 94.99%，**低质量图最强** |

⚠️ **但换模型不是换个文件就完事**，有四个坑：
1. 预处理参数要改（你现在是 **BGR + /128**，多数模型是 **RGB + /127.5**）
2. **阈值必须重新标定** —— 实测有模型给陌生人打的分比另一个高 3 倍，
   同一套阈值结论会完全反过来
3. `faceWorker.js` 里有 `new Float32Array(512)` 和 24 维符号签名分桶的硬假设
4. 全库要重算索引（清三张表 + 重跑 `gen_faces`）

⚠️ 还有个许可问题：**ArcFace/InsightFace 权重是非商用研究许可**，
真要商用得考虑 Apache-2.0 的模型。

------------

## 四、打包结果

| 产物 | 状态 |
|---|---|
| 服务端 `dist_v3/win-unpacked/WaterNasOSServer.exe` | ✅ 12:57 / 204.5 MB |
| ABI 验证 | ✅ ABI=136 / Electron 37.9.0，10 个 native 全通过，better-sqlite3 与 sharp 真调用成功 |
| web `main.dart.js` | ✅ 13:00 / 13008525 bytes（比旧包 +2692）/ SW 0 字节 |
| 两处 web 拷贝 | ✅ `electron_server/web/main/` 与 `dist_v3/win-unpacked/web/main/`，均 13008525 / 30 文件 |
| asar 内含新代码 | ✅ 地图三字段与 GPU 两处改动全部命中 |

⚠️ **打包时踩了个坑**：`dist` 目录 3.7G，electron-builder 清空它时回收站超时直接失败
⇒ 改用 `--config.directories.output=dist_v3` 换新目录，3分19秒成功。

------------

## 五、需要你验证（三件事）

**手动启动** `electron_server/dist_v3/win-unpacked/WaterNasOSServer.exe`
（沙箱里起不了 Electron GUI 服务端），然后：

1. **影视详情** —— 点开任意影片，看是否还报「加载失败」
2. **足迹地图** —— 进「我的足迹」，缩放地图看：
   - 缩小时附近是否合并成带数字的点
   - 数字角标张数是否合理
   - 点开后的照片数是否与地图一致
3. **人脸索引** —— 如果有开了人脸识别的相册目录，观察索引速度是否变快
   （设置里可以开关 GPU）

------------

## 六、遗留问题（本次未处理）

⚠️ **影视详情鉴权口径不一致**：详情用单向前缀匹配，列表用双向 `startsWith`
⇒ **子账号会出现「列表能看、点详情 403」**。主账号不受影响。
