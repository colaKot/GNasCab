const path = require('path');
const fs = require('fs');
const VideoSourceService = require('../source/videoSourceService');
const { escapeLikeValue, LIKE_ESCAPE } = require('../videoVisibilityUtil');

/**
 * 图片表（image_index）的路径可见性过滤。
 * ⚠️ 不能复用下面的 `_applyVideoIndexPathPrefixFilter`：它带「目录行特判」，
 *    会引用 image_index 并不存在的 `is_file` 列 → SQL 直接报错。
 */
function _applyImageIndexPathPrefixFilter(query, paths, alias = 'i') {
  const list = Array.isArray(paths) ? paths.map(p => String(p || '').trim()).filter(Boolean) : [];
  if (list.length === 0) {
    query.whereRaw('1 = 0');
    return;
  }
  const sep = path.sep;
  query.where(builder => {
    for (const p of list) {
      const prefix = p.endsWith(sep) ? p : `${p}${sep}`;
      builder.orWhere(function () {
        this.where(`${alias}.path`, p).orWhereRaw('?? LIKE ? ESCAPE ?', [
          `${alias}.path`,
          `${escapeLikeValue(prefix)}%`,
          LIKE_ESCAPE,
        ]);
      });
    }
  });
}

function _resolveArtworkAbsolute({ baseDir, maybeRelative }) {
  const p = maybeRelative === undefined || maybeRelative === null ? '' : String(maybeRelative).trim();
  if (!p) return '';
  if (path.isAbsolute(p)) return p;
  const base = baseDir === undefined || baseDir === null ? '' : String(baseDir).trim();
  if (!base) return '';
  return path.resolve(base, p);
}

function _normalizeHomeRow(row) {
  if (!row || typeof row !== 'object') return row;
  const baseDir = row.path === undefined || row.path === null ? '' : String(row.path).trim();
  const poster = _resolveArtworkAbsolute({ baseDir, maybeRelative: row.poster_path });
  const fanart = _resolveArtworkAbsolute({ baseDir, maybeRelative: row.fanart_path });
  const logo = _resolveArtworkAbsolute({ baseDir, maybeRelative: row.logo_path });
  const fullPath = baseDir && row.filename ? path.join(baseDir, String(row.filename)) : '';
  const playRelPath = row.play_rel_path === undefined || row.play_rel_path === null ? '' : String(row.play_rel_path).trim();
  const playFilePath = row && (row.media_type === 'bdmv' || row.media_type === 'video_ts') && fullPath && playRelPath ? path.resolve(fullPath, playRelPath) : '';

  let res = {
    ...row,
    poster_path: poster,
    fanart_path: fanart,
    logo_path: logo,
    full_path: fullPath,
    play_file_path: playFilePath,
    first_file_path: row && (row.media_type === 'bdmv' || row.media_type === 'video_ts') && playFilePath ? playFilePath : row.first_file_path,
  };

  return res;
}

function _normalizeHomeRows(rows) {
  return (rows || []).map(r => _normalizeHomeRow(r));
}

function _applyVideoIndexPathPrefixFilter(query, paths, alias = 'v') {
  const list = Array.isArray(paths) ? paths.map(p => String(p || '').trim()).filter(Boolean) : [];
  if (list.length === 0) {
    query.whereRaw('1 = 0');
    return;
  }

  const sep = path.sep;
  const folderExactPairs = [];
  for (const raw of list) {
    const p = raw.endsWith(sep) ? raw.slice(0, -1) : raw;
    if (!p) continue;
    if (path.extname(p)) continue;
    const parent = path.dirname(p);
    const name = path.basename(p);
    if (!parent || !name) continue;
    folderExactPairs.push({ parent, name });
  }

  query.where(builder => {
    for (const p of list) {
      const prefix = p.endsWith(sep) ? p : `${p}${sep}`;
      builder.orWhere(function () {
        this.where(`${alias}.path`, p).orWhere(`${alias}.path`, 'like', `${prefix}%`);
      });
    }
    for (const pair of folderExactPairs) {
      builder.orWhere(function () {
        this.where(`${alias}.is_file`, 0).andWhere(`${alias}.path`, pair.parent).andWhere(`${alias}.filename`, pair.name);
      });
    }
  });
}

