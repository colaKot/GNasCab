/**
 * 影视媒体特性标记（4K / HDR / 杜比）解析工具。
 *
 * 数据源：`video_ffmpeg_info.streams`（= ffprobe 的原始 streams JSON），
 * 由**扫描时**的 `videoIndexIndexUtil` 写入，按 `video_index.file_hash` 关联即可，**不需要重扫库**。
 *
 * ⚠️ 判断规则全部来自实测数据（铁柱库 2017 个已探测的视频文件），别凭印象改：
 * | 特性 | 实测依据 |
 * | --- | --- |
 * | 4K | `width >= 3840` 或 `height >= 2160`（注意 3832x1600 这类"准 4K"也会命中，符合预期） |
 * | HDR10 | `color_transfer === 'smpte2084'`（PQ）+ `color_primaries === 'bt2020'` |
 * | HLG | `color_transfer === 'arib-std-b67'` |
 * | HDR10+ | 流里出现 SMPTE ST 2094（`side_data_list` / `side_data_type` 含 `2094` 或 `hdr10+`） |
 * | Dolby Vision | 复用 `videoFfprobeUtil.isDolbyVisionStream`：`dv_profile > 0` / `codec_tag_string` 为 `dvhe`/`dvh1` / DOVI side data |
 * | Dolby Atmos | **音频流的 `profile` / `tags` 里出现 `atmos`**（实测形如 `profile: 'Dolby Digital Plus + Dolby Atmos'`）。
 *   只认这个字符串，**不要**拿 `truehd` 顶替 —— TrueHD 不等于 Atmos，会误标 |
 *
 * ⚠️ Dolby Vision 与 HDR10 会**同时存在**（实测 `dv_profile=8` + `smpte2084`），
 * 铁柱明确要求「HDR + 杜比都要标出来」⇒ 两者是并列的独立标记，不是互斥。
 */
const { isDolbyVisionStream } = require('./videoFfprobeUtil');

const ATMOS_RE = /atmos/i;

function _toInt(v) {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

function _streamsOf(rawStreams) {
  if (!rawStreams) return [];
  let parsed = rawStreams;
  if (typeof rawStreams === 'string') {
    try {
      parsed = JSON.parse(rawStreams);
    } catch (_) {
      return [];
    }
  }
  if (Array.isArray(parsed)) return parsed;
  if (parsed && typeof parsed === 'object' && Array.isArray(parsed.streams)) return parsed.streams;
  return [];
}

/** 单个文件的 ffprobe streams → 特性标记 */
function buildMediaFlags(streams) {
  const list = Array.isArray(streams) ? streams : _streamsOf(streams);
  const flags = {
    is4k: false,
    hdr10: false,
    hdr10plus: false,
    hlg: false,
    dolbyVision: false,
    dolbyAtmos: false,
  };

  for (const s of list) {
    if (!s || typeof s !== 'object') continue;
    const type = String(s.codec_type || '').toLowerCase();

    if (type === 'video') {
      const w = _toInt(s.width);
      const h = _toInt(s.height);
      if (w >= 3840 || h >= 2160) flags.is4k = true;

      if (isDolbyVisionStream(s)) flags.dolbyVision = true;

      const transfer = String(s.color_transfer || '').toLowerCase();
      const primaries = String(s.color_primaries || '').toLowerCase();
      if (transfer === 'smpte2084' && (primaries === 'bt2020' || !primaries)) {
        flags.hdr10 = true;
      }
      if (transfer === 'arib-std-b67') flags.hlg = true;

      // HDR10+：SMPTE ST 2094 动态元数据，只在 side data 里出现
      const sideData = JSON.stringify(s.side_data_list || []);
      const probe = `${s.side_data_type || ''} ${sideData}`.toLowerCase();
      if (probe.includes('2094') || probe.includes('hdr10+')) flags.hdr10plus = true;
    }

    if (type === 'audio') {
      const profile = String(s.profile || '');
      const tags = s.tags && typeof s.tags === 'object' ? s.tags : {};
      const tagText = `${tags.title || ''} ${tags.handler_name || ''}`;
      if (ATMOS_RE.test(profile) || ATMOS_RE.test(tagText)) flags.dolbyAtmos = true;
    }
  }

  return flags;
}

/** 一组文件的特性标记 → 并集（电视剧/季用：整部剧有任何一集是 HDR 就标 HDR） */
function mergeMediaFlags(list) {
  const out = {
    is4k: false,
    hdr10: false,
    hdr10plus: false,
    hlg: false,
    dolbyVision: false,
    dolbyAtmos: false,
  };
  const source = Array.isArray(list) ? list : [];
  let any = false;
  for (const f of source) {
    if (!f || typeof f !== 'object') continue;
    any = true;
    for (const k of Object.keys(out)) {
      if (f[k] === true) out[k] = true;
    }
  }
  return any ? out : null;
}

/** 是否一个标记都没命中（用于决定要不要返回给前端） */
function hasAnyMediaFlag(flags) {
  if (!flags || typeof flags !== 'object') return false;
  return Object.keys(flags).some(k => flags[k] === true);
}

module.exports = {
  buildMediaFlags,
  mergeMediaFlags,
  hasAnyMediaFlag,
  streamsOf: _streamsOf,
};
