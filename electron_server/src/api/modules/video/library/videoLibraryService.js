const userUtil = require('../../../../utils/userUtil');
const VideoSourceService = require('../source/videoSourceService');

// 影视库类型（创建后不可修改）
const LIB_TYPES = ['movie', 'tv', 'image', 'mixed'];

const VIDEO_MEDIA_TYPES = ['movie', 'bdmv', 'video_ts'];

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
    const list = Array.isArray(paths) ? paths.map(p => String(p || '').trim()).filter(Boolean) : [];
    if (list.length === 0) {
      query.whereRaw('1 = 0');
      return;
    }
    const sep = require('path').sep;
    const escaped = list.map(p => ({
      exact: p,
      prefix: p.endsWith(sep) ? p : `${p}${sep}`,
    }));
    query.where(builder => {
      for (const item of escaped) {
        builder.orWhere(function () {
          this.where('path', item.exact).orWhere('path', 'like', `${_escapeLikeValue(item.prefix)}%`);
        });
      }
    });
  }

  // 每个库的可见条目数：库内来源路径 ∩ 用户可见路径
  async listLibrariesWithCounts(user) {
    const libraries = await this.listLibraries();
    if (!libraries || libraries.length === 0) return [];

    const sourceService = new VideoSourceService(this.knex);
    const validPaths = await sourceService.getValidPaths(user);
    const validSet = new Set((validPaths || []).map(p => String(p)));

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
      const visiblePaths = libPaths.filter(p => validSet.has(p));

      const counts = { movie: 0, tv: 0, image: 0, total: 0 };
      if (visiblePaths.length > 0) {
        const query = this.knex('video_index').select('media_type').count({ total: '*' });
        this._applyIndexPathFilter(query, visiblePaths);
        const rows = await query.groupBy('media_type').catch(() => []);
        for (const r of rows || []) {
          const mt = r && r.media_type ? String(r.media_type).trim() : '';
          const cnt = Number(r && r.total) || 0;
          if (VIDEO_MEDIA_TYPES.includes(mt)) counts.movie += cnt;
          if (mt === 'tv') counts.tv += cnt;
          if (mt === 'image') counts.image += cnt;
        }
        counts.total = counts.movie + counts.tv + counts.image;
      }

      out.push({
        id: libId,
        name: lib.name ? String(lib.name) : '',
        name_key: lib.name_key ? String(lib.name_key) : '',
        lib_type: lib.lib_type ? String(lib.lib_type) : 'movie',
        is_default: Number(lib.is_default || 0),
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
