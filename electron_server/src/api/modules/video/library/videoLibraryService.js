const userUtil = require('../../../../utils/userUtil');
const VideoSourceService = require('../source/videoSourceService');
const { applyVisibleIndexFilter, isPathVisibleTo } = require('../videoVisibilityUtil');

// 影视库类型（创建后不可修改）
const LIB_TYPES = ['movie', 'tv', 'image', 'mixed'];

const VIDEO_MEDIA_TYPES = ['movie', 'bdmv', 'video_ts'];

/**
 * ⚠️ 已废弃：本文件不再使用它（可见性过滤统一到 `../videoVisibilityUtil`）。
 *
 * 这个实现**有 bug，别再抄**：它把反斜杠也翻倍（`\` → `\\`），
 * 而 SQLite 的 LIKE 默认不认 `\` 转义 ⇒ Windows 路径的前缀匹配会**静默失效**
 * （实测 `'E:\Media\sub' LIKE 'E:\\Media\\%'` = 0）。
 * 正确做法见 `videoVisibilityUtil.escapeLikeValue`：只转 `%` `_`，并用 `^` 作 ESCAPE 字符。
 */
function _escapeLikeValue(input) {
  return String(input || '')
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
}

class VideoLibraryService {
  constructor(knex) {
    this.knex = knex;
    this.tableName = 'video_library';
    this.sourceTable = 'video_source';
  }

  normalizeLibType(input) {
    const v = String(input || '')
      .trim()
      .toLowerCase();
    return LIB_TYPES.includes(v) ? v : '';
  }

  normalizeName(input) {
    return String(input === undefined || input === null ? '' : input).trim();
  }

  async listLibraries() {
    return await this.knex(this.tableName).select('*').orderBy('sort', 'asc').orderBy('id', 'asc').catch(() => []);
  }

  async getLibraryById(rawId) {
    const id = Number(rawId || 0) || 0;
    if (!id) return null;
    const row = await this.knex(this.tableName).where({ id }).first().catch(() => null);
    return row || null;
  }

  async isNameTaken(name, excludeId = 0) {
    const target = this.normalizeName(name);
    if (!target) return false;
    const rows = await this.knex(this.tableName).where({ name: target }).select('id').catch(() => []);
    return (rows || []).some(r => Number(r && r.id) !== Number(excludeId || 0));
  }

  async addLibrary(payload = {}) {
    const name = this.normalizeName(payload.name);
    if (!name) throw new Error('validation.VALIDATION_ERROR');

    const libType = this.normalizeLibType(payload.lib_type ?? payload.libType);
    if (!libType) throw new Error('validation.VALIDATION_ERROR');

    if (await this.isNameTaken(name)) throw new Error('video.VIDEO_LIBRARY_NAME_EXISTS');

    const maxRow = await this.knex(this.tableName).max({ m: 'sort' }).first().catch(() => null);
    const sort = (Number(maxRow && maxRow.m) || 0) + 1;

    const row = await this.knex.transaction(async trx => {
      const [id] = await trx(this.tableName).insert({
        name,
        name_key: '',
        lib_type: libType,
        is_default: 0,
        show_in_home: 0,
        sort,
        create_time: new Date(),
      });
      return trx(this.tableName).where({ id }).first();
    });
    return row;
  }

  // 只允许改名，lib_type 创建后不可修改
  async renameLibrary(rawId, payload = {}) {
    const id = Number(rawId || 0) || 0;
    if (!id) throw new Error('validation.VALIDATION_ERROR');

    const name = this.normalizeName(payload.name);
    if (!name) throw new Error('validation.VALIDATION_ERROR');

    const lib = await this.getLibraryById(id);
    if (!lib) throw new Error('common.NOT_FOUND');

    if (await this.isNameTaken(name, id)) throw new Error('video.VIDEO_LIBRARY_NAME_EXISTS');

    await this.knex(this.tableName)
      .where({ id })
      .update({ name, name_key: '' })
      .catch(() => 0);
    return await this.getLibraryById(id);
  }

  // 切换「是否在主页显示该库分类」
  async setShowInHome(rawId, payload = {}) {
    const id = Number(rawId || 0) || 0;
    if (!id) throw new Error('validation.VALIDATION_ERROR');

    const lib = await this.getLibraryById(id);
    if (!lib) throw new Error('common.NOT_FOUND');

    const raw = payload.show_in_home ?? payload.showInHome;
    const showInHome =
      raw === true || raw === 1 || raw === '1' || raw === 'true' ? 1 : 0;

    // ⚠️ 2026-10-09：原来这里 `.catch(() => 0)`把写入异常吞掉了，
    // 表不存在/列缺失时接口照样返回 200，前端只能看到一个「改了没反应」的死开关，
    // 排查时完全没有线索。写失败必须抛出去，让前端提示「操作失败」。
    const affected = await this.knex(this.tableName)
      .where({ id })
      .update({ show_in_home: showInHome });
    if (!Number(affected)) {
      throw new Error('video.VIDEO_LIBRARY_UPDATE_FAILED');
    }

    return await this.getLibraryById(id);
  }

