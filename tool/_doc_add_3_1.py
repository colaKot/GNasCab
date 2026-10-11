# -*- coding: utf-8 -*-
"""在 docs/WaterNasOS-开发速查.md 的第 3 章末尾（`---` + `## 4.` 之前）插入 3.1 节。"""
import io
import os
import sys

DOC = r"G:\work\nascab\docs\WaterNasOS-开发速查.md"
MARK = "### 3.1 \u2b50\u2b50 \u9ed8\u8ba4\u64ad\u653e\u753b\u8d28"

INS = [
    MARK,
    "",
    "- **画质档位只有一个真源**：客户端 `modules/video/base/video_utils/play_quality.dart`",
    "  （`PlayQuality.options` / `shortLabels` / `label` / `widthOf` / `bitrateBpsOf` / `formatBitrate`）。",
    "  服务端 `video/config/videoConfigController.js` 的 `PLAY_QUALITY_OPTIONS` 是**独立副本**",
    "  （跨进程没法共用），**增删档位必须两边同一次改完**，否则服务端判非法返 400。",
    "  ⚠️ `PlayerController.qualityOptions = PlayQuality.options` 刻意保留成**实例字段**——",
    "  视图里是 `controller.qualityOptions` 的写法，改成 static 要连带改 2 个视图。",
    "- **默认播放画质**（服务端级，`config` 表 `videoDefaultPlayQuality`，uid=0）：",
    "  `videoConfigController.getPlayQuality` / `setPlayQuality`。",
    "  ⚠️ **`getPlayQuality` 故意不加 `requireAdmin`**（`setPlayQuality` 加）——",
    "  子账号的播放端也要读它才能遵守管理员配的默认值。",
    "  客户端在 `PlayerController.openPlaylist` 里 `loadDefaultPlayQuality()` 拉一次，",
    "  再在 `_initializePlayer` 的 **`!keepPosition` 复位块内、`_fetchStreamInfo` 之前**",
    "  `applyDefaultPlayQualityForNewPlayback()` ⇒ 已配非原画时，stream info 里那些",
    "  「自动切转码」判定（只在原画时触发）不会把它顶回原画。",
    "  6 处被动降级路径（播放失败 / 容器不支持 / P2P 大文件 / 位图字幕 / Safari HEVC）",
    "  用 `fallbackTranscodeQuality` getter（用户配了就用配的，否则用内置 `1080p_3m`）。",
    "  ⚠️ URL 源仍强制原画（`isUrl && quality != 'original'` 那条）。",
    "- **播放码率显示**：`video_info_drawer.dart` 基础信息区。",
    "  原始码率取主视频流 `bit_rate`，ffprobe 没给时退回「文件大小 ÷ 总时长」；",
    "  转码码率走 `PlayQuality.bitrateBpsOf`（**与发给 transcode 接口的换算同源**，",
    "  别在抽屉里再写一份正则）。整块 `Obx` 包住 ⇒ 播放中切画质会实时变。",
    "- ⭐⭐ **4K/HDR/杜比徽章不用重扫库**：扫描期写的 `video_ffmpeg_info.streams`",
    "  （按 `video_index.file_hash` 关联）已经带齐所有信息。",
    "  `src/utils/videoMediaFlagsUtil.js` 解析出 6 个标记",
    "  `is4k / hdr10 / hdr10plus / hlg / dolbyVision / dolbyAtmos`，",
    "  `detailService.getDetail` 返回值新增 `media_flags`。",
    "  - 铁柱库实测：`is_file=1 & width>0` 共 5750/5757 行已探测，2017 个可播放文件全部命中。",
    "    全库统计 `is4k 293 / hdr10 87 / hlg 39 / dolbyVision 109 / dolbyAtmos 78`，",
    "    **`hdr10plus = 0`（库里确实没有 HDR10+，别按「应该有」去调规则）**。",
    "  - 判定规则全部来自实测，别凭印象改：HDR10 看 `color_transfer == 'smpte2084'`；",
    "    HLG 看 `arib-std-b67`；HDR10+ 看 side data 含 `2094`；Atmos 只认音频",
    "    `profile`/`tags` 里的 `atmos` 字样（**`truehd` ≠ Atmos，会误标**）。",
    "  - `tv`/`season` 取该目录下所有 `episod` 的**并集**；`_collectPlayableFileHashes`",
    "    的结构照抄 `_collectOpenSkipTargetIds`，两处对「剧」的理解必须同步。",
    "  - `_loadMediaFlagsByHashes` **400 一批 `whereIn`**（SQLite 变量数上限 999），",
    "    整部剧几百集不会炸。整段 try/catch 吞异常，**绝不影响详情本身**。",
    "  - 客户端 `detail/view/parts/media_flags_badge_row.dart`：`labelsFor`/`willRender` 是",
    "    静态纯函数（视图和「要不要渲染」判断同源）。HDR10+ 优先于 HDR10（不同时显示，",
    "    避免「HDR10+ HDR10」冗余）；杜比视界与 HDR **互相独立，都要标**。",
    "    ⚠️ PC 端接 `video_detail_top_section.dart` 时**必须保留 `Positioned(right:0,bottom:0)`**——",
    "    直接换成普通 Widget 会被 Stack 默认 `topStart` 甩到左上角。",
    "",
]


def main():
    if not os.path.isfile(DOC):
        print("!! 找不到文档")
        sys.exit(1)
    with io.open(DOC, "r", encoding="utf-8", newline="") as f:
        src = f.read()
    eol = "\r\n" if "\r\n" in src else "\n"
    if MARK in src:
        print("已存在，跳过")
        return
    lines = src.split(eol)

    # 插入点：第 4 章标题之前最近的 `---` 分隔线（`---` 与 `## 4.` 之间可能有空行）
    title_idx = None
    for i, line in enumerate(lines):
        if line.startswith("## 4. "):
            title_idx = i
            break
    if title_idx is None:
        print("!! 定位不到第 4 章")
        sys.exit(1)
    target = None
    for i in range(title_idx - 1, -1, -1):
        if lines[i].strip() == "---":
            target = i
            break
    if target is None:
        print("!! 定位不到分隔线")
        sys.exit(1)

    lines[target:target] = INS
    out = eol.join(lines)
    if not out.startswith(MARK[:10]) and MARK not in out:
        print("!! 插入校验失败")
        sys.exit(1)
    with io.open(DOC, "w", encoding="utf-8", newline="") as f:
        f.write(out)
    print("已在第 %d 行前插入 3.1 节，共 %d 行" % (target + 1, len(INS)))


if __name__ == "__main__":
    main()