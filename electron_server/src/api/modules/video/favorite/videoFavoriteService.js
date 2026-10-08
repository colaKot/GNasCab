const VideoSourceService = require('../source/videoSourceService');

/** 判断 target 是否落在 root 之下（含自身），路径分隔符对齐 */
function _isPathUnderRoot(target, root) {
  const t = String(target || '').trim();
  const r = String(root || '').trim();
  if (!t || !r) return false;
  if (t === r) return true;
  const sep = require('path').sep;
  return t.startsWith(r.endsWith(sep) ? r : `${r}${sep}`);
}

class VideoFavoriteService {
  constructor(knexVideo) {
    this.knexVideo = knexVideo;
    this.tableName = 'video_favorite';
  }

  _getUid(user) {
    const uid = user && user.id ? Number(user.id) : 0;
    return uid > 0 ? uid : 0;
  }

  /** 路径级鉴权：收藏目标必须落在用户有权访问的媒体目录内 */
  async _ensureIndexAccess(user, indexId) {
    const row = await this.knexVideo('video_index').where({ id: indexId }).first('path').catch(() => null);
    const dirPath = row && row.path ? String(row.path) : '';
    if (!dirPath) return false;
    const validPaths = await new VideoSourceService(this.knexVideo).getValidPaths(user).catch(() => []);
    return (validPaths || []).some(v => _isPathUnderRoot(dirPath, v));
  }

  async addFavorite(user, indexId) {
    const uid = this._getUid(user);
    const safeIndexId = Number(indexId) || 0;
    if (!uid || !safeIndexId) return { is_favorite: false };

    const allowed = await this._ensureIndexAccess(user, safeIndexId);
    if (!allowed) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    const insertRow = {
      uid,
      index_id: safeIndexId,
      create_time: this.knexVideo.fn.now(),
    };

    const q = this.knexVideo(this.tableName).insert(insertRow);
    if (typeof q.onConflict === 'function') {
      await q.onConflict(['uid', 'index_id']).ignore();
    } else {
      try {
        await q;
      } catch (_) {}
    }
    return { is_favorite: true };
  }

  async removeFavorite(user, indexId) {
    const uid = this._getUid(user);
    const safeIndexId = Number(indexId) || 0;
    if (!uid || !safeIndexId) return { is_favorite: false };

    await this.knexVideo(this.tableName)
      .where({ uid, index_id: safeIndexId })
      .del()
      .catch(() => {});
    return { is_favorite: false };
  }

  async getFavoriteIndexIdSet(user, indexIds) {
    const uid = this._getUid(user);
    const list = Array.isArray(indexIds) ? indexIds.map(v => Number(v) || 0).filter(v => v > 0) : [];
    if (!uid || list.length === 0) return new Set();

    const rows = await this.knexVideo(this.tableName)
      .where({ uid })
      .whereIn('index_id', list)
      .select('index_id')
      .catch(() => []);

    return new Set((rows || []).map(r => Number(r && r.index_id) || 0).filter(v => v > 0));
  }
}

module.exports = VideoFavoriteService;
