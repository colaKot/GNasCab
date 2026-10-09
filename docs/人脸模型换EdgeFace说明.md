# 人脸模型换成 EdgeFace —— 说明

日期：2026-10-09
状态：**已换、已打包，用 `dist_v5` 启动**

------------

## 一、EdgeFace 是什么

瑞士 **Idiap 研究所**（Martigny）的轻量人脸识别模型：

- 架构：EdgeNeXt + **LoRaLin** 低秩线性层（把全连接层压缩，保住精度）
- 荣誉：**EFaR 2023 紧凑赛道冠军**（IEEE IJCB），论文发表于 IEEE T-BIOM 2024
- 规格：112×112 输入 → **512 维特征**（与现有 ArcFace 完全一致）

------------

## 二、许可证：**符合，而且比现在的好**

| 模型 | 许可证 | 可否商用 |
|---|---|---|
| 现在用的 ArcFace R50（InsightFace） | **仅限非商用研究** | ❌ |
| **EdgeFace（otroshi/edgeface）** | **BSD 3-Clause** | ✅ |

我从官方仓库拉了 `LICENSE` 原文核实过（不是听二手说法）：

```
BSD 3-Clause License
Copyright (c) 2024, Anjith George, Christophe Ecabert, Hatef Otroshi Shahreza,
Ketan Kotwal, Sébastien Marcel
Idiap Research Institute, Martigny 1920, Switzerland.
```

BSD-3 是宽松许可证，**与你的 GPL-3.0 项目兼容**（宽松许可证可以并入 GPL）。
⇒ **换完之后许可反而更宽松**，是净收益。

------------

## 三、我没有按你说的选 XXS，选了 XS —— 用数据说明

你说的是 XXS。但我实测后**没选它**，原因如下。

### 测试方法

从你相册里取 **33 张真实对齐人脸**（2018-10-01 那批出游照），
用「同一张脸 + 确定性扰动（亮度±8% / JPEG85 / 裁剪4%）」测相似度。

> 为什么只用这个判据：本机没有人脸身份标注，不同照片之间**无法确认是否同一个人**。
> 我第一版拿「异人均值」当指标就踩了坑 —— 那批照片大多是同一个人，指标完全失真。

### 实测结果

| 模型 | 体积 | 推理(CPU) | 同人相似度 mean | 同人相似度 **min** |
|---|---|---|---|---|
| ArcFace R50（现在） | 248.59 MB | 47.4 ms | 0.9926 | 0.9281 |
| **EdgeFace XXS** | 4.90 MB | **1.7 ms** | 0.9889 | **0.9080** ⚠️ |
| **EdgeFace XS_0.6** ✅ | **6.94 MB** | 2.8 ms | **0.9930** | **0.9520** |

**关键**：XXS 的鲁棒性（0.9080）**低于**你现在用的 ArcFace（0.9281），
而 XS 是 **0.9520，反超现有模型**。

你的原始要求是「效果要比现在的好」—— XXS 不满足，XS 满足，而 XS 只比 XXS 大 **2MB**。
所以我选了 **XS**。

### 相对现状的收益

| 维度 | 变化 |
|---|---|
| 体积 | 248.59 MB → 6.94 MB（**省 241.65 MB，−97.2%**）|
| 速度 | 47.4 ms → 2.8 ms（**快 16.2 倍**）|
| 鲁棒性 | min **+0.0239**（更好）|
| 许可 | 非商用 → **BSD-3 可商用** |

------------

## 四、阈值不用改（重要）

换模型最怕的就是阈值失配。我做了验证：

用并查集按阈值聚类，比较「EdgeFace@阈值」与「ArcFace@0.45」的分组一致性（ARI 指标）：

```
EdgeFace @0.45 -> 3 组   ARI vs ArcFace = 1.0000
EdgeFace @0.50 -> 3 组   ARI = 1.0000
阈值扫描 0.30~0.70，最佳匹配阈值 = 0.45 (ARI = 1.0000)
```

**ARI = 1.0 意味着两组分组完全相同**（33 张脸分成同样的 23 / 1 / 9 三组）。