function _filterSourceListByValidPaths(sourceList, validPaths) {
  const sources = Array.isArray(sourceList) ? sourceList : [];
  const allowed = Array.isArray(validPaths) ? validPaths.map(p => String(p || '').trim()).filter(Boolean) : [];
  if (allowed.length === 0) return [];
  const sep = path.sep;

  return sources.filter(s => {
    const p = s && s.path ? String(s.path) : '';
    if (!p) return false;
    for (const a of allowed) {
      if (p === a) return true;
      const pPrefix = p.endsWith(sep) ? p : `${p}${sep}`;
      const aPrefix = a.endsWith(sep) ? a : `${a}${sep}`;
      if (p.startsWith(aPrefix) || a.startsWith(pPrefix)) return true;
    }
    return false;
  });
}

async function _enrichSourcesWithAvailability(sourceList) {
  const list = Array.isArray(sourceList) ? sourceList : [];
  if (list.length === 0) return [];

  return await Promise.all(
    list.map(async row => {
      const p = row && row.path ? String(row.path).trim() : '';
      let exists = false;
      if (p) {
        try {
          const stat = await fs.promises.stat(p);
          exists = !!(stat && stat.isDirectory());
        } catch (_) {}
      }
      return { ...row, avaliable: exists };
    })
  );
}

async function _getFirstEpisodeRowUnderFolder({ knex, rootFolder }) {
  const resolved = rootFolder ? path.resolve(String(rootFolder)) : '';
  if (!resolved) return null;
  const prefix = resolved.endsWith(path.sep) ? resolved : `${resolved}${path.sep}`;

  return await knex('video_index')
    .where({ is_file: 1, media_type: 'episod' })
    .andWhere(qb => {
      qb.where('path', resolved).orWhere('path', 'like', `${prefix}%`);
    })
    .orderBy('episod_num', 'asc')
    .orderBy('id', 'asc')
    .first('path', 'filename')
    .catch(() => null);
}

async function _fillFirstFilePathForTvRows({ knex, rows }) {
  const list = Array.isArray(rows) ? rows : [];
  const tvRows = list.filter(r => r && (r.media_type === 'tv' || r.media_type === 'season'));
  if (tvRows.length === 0) return;

  await Promise.all(
    tvRows.map(async r => {
      const poster = r.poster_path ? String(r.poster_path).trim() : '';
      if (poster) return;
      const baseDir = r.path ? String(r.path).trim() : '';
      const name = r.filename ? String(r.filename).trim() : '';
      if (!baseDir || !name) return;
      const showFolder = path.join(baseDir, name);

      const first = await _getFirstEpisodeRowUnderFolder({
        knex,
        rootFolder: showFolder,
      });
      const epPath = first && first.path ? String(first.path).trim() : '';
      const epName = first && first.filename ? String(first.filename).trim() : '';
      if (!epPath || !epName) return;
      r.first_file_path = path.join(epPath, epName);
    })
  );
}

async function _fillFavoriteStateForLists({ knex, uid, lists }) {
  const safeUid = Number(uid) || 0;
  const arr = Array.isArray(lists) ? lists.filter(Boolean) : [];
  if (arr.length === 0) return;

  const allRows = [];
  for (const l of arr) {
    if (Array.isArray(l) && l.length > 0) allRows.push(...l);
  }
  if (allRows.length === 0) return;

  for (const r of allRows) {
    if (r && typeof r === 'object') r.is_favorite = false;
  }
  if (!safeUid) return;

  const ids = allRows.map(r => Number(r && r.id) || 0).filter(v => v > 0);
  if (ids.length === 0) return;

  const favRows = await knex('video_favorite')
    .where({ uid: safeUid })
    .whereIn('index_id', ids)
    .select('index_id')
    .catch(() => []);

  const favSet = new Set((favRows || []).map(r => Number(r && r.index_id) || 0).filter(v => v > 0));
  for (const r of allRows) {
    const id = Number(r && r.id) || 0;
    if (r && typeof r === 'object') r.is_favorite = favSet.has(id);
  }
}

class VideoHomeService {
  constructor(knex, user) {
    this.knex = knex;
    this.user = user;
    this.uid = user && user.id ? Number(user.id) : 0;
  }