  async deleteLibrary(rawId) {
    const id = Number(rawId || 0) || 0;
    if (!id) throw new Error('validation.VALIDATION_ERROR');

    const lib = await this.getLibraryById(id);
    if (!lib) throw new Error('common.NOT_FOUND');
    if (Number(lib.is_default || 0) === 1) throw new Error('video.VIDEO_LIBRARY_BUILTIN_CANNOT_DELETE');

    const row = await this.knex(this.sourceTable)
      .where({ library_id: id })
      .count({ cnt: 'id' })
      .first()
      .catch(() => null);
    if (Number(row && row.cnt) > 0) throw new Error('video.VIDEO_LIBRARY_HAS_SOURCE');

    const affected = await this.knex(this.tableName).where({ id }).delete().catch(() => 0);
    return { affected: Number(affected) || 0 };
  }

  // 库 -> 来源路径
  async getSourcePathsByLibrary(rawId) {
    const id = Number(rawId || 0) || 0;
    if (!id) return [];
    const rows = await this.knex(this.sourceTable).where({ library_id: id }).select('path').catch(() => []);
    return (rows || []).map(r => (r && r.path ? String(r.path) : '')).filter(Boolean);
  }

  _applyIndexPathFilter(query, paths) {
    // ⭐ 统一口径：与列表页、详情鉴权共用同一份实现。
    // 原实现只有「前缀匹配」，**漏了目录行特判**（`is_file=0 且 path=父目录 且 filename=子目录名`），
    // 导致电视剧库那种「剧集文件夹」代表的整部剧不算进计数 ⇒ 库计数虚低、左侧栏显示 0。
    applyVisibleIndexFilter(query, paths);
  }

  // 每个库的可见条目数：库内来源路径 ∩ 用户可见路径
  async listLibrariesWithCounts(user) {
    const libraries = await this.listLibraries();
    if (!libraries || libraries.length === 0) return [];

    const sourceService = new VideoSourceService(this.knex);
    const validPaths = await sourceService.getValidPaths(user);

    const allSources = await this.knex(this.sourceTable).select('path', 'library_id').catch(() => []);
    const pathsByLib = new Map();
    for (const s of allSources || []) {
      const p = s && s.path ? String(s.path) : '';
      const libId = Number(s && s.library_id) || 0;
      if (!p || !libId) continue;
      if (!pathsByLib.has(libId)) pathsByLib.set(libId, []);
      pathsByLib.get(libId).push(p);
    }

    const out = [];
    for (const lib of libraries) {
      const libId = Number(lib && lib.id) || 0;
      const libPaths = pathsByLib.get(libId) || [];
      // ⭐ 原来这里是 `validSet.has(p)` 精确比对：只有当「来源路径」恰好等于某条
      // 「可见路径」时才算数。但 `getValidPaths` 返回的可能是更长的授权子路径
      // （授权 `…\TV\BreakingBad`、来源 `…\TV`），精确比对必然落空 ⇒ 库计数虚低。
      // 改用与 getValidPaths 同源的双向包含判断。
      const visiblePaths = libPaths.filter(p => isPathVisibleTo(p, validPaths));

      const counts = { movie: 0, tv: 0, image: 0, total: 0 };
      if (visiblePaths.length > 0) {
        const query = this.knex('video_index').select('media_type').count({ total: '*' });
        this._applyIndexPathFilter(query, visiblePaths);
        const rows = await query.groupBy('media_type').catch(() => []);
        for (const r of rows || []) {
          const mt = r && r.media_type ? String(r.media_type).trim() : '';
          const cnt = Number(r && r.total) || 0;
          // ⭐ total = 该库内**全部**可见索引行之和，**不按 media_type 白名单筛**。
          //   原来用 `counts.movie + counts.tv + counts.image` 求和，会把白名单
          //   （movie/bdmv/video_ts）之外的媒体类型整类漏算 ⇒ 库明明有条目却算成 0，
          //   被左侧栏当成「空库」隐藏。
          counts.total += cnt;
          if (VIDEO_MEDIA_TYPES.includes(mt)) counts.movie += cnt;
          if (mt === 'tv') counts.tv += cnt;
          if (mt === 'image') counts.image += cnt;
        }
      }

      out.push({
        id: libId,
        name: lib.name ? String(lib.name) : '',
        name_key: lib.name_key ? String(lib.name_key) : '',
        lib_type: lib.lib_type ? String(lib.lib_type) : 'movie',
        is_default: Number(lib.is_default || 0),
        show_in_home: Number(lib.show_in_home || 0),
        sort: Number(lib.sort || 0),
        source_count: libPaths.length,
        counts,
      });
    }
    return out;
  }
}

VideoLibraryService.LIB_TYPES = LIB_TYPES;
VideoLibraryService.VIDEO_MEDIA_TYPES = VIDEO_MEDIA_TYPES;

module.exports = VideoLibraryService;