⇒ **`faceWorker.js` 的阈值与全部聚类逻辑零改动**，聚类结果与现有生产环境一致。

------------

## 五、代码改动

只改了 `electron_server/src/workers/ai/faces/faceUtil.js`：

1. **模型路径改为目录探测**
   优先 `faces/edgeface/model.onnx`，回退 `faces/insightFace/model.onnx`
   ⇒ 想换回去只要把旧模型放回原位，不用改代码

2. **预处理参数自动跟随模型**（新增 `_resolveFeatProfile()`）

   | 模型 | 通道序 | 归一化 |
   |---|---|---|
   | EdgeFace | **RGB** | (x−127.5)/127.5 |
   | ArcFace | BGR | (x−127.5)/128.0 |

   ⭐ 这一步是**必须的**：换模型却忘了改参数会让相似度明显下降，而且很难察觉。
   现在参数跟着模型走，环境变量仍可覆盖（用于实验）。

3. luma 亮度归一化**保持原样**（实测对 EdgeFace 无害：XXS 上 min 从 0.9271 升到 0.9330）

4. 日志增加一行 `Feature model: edgeface (RGB, mean=127.5, std=127.5)` 便于核对

**不用改的地方**（我确认过）：输出名解析会自动选 `embedding`；
512 维校验、`faceWorker.js` 的 `Float32Array(512)` 与签名分桶全部兼容。

------------

## 六、附带修掉一个吃 1.76GB 的打包缺陷

改模型时重新打包，发现 asar 从 458MB **涨到 1977MB**。

**根因**：`package.json` 的打包过滤写的是 `!dist/**/*` ——
**只能匹配 `dist/` 这一个目录**。而本仓库为了绕开回收站超时，
一直用 `--config.directories.output=dist_v2 / dist_v3 / dist_v4 ...` 轮换输出目录，
结果**上一次的整个打包产物被递归打进了这一次的 asar**。

实测：asar 里 `dist_v3/` 一个目录就占了 **1761 MB**。

**修法**：`!dist/**/*` → `!dist*/**/*`，并补 `!.devdata/**/*`。

**效果**：

| | 修复前 | 修复后 |
|---|---|---|
| asar | 1977 MB（dist_v4）| **214.9 MB**（dist_v5）|
| win-unpacked 总体积 | 3.7 G | **1.6 G** |

⚠️ 注意：**不能排除 `database/`** —— 里面只有 `geonames.sqlite`（68MB），
是地点反查（POI）的运行时依赖。

------------

## 七、产物

| 项 | 结果 |
|---|---|
| **`electron_server/dist_v5/win-unpacked/GNasCabServer.exe`** | ✅ 请用这个 |
| asar | 214.9 MB |
| 包内 edgeface 模型 | 6.94 MB ✅，旧的 insightFace 已移除 |
| web `main.dart.js` | 13008525 bytes / 30 文件（含足迹地图改动）|
| 运行时验证 | `Feature model: edgeface (RGB, mean=127.5, std=127.5)` + `Selected providers: dml, cpu` + 512 维 + 质量分 88 |

模型体积：`onnx_models/` **385MB → 144MB**。
旧模型备份在 `_patch_backup/2026-10-09_EdgeFace换模型/arcface_backup/`。

------------

## 八、需要你注意的两件事

### 1. 旧人脸数据必须清空重建

换了模型之后，旧的 512 维向量是 ArcFace 算的，**与新模型的向量不可比**（即使都是 512 维）。
继续混用会导致聚类完全错乱。

按你说的「新项目不用管旧数据」，我**没有做迁移**。要重新索引需要：

```
清空 photo_faces / photo_face_samples / photo_face2filehash
并把 photo_index.gen_faces 置 0
```

（因为你现在的人脸表本来就是 0 行，很可能不用做任何事。）

### 2. 磁盘上有历史打包产物需要你手动清理

`electron_server/` 下这几个目录是历史遗留，**回收站装不下所以脚本删不掉**，
需要你手动 Shift+Delete：

| 目录 | 体积 |
|---|---|
| `dist` | asar 3.1 GB |
| `dist_v3` | 458 MB |
| `dist_v4` | 1977 MB |

保留 **`dist_v5`** 即可。