  /**
   * ⭐ 只保留「勾选了在主页显示」的库所拥有的来源路径（2026-10-09）。
   *
   * 主页的推荐轮播 / 最近播放原先直接吃 validPaths（= 全部可见来源路径），
   * 完全绕过影视库维度 ⇒ 关了开关的库内容照样出现在主页顶部。
   * 这里把路径集收窄到「show_in_home=1 的库」的路径，
   * 再交给 _getRecommend / _getRecentPlay 用。
   *
   * ⚠️ 依赖：video_source.library_id。若该列为空（老库未迁移），
   * 退化为返回 validPaths 原样，避免整站主页空白。
   */
  async _getHomeVisibleSourcePaths(validPaths) {
    const paths = Array.isArray(validPaths) ? validPaths : [];
    if (paths.length === 0) return paths;

    const libs = await this.knex('video_library')
      .where('show_in_home', 1)
      .select('id')
      .catch(() => null);

    // 表/列不存在或读失败 ⇒ 不做过滤，保持旧行为（宁可多显示，不要整页空白）
    if (!Array.isArray(libs) || libs.length === 0) return paths;

    const visibleLibIds = new Set(
      (libs || []).map(l => Number(l && l.id) || 0).filter(v => v > 0),
    );
    if (visibleLibIds.size === 0) return paths;

    const sources = await this.knex('video_source')
      .select('path', 'library_id')
      .catch(() => null);
    // 拿不到 library_id（老库未迁移）⇒ 同样退化为不过滤
    if (!Array.isArray(sources)) return paths;

    const out = [];
    for (const s of sources) {
      const p = s && s.path ? String(s.path) : '';
      const libId = Number(s && s.library_id) || 0;
      if (!p || !libId) continue;
      if (!visibleLibIds.has(libId)) continue;
      out.push(p);
    }
    if (out.length === 0) return paths;

    // 与 validPaths 求交集，保持「用户可见路径」这个安全边界
    const visibleSet = new Set(paths.map(p => String(p)));
    const sep = path.sep;
    const result = out.filter(p => {
      if (visibleSet.has(p)) return true;
      const pPrefix = p.endsWith(sep) ? p : `${p}${sep}`;
      for (const a of paths) {
        const aPrefix = a.endsWith(sep) ? a : `${a}${sep}`;
        if (p.startsWith(aPrefix) || a.startsWith(pPrefix)) return true;
      }
      return false;
    });
    return result.length > 0 ? result : paths;
  }

  async getHomeData({ recommendLimit = 11, recentPlayLimit = 20, recentAddLimit = 20 } = {}) {
    const recLimit = Math.max(1, Math.min(11, Number(recommendLimit || 0) || 11));
    const playLimit = Math.max(1, Math.min(20, Number(recentPlayLimit || 0) || 20));
    const addLimit = Math.max(1, Math.min(20, Number(recentAddLimit || 0) || 20));

    const sourceService = new VideoSourceService(this.knex);
    const allSources = await sourceService.listSources().catch(() => []);
    const validPaths = await sourceService.getValidPaths(this.user).catch(() => []);
    const sourceList = await _enrichSourcesWithAvailability(_filterSourceListByValidPaths(allSources, validPaths));

    // ⭐ 2026-10-09：推荐轮播 / 最近播放也要遵守「在主页显示」开关。
    // 这两个区块原先直接用 validPaths（全部来源路径）取数，绕过了影视库维度，
    // 于是没开开关的库内容照样出现在主页顶部轮播里。
    const homeVisiblePaths = await this._getHomeVisibleSourcePaths(validPaths);

    const recommend = await this._getRecommend({
      limit: recLimit,
      validPaths: homeVisiblePaths,
    });
    const recentPlay = await this._getRecentPlay({
      limit: playLimit,
      validPaths: homeVisiblePaths,
    });
    // 按影视库分类的最近添加：只返回勾选了「主页显示」的库
    const recentAddByLib = await this._getRecentAddByLibrary({ limit: addLimit, validPaths });

    await _fillFavoriteStateForLists({
      knex: this.knex,
      uid: this.uid,
      lists: [recommend, recentPlay, ...recentAddByLib.map(g => g.items)],
    });
    await _fillFirstFilePathForTvRows({ knex: this.knex, rows: recommend });
    await _fillFirstFilePathForTvRows({ knex: this.knex, rows: recentPlay });
    for (const g of recentAddByLib) {
      await _fillFirstFilePathForTvRows({ knex: this.knex, rows: g.items });
    }

    if (recentPlay.length > 0) {
      recentPlay.forEach(row => {
        const duration = row.duration === undefined || row.duration === null ? 0 : Number(row.duration);
        const playback_position = row.playback_position === undefined || row.playback_position === null ? 0 : Number(row.playback_position);
        let progress = 0;
        if (duration > 0 && playback_position > 0) {
          //计算进度保留两位小数
          progress = Number((Math.min(playback_position, duration) / duration).toFixed(2));
        }
        if (progress >= 0 && progress <= 1) {
          row.progress = progress;
        }
      });
    }
    return { sourceList, recommend, recentPlay, recentAddByLib };
  }

  /**
   * 按影视库分组的最近添加：只取勾选了 show_in_home 的库
   * 每个分组 { libraryId, libraryName, libType, items }
   */
  async _getRecentAddByLibrary({ limit, validPaths }) {
    const out = [];
    if (!validPaths || validPaths.length === 0) return out;

    const validSet = new Set(validPaths.map(p => String(p)));
    const sources = await this.knex('video_source')
      .select('path', 'library_id')
      .catch(() => []);

    const pathsByLib = new Map();
    for (const s of sources || []) {
      const p = s && s.path ? String(s.path) : '';
      const libId = Number(s && s.library_id) || 0;
      if (!p || !libId) continue;
      // 来源必须在用户可见路径内
      const visible = validSet.has(p) || (() => {
        const sep = path.sep;
        const pPrefix = p.endsWith(sep) ? p : `${p}${sep}`;
        for (const a of validPaths) {
          const aPrefix = a.endsWith(sep) ? a : `${a}${sep}`;
          if (a.startsWith(pPrefix) || p.startsWith(aPrefix)) return true;
        }
        return false;
      })();
      if (!visible) continue;
      if (!pathsByLib.has(libId)) pathsByLib.set(libId, []);
      pathsByLib.get(libId).push(p);
    }

    const libs = await this.knex('video_library')
      .where('show_in_home', 1)
      .orderBy('sort', 'asc')
      .orderBy('id', 'asc')
      .catch(() => []);

    for (const lib of libs || []) {
      const libId = Number(lib && lib.id) || 0;
      if (!libId) continue;
      const libPaths = pathsByLib.get(libId) || [];
      if (libPaths.length === 0) continue;

      const libTypeRaw = lib.lib_type ? String(lib.lib_type).trim().toLowerCase() : 'movie';
      const isImageLib = libTypeRaw === 'image';
      const isMixedLib = libTypeRaw === 'mixed';

      // ⭐ 首页「最近添加」：图片来自独立表 image_index（按 library_id 等值 + 路径可见性）
      let items = [];
      if (isImageLib || isMixedLib) {
        const imgQuery = this.knex('image_index as i').where('i.library_id', libId);
        _applyImageIndexPathPrefixFilter(imgQuery, libPaths, 'i');
        const imgRows = await imgQuery
          .select('i.id', 'i.path', 'i.filename', 'i.ext', 'i.width', 'i.height', 'i.view_time', 'i.create_time')
          .orderBy('i.taken_at', 'desc')
          .orderBy('i.id', 'desc')
          .limit(limit)
          .catch(() => []);
        items = (imgRows || []).map(r => ({
          id: r.id,
          media_type: 'image',
          path: r.path,
          filename: r.filename,
          ext: r.ext,
          is_file: 1,
          width: r.width,
          height: r.height,
          duration: 0,
          nfo_name: r.filename,
          nfo_year: 0,
          nfo_score: 0,
          nfo_regions: '',
          nfo_genres: '',
          poster_path: '',
          fanart_path: '',
          logo_path: '',
          play_rel_path: '',
          view_time: r.view_time,
          create_time: r.create_time,
        }));
      }

      if (!isImageLib) {
        // 视频侧：movie 显式展开 bdmv/video_ts；mixed 把三类都带上
        const mediaTypes =
          libTypeRaw === 'movie'
            ? ['movie', 'bdmv', 'video_ts']
            : libTypeRaw === 'mixed'
              ? ['movie', 'tv', 'bdmv', 'video_ts']
              : ['tv'];

        const vidRows = await this.knex('video_index as v')
          .whereIn('v.media_type', mediaTypes)
          .modify(qb => _applyVideoIndexPathPrefixFilter(qb, libPaths, 'v'))
          .select(
            'v.id',
            'v.media_type',
            'v.path',
            'v.filename',
            'v.nfo_name',
            'v.nfo_year',
            'v.nfo_score',
            'v.nfo_regions',
            'v.nfo_genres',
            'v.poster_path',
            'v.fanart_path',
            'v.logo_path',
            'v.play_rel_path',
            'v.view_time',
            'v.create_time'
          )
          .orderBy('v.id', 'desc')
          .limit(limit)
          .catch(() => []);
        items = items.concat(vidRows || []);
      }

      if ((items || []).length === 0) continue;
      out.push({
        libraryId: libId,
        libraryName: lib.name_key ? String(lib.name_key) : String(lib.name || ''),
        libType: lib.lib_type ? String(lib.lib_type) : 'movie',
        items: _normalizeHomeRows(items.slice(0, limit)),
      });
    }

    return out;
  }

  async _getRecommend({ limit, validPaths }) {
    const baseQuery = this.knex('video_index as v')
      .whereIn('v.media_type', ['movie', 'tv', 'bdmv', 'video_ts'])
      .andWhere('v.nfo_get_state', 1)
      .modify(qb => {
        if (!validPaths || validPaths.length === 0) {
          qb.whereRaw('1 = 0');
        } else {
          _applyVideoIndexPathPrefixFilter(qb, validPaths, 'v');
        }
      })
      .select(
        'v.id',
        'v.media_type',
        'v.path',
        'v.filename',
        'v.nfo_name',
        'v.nfo_year',
        'v.nfo_score',
        'v.nfo_regions',
        'v.nfo_genres',
        'v.poster_path',
        'v.fanart_path',
        'v.logo_path',
        'v.play_rel_path',
        'v.view_time',
        'v.create_time'
      );

    const withFanart = await baseQuery
      .clone()
      .andWhereNot('v.fanart_path', '')
      .orderByRaw('RANDOM()')
      .limit(limit)
      .catch(() => []);

    if ((withFanart || []).length >= limit) return _normalizeHomeRows(withFanart);

    const remain = limit - (withFanart || []).length;
    const excludeIds = (withFanart || []).map(r => r.id).filter(Boolean);
    const filler = await baseQuery
      .clone()
      .modify(qb => {
        if (excludeIds.length > 0) qb.whereNotIn('id', excludeIds);
      })
      .orderByRaw('RANDOM()')
      .limit(remain)
      .catch(() => []);

    return _normalizeHomeRows([...(withFanart || []), ...(filler || [])]);
  }

  async _getRecentPlay({ limit, validPaths }) {
    const uid = this.uid;
    if (!uid) return [];

    const prefRows = await this.knex('video_play_preference as p')
      .join('video_index as v', 'v.file_hash', 'p.file_hash')
      .where('p.uid', uid)
      .modify(qb => {
        if (!validPaths || validPaths.length === 0) {
          qb.whereRaw('1 = 0');
        } else {
          _applyVideoIndexPathPrefixFilter(qb, validPaths, 'v');
        }
      })
      .orderBy('p.last_watched_at', 'desc')
      .orderBy('p.id', 'desc')
      .limit(Math.max(60, limit * 6))
      .select(
        'p.last_watched_at',
        'p.playback_position',
        'p.file_hash',
        'v.id',
        'v.is_file',
        'v.media_type',
        'v.path',
        'v.filename',
        'v.nfo_name',
        'v.nfo_year',
        'v.nfo_score',
        'v.nfo_regions',
        'v.nfo_genres',
        'v.poster_path',
        'v.fanart_path',
        'v.logo_path',
        'v.play_rel_path',
        'v.view_time',
        'v.create_time',
        'v.duration'
      )
      .catch(() => []);

    const episodeFolders = new Set();
    for (const r of prefRows || []) {
      const mt = r && r.media_type ? String(r.media_type).trim() : '';
      if (mt === 'episod') {
        const epFolder = r.path ? String(r.path).trim() : '';
        if (epFolder) episodeFolders.add(epFolder);
      }
    }

    const seasonPairs = [];
    const tvPairs = [];
    for (const f of episodeFolders) {
      const parent = path.dirname(f);
      const name = path.basename(f);
      if (!parent || !name) continue;
      seasonPairs.push({ path: parent, filename: name });

      tvPairs.push({ path: parent, filename: name });
      const showFolder = parent;
      const showParent = showFolder ? path.dirname(showFolder) : '';
      const showName = showFolder ? path.basename(showFolder) : '';
      if (showParent && showName) {
        tvPairs.push({ path: showParent, filename: showName });
      }
    }

    const seasonMap = new Map();
    const tvMap = new Map();

    if (seasonPairs.length > 0) {
      const rows = await this.knex('video_index as v')
        .where({ 'v.is_file': 0, 'v.media_type': 'season' })
        .modify(qb => {
          qb.andWhere(builder => {
            for (const p of seasonPairs) {
              builder.orWhere(function () {
                this.where('v.path', p.path).andWhere('v.filename', p.filename);
              });
            }
          });
        })
        .modify(qb => {
          if (!validPaths || validPaths.length === 0) {
            qb.whereRaw('1 = 0');
          } else {
            _applyVideoIndexPathPrefixFilter(qb, validPaths, 'v');
          }
        })
        .select(
          'v.id',
          'v.media_type',
          'v.path',
          'v.filename',
          'v.nfo_name',
          'v.nfo_year',
          'v.nfo_score',
          'v.nfo_regions',
          'v.nfo_genres',
          'v.poster_path',
          'v.fanart_path',
          'v.logo_path',
          'v.view_time',
          'v.create_time',
          'v.duration'
        )
        .catch(() => []);

      for (const r of rows || []) {
        const k = `${r.path}||${r.filename}`;
        seasonMap.set(k, r);
      }
    }

    if (tvPairs.length > 0) {
      const rows = await this.knex('video_index as v')
        .where({ 'v.is_file': 0, 'v.media_type': 'tv' })
        .modify(qb => {
          qb.andWhere(builder => {
            for (const p of tvPairs) {
              builder.orWhere(function () {
                this.where('v.path', p.path).andWhere('v.filename', p.filename);
              });
            }
          });
        })
        .modify(qb => {
          if (!validPaths || validPaths.length === 0) {
            qb.whereRaw('1 = 0');
          } else {
            _applyVideoIndexPathPrefixFilter(qb, validPaths, 'v');
          }
        })
        .select(
          'v.id',
          'v.media_type',
          'v.path',
          'v.filename',
          'v.nfo_name',
          'v.nfo_year',
          'v.nfo_score',
          'v.nfo_regions',
          'v.nfo_genres',
          'v.poster_path',
          'v.fanart_path',
          'v.logo_path',
          'v.view_time',
          'v.create_time',
          'v.duration'
        )
        .catch(() => []);

      for (const r of rows || []) {
        const k = `${r.path}||${r.filename}`;
        tvMap.set(k, r);
      }
    }

    const out = [];
    const seen = new Set();

    for (const r of prefRows || []) {
      const mt = r && r.media_type ? String(r.media_type).trim() : '';
      let item = r;
      if (mt === 'episod') {
        const folder = r.path ? String(r.path).trim() : '';
        const parent = folder ? path.dirname(folder) : '';
        const name = folder ? path.basename(folder) : '';
        const k1 = parent && name ? `${parent}||${name}` : '';

        const showFolder = parent;
        const showParent = showFolder ? path.dirname(showFolder) : '';
        const showName = showFolder ? path.basename(showFolder) : '';
        const k2 = showParent && showName ? `${showParent}||${showName}` : '';

        item = (k1 && seasonMap.has(k1) ? seasonMap.get(k1) : null) || (k1 && tvMap.has(k1) ? tvMap.get(k1) : null) || (k2 && tvMap.has(k2) ? tvMap.get(k2) : null);
      } else if (mt !== 'movie' && mt !== 'tv' && mt !== 'season' && mt !== 'bdmv' && mt !== 'video_ts') {
        item = null;
      }

      if (!item || !item.id) continue;
      const id = Number(item.id) || 0;
      if (!id || seen.has(id)) continue;
      seen.add(id);

      out.push({
        ...item,
        last_watched_at: r.last_watched_at,
        playback_position: r.playback_position,
      });
      if (out.length >= limit) break;
    }

    return _normalizeHomeRows(out);
  }
}

module.exports = VideoHomeService;
